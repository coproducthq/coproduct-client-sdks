import XCTest
@testable import Coproduct

// Proves a real flag change delivered by a poll reaches the @CoproductFlag
// holder, exercising the full path: core subscription to observation to
// publisher to the wrapper's published value. This guards against the wrapper
// keeping only a publisher while the underlying observation is released
@MainActor
final class FlagUpdateDeliveryTests: XCTestCase {
    private static let validKey = "cpk_mob_" + String(repeating: "w", count: 32)

    // Always answers 200 with the current snapshot body, ignoring If-None-Match,
    // so each poll applies whatever body is currently set
    private final class SwitchingTransport: HostTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var body: Data
        private var etag: String

        init(body: Data, etag: String) {
            self.body = body
            self.etag = etag
        }

        func set(body: Data, etag: String) {
            lock.lock()
            self.body = body
            self.etag = etag
            lock.unlock()
        }

        // Synchronous so the lock is never taken inside the async request body,
        // which Swift 6 language mode rejects
        private func current() -> (body: Data, etag: String) {
            lock.lock()
            defer { lock.unlock() }
            return (body, etag)
        }

        func request(req _: HttpRequest) async throws -> HttpResponse {
            let snapshot = current()
            return HttpResponse(
                status: 200,
                body: snapshot.body,
                headers: [HttpHeader(name: "ETag", value: snapshot.etag)]
            )
        }
    }

    // A snapshot serving the bool flag `x` as the given value through fallthrough.
    // The JSON mirrors the server snapshot wire shape the SDK consumes: the
    // `{ snapshot, sdkContext }` envelope, and every required flag field
    // including isPaused, targetingRules, prerequisites, and a null experiment
    private func snapshot(x: Bool, version: Int) -> Data {
        let served = x ? "on" : "off"
        let json = """
        {"snapshot":{"schemaVersion":1,"version":\(version),"generatedAt":"2026-01-01T00:00:00Z",\
        "environment":{"slug":"test","projectKey":"test"},\
        "flags":[{"key":"x","type":"BOOL","enabled":true,"isPaused":false,\
        "variations":[{"key":"on","value":true},{"key":"off","value":false}],\
        "offVariation":"off","fallthroughVariation":"\(served)",\
        "targetingRules":[],"prerequisites":[],"experiment":null}],\
        "segments":[]},"sdkContext":{"timezone":"UTC"}}
        """
        return Data(json.utf8)
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    func testPropertyWrapperReceivesPostSubscribeFlagChange() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        let transport = SwitchingTransport(body: snapshot(x: false, version: 1), etag: "v1")
        try await Coproduct.initialize(
            sdkKey: Self.validKey,
            config: CoproductConfig(startupTimeout: 2, transport: transport, secureStore: TestSecureStore())
        )
        // initialize returns Void, so reach the client through the internal
        // registry to drive a poll directly
        let client = try XCTUnwrap(Instances.shared.defaultInstance())

        // The first snapshot must have loaded with x resolving to false, so the
        // wrapper seeds false rather than its default
        XCTAssertFalse(Coproduct.getBool("x", default: true), "first snapshot should serve x as false")

        let holder = CoproductFlag<Bool>.Holder(key: "x", defaultValue: false)
        XCTAssertTrue(holder.isSubscribed)
        XCTAssertFalse(holder.value, "seeded from the first snapshot where x is false")

        // Flip the flag and poll. The change must reach the holder through the
        // live core subscription, not the seeded value
        transport.set(body: snapshot(x: true, version: 2), etag: "v2")
        _ = await client.pollNow()

        try await waitUntil(timeout: 2.0) { holder.value }
        XCTAssertTrue(holder.value, "a post-subscribe flag change should reach the wrapper")
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
