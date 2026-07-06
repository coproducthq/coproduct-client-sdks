import XCTest
@testable import Coproduct

// Concurrency contract for initialize and shutdown. Concurrent initialize calls
// must dedup to a single client and run the post-init side effects once, and a
// shutdown that races an in-flight initialize must not be resurrected by the
// late completion
final class InitializeConcurrencyTests: XCTestCase {
    private static let validKey = "cpk_mob_" + String(repeating: "w", count: 32)

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func increment() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    // Sleeps on the cold-start identity read so the client construct stays in
    // flight long enough for a racing shutdown to land before the instance is
    // stored. The construct no longer touches the network, so the slow seam is
    // the secure store, not the transport
    private final class SlowSecureStore: HostSecureStore, @unchecked Sendable {
        private let delayNanos: UInt64
        init(delaySeconds: Double) { self.delayNanos = UInt64(delaySeconds * 1_000_000_000) }
        func read(key _: String) async throws -> String? {
            try await Task.sleep(nanoseconds: delayNanos)
            return nil
        }
        func write(key _: String, value _: String) async throws {}
    }

    // Never answers, so the provider stays NotReady and initialize sits in the
    // readiness wait, giving a racing shutdown a window during that phase
    private final class StalledTransport: HostTransport, @unchecked Sendable {
        func request(req _: HttpRequest) async throws -> HttpResponse {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return HttpResponse(status: 200, body: Data(), headers: [])
        }
    }

    private func mockConfig() -> CoproductConfig {
        CoproductConfig(startupTimeout: 5, transport: TestTransport(), secureStore: TestSecureStore())
    }

    override func setUp() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    func testConcurrentInitializeShareOneClientAndPostReadyOnce() async throws {
        let readyCount = Counter()
        let observer = NotificationCenter.default.addObserver(
            forName: .coproductDefaultInstanceReady,
            object: nil,
            queue: nil
        ) { _ in readyCount.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        async let first: Void = Coproduct.initialize(sdkKey: Self.validKey, config: mockConfig())
        async let second: Void = Coproduct.initialize(sdkKey: Self.validKey, config: mockConfig())
        try await first
        try await second

        // Both calls dedup to a single core init, so exactly one instance exists
        // and ready is posted exactly once
        XCTAssertNotNil(Instances.shared.defaultInstance(), "concurrent initialize must leave one live instance")

        // Let any queued notification deliver before asserting the count
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(readyCount.value, 1, "ready must be posted exactly once")
    }

    func testShutdownDuringConstructDoesNotResurrectTheInstance() async throws {
        let config = CoproductConfig(
            startupTimeout: 5,
            transport: TestTransport(),
            secureStore: SlowSecureStore(delaySeconds: 0.3)
        )

        async let pending: Void = Coproduct.initialize(sdkKey: Self.validKey, config: config)

        // Let initialize claim the slot and begin the slow cold-start read
        try await Task.sleep(nanoseconds: 50_000_000)
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()

        // The shutdown-race contract is deterministic: a shutdown during the
        // construct fences the store, so initialize reports cancelledByShutdown
        do {
            try await pending
            XCTFail("initialize must throw when a shutdown races the construct")
        } catch let error as CoproductError {
            guard case .cancelledByShutdown = error else {
                return XCTFail("expected cancelledByShutdown, got \(error)")
            }
        } catch {
            XCTFail("expected CoproductError.cancelledByShutdown, got \(error)")
        }

        // The late completion must not have stored a live default instance
        XCTAssertNil(Instances.shared.defaultInstance(), "shutdown must not be resurrected by a late init")
        XCTAssertEqual(Coproduct.state, .notReady)
    }

    func testShutdownDuringReadinessWaitReportsCancelled() async throws {
        // Construct is fast, but the stalled transport keeps the provider NotReady
        // so initialize sits in the readiness wait. A shutdown there must report
        // the same cancelledByShutdown as a shutdown during the construct
        let config = CoproductConfig(
            startupTimeout: 5,
            transport: StalledTransport(),
            secureStore: TestSecureStore()
        )

        async let pending: Void = Coproduct.initialize(sdkKey: Self.validKey, config: config)

        // Let initialize construct, store, and enter the readiness wait
        try await Task.sleep(nanoseconds: 100_000_000)
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()

        do {
            try await pending
            XCTFail("initialize must throw when a shutdown races the readiness wait")
        } catch let error as CoproductError {
            guard case .cancelledByShutdown = error else {
                return XCTFail("expected cancelledByShutdown, got \(error)")
            }
        } catch {
            XCTFail("expected CoproductError.cancelledByShutdown, got \(error)")
        }

        XCTAssertNil(Instances.shared.defaultInstance())
        XCTAssertEqual(Coproduct.state, .notReady)
    }
}
