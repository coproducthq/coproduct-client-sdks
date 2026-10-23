import XCTest
@testable import Coproduct

private final class FakeCoproductClient: CoproductClient, @unchecked Sendable {
    var stringFlags: [String: String] = [:]
    var fetchResult: OnboardingFlowGraph?
    var refreshCalled = false
    var sdkContextAttributes: [String: AttributeValue] = [:]
    var sdkContextSegmentKeys: Set<String> = []

    func resolveStringFlag(_ flagKey: String) -> String? { stringFlags[flagKey] }
    func fetchOnboardingFlow(_: String) async -> OnboardingFlowGraph? { fetchResult }
    func refresh() async { refreshCalled = true }
}

/// Suspends callers of `wait()` until `open()` is called, used to prove
/// the `request` action's dispatch is fire-and-forget: `open()` is never
/// called before asserting on `handleNavigationRequest`'s return value.
private actor Gate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

final class FlowRuntimeTests: XCTestCase {
    private func makeGraph() -> OnboardingFlowGraph {
        OnboardingFlowGraph(startScreenId: "s1", screens: [Screen(id: "s1", html: "", transitions: [], defaultNext: .complete, onLoad: nil)])
    }

    override func tearDown() {
        PermissionBridge.requestPermissionOverrideForTesting = nil
        super.tearDown()
    }

    func testNonActionUrlNavigates() async {
        let runtime = FlowRuntime(client: FakeCoproductClient(), progressStore: LocalProgressStore(defaults: UserDefaults(suiteName: "frt.\(UUID())")!), flowId: nil, flowVersion: nil)
        let decision = await runtime.handleNavigationRequest("https://example.com")
        XCTAssertEqual(decision, .navigate)
    }

    func testTrackSavesProgressBeforeCallingOnEventThenReturnsPrevent() async {
        let store = LocalProgressStore(defaults: UserDefaults(suiteName: "frt.\(UUID())")!)
        var order: [String] = []
        let runtime = FlowRuntime(
            client: FakeCoproductClient(), progressStore: store, flowId: "f1", flowVersion: 3,
            onEvent: { _, _, _ in order.append("onEvent") }
        )
        XCTAssertNil(store.load(flowId: "f1"))
        let decision = await runtime.handleNavigationRequest("coproduct-action:track?event=screen_viewed&screenId=s2")
        XCTAssertEqual(decision, .prevent)
        // The saved progress must exist by the time onEvent is observed to
        // have run -- proving save-before-callback ordering, not just that
        // both eventually happened.
        XCTAssertEqual(store.load(flowId: "f1")?.screenId, "s2")
        XCTAssertEqual(order, ["onEvent"])
    }

    func testTrackWithoutFlowIdOrVersionSkipsPersistence() async {
        let store = LocalProgressStore(defaults: UserDefaults(suiteName: "frt.\(UUID())")!)
        let runtime = FlowRuntime(client: FakeCoproductClient(), progressStore: store, flowId: nil, flowVersion: nil)
        _ = await runtime.handleNavigationRequest("coproduct-action:track?event=flow_dismissed&screenId=s1")
        XCTAssertNil(store.load(flowId: "f1"))
    }

    func testRequestPermissionActionCallsCallback() async {
        var receivedPermission: String?
        let runtime = FlowRuntime(
            client: FakeCoproductClient(), progressStore: LocalProgressStore(defaults: UserDefaults(suiteName: "frt.\(UUID())")!),
            flowId: nil, flowVersion: nil, onRequestPermission: { receivedPermission = $0 }
        )
        _ = await runtime.handleNavigationRequest("coproduct-action:requestPermission?permission=camera")
        XCTAssertEqual(receivedPermission, "camera")
    }

    func testOpenUrlActionCallsCallback() async {
        var receivedUrl: String?
        let runtime = FlowRuntime(
            client: FakeCoproductClient(), progressStore: LocalProgressStore(defaults: UserDefaults(suiteName: "frt.\(UUID())")!),
            flowId: nil, flowVersion: nil, onOpenUrl: { receivedUrl = $0 }
        )
        _ = await runtime.handleNavigationRequest("coproduct-action:openUrl?url=https%3A%2F%2Fexample.com")
        XCTAssertEqual(receivedUrl, "https://example.com")
    }

    func testShowPaywallActionCallsCallback() async {
        var receivedPaywallId: String?
        let runtime = FlowRuntime(
            client: FakeCoproductClient(), progressStore: LocalProgressStore(defaults: UserDefaults(suiteName: "frt.\(UUID())")!),
            flowId: nil, flowVersion: nil, onShowPaywall: { receivedPaywallId = $0 }
        )
        _ = await runtime.handleNavigationRequest("coproduct-action:showPaywall?paywallId=pw_1")
        XCTAssertEqual(receivedPaywallId, "pw_1")
    }

    func testDismissAndCompleteAreNoOpsReturningPrevent() async {
        let runtime = FlowRuntime(client: FakeCoproductClient(), progressStore: LocalProgressStore(defaults: UserDefaults(suiteName: "frt.\(UUID())")!), flowId: nil, flowVersion: nil)
        let dismissDecision = await runtime.handleNavigationRequest("coproduct-action:dismiss")
        XCTAssertEqual(dismissDecision, .prevent)
        let completeDecision = await runtime.handleNavigationRequest("coproduct-action:complete")
        XCTAssertEqual(completeDecision, .prevent)
    }

    func testRequestActionIsFireAndForgetAndLaterResolvesThroughCallback() async {
        let gate = Gate()
        var resolved: (requestId: String, response: [String: String])?
        let runtime = FlowRuntime(
            client: FakeCoproductClient(), progressStore: LocalProgressStore(defaults: UserDefaults(suiteName: "frt.\(UUID())")!),
            flowId: nil, flowVersion: nil,
            onNativeOperation: { operation, params in
                await gate.wait()
                return ["status": "ok", "echoedOperation": operation, "echoedParam": params["foo"] ?? ""]
            }
        )
        runtime.attachResolver { requestId, response in resolved = (requestId, response) }

        let decision = await runtime.handleNavigationRequest(
            "coproduct-action:request?operation=fetchUser&requestId=r1&param_foo=bar"
        )
        // The gate is still closed here -- handleNavigationRequest returned
        // .prevent without waiting for the native operation to resolve.
        XCTAssertEqual(decision, .prevent)
        XCTAssertNil(resolved)

        await gate.open()
        // Give the detached Task a turn to run to completion.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(resolved?.requestId, "r1")
        XCTAssertEqual(resolved?.response["status"], "ok")
        XCTAssertEqual(resolved?.response["echoedOperation"], "fetchUser")
        XCTAssertEqual(resolved?.response["echoedParam"], "bar")
    }

    func testRequestActionWithRequestPermissionOperationRoutesThroughPermissionBridge() async {
        PermissionBridge.requestPermissionOverrideForTesting = { permission in ["status": "granted", "echoed": permission] }
        var resolved: [String: String]?
        let runtime = FlowRuntime(
            client: FakeCoproductClient(), progressStore: LocalProgressStore(defaults: UserDefaults(suiteName: "frt.\(UUID())")!),
            flowId: nil, flowVersion: nil
        )
        runtime.attachResolver { _, response in resolved = response }
        _ = await runtime.handleNavigationRequest(
            "coproduct-action:request?operation=requestPermission&requestId=r1&param_permission=camera"
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(resolved?["status"], "granted")
        XCTAssertEqual(resolved?["echoed"], "camera")
    }

    func testRequestActionWithNoHandlerRegisteredResolvesErrorStatus() async {
        var resolved: [String: String]?
        let runtime = FlowRuntime(client: FakeCoproductClient(), progressStore: LocalProgressStore(defaults: UserDefaults(suiteName: "frt.\(UUID())")!), flowId: nil, flowVersion: nil)
        runtime.attachResolver { _, response in resolved = response }
        _ = await runtime.handleNavigationRequest("coproduct-action:request?operation=fetchUser&requestId=r1")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(resolved?["status"], "error")
        XCTAssertEqual(resolved?["message"], "No handler registered for operation \"fetchUser\"")
    }

    func testRequestActionHandlerThrowingResolvesErrorStatus() async {
        struct HandlerFailure: Error, CustomStringConvertible { var description: String { "boom" } }
        var resolved: [String: String]?
        let runtime = FlowRuntime(
            client: FakeCoproductClient(), progressStore: LocalProgressStore(defaults: UserDefaults(suiteName: "frt.\(UUID())")!),
            flowId: nil, flowVersion: nil, onNativeOperation: { _, _ in throw HandlerFailure() }
        )
        runtime.attachResolver { _, response in resolved = response }
        _ = await runtime.handleNavigationRequest("coproduct-action:request?operation=fetchUser&requestId=r1")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(resolved?["status"], "error")
    }

    func testBuildShellHtmlFallsBackToGraphStartScreenIdWhenNoInitialScreenGiven() {
        let client = FakeCoproductClient()
        let runtime = FlowRuntime(client: client, progressStore: LocalProgressStore(defaults: UserDefaults(suiteName: "frt.\(UUID())")!), flowId: nil, flowVersion: nil)
        let html = runtime.buildShellHtml(graph: makeGraph(), flowId: "f1", initialScreenId: nil, initialAnswers: [:], platformScriptJs: "")
        XCTAssertTrue(html.contains(#""initialScreenId":"s1""#))
    }
}
