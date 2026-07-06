import XCTest
@testable import Coproduct

// startupTimeout bounds how long initialize waits for the first poll, not the
// network's own per-request timeout. A stalled first poll must not block launch
// beyond startupTimeout, and reads fall back to defaults until a snapshot lands.
// A fast first poll resolves the provider ready within the deadline
@MainActor
final class StartupTimeoutTests: XCTestCase {
    private static let validKey = "cpk_mob_" + String(repeating: "w", count: 32)

    // Answers far later than any startupTimeout under test, modeling a stalled or
    // black-holed network. Only startupTimeout can end the wait
    private final class StalledTransport: HostTransport, @unchecked Sendable {
        func request(req _: HttpRequest) async throws -> HttpResponse {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return HttpResponse(status: 200, body: Data(), headers: [])
        }
    }

    // Serves a valid snapshot immediately so the first poll makes the provider
    // ready, with flag x served true through fallthrough
    private final class ReadyTransport: HostTransport, @unchecked Sendable {
        func request(req _: HttpRequest) async throws -> HttpResponse {
            let json = """
            {"snapshot":{"schemaVersion":1,"version":1,"generatedAt":"2026-01-01T00:00:00Z",\
            "environment":{"slug":"test","projectKey":"test"},\
            "flags":[{"key":"x","type":"BOOL","enabled":true,"isPaused":false,\
            "variations":[{"key":"on","value":true},{"key":"off","value":false}],\
            "offVariation":"off","fallthroughVariation":"on",\
            "targetingRules":[],"prerequisites":[],"experiment":null}],"segments":[]},\
            "sdkContext":{"timezone":"UTC"}}
            """
            return HttpResponse(status: 200, body: Data(json.utf8), headers: [HttpHeader(name: "ETag", value: "v1")])
        }
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    func testStalledFirstPollReturnsWithinStartupTimeout() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        let config = CoproductConfig(
            startupTimeout: 1,
            transport: StalledTransport(),
            secureStore: TestSecureStore()
        )

        let started = Date()
        try await Coproduct.initialize(sdkKey: Self.validKey, config: config)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 3.0, "initialize must be bounded by startupTimeout, not the network timeout")
        XCTAssertEqual(Coproduct.state, .notReady, "a stalled first poll leaves the provider not ready")
        XCTAssertTrue(Coproduct.getBool("x", default: true), "reads serve the supplied default until a snapshot arrives")
    }

    func testFastFirstPollResolvesReadyAndServesFlags() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        let config = CoproductConfig(
            startupTimeout: 2,
            transport: ReadyTransport(),
            secureStore: TestSecureStore()
        )

        try await Coproduct.initialize(sdkKey: Self.validKey, config: config)

        // The immediate first poll loaded the snapshot within startupTimeout, so
        // the flag serves its resolved value rather than the default
        XCTAssertTrue(Coproduct.getBool("x", default: false), "x is served true by the loaded snapshot")
    }
}
