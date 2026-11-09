package app.coproduct.compose

import android.app.Activity
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import app.coproduct.paywall.CoproductPaywall
import app.coproduct.paywall.NativePaywallBridge
import app.coproduct.paywall.PaywallClient
import app.coproduct.paywall.PurchaseErrorCallback
import app.coproduct.paywall.PurchaseResultCallback

/**
 * Compose wrapper around app.coproduct.paywall.CoproductPaywall, so a
 * Compose screen can embed the paywall without manual
 * AndroidView(factory = ...) boilerplate. Requires the current Context to
 * be an Activity -- the same real Android constraint CoproductPaywall.load
 * documents for its own Play Billing bridge.
 */
@Composable
fun CoproductPaywall(
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
    val context = LocalContext.current
    val activity = context as? Activity
        ?: throw IllegalStateException("CoproductPaywall composable requires an Activity context")

    AndroidView(
        factory = { ctx ->
            CoproductPaywall(ctx).also { view ->
                view.load(
                    activity = activity,
                    paywallId = paywallId,
                    appUserId = appUserId,
                    sdkKey = sdkKey,
                    platformScriptJsOverride = platformScriptJsOverride,
                    envSlug = envSlug,
                    onPurchaseResult = onPurchaseResult,
                    onPurchaseError = onPurchaseError,
                    onLoadError = onLoadError,
                    onDismiss = onDismiss,
                    client = client,
                    bridge = bridge,
                )
            }
        },
        // Belt-and-suspenders alongside CoproductPaywall's own
        // onDetachedFromWindow teardown: AndroidView tears the factory
        // view down through onRelease when it leaves composition, which is
        // the Compose-recommended hook for this and fires even in
        // recomposition paths that do not cleanly route through the
        // Android view-attachment callbacks. destroy() is idempotent, so
        // this and the View's own onDetachedFromWindow cleanup are safe to
        // both fire for the same instance.
        onRelease = { it.destroy() },
    )
}
