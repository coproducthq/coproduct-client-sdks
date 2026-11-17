import XCTest
@testable import Coproduct

// The paywall records purchases against the app-supplied id when given, and
// against this install's anonymous id otherwise
final class PaywallAppUserIdTests: XCTestCase {
    override func setUp() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    func testUsesTheAnonymousIdWhenAppUserIdIsOmitted() {
        XCTAssertEqual(CoproductPaywall.resolveAppUserId(nil, anonymousId: "anon-1"), "anon-1")
    }

    func testUsesAnExplicitAppUserIdWhenGiven() {
        XCTAssertEqual(CoproductPaywall.resolveAppUserId("user-1", anonymousId: "anon-1"), "user-1")
    }

    func testAnExplicitAppUserIdDoesNotReadTheAnonymousId() {
        var read = false
        let anonymousId: () -> String? = {
            read = true
            return "anon-1"
        }
        XCTAssertEqual(CoproductPaywall.resolveAppUserId("user-1", anonymousId: anonymousId()), "user-1")
        XCTAssertFalse(read)
    }

    func testNoIdIsAvailableBeforeInitialize() {
        XCTAssertNil(CoproductPaywall.resolveAppUserId(nil, anonymousId: Coproduct.anonymousId))
        XCTAssertFalse(PaywallLoadError.missingAppUserId.message.isEmpty)
    }

    func testOmittedAppUserIdResolvesToTheSdkAnonymousId() async throws {
        let config = CoproductConfig(
            startupTimeout: 1,
            anonymousId: "anon-paywall",
            transport: TestTransport(),
            secureStore: TestSecureStore()
        )
        try await Coproduct.initialize(sdkKey: "cpk_mob_" + String(repeating: "p", count: 32), config: config)
        XCTAssertEqual(CoproductPaywall.resolveAppUserId(nil, anonymousId: Coproduct.anonymousId), "anon-paywall")
    }

    @MainActor
    func testAppUserIdIsOptionalOnTheView() {
        // Compile-time check: the pre-existing call shape and the new one
        // without appUserId both build
        let omitted = CoproductPaywall(paywallId: "pw_1", sdkKey: "cpk_mob_test")
        let explicit = CoproductPaywall(paywallId: "pw_1", appUserId: "user-1", sdkKey: "cpk_mob_test")
        XCTAssertNil(omitted.appUserId)
        XCTAssertEqual(explicit.appUserId, "user-1")
    }
}
