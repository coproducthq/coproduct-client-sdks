import Foundation

/// Whether a `coproduct-action:` navigation should be swallowed (a
/// recognized action, already dispatched) or allowed to proceed as real
/// navigation (anything else). A separate type from paywall's own
/// decision enum, not shared, so the two modules stay independently
/// testable and excisable.
enum FlowNavigationDecision: Equatable, Sendable {
    case prevent
    case navigate
}

/// Owns everything native does in the flow-runtime split: assembling the
/// shell, intercepting `coproduct-action:` navigation, persisting progress
/// before the host callback fires, and dispatching native-capability
/// actions. Deliberately does not construct or hold a WebView instance
/// itself, so this logic stays unit-testable without a real WebView.
final class FlowRuntime: @unchecked Sendable {
    private let client: CoproductClient
    private let progressStore: LocalProgressStore
    private let flowId: String?
    private let flowVersion: Int?
    private let onEvent: (@Sendable (String, String, [String: [String]]) async -> Void)?
    private let onRequestPermission: (@Sendable (String) async -> Void)?
    private let onOpenUrl: (@Sendable (String) async -> Void)?
    private let onShowPaywall: (@Sendable (String) async -> Void)?
    private let onNativeOperation: (@Sendable (String, [String: String]) async throws -> [String: String])?
    private let requestPermissionFn: PermissionRequestFn
    private var resolveRequestFn: (@Sendable (String, [String: String]) async -> Void)?

    init(
        client: CoproductClient,
        progressStore: LocalProgressStore,
        flowId: String?,
        flowVersion: Int?,
        onEvent: (@Sendable (String, String, [String: [String]]) async -> Void)? = nil,
        onRequestPermission: (@Sendable (String) async -> Void)? = nil,
        onOpenUrl: (@Sendable (String) async -> Void)? = nil,
        onShowPaywall: (@Sendable (String) async -> Void)? = nil,
        onNativeOperation: (@Sendable (String, [String: String]) async throws -> [String: String])? = nil,
        requestPermission: @escaping PermissionRequestFn = PermissionBridge.requestPermission
    ) {
        self.client = client
        self.progressStore = progressStore
        self.flowId = flowId
        self.flowVersion = flowVersion
        self.onEvent = onEvent
        self.onRequestPermission = onRequestPermission
        self.onOpenUrl = onOpenUrl
        self.onShowPaywall = onShowPaywall
        self.onNativeOperation = onNativeOperation
        self.requestPermissionFn = requestPermission
    }

    /// Wired by `CoproductOnboardingFlow` once its WebView exists, so this
    /// class never has to import WebKit or hold a reference itself.
    func attachResolver(_ resolveRequest: @escaping @Sendable (String, [String: String]) async -> Void) {
        resolveRequestFn = resolveRequest
    }

    func buildShellHtml(
        graph: OnboardingFlowGraph,
        flowId: String,
        initialScreenId: String?,
        initialAnswers: [String: [String]],
        platformScriptJs: String
    ) -> String {
        let resolvedInitialScreenId = (initialScreenId?.isEmpty == false) ? initialScreenId! : graph.startScreenId
        return ShellAssembler.assemble(
            graph: graph,
            sdkContextAttributes: client.sdkContextAttributes,
            sdkContextSegmentKeys: client.sdkContextSegmentKeys,
            initialAnswers: initialAnswers,
            initialScreenId: resolvedInitialScreenId,
            platformScriptJs: platformScriptJs
        )
    }

    func handleNavigationRequest(_ url: String) async -> FlowNavigationDecision {
        guard let action = parseCoproductAction(url) else { return .navigate }

        switch action {
        case let .track(event, screenId, answers):
            if let flowId, let flowVersion {
                progressStore.save(flowId: flowId, version: flowVersion, screenId: screenId, answers: answers)
            }
            await onEvent?(event, screenId, answers)
        case let .requestPermission(permission):
            await onRequestPermission?(permission)
        case let .openUrl(url):
            await onOpenUrl?(url)
        case let .showPaywall(paywallId):
            await onShowPaywall?(paywallId)
        case .request:
            // Deliberately not awaited: the decision below must return
            // immediately without waiting for a slow native operation or
            // permission prompt to resolve.
            Task { await self.handleRequestAction(action) }
        case .dismiss, .complete:
            // The track call for flow_dismissed/flow_completed that
            // precedes these already reported the event.
            break
        }

        return .prevent
    }

    private func handleRequestAction(_ action: CoproductAction) async {
        guard case let .request(operation, requestId, params) = action else { return }
        let response = await computeRequestResponse(operation: operation, params: params)
        await resolveRequestFn?(requestId, response)
    }

    private func computeRequestResponse(operation: String, params: [String: String]) async -> [String: String] {
        if operation == "requestPermission" {
            do {
                return try await requestPermissionFn(params["permission"] ?? "")
            } catch {
                return ["status": "error", "message": "\(error)"]
            }
        }
        guard let handler = onNativeOperation else {
            return ["status": "error", "message": "No handler registered for operation \"\(operation)\""]
        }
        do {
            return try await handler(operation, params)
        } catch {
            return ["status": "error", "message": "\(error)"]
        }
    }
}
