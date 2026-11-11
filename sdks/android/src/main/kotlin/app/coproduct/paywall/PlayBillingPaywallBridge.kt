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
    /**
     * Decides whether a returned intro offer may be shown and bought. Play
     * filters `subscriptionOfferDetails` to eligible offers only for offers
     * whose eligibility Play itself determines (new customer acquisition,
     * upgrade, ...). Offers configured as "developer determined" are
     * returned to EVERY user, and Play exposes no field marking them. The
     * default therefore excludes any offer tagged
     * [DEVELOPER_DETERMINED_OFFER_TAG] in Play Console; apps with their own
     * eligibility logic pass a predicate instead.
     */
    private val isIntroOfferEligible: (ProductDetails.SubscriptionOfferDetails) -> Boolean = { offer ->
        DEVELOPER_DETERMINED_OFFER_TAG !in offer.offerTags
    },
    private val activityProvider: () -> android.app.Activity,
) : NativePaywallBridge, PurchasesUpdatedListener {

    companion object {
        /**
         * Play Console offer tag that marks a developer-determined offer the
         * default eligibility check must never present as a trial.
         */
        const val DEVELOPER_DETERMINED_OFFER_TAG = "cp-developer-determined"
    }

    private var pendingPurchase: PendingPurchase? = null

    private class PendingPurchase(
        val productId: String,
        val kind: PackageKind,
        val deferred: CompletableDeferred<PurchaseResult>,
    )

    override suspend fun priceFor(productId: String, kind: PackageKind): String {
        val productDetails = queryProductDetails(productId, kind)
        return if (kind == PackageKind.SUBSCRIPTION) {
            selectSubscriptionOffer(productId, productDetails).regularPhase.formattedPrice
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
     * queryProductDetails's `subscriptionOfferDetails` server-side to the
     * offers this Play account is eligible for -- except developer-determined
     * offers, which it returns to everyone; those are screened by
     * [isIntroOfferEligible]. Offer choice lives in [selectSubscriptionOffer]
     * and is shared with [purchase], so the offer labelled is the offer
     * bought. Consumable/lifetime
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
        val selection = selectSubscriptionOffer(productId, productDetails)
        return PaywallPackageRuntime(price = selection.regularPhase.formattedPrice, intro = selection.intro)
    }

    /**
     * The one offer a subscription package is both labelled and bought
     * with, so the paywall can never show one offer's trial and then
     * charge through another offer's token.
     */
    internal class SubscriptionOfferSelection(
        val offer: ProductDetails.SubscriptionOfferDetails,
        val regularPhase: ProductDetails.PricingPhase,
        val intro: PaywallIntroOffer?,
    )

    /**
     * Picks a single base plan (the one Play lists a plain base-plan offer
     * for first, else the first offer's), then within ONLY that base plan:
     * the regular price comes from the base-plan offer's recurring phase,
     * and the intro comes from the first eligible offer whose leading phase
     * is discounted below that regular price. Offers from other base plans
     * are ignored, so the price and the trial always describe the same
     * plan. Falls back to the base-plan offer with `intro = null` whenever
     * no offer can be cleanly labelled -- never a fabricated trial.
     */
    internal fun selectSubscriptionOffer(productId: String, productDetails: ProductDetails): SubscriptionOfferSelection {
        val offers = productDetails.subscriptionOfferDetails.orEmpty()
        if (offers.isEmpty()) throw IllegalStateException("No subscription offer found for product \"$productId\"")
        val basePlanId = (offers.firstOrNull { it.offerId == null } ?: offers.first()).basePlanId
        val planOffers = offers.filter { it.basePlanId == basePlanId }
        val baseOffer = planOffers.firstOrNull { it.offerId == null } ?: planOffers.first()
        val regularPhase = recurringPhase(baseOffer)
            ?: throw IllegalStateException("No subscription offer found for product \"$productId\"")

        for (offer in planOffers) {
            if (offer.offerId == null || !isIntroOfferEligible(offer)) continue
            val phases = offer.pricingPhases.pricingPhaseList
            if (phases.size < 2) continue
            val introPhase = phases.first()
            if (introPhase.priceAmountMicros >= regularPhase.priceAmountMicros) continue
            val label = introLabelFor(introPhase, regularPhase) ?: continue
            return SubscriptionOfferSelection(offer, regularPhase, PaywallIntroOffer(eligible = true, label = label))
        }
        return SubscriptionOfferSelection(baseOffer, regularPhase, intro = null)
    }

    private fun recurringPhase(offer: ProductDetails.SubscriptionOfferDetails): ProductDetails.PricingPhase? {
        val phases = offer.pricingPhases.pricingPhaseList
        return phases.lastOrNull { it.recurrenceMode == ProductDetails.RecurrenceMode.INFINITE_RECURRING }
            ?: phases.lastOrNull()
    }

    private fun introLabelFor(introPhase: ProductDetails.PricingPhase, regularPhase: ProductDetails.PricingPhase): String? {
        val kind = when {
            introPhase.priceAmountMicros == 0L -> IntroOfferKind.FREE_TRIAL
            introPhase.recurrenceMode == ProductDetails.RecurrenceMode.NON_RECURRING -> IntroOfferKind.PAY_UP_FRONT
            else -> IntroOfferKind.PAY_AS_YOU_GO
        }
        // A FINITE_RECURRING phase repeats its billingPeriod
        // billingCycleCount times ("$1.99/mo for 3 months" is P1M x 3); a
        // NON_RECURRING one is charged once for its whole billingPeriod.
        val cycles = if (introPhase.recurrenceMode == ProductDetails.RecurrenceMode.FINITE_RECURRING) {
            introPhase.billingCycleCount
        } else {
            1
        }
        val period = formatBillingPeriod(introPhase.billingPeriod, cycles) ?: return null
        val regularPrice = appendRenewalSuffix(regularPhase.formattedPrice, regularPhase.billingPeriod) ?: return null
        return composeIntroLabel(kind, period, introPhase.formattedPrice, regularPrice)
    }

    override suspend fun purchase(productId: String, kind: PackageKind): PurchaseResult {
        val productDetails = queryProductDetails(productId, kind)
        val offerToken = if (kind == PackageKind.SUBSCRIPTION) {
            selectSubscriptionOffer(productId, productDetails).offer.offerToken
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
 * (e.g. "P1W", "P3M", "P1Y", "P7D"). Parses exactly one non-zero
 * component; returns null for a combined period (e.g. "P1Y6M") or anything
 * unrecognized, which callers treat as "can't cleanly label this offer" and
 * fail safe to no intro.
 */
internal fun parseBillingPeriod(iso: String): Pair<Int, String>? {
    val match = Regex("^P(?:(\\d+)Y)?(?:(\\d+)M)?(?:(\\d+)W)?(?:(\\d+)D)?$").matchEntire(iso) ?: return null
    val components = match.groupValues.drop(1)
        .zip(listOf("year", "month", "week", "day"))
        .mapNotNull { (value, unit) -> value.toIntOrNull()?.takeIf { it > 0 }?.let { it to unit } }
    return components.singleOrNull()
}

/**
 * Spells out a billing period's TOTAL duration in words -- [cycles]
 * repetitions of [iso] -- e.g. ("P1M", 3) -> "3 months". Ported from
 * sdks/flutter/coproduct/android/src/main/kotlin/app/coproduct/flutter/CoproductPaywallPlugin.kt.
 */
internal fun formatBillingPeriod(iso: String, cycles: Int = 1): String? {
    val (count, unit) = parseBillingPeriod(iso) ?: return null
    val total = count * cycles.coerceAtLeast(1)
    return "$total $unit${if (total == 1) "" else "s"}"
}

/**
 * Appends a short renewal suffix for a single-unit recurring period, e.g.
 * ("$39.99", "P1Y") -> "$39.99/yr". A multi-unit period ("P3M") reads as
 * "$24.99 every 3 months". Returns null when the period can't be parsed.
 */
internal fun appendRenewalSuffix(formattedPrice: String, iso: String): String? {
    val (count, unit) = parseBillingPeriod(iso) ?: return null
    if (count != 1) return "$formattedPrice every $count ${unit}s"
    val suffix = when (unit) {
        "year" -> "/yr"
        "month" -> "/mo"
        "week" -> "/wk"
        else -> "/day"
    }
    return "$formattedPrice$suffix"
}
