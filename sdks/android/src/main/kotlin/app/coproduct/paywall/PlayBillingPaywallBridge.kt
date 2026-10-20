package app.coproduct.paywall

import app.coproduct.paywall.models.PackageKind
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.consumePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch

/**
 * Play Billing-backed NativePaywallBridge -- the first native Android
 * purchase bridge in this repository. Owns the one genuinely new piece of
 * logic this feature needs: Play Billing's launchBillingFlow() is
 * fire-and-forget -- its own returned BillingResult only says whether the
 * flow launched, never the purchase outcome, which arrives later through
 * PurchasesUpdatedListener (shared across every in-flight launch on this
 * client; Play Billing allows exactly one listener and one flow in flight
 * at a time, so a single pending CompletableDeferred slot is enough
 * correlation state). Settles every successful purchase (consumePurchase
 * for CONSUMABLE, acknowledgePurchase for SUBSCRIPTION/LIFETIME) before
 * resolving that deferred -- Play Billing auto-refunds an unsettled
 * purchase within 3 days, so a later backend-recording failure must never
 * leave a purchase unsettled.
 *
 * Takes an already-constructed BillingClient via constructor injection so
 * this class stays unit-testable against a fake/mocked BillingClient with
 * no real Play Store connection. The caller owns building the real
 * BillingClient (wiring this bridge in as its PurchasesUpdatedListener) and
 * owns calling startConnection/endConnection.
 *
 * Note on billing-ktx:9.1.0 API names used below (verified against the
 * real jar -- see PlayBillingPaywallBridgeTest's class kdoc and the Task 5
 * report for exact verification commands): the suspend extension for
 * querying owned purchases is `queryPurchasesAsync`, not `queryPurchases`;
 * `queryProductDetails` returns the ktx-only `ProductDetailsResult`
 * (billingResult + productDetailsList), a different class from the raw
 * billing library's callback-oriented `QueryProductDetailsResult`.
 */
class PlayBillingPaywallBridge(
    private val billingClient: BillingClient,
    private val activityProvider: () -> android.app.Activity,
) : NativePaywallBridge, PurchasesUpdatedListener {

    private var pendingPurchase: PendingPurchase? = null

    private class PendingPurchase(
        val productId: String,
        val kind: PackageKind,
        val deferred: CompletableDeferred<PurchaseResult>,
    )

    override suspend fun priceFor(productId: String, kind: PackageKind): String {
        val productDetails = queryProductDetails(productId, kind)
        return if (kind == PackageKind.SUBSCRIPTION) {
            val offer = productDetails.subscriptionOfferDetails?.firstOrNull()
                ?: throw IllegalStateException("No subscription offer found for product \"$productId\"")
            offer.pricingPhases.pricingPhaseList.last().formattedPrice
        } else {
            val offer = productDetails.oneTimePurchaseOfferDetailsList?.firstOrNull()
                ?: throw IllegalStateException("No one-time offer found for product \"$productId\"")
            offer.formattedPrice
        }
    }

    override suspend fun purchase(productId: String, kind: PackageKind): PurchaseResult {
        val productDetails = queryProductDetails(productId, kind)
        val offerToken = if (kind == PackageKind.SUBSCRIPTION) {
            productDetails.subscriptionOfferDetails?.firstOrNull()?.offerToken
        } else {
            productDetails.oneTimePurchaseOfferDetailsList?.firstOrNull()?.offerToken
        } ?: throw IllegalStateException("No purchasable offer found for product \"$productId\"")

        val deferred = CompletableDeferred<PurchaseResult>()
        pendingPurchase = PendingPurchase(productId, kind, deferred)

        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(productDetails)
                        .setOfferToken(offerToken)
                        .build()
                )
            )
            .build()

        // launchBillingFlow must be called from the main thread per the
        // Play Billing docs; the caller (CoproductPaywall, Task 7) is
        // responsible for dispatching this call appropriately -- this
        // bridge does not hop threads itself, matching how it takes an
        // already-constructed BillingClient rather than owning Context/
        // Activity concerns.
        val launchResult = billingClient.launchBillingFlow(activityProvider(), params)
        if (launchResult.responseCode != BillingClient.BillingResponseCode.OK) {
            pendingPurchase = null
            throw IllegalStateException("launchBillingFlow failed: ${launchResult.debugMessage}")
        }

        return deferred.await()
    }

    override suspend fun restore(): List<RestoredTransaction> {
        val subsResult = billingClient.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build()
        )
        val inappResult = billingClient.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()
        )
        val restored = mutableListOf<RestoredTransaction>()
        for (purchase in subsResult.purchasesList + inappResult.purchasesList) {
            if (!purchase.isAcknowledged) {
                billingClient.acknowledgePurchase(
                    AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
                )
            }
            restored.add(
                RestoredTransaction(
                    transactionId = purchase.purchaseToken,
                    productId = purchase.products.firstOrNull().orEmpty(),
                    purchaseDateMillis = purchase.purchaseTime,
                )
            )
        }
        return restored
    }

    override fun onPurchasesUpdated(billingResult: BillingResult, purchases: List<Purchase>?) {
        val pending = pendingPurchase ?: return
        when (billingResult.responseCode) {
            BillingClient.BillingResponseCode.USER_CANCELED -> {
                pendingPurchase = null
                pending.deferred.complete(PurchaseResult(outcome = PurchaseOutcome.CANCELLED))
            }
            BillingClient.BillingResponseCode.OK -> {
                val purchase = purchases?.firstOrNull { it.products.contains(pending.productId) }
                if (purchase == null) return
                pendingPurchase = null
                handleUpdatedPurchase(pending, purchase)
            }
            else -> {
                pendingPurchase = null
                pending.deferred.completeExceptionally(
                    IllegalStateException("Billing error ${billingResult.responseCode}: ${billingResult.debugMessage}")
                )
            }
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    private fun handleUpdatedPurchase(pending: PendingPurchase, purchase: Purchase) {
        if (purchase.purchaseState == Purchase.PurchaseState.PENDING) {
            pending.deferred.complete(PurchaseResult(outcome = PurchaseOutcome.PENDING))
            return
        }
        // Settle (consume or acknowledge) before completing the deferred --
        // see this class's own kdoc and this plan's Global Constraints for
        // why this ordering is load-bearing. kotlinx.coroutines has no
        // synchronous bridge out of this listener callback, so settlement
        // runs on a fire-and-forget coroutine that completes the deferred
        // only after the settlement call returns; a settlement failure
        // (e.g. ITEM_NOT_OWNED on a race) still completes the deferred
        // successfully, since the charge already happened and the caller
        // must still learn the purchase succeeded.
        //
        // GlobalScope is intentional, not an oversight: settlement must
        // complete even if some caller-owned scope gets cancelled, since
        // the charge already happened by the time this callback fires.
        GlobalScope.launch(Dispatchers.IO) {
            try {
                if (pending.kind == PackageKind.CONSUMABLE) {
                    billingClient.consumePurchase(
                        ConsumeParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
                    )
                } else {
                    billingClient.acknowledgePurchase(
                        AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
                    )
                }
            } catch (_: Exception) {
                // Settlement failure must not block reporting the purchase
                // -- the charge already happened
            } finally {
                pending.deferred.complete(
                    PurchaseResult(
                        outcome = PurchaseOutcome.SUCCESS,
                        transactionId = purchase.purchaseToken,
                        productId = pending.productId,
                        purchaseDateMillis = purchase.purchaseTime,
                    )
                )
            }
        }
    }

    private suspend fun queryProductDetails(productId: String, kind: PackageKind) =
        billingClient.queryProductDetails(
            QueryProductDetailsParams.newBuilder()
                .setProductList(
                    listOf(
                        QueryProductDetailsParams.Product.newBuilder()
                            .setProductId(productId)
                            .setProductType(
                                if (kind == PackageKind.SUBSCRIPTION) BillingClient.ProductType.SUBS
                                else BillingClient.ProductType.INAPP
                            )
                            .build()
                    )
                )
                .build()
        ).productDetailsList?.firstOrNull()
            ?: throw IllegalStateException("No product found for id \"$productId\"")
}
