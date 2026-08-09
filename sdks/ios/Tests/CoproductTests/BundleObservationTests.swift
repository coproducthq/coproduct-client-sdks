import XCTest
@testable import Coproduct

// Exercises the live observe(keys:) path end to end: a JSON flag change delivered
// by a poll must reach the bundle observation as a .json value, not a flattened
// string. This covers the bundle drain feeding replace, which the FlagValue
// detailValue unit test does not drive directly
@MainActor
final class BundleObservationTests: XCTestCase {
    private static let validKey = "cpk_mob_" + String(repeating: "w", count: 32)

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

        private func current() -> (body: Data, etag: String) {
            lock.lock()
            defer { lock.unlock() }
            return (body, etag)
        }

        func request(req _: HttpRequest) async throws -> HttpResponse {
            let snapshot = current()
            return HttpResponse(status: 200, body: snapshot.body, headers: [HttpHeader(name: "ETag", value: snapshot.etag)])
        }
    }

    // A snapshot whose JSON flag `j` serves {"a":<n>} through fallthrough
    private func snapshot(a: Int, version: Int) -> Data {
        let json = """
        {"snapshot":{"schemaVersion":1,"version":\(version),"generatedAt":"2026-01-01T00:00:00Z",\
        "environment":{"slug":"test","projectKey":"test"},\
        "flags":[{"key":"j","type":"JSON","enabled":true,"isPaused":false,\
        "variations":[{"key":"v","value":{"a":\(a)}}],\
        "offVariation":"v","fallthroughVariation":"v",\
        "targetingRules":[],"prerequisites":[],"experiment":null}],\
        "segments":[]},"sdkContext":{"timezone":"UTC"}}
        """
        return Data(json.utf8)
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    func testBundleObservationKeepsJSONFlagAsJSON() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        let transport = SwitchingTransport(body: snapshot(a: 1, version: 1), etag: "v1")
        try await Coproduct.initialize(
            sdkKey: Self.validKey,
            config: CoproductConfig(startupTimeout: 2, transport: transport, secureStore: TestSecureStore())
        )
        let client = try XCTUnwrap(Instances.shared.defaultInstance())

        let bundle = Coproduct.observe(keys: ["j"])
        // The bundle is seeded with the v1 value {"a":1} at subscription, so wait
        // for the v2 value {"a":2} specifically. Asserting only that the key is
        // present or that the JSON contains "a" would pass on the seed alone and
        // would not prove the live poll reached the bundle observer
        func currentA() -> Int? {
            guard case let .json(raw)? = bundle.current["j"],
                  let decoded = try? JSONDecoder().decode([String: Int].self, from: Data(raw.utf8))
            else { return nil }
            return decoded["a"]
        }

        // Flip the JSON flag and poll so the change reaches the bundle observer
        transport.set(body: snapshot(a: 2, version: 2), etag: "v2")
        _ = await client.pollNow()

        try await waitUntil(timeout: 2.0) { currentA() == 2 }

        guard case let .json(raw)? = bundle.current["j"] else {
            return XCTFail("bundle must carry the flag as .json, got \(String(describing: bundle.current["j"]))")
        }
        XCTAssertTrue(raw.contains("\"a\""), "the JSON payload is preserved verbatim, not flattened")
        XCTAssertEqual(currentA(), 2, "the live poll delivered the updated value to the bundle")
    }

    // A bundle observation is seeded with each key's current value at subscription,
    // so it is populated immediately rather than only after a key next changes
    func testBundleSeedsCurrentValuesAtSubscription() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        let transport = SwitchingTransport(body: snapshot(a: 1, version: 1), etag: "v1")
        try await Coproduct.initialize(
            sdkKey: Self.validKey,
            config: CoproductConfig(startupTimeout: 2, transport: transport, secureStore: TestSecureStore())
        )

        let bundle = Coproduct.observe(keys: ["j"])

        guard case let .json(raw)? = bundle.current["j"] else {
            return XCTFail("bundle must be seeded at subscription, got \(String(describing: bundle.current["j"]))")
        }
        XCTAssertTrue(raw.contains("\"a\""), "the seeded value carries the current JSON payload")
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
