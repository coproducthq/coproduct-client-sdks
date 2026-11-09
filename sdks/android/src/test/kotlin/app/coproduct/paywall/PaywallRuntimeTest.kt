package app.coproduct.paywall

import app.coproduct.paywall.models.Entitlement
import app.coproduct.paywall.models.PackageKind
import app.coproduct.paywall.models.PaywallContent
import app.coproduct.paywall.models.PaywallCta
import app.coproduct.paywall.models.PaywallPackageRef
import app.coproduct.paywall.models.PaywallSnapshot
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PaywallRuntimeTest {
    private fun snapshotWith(packages: Map<String, PaywallPackageRef>) = PaywallSnapshot(
        paywallId = "p-1",
        version = 1,
        templateType = "hero_single_offer",
        content = PaywallContent(
            offeringKey = "default",
            ctas = packages.keys.map { PaywallCta(packageKey = it, label = it) },
            html = "<div/>",
        ),
        packages = packages,
        html = "<div/>",
    )

    @Test
    fun `onSnapshotLoaded injects a price per resolvable package, skipping one that fails`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        coEvery { bridge.priceFor("monthly_android", PackageKind.SUBSCRIPTION) } returns "$9.99/mo"
        coEvery { bridge.priceFor("broken_android", PackageKind.SUBSCRIPTION) } throws IllegalStateException("boom")
        var injectedPrices: Map<String, String>? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = mockk(),
            appUserId = "u-1",
            setPrices = { prices -> injectedPrices = prices },
        )

        runtime.onSnapshotLoaded(
            snapshotWith(
                mapOf(
                    "monthly" to PaywallPackageRef(null, "monthly_android", null, PackageKind.SUBSCRIPTION),
                    "broken" to PaywallPackageRef(null, "broken_android", null, PackageKind.SUBSCRIPTION),
                )
            )
        )

        assertEquals(mapOf("monthly" to "$9.99/mo"), injectedPrices)
    }

    @Test
    fun `onSnapshotLoaded skips a package with no androidProductId`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        var called = false
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = mockk(),
            appUserId = "u-1",
            setPrices = { called = true },
        )

        runtime.onSnapshotLoaded(
            snapshotWith(mapOf("monthly" to PaywallPackageRef("ios-only", null, null, PackageKind.SUBSCRIPTION)))
        )

        assertEquals(false, called)
    }

    @Test
    fun `a purchase with an unresolved package reports unresolvedProduct without calling the bridge`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        var error: PaywallPurchaseError? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = mockk(),
            appUserId = "u-1",
            setPrices = {},
            onPurchaseError = { error = it },
        )
        runtime.onSnapshotLoaded(snapshotWith(mapOf()))

        runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=missing")

        assertEquals(PaywallPurchaseErrorReason.UNRESOLVED_PRODUCT, error?.reason)
        coVerify(exactly = 0) { bridge.purchase(any(), any()) }
    }

    @Test
    fun `a successful purchase records it and reports onPurchaseResult with entitlements`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        val client = mockk<PaywallClient>()
        coEvery { bridge.purchase("monthly_android", PackageKind.SUBSCRIPTION) } returns
            PurchaseResult(PurchaseOutcome.SUCCESS, "tx-1", "monthly_android", 1700000000000L)
        coEvery {
            client.recordPurchase("u-1", "ANDROID", "monthly_android", "tx-1", any(), null)
        } returns listOf(Entitlement("premium", true, null, true, "PURCHASE"))
        var result: PurchaseResult? = null
        var entitlements: List<Entitlement>? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = client,
            appUserId = "u-1",
            setPrices = {},
            onPurchaseResult = { r, e -> result = r; entitlements = e },
        )
        runtime.onSnapshotLoaded(
            snapshotWith(mapOf("monthly" to PaywallPackageRef(null, "monthly_android", null, PackageKind.SUBSCRIPTION)))
        )

        runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=monthly")

        assertEquals(PurchaseOutcome.SUCCESS, result?.outcome)
        assertEquals(1, entitlements?.size)
    }

    @Test
    fun `a non-success purchase outcome reports onPurchaseResult directly, never onPurchaseError`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        coEvery { bridge.purchase("monthly_android", PackageKind.SUBSCRIPTION) } returns
            PurchaseResult(PurchaseOutcome.CANCELLED)
        var result: PurchaseResult? = null
        var errorCalled = false
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = mockk(),
            appUserId = "u-1",
            setPrices = {},
            onPurchaseResult = { r, _ -> result = r },
            onPurchaseError = { errorCalled = true },
        )
        runtime.onSnapshotLoaded(
            snapshotWith(mapOf("monthly" to PaywallPackageRef(null, "monthly_android", null, PackageKind.SUBSCRIPTION)))
        )

        runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=monthly")

        assertEquals(PurchaseOutcome.CANCELLED, result?.outcome)
        assertEquals(false, errorCalled)
    }

    @Test
    fun `a server rejection after a successful purchase reports serverRejected with the server's code`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        val client = mockk<PaywallClient>()
        coEvery { bridge.purchase("monthly_android", PackageKind.SUBSCRIPTION) } returns
            PurchaseResult(PurchaseOutcome.SUCCESS, "tx-1", "monthly_android", 1700000000000L)
        coEvery { client.recordPurchase(any(), any(), any(), any(), any(), any()) } throws
            PaywallServerError(404, "unknown_product", "Unknown product for this platform.")
        var error: PaywallPurchaseError? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = client,
            appUserId = "u-1",
            setPrices = {},
            onPurchaseError = { error = it },
        )
        runtime.onSnapshotLoaded(
            snapshotWith(mapOf("monthly" to PaywallPackageRef(null, "monthly_android", null, PackageKind.SUBSCRIPTION)))
        )

        runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=monthly")

        assertEquals(PaywallPurchaseErrorReason.SERVER_REJECTED, error?.reason)
        assertEquals("unknown_product", error?.serverCode)
    }

    @Test
    fun `a transport failure after a successful purchase reports networkError`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        val client = mockk<PaywallClient>()
        coEvery { bridge.purchase("monthly_android", PackageKind.SUBSCRIPTION) } returns
            PurchaseResult(PurchaseOutcome.SUCCESS, "tx-1", "monthly_android", 1700000000000L)
        coEvery { client.recordPurchase(any(), any(), any(), any(), any(), any()) } throws RuntimeException("offline")
        var error: PaywallPurchaseError? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = client,
            appUserId = "u-1",
            setPrices = {},
            onPurchaseError = { error = it },
        )
        runtime.onSnapshotLoaded(
            snapshotWith(mapOf("monthly" to PaywallPackageRef(null, "monthly_android", null, PackageKind.SUBSCRIPTION)))
        )

        runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=monthly")

        assertEquals(PaywallPurchaseErrorReason.NETWORK_ERROR, error?.reason)
    }

    @Test
    fun `restore with nothing to restore reports success with no entitlements`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        coEvery { bridge.restore() } returns emptyList()
        var result: PurchaseResult? = null
        var entitlements: List<Entitlement>? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = mockk(),
            appUserId = "u-1",
            setPrices = {},
            onPurchaseResult = { r, e -> result = r; entitlements = e },
        )

        runtime.handleNavigationRequest("coproduct-action:restore")

        assertEquals(PurchaseOutcome.SUCCESS, result?.outcome)
        assertTrue(entitlements.isNullOrEmpty())
    }

    @Test
    fun `restore continues past one failed transaction and reports the last successful entitlement set`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        val client = mockk<PaywallClient>()
        coEvery { bridge.restore() } returns listOf(
            RestoredTransaction("tx-1", "monthly_android", 1700000000000L),
            RestoredTransaction("tx-2", "remove_ads", 1700000001000L),
        )
        coEvery { client.recordPurchase("u-1", "ANDROID", "monthly_android", "tx-1", any(), null) } throws
            RuntimeException("transient")
        coEvery { client.recordPurchase("u-1", "ANDROID", "remove_ads", "tx-2", any(), null) } returns
            listOf(Entitlement("remove_ads", true, null, false, "PURCHASE"))
        var result: PurchaseResult? = null
        var entitlements: List<Entitlement>? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = client,
            appUserId = "u-1",
            setPrices = {},
            onPurchaseResult = { r, e -> result = r; entitlements = e },
        )

        runtime.handleNavigationRequest("coproduct-action:restore")

        assertEquals(PurchaseOutcome.SUCCESS, result?.outcome)
        assertEquals(1, entitlements?.size)
    }

    @Test
    fun `restore reports networkError only when every transaction fails to record`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        val client = mockk<PaywallClient>()
        coEvery { bridge.restore() } returns listOf(RestoredTransaction("tx-1", "monthly_android", 1700000000000L))
        coEvery { client.recordPurchase(any(), any(), any(), any(), any(), any()) } throws RuntimeException("offline")
        var error: PaywallPurchaseError? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = client,
            appUserId = "u-1",
            setPrices = {},
            onPurchaseError = { error = it },
        )

        runtime.handleNavigationRequest("coproduct-action:restore")

        assertEquals(PaywallPurchaseErrorReason.NETWORK_ERROR, error?.reason)
    }

    @Test
    fun `dismiss invokes onDismiss`() = runTest {
        var dismissed = false
        val runtime = PaywallRuntime(
            bridge = mockk(),
            client = mockk(),
            appUserId = "u-1",
            setPrices = {},
            onDismiss = { dismissed = true },
        )

        runtime.handleNavigationRequest("coproduct-action:dismiss")

        assertTrue(dismissed)
    }

    @Test
    fun `an unrecognized url returns navigate without side effects`() = runTest {
        val runtime = PaywallRuntime(bridge = mockk(), client = mockk(), appUserId = "u-1", setPrices = {})

        val decision = runtime.handleNavigationRequest("https://example.com")

        assertEquals(PaywallNavigationDecision.NAVIGATE, decision)
    }
}
