package app.coproduct.onboarding

import android.content.Context
import android.view.View
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import androidx.activity.result.ActivityResultCaller
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

// Renders and drives one onboarding flow, resolved from [flagKey] via
// [client] exactly the way any other flag resolves. Shows a plain
// ProgressBar (or [fallbackSplash], if supplied) until the shell is
// assembled and the WebView has loaded it. Constructed programmatically
// only -- see this plan's Global Constraints for why there is no
// (Context, AttributeSet) XML-inflation constructor. Mirrors
// sdks/flutter/coproduct/lib/src/onboarding/coproduct_onboarding.dart and
// sdks/react-native/coproduct/src/onboarding/CoproductOnboardingFlow.tsx.
class CoproductOnboardingFlow(
    context: Context,
    private val flagKey: String,
    private val client: CoproductClient,
    private val platformScriptJs: String = PLATFORM_SCRIPT_JS,
    private val fallbackSplash: View? = null,
    private val permissionCaller: ActivityResultCaller? = null,
    private val onEvent: EventCallback? = null,
    private val onOpenUrl: OpenUrlCallback? = null,
    private val onShowPaywall: PaywallCallback? = null,
    private val onNativeOperation: NativeOperationCallback? = null,
) : FrameLayout(context) {
    private val scope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())
    private val progressStore = LocalProgressStore(context)
    private val permissionRequester: PermissionRequestFn? =
        permissionCaller?.let { DefaultPermissionRequester(it) }
    private var webView: WebView? = null
    private var runtime: FlowRuntime? = null
    private var debugOverlay: DebugFlowOverlay? = null

    init {
        showSplash()
        scope.launch { boot() }
        if (isDebugBuild()) {
            val overlay = DebugFlowOverlay(
                context,
                onRestartFlow = { rebuild(clearProgress = true) },
                onRefresh = { rebuild(clearProgress = false) },
            )
            debugOverlay = overlay
            addView(overlay)
        }
    }

    private fun isDebugBuild(): Boolean =
        (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private fun showSplash() {
        removeAllViews()
        addView(fallbackSplash ?: ProgressBar(context).apply {
            layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, android.view.Gravity.CENTER)
        })
        debugOverlay?.let { addView(it) }
    }

    private suspend fun boot() {
        val flowId = client.resolveStringFlag(flagKey) ?: return
        val graph = try {
            client.fetchOnboardingFlow(flowId)
        } catch (e: Exception) {
            return
        } ?: return

        val progress = progressStore.load(flowId)
        val newRuntime = FlowRuntime(
            client = client,
            progressStore = progressStore,
            flowId = flowId,
            flowVersion = progress?.version ?: 1,
            onEvent = onEvent,
            onOpenUrl = onOpenUrl,
            onShowPaywall = onShowPaywall,
            onNativeOperation = onNativeOperation,
            requestPermission = permissionRequester,
        )
        runtime = newRuntime

        val html = newRuntime.buildShellHtml(
            graph = graph,
            flowId = flowId,
            initialScreenId = progress?.screenId ?: graph.startScreenId,
            initialAnswers = progress?.answers ?: emptyMap(),
            platformScriptJs = platformScriptJs,
        )

        val newWebView = WebView(context).apply {
            settings.javaScriptEnabled = true
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val url = request.url.toString()
                    val isAction = url.startsWith("coproduct-action:")
                    if (isAction) {
                        // shouldOverrideUrlLoading must return synchronously;
                        // the real dispatch runs in the background and
                        // cannot block this return, matching RN's identical
                        // constraint on onShouldStartLoadWithRequest.
                        scope.launch { newRuntime.handleNavigationRequest(url) }
                    }
                    return isAction
                }
            }
            loadDataWithBaseURL(null, html, "text/html", "utf-8", null)
        }
        webView = newWebView

        newRuntime.attachResolver { requestId, response ->
            val responseJson = response.entries.joinToString(",") { (k, v) ->
                "\"${k}\":\"${v.replace("\"", "\\\"")}\""
            }
            val script = "window.__coproductResolveRequest__('${requestId}', {${responseJson}});"
            try {
                newWebView.evaluateJavascript(script, null)
            } catch (e: Exception) {
                // The WebView may already be torn down (user navigated
                // away, debug restart) by the time a slow request
                // resolves -- nothing to do
            }
        }

        removeAllViews()
        addView(newWebView)
        debugOverlay?.let { addView(it) }
    }

    private suspend fun rebuild(clearProgress: Boolean) {
        if (clearProgress) {
            client.resolveStringFlag(flagKey)?.let { progressStore.clear(it) }
        } else {
            client.refresh()
        }
        webView = null
        runtime = null
        showSplash()
        boot()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        scope.cancel()
    }

    companion object {
        // Loads the platform script bundled with this SDK. A host app calls
        // this once and passes the result into platformScriptJs rather than
        // knowing the bundling mechanism itself. Stays suspend-shaped for
        // call-site parity with Flutter's loadPlatformScript/RN's
        // loadPlatformScript, even though this implementation does zero I/O.
        suspend fun loadPlatformScript(): String = PLATFORM_SCRIPT_JS
    }
}
