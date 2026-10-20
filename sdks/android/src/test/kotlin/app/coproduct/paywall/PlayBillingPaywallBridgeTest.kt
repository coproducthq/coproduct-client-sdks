package app.coproduct.paywall

import app.coproduct.paywall.models.PackageKind
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.ProductDetailsResult
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.consumePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.slot
import io.mockk.unmockkStatic
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test

/**
 * Verified against the real com.android.billingclient:billing-ktx:9.1.0 jar
 * (decompiled via javap against the AAR's classes.jar in the Gradle cache --
 * see the Task 5 report for exact commands) before writing this file:
 *
 * - The ktx suspend extension is `queryPurchasesAsync`, not `queryPurchases`
 *   as originally assumed -- BillingClientKotlinKt.queryPurchasesAsync(BillingClient,
 *   QueryPurchasesParams, Continuation<PurchasesResult>).
 * - The ktx suspend extension `queryProductDetails` returns the ktx-only
 *   `ProductDetailsResult` (billingResult + productDetailsList), NOT the raw
 *   billing library's `QueryProductDetailsResult` (which is what the
 *   callback-based OnProductDetailsResponseListener receives, and is a
 *   different class with its own `.create(...)` factory that doesn't apply
 *   here).
 * - `ProductDetails.OneTimePurchaseOfferDetails.getFormattedPrice()` and
 *   `ProductDetails.PricingPhase.getFormattedPrice()` are both confirmed
 *   public -- `formattedPrice` was the right guess.
 * - `QueryProductDetailsParams.Product` and `QueryPurchasesParams` do NOT
 *   expose documented `productId`/`productType`/`productList` getters in
 *   this version -- only the request-builder setters are public. The built
 *   objects do carry public (but internally-named) accessor methods --
 *   `QueryProductDetailsParams.zza()` returns the product list,
 *   `QueryProductDetailsParams.Product.zza()`/`zzb()` return productId/
 *   productType respectively, and `QueryPurchasesParams.zza()` returns
 *   productType -- confirmed by disassembling the Builder's bytecode
 *   (javap -c) to trace exactly which Builder field each setter writes and
 *   which field the Product/QueryPurchasesParams constructor reads back, not
 *   by guessing from naming/declaration order. These are what this file
 *   uses below to assert SUBS vs INAPP was requested; if a future
 *   billing-ktx upgrade renames/removes them, this file will fail to
 *   compile (not silently pass), which is the safe failure mode.
 *
 * Also discovered while getting these tests to actually run (not from the
 * jar, but from a real deadlock observed via jstack): `coEvery { billingClient
 * .queryProductDetails(...) }` on a bare, non-static-mocked BillingClient mock
 * hangs forever. `queryProductDetails`/`queryPurchasesAsync`/`consumePurchase`/
 * `acknowledgePurchase` are top-level *extension* functions, not members of
 * BillingClient -- so during coEvery's recording pass, MockK actually runs
 * the real extension function body (only `billingClient` itself is a mock,
 * the extension function is not). That real body wraps the callback-based
 * BillingClient API (queryProductDetailsAsync, etc.) in
 * suspendCancellableCoroutine; since the bare mock's callback-based method is
 * unstubbed at that point, the callback never fires and the coroutine never
 * resumes -- and because MockK's recorder drives this via a blocking
 * runCoroutine/runBlocking, the whole test thread deadlocks. mockkStatic on
 * the generated facade class (BillingClientKotlinKt, confirmed via javap)
 * makes MockK intercept these calls at the extension-function level instead
 * of running their real bodies, which is required for `coEvery` on any of
 * them to work at all here.
 *
 * Also required: real (unmocked) BillingFlowParams.Builder.build() always
 * constructs a default BillingFlowParams.SubscriptionUpdateParams internally
 * (even though this bridge never calls setSubscriptionUpdateParams), and
 * that nested Builder's build() branches on
 * android.text.TextUtils.isEmpty(...). This module's testOptions already set
 * isReturnDefaultValues = true so unmocked android.* calls don't throw, but
 * that makes every stubbed Android method return its primitive default --
 * isEmpty() always returning `false` is wrong here (a null token IS empty)
 * and sends that real validation logic down the wrong branch
 * ("...not both" instead of treating neither as provided). So
 * TextUtils.isEmpty specifically needs a real implementation, not the
 * blanket default.
 */
class PlayBillingPaywallBridgeTest {
    @Before
    fun setUp() {
        mockkStatic("com.android.billingclient.api.BillingClientKotlinKt")
        mockkStatic(android.text.TextUtils::class)
        every { android.text.TextUtils.isEmpty(any()) } answers {
            (it.invocation.args[0] as? CharSequence).isNullOrEmpty()
        }
    }

    @After
    fun tearDown() {
        unmockkStatic("com.android.billingclient.api.BillingClientKotlinKt")
        unmockkStatic(android.text.TextUtils::class)
    }

    private fun fakeProductDetails(productId: String, formattedPrice: String, isSubscription: Boolean): ProductDetails {
        val productDetails = mockk<ProductDetails>()
        every { productDetails.productId } returns productId
        // BillingFlowParams.ProductDetailsParams.Builder.setProductDetails() --
        // real, unmocked code -- reads this singular (legacy, pre-multi-offer)
        // getter itself (confirmed via javap -c disassembly) to opportunistically
        // default an offer token before our own .setOfferToken(...) overwrites
        // it; our bridge never reads this field, but the mock must answer it or
        // purchase() throws MockKException before ever reaching our logic.
        every { productDetails.oneTimePurchaseOfferDetails } returns null
        // BillingFlowParams.Builder.build() -- also real, unmocked code --
        // reads ProductDetails' internal (obfuscated-but-public, see this
        // file's class kdoc) packageName accessor `zza()` to decide an
        // internal flag unrelated to anything this bridge or its tests
        // assert on; must still be answered or the mock throws.
        every { productDetails.zza() } returns ""
        if (isSubscription) {
            val pricingPhase = mockk<ProductDetails.PricingPhase> {
                every { this@mockk.formattedPrice } returns formattedPrice
            }
            val offer = mockk<ProductDetails.SubscriptionOfferDetails> {
                every { offerToken } returns "offer-token-$productId"
                every { pricingPhases.pricingPhaseList } returns listOf(pricingPhase)
            }
            every { productDetails.subscriptionOfferDetails } returns listOf(offer)
        } else {
            val offer = mockk<ProductDetails.OneTimePurchaseOfferDetails> {
                every { offerToken } returns "offer-token-$productId"
                every { this@mockk.formattedPrice } returns formattedPrice
            }
            every { productDetails.oneTimePurchaseOfferDetailsList } returns listOf(offer)
        }
        return productDetails
    }

    private fun okResult(): BillingResult = mockk {
        every { responseCode } returns BillingClient.BillingResponseCode.OK
    }

    /**
     * See this file's class kdoc: QueryProductDetailsParams.Product has no
     * public getProductType(); `zzb()` is the real (verified via javap -c)
     * public accessor for it on this pinned billing-ktx version.
     */
    @Suppress("UNCHECKED_CAST")
    private fun QueryProductDetailsParams.firstRequestedProductType(): String {
        val products = this.zza() as List<QueryProductDetailsParams.Product>
        return products[0].zzb()
    }

    @Test
    fun `priceFor a subscription queries SUBS and reads the base plan's formatted price`() = runTest {
        val billingClient = mockk<BillingClient>()
        val productDetails = fakeProductDetails("premium_monthly", "$9.99/mo", isSubscription = true)
        val paramsSlot = slot<QueryProductDetailsParams>()
        coEvery { billingClient.queryProductDetails(capture(paramsSlot)) } returns
            ProductDetailsResult(okResult(), listOf(productDetails))

        val bridge = PlayBillingPaywallBridge(billingClient)
        val price = bridge.priceFor("premium_monthly", PackageKind.SUBSCRIPTION)

        assertEquals("$9.99/mo", price)
        assertEquals(
            BillingClient.ProductType.SUBS,
            paramsSlot.captured.firstRequestedProductType(),
        )
    }

    @Test
    fun `priceFor a consumable queries INAPP and reads the one-time offer's formatted price`() = runTest {
        val billingClient = mockk<BillingClient>()
        val productDetails = fakeProductDetails("points_pack_300", "$4.99", isSubscription = false)
        val paramsSlot = slot<QueryProductDetailsParams>()
        coEvery { billingClient.queryProductDetails(capture(paramsSlot)) } returns
            ProductDetailsResult(okResult(), listOf(productDetails))

        val bridge = PlayBillingPaywallBridge(billingClient)
        val price = bridge.priceFor("points_pack_300", PackageKind.CONSUMABLE)

        assertEquals("$4.99", price)
        assertEquals(
            BillingClient.ProductType.INAPP,
            paramsSlot.captured.firstRequestedProductType(),
        )
    }

    @Test
    fun `priceFor a lifetime product also queries INAPP`() = runTest {
        val billingClient = mockk<BillingClient>()
        val productDetails = fakeProductDetails("remove_ads", "$19.99", isSubscription = false)
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), listOf(productDetails))

        val bridge = PlayBillingPaywallBridge(billingClient)
        assertEquals("$19.99", bridge.priceFor("remove_ads", PackageKind.LIFETIME))
    }

    @Test
    fun `priceFor throws when no product is found`() = runTest {
        val billingClient = mockk<BillingClient>()
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), emptyList())

        val bridge = PlayBillingPaywallBridge(billingClient)
        assertThrows(Exception::class.java) {
            kotlinx.coroutines.runBlocking { bridge.priceFor("unknown", PackageKind.SUBSCRIPTION) }
        }
    }

    @Test
    fun `purchase of a subscription acknowledges (not consumes) on success`() = runTest {
        val billingClient = mockk<BillingClient>()
        val productDetails = fakeProductDetails("premium_monthly", "$9.99/mo", isSubscription = true)
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), listOf(productDetails))
        val bridge = PlayBillingPaywallBridge(billingClient)
        every { billingClient.launchBillingFlow(any(), any()) } answers {
            val purchase = mockk<Purchase> {
                every { products } returns listOf("premium_monthly")
                every { purchaseState } returns Purchase.PurchaseState.PURCHASED
                every { purchaseToken } returns "token-1"
                every { orderId } returns "order-1"
                every { purchaseTime } returns 1700000000000L
                every { isAcknowledged } returns false
            }
            bridge.onPurchasesUpdated(okResult(), listOf(purchase))
            okResult()
        }
        val ackSlot = slot<AcknowledgePurchaseParams>()
        coEvery { billingClient.acknowledgePurchase(capture(ackSlot)) } returns okResult()

        val result = bridge.purchase("premium_monthly", PackageKind.SUBSCRIPTION)

        assertEquals(PurchaseOutcome.SUCCESS, result.outcome)
        assertEquals("token-1", result.transactionId)
        assertEquals("premium_monthly", result.productId)
        assertEquals("token-1", ackSlot.captured.purchaseToken)
        io.mockk.coVerify(exactly = 0) { billingClient.consumePurchase(any()) }
    }

    @Test
    fun `purchase of a consumable consumes (not acknowledges) on success`() = runTest {
        val billingClient = mockk<BillingClient>()
        val productDetails = fakeProductDetails("points_pack_300", "$4.99", isSubscription = false)
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), listOf(productDetails))
        val bridge = PlayBillingPaywallBridge(billingClient)
        every { billingClient.launchBillingFlow(any(), any()) } answers {
            val purchase = mockk<Purchase> {
                every { products } returns listOf("points_pack_300")
                every { purchaseState } returns Purchase.PurchaseState.PURCHASED
                every { purchaseToken } returns "token-2"
                every { orderId } returns "order-2"
                every { purchaseTime } returns 1700000000000L
                every { isAcknowledged } returns false
            }
            bridge.onPurchasesUpdated(okResult(), listOf(purchase))
            okResult()
        }
        val consumeSlot = slot<ConsumeParams>()
        coEvery { billingClient.consumePurchase(capture(consumeSlot)) } returns
            mockk { every { billingResult } returns okResult() }

        val result = bridge.purchase("points_pack_300", PackageKind.CONSUMABLE)

        assertEquals(PurchaseOutcome.SUCCESS, result.outcome)
        assertEquals("token-2", consumeSlot.captured.purchaseToken)
        io.mockk.coVerify(exactly = 0) { billingClient.acknowledgePurchase(any()) }
    }

    @Test
    fun `purchase of a lifetime product consumes nothing but acknowledges, like a subscription`() = runTest {
        val billingClient = mockk<BillingClient>()
        val productDetails = fakeProductDetails("remove_ads", "$19.99", isSubscription = false)
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), listOf(productDetails))
        val bridge = PlayBillingPaywallBridge(billingClient)
        every { billingClient.launchBillingFlow(any(), any()) } answers {
            val purchase = mockk<Purchase> {
                every { products } returns listOf("remove_ads")
                every { purchaseState } returns Purchase.PurchaseState.PURCHASED
                every { purchaseToken } returns "token-3"
                every { orderId } returns "order-3"
                every { purchaseTime } returns 1700000000000L
                every { isAcknowledged } returns false
            }
            bridge.onPurchasesUpdated(okResult(), listOf(purchase))
            okResult()
        }
        coEvery { billingClient.acknowledgePurchase(any()) } returns okResult()

        val result = bridge.purchase("remove_ads", PackageKind.LIFETIME)

        assertEquals(PurchaseOutcome.SUCCESS, result.outcome)
        io.mockk.coVerify(exactly = 1) { billingClient.acknowledgePurchase(any()) }
        io.mockk.coVerify(exactly = 0) { billingClient.consumePurchase(any()) }
    }

    @Test
    fun `purchase resolves cancelled, not an error, on USER_CANCELED`() = runTest {
        val billingClient = mockk<BillingClient>()
        val productDetails = fakeProductDetails("premium_monthly", "$9.99/mo", isSubscription = true)
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), listOf(productDetails))
        val bridge = PlayBillingPaywallBridge(billingClient)
        every { billingClient.launchBillingFlow(any(), any()) } answers {
            val cancelResult = mockk<BillingResult> {
                every { responseCode } returns BillingClient.BillingResponseCode.USER_CANCELED
            }
            bridge.onPurchasesUpdated(cancelResult, null)
            okResult()
        }

        val result = bridge.purchase("premium_monthly", PackageKind.SUBSCRIPTION)

        assertEquals(PurchaseOutcome.CANCELLED, result.outcome)
        io.mockk.coVerify(exactly = 0) { billingClient.acknowledgePurchase(any()) }
    }

    @Test
    fun `purchase resolves pending, not an error, when the reported purchase is PENDING`() = runTest {
        val billingClient = mockk<BillingClient>()
        val productDetails = fakeProductDetails("premium_monthly", "$9.99/mo", isSubscription = true)
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), listOf(productDetails))
        val bridge = PlayBillingPaywallBridge(billingClient)
        every { billingClient.launchBillingFlow(any(), any()) } answers {
            val purchase = mockk<Purchase> {
                every { products } returns listOf("premium_monthly")
                every { purchaseState } returns Purchase.PurchaseState.PENDING
                every { purchaseToken } returns "token-4"
            }
            bridge.onPurchasesUpdated(okResult(), listOf(purchase))
            okResult()
        }

        val result = bridge.purchase("premium_monthly", PackageKind.SUBSCRIPTION)

        assertEquals(PurchaseOutcome.PENDING, result.outcome)
        io.mockk.coVerify(exactly = 0) { billingClient.acknowledgePurchase(any()) }
    }

    @Test
    fun `purchase throws on any other error response code`() = runTest {
        val billingClient = mockk<BillingClient>()
        val productDetails = fakeProductDetails("premium_monthly", "$9.99/mo", isSubscription = true)
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), listOf(productDetails))
        val bridge = PlayBillingPaywallBridge(billingClient)
        every { billingClient.launchBillingFlow(any(), any()) } answers {
            val errorResult = mockk<BillingResult> {
                every { responseCode } returns BillingClient.BillingResponseCode.ERROR
                every { debugMessage } returns "network error"
            }
            bridge.onPurchasesUpdated(errorResult, null)
            okResult()
        }

        assertThrows(Exception::class.java) {
            kotlinx.coroutines.runBlocking { bridge.purchase("premium_monthly", PackageKind.SUBSCRIPTION) }
        }
    }

    @Test
    fun `restore queries both SUBS and INAPP, acknowledges unacknowledged purchases, and never consumes`() = runTest {
        val billingClient = mockk<BillingClient>()
        val subsPurchase = mockk<Purchase> {
            every { products } returns listOf("premium_monthly")
            every { purchaseToken } returns "sub-token"
            every { orderId } returns "sub-order"
            every { purchaseTime } returns 1700000000000L
            every { isAcknowledged } returns false
        }
        val inappPurchase = mockk<Purchase> {
            every { products } returns listOf("remove_ads")
            every { purchaseToken } returns "lifetime-token"
            every { orderId } returns "lifetime-order"
            every { purchaseTime } returns 1700000001000L
            every { isAcknowledged } returns true
        }
        coEvery { billingClient.queryPurchasesAsync(match { it.zza() == BillingClient.ProductType.SUBS }) } returns
            mockk { every { billingResult } returns okResult(); every { purchasesList } returns listOf(subsPurchase) }
        coEvery { billingClient.queryPurchasesAsync(match { it.zza() == BillingClient.ProductType.INAPP }) } returns
            mockk { every { billingResult } returns okResult(); every { purchasesList } returns listOf(inappPurchase) }
        coEvery { billingClient.acknowledgePurchase(any()) } returns okResult()

        val bridge = PlayBillingPaywallBridge(billingClient)
        val restored = bridge.restore()

        assertEquals(2, restored.size)
        assertEquals("sub-token", restored[0].transactionId)
        assertEquals("lifetime-token", restored[1].transactionId)
        io.mockk.coVerify(exactly = 1) { billingClient.acknowledgePurchase(any()) } // only the unacknowledged one
        io.mockk.coVerify(exactly = 0) { billingClient.consumePurchase(any()) } // restore never consumes
    }

    @Test
    fun `restore returns an empty list when nothing is found`() = runTest {
        val billingClient = mockk<BillingClient>()
        coEvery { billingClient.queryPurchasesAsync(any()) } returns
            mockk { every { billingResult } returns okResult(); every { purchasesList } returns emptyList() }

        val bridge = PlayBillingPaywallBridge(billingClient)
        assertEquals(emptyList<RestoredTransaction>(), bridge.restore())
    }
}
