import XCTest
@testable import Coproduct

private func snap(_ id: String) -> PaywallSnapshot {
    PaywallSnapshot(
        paywallId: id, version: 1, templateType: "hero_single_offer",
        content: PaywallContent(offeringKey: "default", ctas: [], html: "<p/>"),
        packages: [:], html: "<p/>"
    )
}

/// A mutable, thread-safe wall clock the cache reads through its injected
/// `now`, so a test can step time across the ttl boundary.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ seconds: TimeInterval) { value = Date(timeIntervalSince1970: seconds) }
    var now: Date {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }
}

/// Counts fetch invocations across the background revalidation's own task.
private actor CallLog {
    private(set) var count = 0
    func record() { count += 1 }
}

final class SnapshotCacheTests: XCTestCase {
    func testSnapshotCacheKeyIncludesEnvDefaultingToApi() {
        XCTAssertEqual(snapshotCacheKey("p1", "production"), "p1|production")
        XCTAssertEqual(snapshotCacheKey("p1", nil), "p1|api")
    }

    func testColdMissBlocksOnFetchAndStores() async {
        let cache = SnapshotCache(now: { Date(timeIntervalSince1970: 1000) })
        let calls = CallLog()
        let out = await cache.resolve("p1|api") { await calls.record(); return snap("p1") }
        XCTAssertEqual(out?.paywallId, "p1")
        let count = await calls.count
        XCTAssertEqual(count, 1)
    }

    func testColdMissReturnsNilWithoutStoring() async {
        let cache = SnapshotCache(now: { Date(timeIntervalSince1970: 1000) })
        let first = await cache.resolve("p1|api") { nil }
        XCTAssertNil(first)
        // A nil cold miss stored nothing, so the next read is still a cold miss
        // that reaches the fetch rather than serving a cached nil.
        let calls = CallLog()
        _ = await cache.resolve("p1|api") { await calls.record(); return nil }
        let count = await calls.count
        XCTAssertEqual(count, 1)
    }

    func testFreshHitServesCachedAndRevalidatesInBackground() async {
        let clock = Clock(1000)
        let cache = SnapshotCache(now: { clock.now })
        _ = await cache.resolve("p1|api") { snap("v1") }

        clock.now = Date(timeIntervalSince1970: 1000 + snapshotTtl - 1) // still fresh
        let calls = CallLog()
        let served = await cache.resolve("p1|api") { await calls.record(); return snap("v2") }
        XCTAssertEqual(served?.paywallId, "v1") // served the cached one

        await cache.awaitRevalidation("p1|api")
        let count = await calls.count
        XCTAssertEqual(count, 1) // revalidate fired once

        let after = await cache.resolve("p1|api") { snap("v3") }
        XCTAssertEqual(after?.paywallId, "v2") // background refresh updated the entry
    }

    func testStaleHitBlockFetchesAndReplaces() async {
        let clock = Clock(1000)
        let cache = SnapshotCache(now: { clock.now })
        _ = await cache.resolve("p1|api") { snap("v1") }
        clock.now = Date(timeIntervalSince1970: 1000 + snapshotTtl) // exactly at cap => stale
        let served = await cache.resolve("p1|api") { snap("v2") }
        XCTAssertEqual(served?.paywallId, "v2")
    }

    func testStaleHitServesStaleSnapshotWhenRefetchReturnsNil() async {
        let clock = Clock(1000)
        let cache = SnapshotCache(now: { clock.now })
        _ = await cache.resolve("p1|api") { snap("v1") }
        clock.now = Date(timeIntervalSince1970: 1000 + snapshotTtl)
        let served = await cache.resolve("p1|api") { nil }
        XCTAssertEqual(served?.paywallId, "v1") // fell back to stale rather than failing
    }

    func testDedupsConcurrentBackgroundRevalidations() async {
        let clock = Clock(1000)
        let cache = SnapshotCache(now: { clock.now })
        _ = await cache.resolve("p1|api") { snap("v1") }
        clock.now = Date(timeIntervalSince1970: 1001) // fresh
        let calls = CallLog()
        let fetchFn: SnapshotFetch = { await calls.record(); return snap("v2") }
        _ = await cache.resolve("p1|api", fetchFn)
        _ = await cache.resolve("p1|api", fetchFn)
        await cache.awaitRevalidation("p1|api")
        let count = await calls.count
        XCTAssertEqual(count, 1) // second revalidate deduped
    }

    func testWarmAlwaysFetchesAndStores() async {
        let clock = Clock(1000)
        let cache = SnapshotCache(now: { clock.now })
        _ = await cache.resolve("p1|api") { snap("v1") }
        clock.now = Date(timeIntervalSince1970: 1001) // fresh
        await cache.warm("p1|api") { snap("v2") }
        let served = await cache.resolve("p1|api") { snap("v3") }
        XCTAssertEqual(served?.paywallId, "v2") // warm overwrote even while fresh
    }
}
