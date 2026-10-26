package app.coproduct.flutter

import android.app.Activity
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.ProductDetailsResult
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.consumePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.slot
import io.mockk.unmockkStatic
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Unit tests against a mockk'd BillingClient -- no real Play Store
 * connection. Three parts of the MockK setup are load-bearing, not
 * incidental, and are verified against the real billing-ktx:9.1.0 jar:
 *
 * - `queryProductDetails`/`queryPurchasesAsync`/`consumePurchase`/
 *   `acknowledgePurchase` are top-level *extension* functions on
 *   BillingClient (in the generated facade class
 *   `com.android.billingclient.api.BillingClientKotlinKt`), not members.
 *   Without `mockkStatic` on that facade, `coEvery { billingClient
 *   .queryProductDetails(...) }` runs the real extension body against the
 *   bare mock and deadlocks the test thread.
 * - The real (unmocked) `BillingFlowParams.Builder.build()` call inside
 *   `purchase()` reaches `android.text.TextUtils.isEmpty(...)` internally.
 *   Plain `testDebugUnitTest` throws "not mocked" for any unmocked
 *   `android.*` static call, so this file gives it a real, scoped
 *   implementation rather than a module-wide `returnDefaultValues` override
 *   (which would make `isEmpty()` always return `false`, silently wrong for
 *   a null token).
 * - `ProductDetails.zza()`, `QueryProductDetailsParams.Product.zzb()`, and
 *   `QueryPurchasesParams.zza()` are this billing-ktx version's real public
 *   (if obfuscated-looking) accessors for fields with no documented getter,
 *   needed because real (unmocked) builder code reads them internally. All
 *   three are `public final` in billing-9.1.0 (verified with javap). If a
 *   future billing-ktx upgrade renames or removes them, this file fails to
 *   compile -- the safe failure mode -- rather than silently passing against
 *   a changed internal shape. Re-verify with javap before bumping the
 *   dependency version.
 */
class CoproductPaywallPluginTest {
    // purchase() hops to Dispatchers.Main.immediate to call launchBillingFlow
    // (Play Billing requires the main thread). A plain JVM unit test has no
    // Android main looper, so a TestDispatcher stands in for Main here.
    private val mainDispatcher = UnconfinedTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(mainDispatcher)
        mockkStatic("com.android.billingclient.api.BillingClientKotlinKt")
        mockkStatic(android.text.TextUtils::class)
        every { android.text.TextUtils.isEmpty(any()) } answers {
            (it.invocation.args[0] as? CharSequence).isNullOrEmpty()
        }
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        unmockkStatic("com.android.billingclient.api.BillingClientKotlinKt")
        unmockkStatic(android.text.TextUtils::class)
    }

    private fun fakeProductDetails(
        productId: String,
        formattedPrice: String,
        isSubscription: Boolean,
    ): ProductDetails {
        val productDetails = mockk<ProductDetails>()
        every { productDetails.productId } returns productId
        every { productDetails.oneTimePurchaseOfferDetails } returns null
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

    @Suppress("UNCHECKED_CAST")
    private fun QueryProductDetailsParams.firstRequestedProductType(): String {
        val products = this.zza() as List<QueryProductDetailsParams.Product>
        return products[0].zzb()
    }

    @Test
    fun `priceFor a subscription queries SUBS and reads the formatted price`() = runTest {
        val billingClient = mockk<BillingClient>()
        val plugin = CoproductPaywallPlugin()
        plugin.billingClientForTest = billingClient
        val details = fakeProductDetails("premium_monthly", "$9.99/mo", isSubscription = true)
        val paramsSlot = slot<QueryProductDetailsParams>()
        coEvery { billingClient.queryProductDetails(capture(paramsSlot)) } returns
            ProductDetailsResult(okResult(), listOf(details))

        val price = plugin.priceFor("premium_monthly", PackageKind.SUBSCRIPTION)

        assertEquals("$9.99/mo", price)
        assertEquals(BillingClient.ProductType.SUBS, paramsSlot.captured.firstRequestedProductType())
    }

    @Test
    fun `priceFor a consumable queries INAPP and reads the one-time offer price`() = runTest {
        val billingClient = mockk<BillingClient>()
        val plugin = CoproductPaywallPlugin()
        plugin.billingClientForTest = billingClient
        val details = fakeProductDetails("coins_100", "$1.99", isSubscription = false)
        val paramsSlot = slot<QueryProductDetailsParams>()
        coEvery { billingClient.queryProductDetails(capture(paramsSlot)) } returns
            ProductDetailsResult(okResult(), listOf(details))

        val price = plugin.priceFor("coins_100", PackageKind.CONSUMABLE)

        assertEquals("$1.99", price)
        assertEquals(BillingClient.ProductType.INAPP, paramsSlot.captured.firstRequestedProductType())
    }

    @Test
    fun `priceFor throws when no product is found`() = runTest {
        val billingClient = mockk<BillingClient>()
        val plugin = CoproductPaywallPlugin()
        plugin.billingClientForTest = billingClient
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), emptyList())

        assertThrows(Exception::class.java) {
            runBlocking { plugin.priceFor("missing_product", PackageKind.SUBSCRIPTION) }
        }
    }

    @Test
    fun `purchase of a subscription acknowledges (not consumes) on success`() = runTest {
        val billingClient = mockk<BillingClient>()
        val activity = mockk<Activity>()
        val plugin = CoproductPaywallPlugin()
        plugin.billingClientForTest = billingClient
        plugin.activity = activity
        val details = fakeProductDetails("premium_monthly", "$9.99/mo", isSubscription = true)
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), listOf(details))
        every { billingClient.launchBillingFlow(activity, any()) } answers {
            val purchase = mockk<Purchase> {
                every { products } returns listOf("premium_monthly")
                every { purchaseState } returns Purchase.PurchaseState.PURCHASED
                every { purchaseToken } returns "token-1"
                every { purchaseTime } returns 1700000000000L
            }
            plugin.onPurchasesUpdated(okResult(), listOf(purchase))
            okResult()
        }
        val ackSlot = slot<AcknowledgePurchaseParams>()
        coEvery { billingClient.acknowledgePurchase(capture(ackSlot)) } returns okResult()

        val result = plugin.purchase("premium_monthly", PackageKind.SUBSCRIPTION)

        assertEquals(PurchaseOutcome.SUCCESS, result.outcome)
        assertEquals("token-1", result.transactionId)
        assertEquals("premium_monthly", result.productId)
        assertEquals(1700000000000L, result.purchaseDateMillis)
        assertEquals("token-1", ackSlot.captured.purchaseToken)
        coVerify(exactly = 0) { billingClient.consumePurchase(any()) }
    }

    @Test
    fun `purchase of a consumable consumes (not acknowledges) on success`() = runTest {
        val billingClient = mockk<BillingClient>()
        val activity = mockk<Activity>()
        val plugin = CoproductPaywallPlugin()
        plugin.billingClientForTest = billingClient
        plugin.activity = activity
        val details = fakeProductDetails("coins_100", "$1.99", isSubscription = false)
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), listOf(details))
        every { billingClient.launchBillingFlow(activity, any()) } answers {
            val purchase = mockk<Purchase> {
                every { products } returns listOf("coins_100")
                every { purchaseState } returns Purchase.PurchaseState.PURCHASED
                every { purchaseToken } returns "token-2"
                every { purchaseTime } returns 1700000000000L
            }
            plugin.onPurchasesUpdated(okResult(), listOf(purchase))
            okResult()
        }
        val consumeSlot = slot<ConsumeParams>()
        coEvery { billingClient.consumePurchase(capture(consumeSlot)) } returns
            mockk { every { billingResult } returns okResult() }

        val result = plugin.purchase("coins_100", PackageKind.CONSUMABLE)

        assertEquals(PurchaseOutcome.SUCCESS, result.outcome)
        assertEquals("token-2", consumeSlot.captured.purchaseToken)
        coVerify(exactly = 0) { billingClient.acknowledgePurchase(any()) }
    }

    @Test
    fun `purchase still reports success when settlement throws, since the charge already happened`() = runTest {
        val billingClient = mockk<BillingClient>()
        val activity = mockk<Activity>()
        val plugin = CoproductPaywallPlugin()
        plugin.billingClientForTest = billingClient
        plugin.activity = activity
        val details = fakeProductDetails("premium_monthly", "$9.99/mo", isSubscription = true)
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), listOf(details))
        every { billingClient.launchBillingFlow(activity, any()) } answers {
            val purchase = mockk<Purchase> {
                every { products } returns listOf("premium_monthly")
                every { purchaseState } returns Purchase.PurchaseState.PURCHASED
                every { purchaseToken } returns "token-5"
                every { purchaseTime } returns 1700000000000L
            }
            plugin.onPurchasesUpdated(okResult(), listOf(purchase))
            okResult()
        }
        coEvery { billingClient.acknowledgePurchase(any()) } throws RuntimeException("ITEM_NOT_OWNED on a race")

        val result = plugin.purchase("premium_monthly", PackageKind.SUBSCRIPTION)

        assertEquals(PurchaseOutcome.SUCCESS, result.outcome)
        assertEquals("token-5", result.transactionId)
        coVerify(exactly = 1) { billingClient.acknowledgePurchase(any()) }
    }

    @Test
    fun `purchase resolves cancelled, not an error, on USER_CANCELED`() = runTest {
        val billingClient = mockk<BillingClient>()
        val activity = mockk<Activity>()
        val plugin = CoproductPaywallPlugin()
        plugin.billingClientForTest = billingClient
        plugin.activity = activity
        val details = fakeProductDetails("premium_monthly", "$9.99/mo", isSubscription = true)
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), listOf(details))
        every { billingClient.launchBillingFlow(activity, any()) } answers {
            val cancelResult = mockk<BillingResult> {
                every { responseCode } returns BillingClient.BillingResponseCode.USER_CANCELED
            }
            plugin.onPurchasesUpdated(cancelResult, null)
            okResult()
        }

        val result = plugin.purchase("premium_monthly", PackageKind.SUBSCRIPTION)

        assertEquals(PurchaseOutcome.CANCELLED, result.outcome)
        coVerify(exactly = 0) { billingClient.acknowledgePurchase(any()) }
    }

    @Test
    fun `purchase resolves pending, not an error, when the reported purchase is PENDING`() = runTest {
        val billingClient = mockk<BillingClient>()
        val activity = mockk<Activity>()
        val plugin = CoproductPaywallPlugin()
        plugin.billingClientForTest = billingClient
        plugin.activity = activity
        val details = fakeProductDetails("premium_monthly", "$9.99/mo", isSubscription = true)
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), listOf(details))
        every { billingClient.launchBillingFlow(activity, any()) } answers {
            val purchase = mockk<Purchase> {
                every { products } returns listOf("premium_monthly")
                every { purchaseState } returns Purchase.PurchaseState.PENDING
                every { purchaseToken } returns "token-4"
            }
            plugin.onPurchasesUpdated(okResult(), listOf(purchase))
            okResult()
        }

        val result = plugin.purchase("premium_monthly", PackageKind.SUBSCRIPTION)

        assertEquals(PurchaseOutcome.PENDING, result.outcome)
        coVerify(exactly = 0) { billingClient.acknowledgePurchase(any()) }
    }

    @Test
    fun `purchase throws on any other error response code`() = runTest {
        val billingClient = mockk<BillingClient>()
        val activity = mockk<Activity>()
        val plugin = CoproductPaywallPlugin()
        plugin.billingClientForTest = billingClient
        plugin.activity = activity
        val details = fakeProductDetails("premium_monthly", "$9.99/mo", isSubscription = true)
        coEvery { billingClient.queryProductDetails(any()) } returns
            ProductDetailsResult(okResult(), listOf(details))
        every { billingClient.launchBillingFlow(activity, any()) } answers {
            val errorResult = mockk<BillingResult> {
                every { responseCode } returns BillingClient.BillingResponseCode.ERROR
                every { debugMessage } returns "network error"
            }
            plugin.onPurchasesUpdated(errorResult, null)
            okResult()
        }

        assertThrows(Exception::class.java) {
            runBlocking { plugin.purchase("premium_monthly", PackageKind.SUBSCRIPTION) }
        }
    }

    @Test
    fun `purchase throws a NoActivityException when no activity is attached`() = runTest {
        val billingClient = mockk<BillingClient>()
        val plugin = CoproductPaywallPlugin()
        plugin.billingClientForTest = billingClient
        plugin.activity = null

        // No queryProductDetails/launchBillingFlow stub is installed: the
        // Activity check must run before either, so this must throw without
        // ever touching the (unmocked, thus deadlock-prone per this file's
        // class kdoc) billing-ktx extension functions.
        assertThrows(NoActivityException::class.java) {
            runBlocking { plugin.purchase("premium_monthly", PackageKind.SUBSCRIPTION) }
        }
    }

    @Test
    fun `restore queries both SUBS and INAPP and acknowledges unacknowledged purchases`() = runTest {
        val billingClient = mockk<BillingClient>()
        val plugin = CoproductPaywallPlugin()
        plugin.billingClientForTest = billingClient
        val subsPurchase = mockk<Purchase> {
            every { products } returns listOf("premium_monthly")
            every { purchaseToken } returns "subs-token"
            every { purchaseTime } returns 1700000000000L
            every { isAcknowledged } returns false
        }
        val inappPurchase = mockk<Purchase> {
            every { products } returns listOf("coins_100")
            every { purchaseToken } returns "inapp-token"
            every { purchaseTime } returns 1700000001000L
            every { isAcknowledged } returns true
        }
        coEvery {
            billingClient.queryPurchasesAsync(match<QueryPurchasesParams> { it.zza() == BillingClient.ProductType.SUBS })
        } returns mockk { every { billingResult } returns okResult(); every { purchasesList } returns listOf(subsPurchase) }
        coEvery {
            billingClient.queryPurchasesAsync(match<QueryPurchasesParams> { it.zza() == BillingClient.ProductType.INAPP })
        } returns mockk { every { billingResult } returns okResult(); every { purchasesList } returns listOf(inappPurchase) }
        coEvery { billingClient.acknowledgePurchase(any()) } returns okResult()

        val restored = plugin.restore()

        assertEquals(2, restored.size)
        assertEquals("subs-token", restored[0].transactionId)
        assertEquals("premium_monthly", restored[0].productId)
        assertEquals("inapp-token", restored[1].transactionId)
        coVerify(exactly = 1) { billingClient.acknowledgePurchase(any()) } // only the unacknowledged one
        coVerify(exactly = 0) { billingClient.consumePurchase(any()) } // restore never consumes
    }

    @Test
    fun `restore returns an empty list when nothing is found`() = runTest {
        val billingClient = mockk<BillingClient>()
        val plugin = CoproductPaywallPlugin()
        plugin.billingClientForTest = billingClient
        coEvery { billingClient.queryPurchasesAsync(any<QueryPurchasesParams>()) } returns
            mockk { every { billingResult } returns okResult(); every { purchasesList } returns emptyList() }

        val restored = plugin.restore()

        assertTrue(restored.isEmpty())
    }
}
