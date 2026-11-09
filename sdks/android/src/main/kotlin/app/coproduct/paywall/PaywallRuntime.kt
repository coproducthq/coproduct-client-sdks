package app.coproduct.paywall

import app.coproduct.paywall.models.Entitlement
import app.coproduct.paywall.models.PackageKind
import app.coproduct.paywall.models.PaywallSnapshot
import java.time.Instant

/**
 * A native-side decision about a WebView navigation request. Deliberately
 * not an android.webkit type, mirroring onboarding's FlowNavigationDecision
 * -- keeps this class testable without a real WebView.
 */
enum class PaywallNavigationDecision { PREVENT, NAVIGATE }

enum class PaywallPurchaseErrorReason { UNRESOLVED_PRODUCT, SERVER_REJECTED, NETWORK_ERROR }

data class PaywallPurchaseError(val reason: PaywallPurchaseErrorReason, val serverCode: String? = null)

typealias SetPricesCallback = (pricesByPackageKey: Map<String, String>) -> Unit
// entitlements is the resolved set after this purchase/restore landed --
// empty for a cancelled/pending outcome, since nothing was recorded server-side
typealias PurchaseResultCallback = (result: PurchaseResult, entitlements: List<Entitlement>) -> Unit
typealias PurchaseErrorCallback = (error: PaywallPurchaseError) -> Unit

/**
 * Owns everything native does for one paywall session: resolving and
 * injecting prices after load, and intercepting purchase/restore/dismiss
 * taps. Deliberately does not construct or hold a WebView itself, so this
 * logic stays unit-testable without a real WebView -- mirrors Flutter's
 * PaywallRuntime (paywall_runtime.dart) and RN's (paywallRuntime.ts)
 * class-for-class, reading androidProductId instead of iosProductId.
 */
class PaywallRuntime(
    private val bridge: NativePaywallBridge,
    private val client: PaywallClient,
    private val appUserId: String,
    private val setPrices: SetPricesCallback,
    private val onPurchaseResult: PurchaseResultCallback? = null,
    private val onPurchaseError: PurchaseErrorCallback? = null,
    private val onDismiss: (() -> Unit)? = null,
    private val platform: String = "ANDROID",
) {
    private var snapshot: PaywallSnapshot? = null

    /**
     * Resolves a localized price for every cta with a known product id,
     * then hands the whole map to setPrices in one call. A cta with no
     * resolvable product id, or whose priceFor call fails, is silently
     * skipped -- the server never renders a price for it either.
     */
    suspend fun onSnapshotLoaded(snapshot: PaywallSnapshot) {
        this.snapshot = snapshot
        val prices = mutableMapOf<String, String>()
        for (cta in snapshot.content.ctas) {
            val packageRef = snapshot.packages[cta.packageKey]
            val productId = packageRef?.androidProductId ?: continue
            try {
                prices[cta.packageKey] = bridge.priceFor(productId, packageRef.kind)
            } catch (_: Exception) {
                continue
            }
        }
        if (prices.isNotEmpty()) setPrices(prices)
    }

    suspend fun handleNavigationRequest(url: String): PaywallNavigationDecision {
        val action = parsePaywallAction(url) ?: return PaywallNavigationDecision.NAVIGATE

        when (action) {
            is PaywallAction.Purchase -> handlePurchase(action.packageKey)
            is PaywallAction.Restore -> handleRestore()
            is PaywallAction.Dismiss -> onDismiss?.invoke()
        }
        return PaywallNavigationDecision.PREVENT
    }

    private suspend fun handlePurchase(packageKey: String) {
        val packageRef = snapshot?.packages?.get(packageKey)
        val productId = packageRef?.androidProductId
        if (productId == null) {
            onPurchaseError?.invoke(PaywallPurchaseError(PaywallPurchaseErrorReason.UNRESOLVED_PRODUCT))
            return
        }
        val kind = packageRef.kind

        val result = bridge.purchase(productId, kind)
        if (result.outcome != PurchaseOutcome.SUCCESS) {
            onPurchaseResult?.invoke(result, emptyList())
            return
        }

        val entitlements: List<Entitlement>
        try {
            entitlements = client.recordPurchase(
                appUserId = appUserId,
                platform = platform,
                storeProductId = productId,
                storeTransactionId = result.transactionId!!,
                purchaseDateIso = isoFromMillis(result.purchaseDateMillis!!),
                expiresDateIso = null,
            )
        } catch (e: PaywallServerError) {
            onPurchaseError?.invoke(PaywallPurchaseError(PaywallPurchaseErrorReason.SERVER_REJECTED, e.code))
            return
        } catch (_: Exception) {
            // The purchase is already settled by this point (outcome ==
            // SUCCESS, above) -- a transport failure reporting it must
            // still surface a terminal callback, not propagate uncaught and
            // leave the paywall UI with no signal after a real charge
            onPurchaseError?.invoke(PaywallPurchaseError(PaywallPurchaseErrorReason.NETWORK_ERROR))
            return
        }
        // Outside the try: a throwing onPurchaseResult callback must never
        // be misattributed as a networkError by the catch above
        onPurchaseResult?.invoke(result, entitlements)
    }

    private suspend fun handleRestore() {
        val transactions = bridge.restore()
        if (transactions.isEmpty()) {
            // Nothing to restore is a legitimate, successful outcome --
            // distinct from every found transaction failing to record, below
            onPurchaseResult?.invoke(PurchaseResult(outcome = PurchaseOutcome.SUCCESS), emptyList())
            return
        }

        // recordPurchase recomputes and returns this appUserId's FULL
        // entitlement set from every active transaction on each call (not
        // an incremental diff), so the last successful call's result
        // already reflects every transaction recorded earlier in this loop
        var entitlements: List<Entitlement> = emptyList()
        var anyRecorded = false
        for (tx in transactions) {
            try {
                entitlements = client.recordPurchase(
                    appUserId = appUserId,
                    platform = platform,
                    storeProductId = tx.productId,
                    storeTransactionId = tx.transactionId,
                    purchaseDateIso = isoFromMillis(tx.purchaseDateMillis),
                    expiresDateIso = null,
                )
                anyRecorded = true
            } catch (_: Exception) {
                continue
            }
        }
        if (!anyRecorded) {
            // Transactions existed but none recorded -- reporting success
            // with an empty entitlement list here would be indistinguishable
            // from a user who genuinely has nothing to restore, hiding a
            // real prior purchase whose restore never reached the server
            onPurchaseError?.invoke(PaywallPurchaseError(PaywallPurchaseErrorReason.NETWORK_ERROR))
            return
        }
        onPurchaseResult?.invoke(PurchaseResult(outcome = PurchaseOutcome.SUCCESS), entitlements)
    }

    private fun isoFromMillis(millis: Long): String = Instant.ofEpochMilli(millis).toString()
}
