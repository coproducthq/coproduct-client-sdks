package app.coproduct.paywall

import android.app.Activity
import android.content.Context
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.PendingPurchasesParams
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Renders and drives one resolved paywall: fetches it, loads its html into
 * a WebView, resolves and injects live Play Billing prices, and completes
 * a purchase or restore when the user taps a cta. paywallId is resolved
 * the same way coproduct_onboarding resolves a flowId: from an ordinary
 * flag read, done by the caller before constructing this view. Mirrors
 * sdks/flutter/coproduct/lib/src/paywall/coproduct_paywall.dart and
 * sdks/react-native/coproduct/src/paywall/CoproductPaywall.tsx as a plain
 * Android View -- the same host-View pattern this plan's onboarding
 * sibling (CoproductOnboardingFlow) uses, not a Fragment.
 */
class CoproductPaywall(context: Context) : FrameLayout(context) {
    private var webView: WebView? = null
    private val scope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())

    /**
     * Boots this paywall session. activity is required because
     * PlayBillingPaywallBridge's launchBillingFlow needs an Activity to
     * launch from -- the same real Android constraint this plan's
     * onboarding sibling documents for its own permission bridge. Call
     * this once per CoproductPaywall instance.
     */
    fun load(
        activity: Activity,
        paywallId: String,
        appUserId: String,
        sdkKey: String,
        platformScriptJsOverride: String? = null,
        envSlug: String? = null,
        onPurchaseResult: PurchaseResultCallback? = null,
        onPurchaseError: PurchaseErrorCallback? = null,
        onLoadError: ((String) -> Unit)? = null,
        onDismiss: (() -> Unit)? = null,
        client: PaywallClient? = null,
        bridge: NativePaywallBridge? = null,
    ) {
        scope.launch {
            val resolvedClient = client ?: HttpPaywallClient(sdkKey = sdkKey, envSlug = envSlug)
            val resolvedBridge = bridge ?: buildDefaultBridge(activity)

            val snapshot = try {
                resolvedClient.fetchPaywall(paywallId)
            } catch (e: Exception) {
                onLoadError?.invoke(e.message ?: "Failed to fetch paywall.")
                return@launch
            }
            if (snapshot == null) {
                onLoadError?.invoke("Paywall not found for this environment.")
                return@launch
            }

            val webView = WebView(context).also {
                it.settings.javaScriptEnabled = true
                this@CoproductPaywall.webView = it
            }

            fun reportResultToWebView(state: String, message: String? = null) {
                val messageJs = if (message != null) "\"${message.replace("\"", "\\\"")}\"" else "null"
                webView.evaluateJavascript(
                    "window.__coproductOnPurchaseResult__(\"$state\", $messageJs);",
                    null,
                )
            }

            val runtime = PaywallRuntime(
                bridge = resolvedBridge,
                client = resolvedClient,
                appUserId = appUserId,
                setPrices = { prices ->
                    val json = org.json.JSONObject(prices).toString()
                    webView.evaluateJavascript("window.__coproductSetPrices__($json);", null)
                },
                // The default [data-cp-result] sections (success/cancel/fail)
                // own showing the outcome and, for cancel/fail, waiting for
                // the user's own dismiss tap -- success auto-dismisses
                // itself after a brief hold. onDismiss (not
                // onPurchaseResult/onPurchaseError) is therefore the single
                // place a host app should navigate away from the paywall.
                onPurchaseResult = { result, entitlements ->
                    when (result.outcome) {
                        PurchaseOutcome.SUCCESS -> reportResultToWebView("success")
                        PurchaseOutcome.PENDING -> reportResultToWebView("cancel", "Waiting for approval.")
                        PurchaseOutcome.CANCELLED -> reportResultToWebView("cancel")
                    }
                    onPurchaseResult?.invoke(result, entitlements)
                },
                onPurchaseError = { error ->
                    reportResultToWebView("fail")
                    onPurchaseError?.invoke(error)
                },
                onDismiss = onDismiss,
            )

            webView.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val url = request.url.toString()
                    val isAction = url.startsWith("coproduct-action:")
                    if (isAction) {
                        scope.launch { runtime.handleNavigationRequest(url) }
                    }
                    return isAction
                }

                override fun onPageFinished(view: WebView, url: String?) {
                    // Price injection runs JS against the page's own global,
                    // so it must wait for the inline <script> to have
                    // actually executed -- firing right after loadDataWithBaseURL
                    // returns (which only means the load was *initiated*)
                    // races a cold WebView's first paint and can silently
                    // miss, especially since a cached Play Billing price can
                    // resolve faster than that paint. Mirrors Flutter's
                    // onPageFinished placement and RN's onLoadEnd exactly.
                    scope.launch { runtime.onSnapshotLoaded(snapshot) }
                }
            }

            val html = PaywallShellAssembler.assemble(
                bodyHtml = snapshot.html,
                platformScriptJs = platformScriptJsOverride ?: platformScriptJs,
            )
            webView.loadDataWithBaseURL(null, html, "text/html", "utf-8", null)

            removeAllViews()
            addView(webView)
        }
    }

    private fun buildDefaultBridge(activity: Activity): PlayBillingPaywallBridge {
        lateinit var bridge: PlayBillingPaywallBridge
        val billingClient = BillingClient.newBuilder(context)
            .setListener { billingResult, purchases -> bridge.onPurchasesUpdated(billingResult, purchases) }
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .enableAutoServiceReconnection()
            .build()
        bridge = PlayBillingPaywallBridge(billingClient) { activity }
        billingClient.startConnection(object : com.android.billingclient.api.BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: com.android.billingclient.api.BillingResult) {
                // Connection failures surface per-call as exceptions from
                // priceFor/purchase/restore rather than here -- there is no
                // separate "billing unavailable" callback surface on
                // CoproductPaywall, matching how a transport failure
                // surfaces through PaywallRuntime's own error paths instead
                // of a connection-level callback.
            }
            override fun onBillingServiceDisconnected() {
                // enableAutoServiceReconnection() handles retry; nothing to do here.
            }
        })
        return bridge
    }

    /** Tears down this session's WebView and Play Billing connection. Call from the host's onDestroy. */
    fun destroy() {
        webView?.destroy()
        webView = null
        scope.cancel()
    }
}
