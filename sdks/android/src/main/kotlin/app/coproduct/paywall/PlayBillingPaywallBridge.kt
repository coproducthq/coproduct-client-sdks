package app.coproduct.paywall

import app.coproduct.paywall.models.PackageKind
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.ProductDetails
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

    /**
     * Resolves a product's regular price and, when Play Billing returns an
     * offer with an introductory pricing phase ahead of the regular one,
     * that offer's localized label. Play Billing filters
     * queryProductDetails's `subscriptionOfferDetails` server-side to only
     * the offers this signed-in Play account is currently eligible for
     * (there is no separate boolean the way StoreKit2's
     * isEligibleForIntroOffer is) -- so a returned offer with more than one
     * pricing phase already implies eligibility. Consumable/lifetime
     * products have no periodic offers and always resolve price-only.
     * Fails safe to `intro = null`, never fabricating eligibility, when no
     * such offer is present or its billing period can't be parsed. Ported
     * from sdks/flutter/coproduct/android/src/main/kotlin/app/coproduct/flutter/CoproductPaywallPlugin.kt's
     * packageFor.
     */
    override suspend fun packageFor(productId: String, kind: PackageKind): PaywallPackageRuntime {
        val productDetails = queryProductDetails(productId, kind)
        if (kind != PackageKind.SUBSCRIPTION) {
            val offer = productDetails.oneTimePurchaseOfferDetailsList?.firstOrNull()
                ?: throw IllegalStateException("No one-time offer found for product \"$productId\"")
            return PaywallPackageRuntime(price = offer.formattedPrice, intro = null)
        }
        val offers = productDetails.subscriptionOfferDetails
            ?: throw IllegalStateException("No subscription offer found for product \"$productId\"")
        // The regular price is the last pricing phase of any offer -- every
        // offer for the same base plan ends at the same recurring price,
        // whether or not it leads with an introductory phase.
        val regularPrice = offers.firstOrNull()?.pricingPhases?.pricingPhaseList?.lastOrNull()?.formattedPrice
            ?: throw IllegalStateException("No subscription offer found for product \"$productId\"")
        val intro = offers.firstNotNullOfOrNull { offer ->
            val phases = offer.pricingPhases.pricingPhaseList
            if (phases.size < 2) null else introOfferFor(phases.first(), regularPrice)
        }
        return PaywallPackageRuntime(price = regularPrice, intro = intro)
    }

    private fun introOfferFor(introPhase: ProductDetails.PricingPhase, regularPrice: String): PaywallIntroOffer? {
        val period = formatBillingPeriod(introPhase.billingPeriod) ?: return null
        val kind = when {
            introPhase.priceAmountMicros == 0L -> IntroOfferKind.FREE_TRIAL
            introPhase.recurrenceMode == ProductDetails.RecurrenceMode.NON_RECURRING -> IntroOfferKind.PAY_UP_FRONT
            else -> IntroOfferKind.PAY_AS_YOU_GO
        }
        val label = composeIntroLabel(kind, period, introPhase.formattedPrice, regularPrice)
        return PaywallIntroOffer(eligible = true, label = label)
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

    /**
     * Ends this bridge's Play Billing connection. The caller owns the
     * BillingClient's lifecycle (construction and startConnection, per this
     * class's own kdoc), so it also owns calling this from its teardown --
     * CoproductPaywall.destroy() calls this for the default bridge it
     * builds itself.
     */
    fun close() {
        billingClient.endConnection()
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

/**
 * Billing periods Play returns for a pricing phase are ISO 8601 durations
 * (e.g. "P1W", "P3M", "P1Y", "P7D") -- ordinary store SDKs just display the
 * price and never need this parsed, but the intro label needs its duration
 * spelled out in words ("7 days", "3 months"). Returns null, rather than a
 * best-effort guess, for a period this parser doesn't recognize (e.g. a
 * combined "P1Y6M"), which packageFor's caller treats as "can't cleanly
 * determine this offer" and fails safe to no intro. Ported from
 * sdks/flutter/coproduct/android/src/main/kotlin/app/coproduct/flutter/CoproductPaywallPlugin.kt.
 */
internal fun formatBillingPeriod(iso: String): String? {
    val match = Regex("^P(?:(\\d+)Y)?(?:(\\d+)M)?(?:(\\d+)W)?(?:(\\d+)D)?$").matchEntire(iso) ?: return null
    val (years, months, weeks, days) = match.destructured
    return when {
        years.isNotEmpty() && years != "0" -> pluralizePeriod(years.toInt(), "year")
        months.isNotEmpty() && months != "0" -> pluralizePeriod(months.toInt(), "month")
        weeks.isNotEmpty() && weeks != "0" -> pluralizePeriod(weeks.toInt(), "week")
        days.isNotEmpty() && days != "0" -> pluralizePeriod(days.toInt(), "day")
        else -> null
    }
}

private fun pluralizePeriod(count: Int, unit: String): String = "$count $unit${if (count == 1) "" else "s"}"
