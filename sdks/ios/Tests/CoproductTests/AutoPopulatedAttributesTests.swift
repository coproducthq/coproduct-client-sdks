import XCTest
@testable import Coproduct

@MainActor
final class AutoPopulatedAttributesTests: XCTestCase {
    private static let validKey = "cpk_mob_" + String(repeating: "a", count: 32)

    // Serves a snapshot with one flag gated on platform and one on network_type
    private final class RulesTransport: HostTransport, @unchecked Sendable {
        func request(req _: HttpRequest) async throws -> HttpResponse {
            let json = """
            {"snapshot":{"schemaVersion":1,"version":1,"generatedAt":"2026-01-01T00:00:00Z",\
            "environment":{"slug":"test","projectKey":"test"},\
            "flags":[\
            {"key":"ios-only","type":"BOOL","enabled":true,"isPaused":false,\
            "variations":[{"key":"on","value":true},{"key":"off","value":false}],\
            "offVariation":"off","fallthroughVariation":"off",\
            "targetingRules":[{"rule_id":"00000000-0000-4000-8000-0000000000cc",\
            "condition":{"type":"attribute","attribute":"platform","operator":"equals","values":["ios"]},\
            "coverage":10000,"rollout":{"type":"variation","variation":"on"}}],\
            "prerequisites":[],"experiment":null},\
            {"key":"wifi-only","type":"BOOL","enabled":true,"isPaused":false,\
            "variations":[{"key":"on","value":true},{"key":"off","value":false}],\
            "offVariation":"off","fallthroughVariation":"off",\
            "targetingRules":[{"rule_id":"00000000-0000-4000-8000-0000000000cd",\
            "condition":{"type":"attribute","attribute":"network_type","operator":"equals","values":["wifi"]},\
            "coverage":10000,"rollout":{"type":"variation","variation":"on"}}],\
            "prerequisites":[],"experiment":null}],"segments":[]},\
            "sdkContext":{"timezone":"UTC"}}
            """
            return HttpResponse(status: 200, body: Data(json.utf8), headers: [HttpHeader(name: "ETag", value: "v1")])
        }
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        SessionStore.resetProcessGuardForTesting()
        clearCoproductSessionDefaults()
        NetworkMonitor.sourceOverrideForTesting = nil
    }

    private func freshStart() async {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        SessionStore.resetProcessGuardForTesting()
        clearCoproductSessionDefaults()
        // Global test state is cleared at start as well as tearDown so each
        // test's isolation is self-evident
        NetworkMonitor.sourceOverrideForTesting = nil
    }

    func testPlatformRuleMatchesThroughTheAutoPopulatedLayer() async throws {
        await freshStart()
        let config = CoproductConfig(
            startupTimeout: 2,
            transport: RulesTransport(),
            secureStore: TestSecureStore()
        )

        try await Coproduct.initialize(sdkKey: Self.validKey, config: config)

        XCTAssertTrue(
            Coproduct.getBool("ios-only", default: false),
            "the platform rule matches only if auto-population ran before initialize returned"
        )
    }

    func testLiveNetworkChangeReachesTheCoreAndUpdatesFlags() async throws {
        await freshStart()
        let source = FakePathSource()
        NetworkMonitor.sourceOverrideForTesting = source
        let config = CoproductConfig(
            startupTimeout: 2,
            transport: RulesTransport(),
            secureStore: TestSecureStore()
        )
        try await Coproduct.initialize(sdkKey: Self.validKey, config: config)

        XCTAssertTrue(source.started, "initialize starts and retains the injected path source")
        XCTAssertFalse(
            Coproduct.getBool("wifi-only", default: false),
            "network_type is absent before the first path callback"
        )

        source.emit(satisfied: true, wifi: true)

        // Delivery flows through the ordered identity queue, so wait for the
        // value to land rather than asserting synchronously
        var matched = false
        for _ in 0..<200 {
            if Coproduct.getBool("wifi-only", default: false) {
                matched = true
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(matched, "a live network change must reach the core as network_type")

        await Coproduct.shutdown()
        XCTAssertTrue(source.cancelled, "shutdown cancels the path source")
    }
}
