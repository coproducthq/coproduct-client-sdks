import XCTest
@testable import Coproduct

// The README documents shutdown() then initialize with a new key as the way to
// switch environments. The on-disk snapshot cache is bound to the sdk key, so a
// new key must not hydrate the old key's snapshot and come up ready serving the
// old environment's values. This drives that exact sequence end to end.
@MainActor
final class CacheKeyIsolationTests: XCTestCase {
    private static let keyA = "cpk_mob_" + String(repeating: "a", count: 32)
    private static let keyB = "cpk_mob_" + String(repeating: "b", count: 32)

    // Serves env-a where flag `x` is true, so a key that hydrates it would report
    // x == true from cache
    private final class EnvATransport: HostTransport, @unchecked Sendable {
        func request(req _: HttpRequest) async throws -> HttpResponse {
            let json = """
            {"snapshot":{"schemaVersion":1,"version":1,"generatedAt":"2026-01-01T00:00:00Z",\
            "environment":{"slug":"env-a","projectKey":"p"},\
            "flags":[{"key":"x","type":"BOOL","enabled":true,"isPaused":false,\
            "variations":[{"key":"on","value":true},{"key":"off","value":false}],\
            "offVariation":"off","fallthroughVariation":"on",\
            "targetingRules":[],"prerequisites":[],"experiment":null}],\
            "segments":[]},"sdkContext":{"timezone":"UTC"}}
            """
            return HttpResponse(status: 200, body: Data(json.utf8), headers: [HttpHeader(name: "ETag", value: "v1")])
        }
    }

    // Never completes a fetch, so the second key can only come up ready if it
    // wrongly hydrated the first key's cache
    private final class StalledTransport: HostTransport, @unchecked Sendable {
        func request(req _: HttpRequest) async throws -> HttpResponse {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            return HttpResponse(status: 200, body: Data(), headers: [])
        }
    }

    override func setUp() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    func testSwitchingKeysDoesNotServeThePreviousKeysCache() async throws {
        // Key A loads env-a and persists it on shutdown
        try await Coproduct.initialize(
            sdkKey: Self.keyA,
            config: CoproductConfig(startupTimeout: 2, transport: EnvATransport(), secureStore: TestSecureStore())
        )
        XCTAssertEqual(Coproduct.state, .ready)
        XCTAssertTrue(Coproduct.getBool("x", default: false), "key A serves env-a's value")
        await Coproduct.shutdown()

        // Key B, per the documented switch path, against a stalled transport. It
        // must NOT hydrate key A's snapshot: it comes up not ready, serves the
        // default, and does not report env-a as its environment
        try await Coproduct.initialize(
            sdkKey: Self.keyB,
            config: CoproductConfig(startupTimeout: 1, transport: StalledTransport(), secureStore: TestSecureStore())
        )
        XCTAssertEqual(Coproduct.state, .notReady, "key B must not come up ready from key A's cache")
        XCTAssertFalse(Coproduct.getBool("x", default: false), "key B must serve the default, not env-a's value")
        XCTAssertNotEqual(Coproduct.snapshot.environment, "env-a", "key B must not report key A's environment")
    }
}
