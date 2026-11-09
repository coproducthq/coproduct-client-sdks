package app.coproduct.flutter

import android.app.Activity
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.consumePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What kind of store product a productId is, as sent over the method
 * channel by the Dart PackageKind enum (its uppercase name arrives
 * literally as the "kind" argument). Determines the Play Billing product
 * type (SUBSCRIPTION -> SUBS, CONSUMABLE/LIFETIME -> INAPP) and whether a
 * successful purchase is consumed or acknowledged. */
enum class PackageKind { SUBSCRIPTION, CONSUMABLE, LIFETIME }

enum class PurchaseOutcome { SUCCESS, CANCELLED, PENDING }

/** Thrown by purchase() when no Activity is attached (e.g. a purchase
 * attempted before the engine has one). Distinct from the generic
 * IllegalStateException the rest of this class throws, so onMethodCall can
 * map it to its own "NO_ACTIVITY" channel error code instead of the
 * catch-all "BILLING_ERROR". */
class NoActivityException(message: String) : IllegalStateException(message)

/** What this plugin reports back to Dart for one purchase attempt or one
 * restored transaction. purchaseDateMillis/expirationDateMillis cross the
 * channel as millis-since-epoch, matching the iOS plugin's StandardMethodCodec
 * encoding exactly. */
class PurchaseResult(
    val outcome: PurchaseOutcome,
    val transactionId: String? = null,
    val productId: String? = null,
    val purchaseDateMillis: Long? = null,
    val expirationDateMillis: Long? = null,
)

class RestoredTransaction(
    val transactionId: String,
    val productId: String,
    val purchaseDateMillis: Long,
    val expirationDateMillis: Long? = null,
)

/**
 * The native side of app.coproduct.flutter/paywall on Android: Play Billing
 * price lookup, purchase, and restore. Deliberately small -- it holds no SDK
 * state, knows nothing about the SDK key, and performs no network call of
 * its own beyond what Play Billing itself makes. PaywallRuntime (Dart) owns
 * reporting a completed transaction to Coproduct's backend.
 *
 * This mirrors ios/Classes/CoproductPaywallPlugin.swift's role exactly: it
 * answers the same priceFor/purchase/restore method channel, returns the
 * same wire shape (dates as millis-since-epoch; the Play purchaseToken takes
 * the place of StoreKit's transactionId), and is registered the same way --
 * never as its own top-level pluginClass. Android's v2 embedding only
 * delivers Activity lifecycle callbacks to a class the engine's plugin
 * registry holds directly, so CoproductHostContextPlugin constructs and
 * attaches this class itself and forwards its own ActivityAware callbacks to
 * it, the structural counterpart of iOS's
 * CoproductHostContextPlugin.register(with:) chaining
 * CoproductPaywallPlugin.register(with:).
 *
 * The Android-specific billing behavior (subscription offer tokens, consume
 * vs. acknowledge, pending purchases arriving through the update listener)
 * matches the React Native paywall bridge,
 * sdks/react-native/coproduct/src/paywall/iapPaywallBridge.ts.
 */
class CoproductPaywallPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, PurchasesUpdatedListener {
    @Volatile private var channel: MethodChannel? = null
    @Volatile private var billingClient: BillingClient? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /** Set by CoproductHostContextPlugin's forwarded onAttachedToActivity /
     * onDetachedFromActivity. purchase() fails fast with a clear error when
     * this is null, e.g. a purchase attempted before the engine has an
     * Activity. */
    @Volatile var activity: Activity? = null

    /** Test-only seam: a real connection needs a live Play Store, so unit
     * tests inject a mockk'd BillingClient here instead of going through
     * onAttachedToEngine. */
    @Volatile internal var billingClientForTest: BillingClient? = null

    private var pendingPurchase: PendingPurchase? = null

    private class PendingPurchase(
        val productId: String,
        val kind: PackageKind,
        val deferred: CompletableDeferred<PurchaseResult>,
    )

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val client = BillingClient.newBuilder(binding.applicationContext)
            .setListener(this)
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .enableAutoServiceReconnection()
            .build()
        billingClient = client
        client.startConnection(object : com.android.billingclient.api.BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                // Connection failures surface per-call as thrown exceptions from
                // priceFor/purchase/restore rather than here -- there is no
                // separate "billing unavailable" channel method on the Dart side
            }
            override fun onBillingServiceDisconnected() {
                // enableAutoServiceReconnection() handles retry; nothing to do here.
            }
        })
        channel = registerChannel(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        billingClient?.endConnection()
        billingClient = null
        scope.cancel()
    }

    private fun activeBillingClient(): BillingClient =
        billingClientForTest ?: billingClient
            ?: throw IllegalStateException("CoproductPaywallPlugin's BillingClient is not attached to an engine")

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        when (call.method) {
            "priceFor" -> {
                val productId = args?.get("productId") as? String
                val kind = parseKind(args?.get("kind") as? String)
                if (productId == null) {
                    result.error("INVALID_ARGUMENTS", "productId is required", null)
                    return
                }
                scope.launch {
                    try {
                        result.success(priceFor(productId, kind))
                    } catch (e: Exception) {
                        result.error("BILLING_ERROR", e.message, null)
                    }
                }
            }
            "purchase" -> {
                val productId = args?.get("productId") as? String
                val kind = parseKind(args?.get("kind") as? String)
                if (productId == null) {
                    result.error("INVALID_ARGUMENTS", "productId is required", null)
                    return
                }
                scope.launch {
                    try {
                        result.success(purchase(productId, kind).toChannelMap())
                    } catch (e: NoActivityException) {
                        result.error("NO_ACTIVITY", e.message, null)
                    } catch (e: Exception) {
                        result.error("BILLING_ERROR", e.message, null)
                    }
                }
            }
            "restore" -> scope.launch {
                try {
                    result.success(restore().map { it.toChannelMap() })
                } catch (e: Exception) {
                    result.error("BILLING_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    internal suspend fun priceFor(productId: String, kind: PackageKind): String {
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

    internal suspend fun purchase(productId: String, kind: PackageKind): PurchaseResult {
        val currentActivity = activity
            ?: throw NoActivityException("No Activity is attached; cannot launch a billing flow")

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

        // launchBillingFlow must be called from the main thread per the Play
        // Billing docs; this method itself runs on Dispatchers.IO (see the
        // scope this is launched on in onMethodCall), so this one call hops
        // back to the main thread rather than the whole method running there
        val launchResult = withContext(Dispatchers.Main.immediate) {
            activeBillingClient().launchBillingFlow(currentActivity, params)
        }
        if (launchResult.responseCode != BillingClient.BillingResponseCode.OK) {
            pendingPurchase = null
            throw IllegalStateException("launchBillingFlow failed: ${launchResult.debugMessage}")
        }

        return deferred.await()
    }

    internal suspend fun restore(): List<RestoredTransaction> {
        val subsResult = activeBillingClient().queryPurchasesAsync(
            QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build()
        )
        val inappResult = activeBillingClient().queryPurchasesAsync(
            QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()
        )
        val restored = mutableListOf<RestoredTransaction>()
        for (purchase in subsResult.purchasesList + inappResult.purchasesList) {
            if (!purchase.isAcknowledged) {
                activeBillingClient().acknowledgePurchase(
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

    private fun handleUpdatedPurchase(pending: PendingPurchase, purchase: Purchase) {
        if (purchase.purchaseState == Purchase.PurchaseState.PENDING) {
            pending.deferred.complete(PurchaseResult(outcome = PurchaseOutcome.PENDING))
            return
        }
        // Settle (consume or acknowledge) before completing the deferred: Play
        // Billing auto-refunds an unsettled purchase within 3 days, so a later
        // backend-recording failure must never leave a purchase unsettled.
        // This runs on the plugin's own scope rather than inline, since
        // onPurchasesUpdated is a synchronous callback with no suspend path
        // out -- settlement must still complete even if the caller that
        // triggered this specific purchase has since moved on.
        scope.launch {
            try {
                if (pending.kind == PackageKind.CONSUMABLE) {
                    activeBillingClient().consumePurchase(
                        ConsumeParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
                    )
                } else {
                    activeBillingClient().acknowledgePurchase(
                        AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
                    )
                }
            } catch (_: Exception) {
                // Settlement failure must not block reporting the purchase --
                // the charge already happened
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
        activeBillingClient().queryProductDetails(
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

    companion object {
        internal const val CHANNEL_NAME = "app.coproduct.flutter/paywall"

        /** Mirrors CoproductHostContextPlugin.registerChannel: a background
         * task queue, because Play Billing's suspend calls must not run on
         * the platform thread. Separate from attach so a test can see which
         * queue the channel registered with. */
        internal fun registerChannel(
            messenger: BinaryMessenger,
            handler: MethodChannel.MethodCallHandler,
        ): MethodChannel {
            val taskQueue = messenger.makeBackgroundTaskQueue()
            return MethodChannel(messenger, CHANNEL_NAME, StandardMethodCodec.INSTANCE, taskQueue)
                .also { it.setMethodCallHandler(handler) }
        }

        private fun parseKind(value: String?): PackageKind =
            when (value) {
                "CONSUMABLE" -> PackageKind.CONSUMABLE
                "LIFETIME" -> PackageKind.LIFETIME
                else -> PackageKind.SUBSCRIPTION
            }
    }
}

private fun PurchaseResult.toChannelMap(): Map<String, Any?> = mapOf(
    "outcome" to outcome.name.lowercase(),
    "transactionId" to transactionId,
    "productId" to productId,
    "purchaseDate" to purchaseDateMillis,
    "expirationDate" to expirationDateMillis,
)

private fun RestoredTransaction.toChannelMap(): Map<String, Any?> = mapOf(
    "transactionId" to transactionId,
    "productId" to productId,
    "purchaseDate" to purchaseDateMillis,
    "expirationDate" to expirationDateMillis,
)
