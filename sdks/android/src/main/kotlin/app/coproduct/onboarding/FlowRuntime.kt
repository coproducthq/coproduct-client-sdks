package app.coproduct.onboarding

import app.coproduct.onboarding.models.OnboardingFlowGraph

enum class FlowNavigationDecision { PREVENT, NAVIGATE }

typealias EventCallback = suspend (event: String, screenId: String, answers: Map<String, List<String>>) -> Unit
typealias OpenUrlCallback = suspend (url: String) -> Unit
typealias PaywallCallback = suspend (paywallId: String) -> Unit
typealias NativeOperationCallback = suspend (operation: String, params: Map<String, String>) -> Map<String, String>
typealias ResolveRequestFn = suspend (requestId: String, response: Map<String, String>) -> Unit

// Owns everything native does in the flow-runtime split: assembling the
// shell, intercepting coproduct-action: navigation, persisting progress
// before the host callback fires, and dispatching native-capability
// actions. Deliberately does not construct or hold a WebView itself, so
// this logic stays unit-testable without a real WebView. Mirrors
// sdks/flutter/coproduct/lib/src/onboarding/flow_runtime.dart and
// sdks/react-native/coproduct/src/onboarding/flowRuntime.ts.
class FlowRuntime(
    private val client: CoproductClient,
    private val progressStore: LocalProgressStore?,
    private val flowId: String? = null,
    private val flowVersion: Int? = null,
    private val onEvent: EventCallback? = null,
    private val onOpenUrl: OpenUrlCallback? = null,
    private val onShowPaywall: PaywallCallback? = null,
    private val onNativeOperation: NativeOperationCallback? = null,
    private val requestPermission: PermissionRequestFn? = null,
) {
    private var resolveRequestFn: ResolveRequestFn? = null

    // Wired by CoproductOnboardingFlow once its WebView exists, so this
    // class never has to import android.webkit.WebView or hold one itself.
    fun attachResolver(resolveRequest: ResolveRequestFn) {
        resolveRequestFn = resolveRequest
    }

    fun buildShellHtml(
        graph: OnboardingFlowGraph,
        flowId: String,
        initialScreenId: String = "",
        initialAnswers: Map<String, List<String>> = emptyMap(),
        platformScriptJs: String = "",
    ): String = ShellAssembler.assemble(
        graph = graph,
        sdkContextAttributes = client.sdkContextAttributes,
        sdkContextSegmentKeys = client.sdkContextSegmentKeys,
        initialAnswers = initialAnswers,
        initialScreenId = initialScreenId.ifEmpty { graph.startScreenId },
        platformScriptJs = platformScriptJs,
    )

    suspend fun handleNavigationRequest(url: String): FlowNavigationDecision {
        val action = CoproductAction.parse(url) ?: return FlowNavigationDecision.NAVIGATE

        when (action) {
            is CoproductAction.TrackAction -> {
                if (flowId != null && flowVersion != null) {
                    progressStore?.save(flowId, flowVersion, action.screenId, action.answers)
                }
                onEvent?.invoke(action.event, action.screenId, action.answers)
            }
            is CoproductAction.RequestPermissionAction -> {
                // Fire-and-forget notification only -- no response is
                // injected back for this action type. A flow that needs the
                // real OS result uses the "request" action with
                // operation="requestPermission" instead, handled below.
            }
            is CoproductAction.OpenUrlAction -> onOpenUrl?.invoke(action.url)
            is CoproductAction.ShowPaywallAction -> onShowPaywall?.invoke(action.paywallId)
            is CoproductAction.RequestAction -> handleRequestAction(action)
            is CoproductAction.DismissAction, is CoproductAction.CompleteAction -> {
                // dismiss/complete are reported via the track action that
                // precedes them (flow_dismissed / flow_completed) --
                // nothing further to do here
            }
        }

        return FlowNavigationDecision.PREVENT
    }

    private suspend fun handleRequestAction(action: CoproductAction.RequestAction) {
        val response = computeRequestResponse(action)
        resolveRequestFn?.invoke(action.requestId, response)
    }

    private suspend fun computeRequestResponse(action: CoproductAction.RequestAction): Map<String, String> {
        if (action.operation == "requestPermission") {
            val requester = requestPermission
                ?: return mapOf("status" to "error", "message" to "No permission requester configured")
            return try {
                requester.request(action.params["permission"] ?: "")
            } catch (e: Exception) {
                mapOf("status" to "error", "message" to e.toString())
            }
        }
        val handler = onNativeOperation
            ?: return mapOf("status" to "error", "message" to "No handler registered for operation \"${action.operation}\"")
        return try {
            handler(action.operation, action.params)
        } catch (e: Exception) {
            mapOf("status" to "error", "message" to e.toString())
        }
    }
}
