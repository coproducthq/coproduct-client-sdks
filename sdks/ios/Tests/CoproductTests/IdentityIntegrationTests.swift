import XCTest
@testable import Coproduct

// Drives the public, synchronous identity API against a live client and observes
// the settled context through flag evaluation. The flag `x` is served true only
// when the attribute tier equals "on", so the value getBool returns reflects the
// last context mutation that was applied. This proves the public identify and
// updateAttributes path routes through the ordered queue, not just the queue in
// isolation
@MainActor
final class IdentityIntegrationTests: XCTestCase {
    private static let validKey = "cpk_mob_" + String(repeating: "w", count: 32)

    // Serves a single snapshot whose bool flag `x` falls through to false but is
    // served true by a targeting rule when the attribute tier equals "on"
    private final class FixedTransport: HostTransport, @unchecked Sendable {
        private let body: Data
        init(body: Data) { self.body = body }
        func request(req _: HttpRequest) async throws -> HttpResponse {
            HttpResponse(status: 200, body: body, headers: [HttpHeader(name: "ETag", value: "v1")])
        }
    }

    private static func snapshotBody() -> Data {
        let json = """
        {"snapshot":{"schemaVersion":1,"version":1,"generatedAt":"2026-01-01T00:00:00Z",\
        "environment":{"slug":"test","projectKey":"test"},\
        "flags":[{"key":"x","type":"BOOL","enabled":true,"isPaused":false,\
        "variations":[{"key":"on","value":true},{"key":"off","value":false}],\
        "offVariation":"off","fallthroughVariation":"off",\
        "targetingRules":[{"rule_id":"00000000-0000-0000-0000-000000000001",\
        "condition":{"type":"attribute","attribute":"tier","operator":"equals","values":["on"]},\
        "rollout":{"type":"variation","variation":"on"},"coverage":10000}],\
        "prerequisites":[],"experiment":null}],"segments":[]},"sdkContext":{"timezone":"UTC"}}
        """
        return Data(json.utf8)
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    func testRapidPublicContextUpdatesApplyInCallOrder() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        let config = CoproductConfig(
            startupTimeout: 2,
            transport: FixedTransport(body: Self.snapshotBody()),
            secureStore: TestSecureStore()
        )
        try await Coproduct.initialize(sdkKey: Self.validKey, config: config)

        // Baseline: no tier attribute, so the rule misses and x falls through false
        XCTAssertFalse(Coproduct.getBool("x", default: true), "x should fall through to false with no tier")

        // A single update through the public path flips the rule on, confirming
        // the targeting rule and the public updateAttributes path work end to end
        Coproduct.updateAttributes(["tier": .string("on")])
        await IdentitySerializer.shared.drain()
        XCTAssertTrue(Coproduct.getBool("x", default: false), "tier on should match the rule")

        // A burst of fire-and-forget updates. If they applied out of order the
        // final value would not match the last call. The last call sets tier off
        Coproduct.updateAttributes(["tier": .string("on")])
        Coproduct.updateAttributes(["tier": .string("off")])
        Coproduct.updateAttributes(["tier": .string("on")])
        Coproduct.updateAttributes(["tier": .string("off")])
        await IdentitySerializer.shared.drain()
        XCTAssertFalse(Coproduct.getBool("x", default: true), "last update set tier off, so x must be false")

        // And once more ending on, to rule out a value that happens to be false
        Coproduct.updateAttributes(["tier": .string("off")])
        Coproduct.updateAttributes(["tier": .string("on")])
        await IdentitySerializer.shared.drain()
        XCTAssertTrue(Coproduct.getBool("x", default: false), "last update set tier on, so x must be true")
    }
}
