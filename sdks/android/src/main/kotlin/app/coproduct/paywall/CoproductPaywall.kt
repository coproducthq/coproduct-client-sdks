package app.coproduct.paywall

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.PendingPurchasesParams
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Flag-reading surface [CoproductPaywall.prefetchPlacements] uses to resolve a
 * placement flag to a paywallId. The base [app.coproduct.CoproductClient]
 * implements it, so a host passes its client directly.
 */
interface FlagReader {
    fun getString(key: String, default: String): String
}

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

    // The WebView is added hidden and transparent beneath this spinner, and
    // revealed only once it has painted and had prices applied (see reveal), so
    // the user never sees a white flash or a price-less frame.
    private var progressBar: ProgressBar? = null
    private var revealed = false
    private var revealJob: Job? = null

    // Only set when load() builds its own default bridge (buildDefaultBridge
    // below): that is the one case this view owns the BillingClient's
    // connection and must end it itself. A bridge supplied by the caller is
    // caller-owned, so its connection is the caller's to end
    private var ownedBridge: PlayBillingPaywallBridge? = null

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
                snapshotCache.resolve(snapshotCacheKey(paywallId, envSlug)) {
                    resolvedClient.fetchPaywall(paywallId)
                }
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
                // Transparent so the hidden WebView's blank first paint is never
                // a white flash; the html paints its own background once loaded.
                it.setBackgroundColor(Color.TRANSPARENT)
                it.visibility = View.INVISIBLE
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
                    // Prices are the last thing to land, so reveal now.
                    // onPageFinished still covers the case where they never resolve.
                    reveal()
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
                    // Reveal if prices have not already; setPrices reveals sooner.
                    reveal()
                    // Inject prices only now the page's inline script has run, so
                    // the global it defines exists.
                    scope.launch { runtime.onSnapshotLoaded(snapshot) }
                }
            }

            val html = PaywallShellAssembler.assemble(
                bodyHtml = snapshot.html,
                platformScriptJs = platformScriptJsOverride ?: platformScriptJs,
            )
            webView.loadDataWithBaseURL(null, html, "text/html", "utf-8", null)

            val spinner = ProgressBar(context).also {
                it.layoutParams = LayoutParams(
                    LayoutParams.WRAP_CONTENT,
                    LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER,
                )
                this@CoproductPaywall.progressBar = it
            }
            removeAllViews()
            addView(webView)
            addView(spinner)

            // Hang guard only: reveal is driven by paint (onPageFinished) or
            // prices (setPrices), never a fixed delay. This fires only if the
            // WebView never finishes, so a hung load reveals instead of spinning.
            revealJob?.cancel()
            revealJob = scope.launch {
                delay(8000)
                reveal()
            }
        }
    }

    /**
     * Reveals the finished paywall in one cut from the spinner. Idempotent: the
     * first of paint, prices, or the hang guard wins.
     */
    private fun reveal() {
        if (revealed) return
        revealed = true
        revealJob?.cancel()
        revealJob = null
        webView?.visibility = View.VISIBLE
        progressBar?.let { removeView(it) }
        progressBar = null
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
        ownedBridge = bridge
        return bridge
    }

    /**
     * Tears down this session's WebView and ends this view's own Play
     * Billing connection, if it built one. Idempotent, since both automatic
     * teardown (onDetachedFromWindow, below) and a caller holding a direct
     * reference to this View may each call this.
     */
    fun destroy() {
        webView?.destroy()
        webView = null
        ownedBridge?.close()
        ownedBridge = null
        scope.cancel()
    }

    // Mirrors CoproductOnboardingFlow.onDetachedFromWindow's pattern: a host
    // app that discards this View (navigates away, recomposes it out) without
    // remembering to call destroy() itself must not leak the WebView or the
    // Play Billing connection.
    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        destroy()
    }

    companion object {
        /**
         * Fetches a paywall's snapshot into the process-level cache so a later
         * [CoproductPaywall] for the same id and environment opens without a
         * network round-trip. Best-effort; safe to call more than once.
         */
        suspend fun prefetch(
            paywallId: String,
            sdkKey: String,
            envSlug: String? = null,
            client: PaywallClient? = null,
        ) {
            val resolved = client ?: HttpPaywallClient(sdkKey = sdkKey, envSlug = envSlug)
            snapshotCache.warm(snapshotCacheKey(paywallId, envSlug)) { resolved.fetchPaywall(paywallId) }
        }

        /**
         * Warms every paywall the given placement flags resolve to, reading each
         * paywallId through [client] so targeting is respected. Best-effort.
         */
        suspend fun prefetchPlacements(
            client: FlagReader,
            flagKeys: List<String>,
            sdkKey: String,
            envSlug: String? = null,
            paywallClient: PaywallClient? = null,
        ) {
            val resolved = paywallClient ?: HttpPaywallClient(sdkKey = sdkKey, envSlug = envSlug)
            val seen = mutableSetOf<String>()
            coroutineScope {
                flagKeys.forEach { flagKey ->
                    val paywallId = client.getString(flagKey, "")
                    if (paywallId.isEmpty() || !seen.add(paywallId)) return@forEach
                    launch {
                        snapshotCache.warm(snapshotCacheKey(paywallId, envSlug)) {
                            resolved.fetchPaywall(paywallId)
                        }
                    }
                }
            }
        }
    }
}
