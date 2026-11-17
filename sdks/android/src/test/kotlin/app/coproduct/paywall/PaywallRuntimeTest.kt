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
    fun `onSnapshotLoaded injects a package per resolvable package, skipping one that fails`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        coEvery { bridge.packageFor("monthly_android", PackageKind.SUBSCRIPTION) } returns
            PaywallPackageRuntime(price = "$9.99/mo", intro = null)
        coEvery { bridge.packageFor("broken_android", PackageKind.SUBSCRIPTION) } throws IllegalStateException("boom")
        var injectedPackages: Map<String, PaywallPackageRuntime>? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = mockk(),
            appUserId = "u-1",
            setPackages = { packages -> injectedPackages = packages },
        )

        runtime.onSnapshotLoaded(
            snapshotWith(
                mapOf(
                    "monthly" to PaywallPackageRef(null, "monthly_android", null, PackageKind.SUBSCRIPTION),
                    "broken" to PaywallPackageRef(null, "broken_android", null, PackageKind.SUBSCRIPTION),
                )
            )
        )

        assertEquals(mapOf("monthly" to PaywallPackageRuntime(price = "$9.99/mo", intro = null)), injectedPackages)
    }

    @Test
    fun `onSnapshotLoaded injects the eligible intro offer a packageFor call resolves`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        coEvery { bridge.packageFor("monthly_android", PackageKind.SUBSCRIPTION) } returns
            PaywallPackageRuntime(
                price = "$9.99/mo",
                intro = PaywallIntroOffer(eligible = true, label = "1 week free, then $9.99/mo"),
            )
        var injectedPackages: Map<String, PaywallPackageRuntime>? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = mockk(),
            appUserId = "u-1",
            setPackages = { packages -> injectedPackages = packages },
        )

        runtime.onSnapshotLoaded(
            snapshotWith(mapOf("monthly" to PaywallPackageRef(null, "monthly_android", null, PackageKind.SUBSCRIPTION)))
        )

        assertEquals(true, injectedPackages?.get("monthly")?.intro?.eligible)
        assertEquals("1 week free, then $9.99/mo", injectedPackages?.get("monthly")?.intro?.label)
    }

    @Test
    fun `onSnapshotLoaded skips a package with no androidProductId`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        var called = false
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = mockk(),
            appUserId = "u-1",
            setPackages = { called = true },
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
            setPackages = {},
            onPurchaseError = { error = it },
        )
        runtime.onSnapshotLoaded(snapshotWith(mapOf()))

        runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=missing")

        assertEquals(PaywallPurchaseErrorReason.UNRESOLVED_PRODUCT, error?.reason)
        coVerify(exactly = 0) { bridge.purchaseForUser(any(), any(), any()) }
    }

    @Test
    fun `a successful purchase records it and reports onPurchaseResult with entitlements`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        val client = mockk<PaywallClient>()
        coEvery { bridge.purchaseForUser("monthly_android", PackageKind.SUBSCRIPTION, "u-1") } returns
            PurchaseResult(PurchaseOutcome.SUCCESS, "tx-1", "monthly_android", 1700000000000L)
        coEvery {
            client.recordPurchaseWithProof("u-1", "ANDROID", "monthly_android", "tx-1", any(), null, any(), any())
        } returns listOf(Entitlement("premium", true, null, true, "PURCHASE"))
        var result: PurchaseResult? = null
        var entitlements: List<Entitlement>? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = client,
            appUserId = "u-1",
            setPackages = {},
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
        coEvery { bridge.purchaseForUser("monthly_android", PackageKind.SUBSCRIPTION, "u-1") } returns
            PurchaseResult(PurchaseOutcome.CANCELLED)
        var result: PurchaseResult? = null
        var errorCalled = false
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = mockk(),
            appUserId = "u-1",
            setPackages = {},
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
        coEvery { bridge.purchaseForUser("monthly_android", PackageKind.SUBSCRIPTION, "u-1") } returns
            PurchaseResult(PurchaseOutcome.SUCCESS, "tx-1", "monthly_android", 1700000000000L)
        coEvery { client.recordPurchaseWithProof(any(), any(), any(), any(), any(), any(), any(), any()) } throws
            PaywallServerError(404, "unknown_product", "Unknown product for this platform.")
        var error: PaywallPurchaseError? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = client,
            appUserId = "u-1",
            setPackages = {},
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
        coEvery { bridge.purchaseForUser("monthly_android", PackageKind.SUBSCRIPTION, "u-1") } returns
            PurchaseResult(PurchaseOutcome.SUCCESS, "tx-1", "monthly_android", 1700000000000L)
        coEvery { client.recordPurchaseWithProof(any(), any(), any(), any(), any(), any(), any(), any()) } throws RuntimeException("offline")
        var error: PaywallPurchaseError? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = client,
            appUserId = "u-1",
            setPackages = {},
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
            setPackages = {},
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
        coEvery { client.recordPurchaseWithProof("u-1", "ANDROID", "monthly_android", "tx-1", any(), null, any(), any()) } throws
            RuntimeException("transient")
        coEvery { client.recordPurchaseWithProof("u-1", "ANDROID", "remove_ads", "tx-2", any(), null, any(), any()) } returns
            listOf(Entitlement("remove_ads", true, null, false, "PURCHASE"))
        var result: PurchaseResult? = null
        var entitlements: List<Entitlement>? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = client,
            appUserId = "u-1",
            setPackages = {},
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
        coEvery { client.recordPurchaseWithProof(any(), any(), any(), any(), any(), any(), any(), any()) } throws RuntimeException("offline")
        var error: PaywallPurchaseError? = null
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = client,
            appUserId = "u-1",
            setPackages = {},
            onPurchaseError = { error = it },
        )

        runtime.handleNavigationRequest("coproduct-action:restore")

        assertEquals(PaywallPurchaseErrorReason.NETWORK_ERROR, error?.reason)
    }

    @Test
    fun `a purchase passes the app user id to the bridge and the purchase token to the client`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        val client = mockk<PaywallClient>()
        coEvery { bridge.purchaseForUser("monthly_android", PackageKind.SUBSCRIPTION, "u-1") } returns
            PurchaseResult(
                outcome = PurchaseOutcome.SUCCESS,
                transactionId = "tx-1",
                productId = "monthly_android",
                purchaseDateMillis = 1700000000000L,
                purchaseToken = "token-1",
            )
        coEvery {
            client.recordPurchaseWithProof(any(), any(), any(), any(), any(), any(), any(), any())
        } returns emptyList()
        val runtime = PaywallRuntime(bridge = bridge, client = client, appUserId = "u-1", setPackages = {})
        runtime.onSnapshotLoaded(
            snapshotWith(mapOf("monthly" to PaywallPackageRef(null, "monthly_android", null, PackageKind.SUBSCRIPTION)))
        )

        runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=monthly")

        coVerify(exactly = 1) { bridge.purchaseForUser("monthly_android", PackageKind.SUBSCRIPTION, "u-1") }
        coVerify(exactly = 1) {
            client.recordPurchaseWithProof("u-1", "ANDROID", "monthly_android", "tx-1", any(), null, null, "token-1")
        }
    }

    @Test
    fun `restore passes each transaction's purchase token to the client`() = runTest {
        val bridge = mockk<NativePaywallBridge>()
        val client = mockk<PaywallClient>()
        coEvery { bridge.restore() } returns listOf(
            RestoredTransaction("tx-1", "monthly_android", 1700000000000L, purchaseToken = "token-1"),
            RestoredTransaction("tx-2", "remove_ads", 1700000001000L),
        )
        coEvery {
            client.recordPurchaseWithProof(any(), any(), any(), any(), any(), any(), any(), any())
        } returns emptyList()
        val runtime = PaywallRuntime(bridge = bridge, client = client, appUserId = "u-1", setPackages = {})

        runtime.handleNavigationRequest("coproduct-action:restore")

        coVerify(exactly = 1) {
            client.recordPurchaseWithProof("u-1", "ANDROID", "monthly_android", "tx-1", any(), null, null, "token-1")
        }
        coVerify(exactly = 1) {
            client.recordPurchaseWithProof("u-1", "ANDROID", "remove_ads", "tx-2", any(), null, null, null)
        }
    }

    @Test
    fun `a bridge and client that implement only the original methods still purchase and restore`() = runTest {
        val purchased = mutableListOf<String>()
        val bridge = object : NativePaywallBridge {
            override suspend fun priceFor(productId: String, kind: PackageKind): String = "$9.99"
            override suspend fun purchase(productId: String, kind: PackageKind): PurchaseResult {
                purchased.add(productId)
                return PurchaseResult(PurchaseOutcome.SUCCESS, "tx-1", productId, 1700000000000L)
            }

            override suspend fun restore(): List<RestoredTransaction> =
                listOf(RestoredTransaction("tx-2", "remove_ads", 1700000001000L))
        }
        val recorded = mutableListOf<String>()
        val client = object : PaywallClient {
            override suspend fun fetchPaywall(paywallId: String): PaywallSnapshot? = null
            override suspend fun recordPurchase(
                appUserId: String,
                platform: String,
                storeProductId: String,
                storeTransactionId: String,
                purchaseDateIso: String,
                expiresDateIso: String?,
            ): List<Entitlement> {
                recorded.add("$appUserId:$storeProductId:$storeTransactionId")
                return listOf(Entitlement("premium", true, null, true, "PURCHASE"))
            }

            override suspend fun getEntitlements(appUserId: String): List<Entitlement> = emptyList()
            override suspend fun identify(appUserId: String, targetingKey: String) {}
        }
        val results = mutableListOf<List<Entitlement>>()
        val runtime = PaywallRuntime(
            bridge = bridge,
            client = client,
            appUserId = "u-1",
            setPackages = {},
            onPurchaseResult = { _, e -> results.add(e) },
        )
        runtime.onSnapshotLoaded(
            snapshotWith(mapOf("monthly" to PaywallPackageRef(null, "monthly_android", null, PackageKind.SUBSCRIPTION)))
        )

        runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=monthly")
        runtime.handleNavigationRequest("coproduct-action:restore")

        assertEquals(listOf("monthly_android"), purchased)
        assertEquals(listOf("u-1:monthly_android:tx-1", "u-1:remove_ads:tx-2"), recorded)
        assertEquals(listOf(1, 1), results.map { it.size })
    }

    @Test
    fun `dismiss invokes onDismiss`() = runTest {
        var dismissed = false
        val runtime = PaywallRuntime(
            bridge = mockk(),
            client = mockk(),
            appUserId = "u-1",
            setPackages = {},
            onDismiss = { dismissed = true },
        )

        runtime.handleNavigationRequest("coproduct-action:dismiss")

        assertTrue(dismissed)
    }

    @Test
    fun `an unrecognized url returns navigate without side effects`() = runTest {
        val runtime = PaywallRuntime(bridge = mockk(), client = mockk(), appUserId = "u-1", setPackages = {})

        val decision = runtime.handleNavigationRequest("https://example.com")

        assertEquals(PaywallNavigationDecision.NAVIGATE, decision)
    }
}
