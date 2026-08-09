import XCTest
@testable import Coproduct

// A flag that leaves the snapshot must take the observation back to the caller's
// default, and must leave a bundle's public dictionary. This drives the real
// registration and the real drain task rather than the observation types
// directly, so it fails if the registration stops mapping unavailable. The
// single-key test drives two deliveries, so it also fails if the drain stops
// after its first one. Both ends of that test are discriminating: the flag is
// served as false while the caller's default is true, so neither the seed nor
// the unavailable mapping can pass by landing on Bool's type zero. The transport
// double and the snapshot bodies follow FlagUpdateDeliveryTests
@MainActor
final class ObservationUnavailableEndToEndTests: XCTestCase {
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

    // A snapshot carrying exactly the named bool flags. A key listed in
    // `servingFalse` resolves to false through fallthrough, every other key
    // resolves to true, so a test can pick a served value that differs from the
    // caller's default. A key absent from `keys` is absent from the snapshot,
    // which is how a flag becomes unavailable
    private func snapshot(keys: [String], version: Int, servingFalse: Set<String> = []) -> Data {
        let flags = keys.map { key in
            let served = servingFalse.contains(key) ? "off" : "on"
            return """
            {"key":"\(key)","type":"BOOL","enabled":true,"isPaused":false,\
            "variations":[{"key":"on","value":true},{"key":"off","value":false}],\
            "offVariation":"off","fallthroughVariation":"\(served)",\
            "targetingRules":[],"prerequisites":[],"experiment":null}
            """
        }.joined(separator: ",")
        let json = """
        {"snapshot":{"schemaVersion":1,"version":\(version),"generatedAt":"2026-01-01T00:00:00Z",\
        "environment":{"slug":"test","projectKey":"test"},\
        "flags":[\(flags)],\
        "segments":[]},"sdkContext":{"timezone":"UTC"}}
        """
        return Data(json.utf8)
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    func testSingleObservationRevertsToDefaultWhenTheFlagLeavesTheSnapshot() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        // `gate` is served as false against a caller default of true, so every
        // assertion below distinguishes the served value from the default
        let transport = SwitchingTransport(
            body: snapshot(keys: ["gate", "other"], version: 1, servingFalse: ["gate"]),
            etag: "\"1\""
        )
        try await Coproduct.initialize(
            sdkKey: Self.validKey,
            config: CoproductConfig(startupTimeout: 2, transport: transport, secureStore: TestSecureStore())
        )
        // initialize returns Void, so reach the client through the internal
        // registry to drive a poll directly
        let client = try XCTUnwrap(Instances.shared.defaultInstance())

        let observation = Coproduct.observe("gate", default: true)
        XCTAssertEqual(observation.current, false, "the session seeds from the held snapshot, not from the default")

        transport.set(body: snapshot(keys: ["other"], version: 2), etag: "\"2\"")
        _ = await client.pollNow()

        // The delivery carries unavailable, which resolves to the caller's own
        // default rather than to Bool's type zero
        try await waitUntil(timeout: 2.0) { observation.current == true }
        XCTAssertEqual(observation.current, true, "an unavailable flag serves the caller's default")

        // A second delivery, so a drain that stopped after its first one fails here
        transport.set(
            body: snapshot(keys: ["gate", "other"], version: 3, servingFalse: ["gate"]),
            etag: "\"3\""
        )
        _ = await client.pollNow()

        try await waitUntil(timeout: 2.0) { observation.current == false }
        XCTAssertEqual(observation.current, false, "the drain keeps delivering after the flag returns")
    }

    func testBundleDropsAKeyThatLeavesTheSnapshot() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        let transport = SwitchingTransport(body: snapshot(keys: ["gate", "other"], version: 1), etag: "\"1\"")
        try await Coproduct.initialize(
            sdkKey: Self.validKey,
            config: CoproductConfig(startupTimeout: 2, transport: transport, secureStore: TestSecureStore())
        )
        let client = try XCTUnwrap(Instances.shared.defaultInstance())

        let bundle = Coproduct.observe(keys: ["gate", "other"])
        XCTAssertEqual(bundle.current["gate"], .bool(true), "the session seeds the whole map")
        XCTAssertEqual(bundle.current["other"], .bool(true))

        transport.set(body: snapshot(keys: ["other"], version: 2), etag: "\"2\"")
        _ = await client.pollNow()

        try await waitUntil(timeout: 2.0) { bundle.current["gate"] == nil }
        XCTAssertNil(bundle.current["gate"], "an unavailable key leaves the public dictionary")
        XCTAssertNotNil(bundle.current["other"], "the surviving key stays")
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
