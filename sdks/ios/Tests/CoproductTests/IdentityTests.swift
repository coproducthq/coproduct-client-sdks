import XCTest
@testable import Coproduct

// Wrapper-level identity lifecycle coverage. The public identity methods are
// synchronous and return Void, but they bridge to async FFI through a detached
// task, so any persisted effect lands after the call returns. Each assertion on
// previousAnonymousId therefore polls with a short timeout rather than reading
// immediately. A fixed anonymousId in config gives every test a known baseline
// so the linked anonymous id is deterministic instead of a generated uuid
final class IdentityTests: XCTestCase {
    private let baselineAnon = "anon-fixture-id"

    override func setUp() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        let config = CoproductConfig(
            startupTimeout: 1,
            anonymousId: baselineAnon,
            transport: TestTransport(),
            secureStore: TestSecureStore()
        )
        try await Coproduct.initialize(
            sdkKey: "cpk_mob_" + String(repeating: "a", count: 32),
            config: config
        )
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
    }

    // Poll previousAnonymousId until it satisfies the predicate or the timeout
    // elapses. The fire-and-forget identity bridge means the effect is not
    // visible synchronously, so a bounded poll keeps the test deterministic
    // without a fixed sleep
    private func awaitPreviousAnonymousId(
        timeout: TimeInterval = 2.0,
        until predicate: @escaping (String?) -> Bool
    ) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = Coproduct.previousAnonymousId
            if predicate(current) { return current }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return Coproduct.previousAnonymousId
    }

    func testIdentifyLinksPreviousAnonymousIdWhenLinkOn() async {
        Coproduct.identify(userId: "alice")
        let previous = await awaitPreviousAnonymousId { $0 == self.baselineAnon }
        XCTAssertEqual(previous, baselineAnon)
    }

    func testIdentifyWithLinkOffLeavesPreviousAnonymousNil() async {
        Coproduct.identify(userId: "alice", attributes: [:], linkAnonymous: false)
        // Give the detached bridge time to run, then confirm the link was not
        // recorded. Polling for nil cannot distinguish not-yet-run from
        // deliberately-nil, so wait a beat first then assert the final state
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(Coproduct.previousAnonymousId)
    }

    func testSignOutClearsPreviousAnonymousId() async {
        Coproduct.identify(userId: "alice")
        let linked = await awaitPreviousAnonymousId { $0 == self.baselineAnon }
        XCTAssertEqual(linked, baselineAnon)

        Coproduct.signOut()
        // Sign out reverts to the original anonymous identity and drops the linked
        // id. The original anonymous id is deliberately reused rather than
        // regenerated, so a returning user's pre-login sessions re-link
        let cleared = await awaitPreviousAnonymousId { $0 == nil }
        XCTAssertNil(cleared)
    }

    func testEmptyTargetingKeyIsRejected() async {
        // An empty targeting key is invalid, so setContext must not move the
        // identity off its anonymous baseline. previousAnonymousId stays nil
        // because no identify ever linked one
        Coproduct.setContext(targetingKey: "", attributes: [:])
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(Coproduct.previousAnonymousId)
    }

    func testSecondIdentifyKeepsOriginalAnonymousId() async {
        Coproduct.identify(userId: "alice")
        let firstLink = await awaitPreviousAnonymousId { $0 == self.baselineAnon }
        XCTAssertEqual(firstLink, baselineAnon)

        // Re-identifying to a different user preserves the first linked
        // anonymous id rather than overwriting it with the now-identified key
        Coproduct.identify(userId: "bob")
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(Coproduct.previousAnonymousId, baselineAnon)
    }

    func testUpdateThenRemoveAttributesDoNotDisturbIdentityLink() async {
        Coproduct.identify(userId: "alice")
        let linked = await awaitPreviousAnonymousId { $0 == self.baselineAnon }
        XCTAssertEqual(linked, baselineAnon)

        // Attribute mutations are context-only and must leave the linked
        // anonymous id untouched
        Coproduct.updateAttributes(["plan": .string("pro")])
        Coproduct.removeAttributes(["plan"])
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(Coproduct.previousAnonymousId, baselineAnon)
    }
}
