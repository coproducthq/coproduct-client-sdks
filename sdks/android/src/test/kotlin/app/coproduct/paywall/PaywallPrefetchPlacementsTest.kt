package app.coproduct.paywall

import app.coproduct.paywall.models.Entitlement
import app.coproduct.paywall.models.PaywallContent
import app.coproduct.paywall.models.PaywallSnapshot
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

private fun snap(id: String) = PaywallSnapshot(
    paywallId = id,
    version = 1,
    templateType = "t",
    content = PaywallContent(offeringKey = "default", ctas = emptyList(), html = ""),
    packages = emptyMap(),
    html = "",
)

class PaywallPrefetchPlacementsTest {
    @Test
    fun `resolves each flag key, warms it, skips empties and dedups`() = runTest {
        val reader = object : FlagReader {
            override fun getString(key: String, default: String): String =
                mapOf("f.paid" to "pw_pfa1", "f.also" to "pw_pfa1", "f.empty" to "")[key] ?: default
        }
        val fetched = mutableListOf<String>()
        val paywallClient = object : PaywallClient {
            override suspend fun fetchPaywall(paywallId: String): PaywallSnapshot? {
                fetched.add(paywallId)
                return snap(paywallId)
            }

            override suspend fun recordPurchase(
                appUserId: String,
                platform: String,
                storeProductId: String,
                storeTransactionId: String,
                purchaseDateIso: String,
                expiresDateIso: String?,
            ): List<Entitlement> = emptyList()

            override suspend fun getEntitlements(appUserId: String): List<Entitlement> = emptyList()
            override suspend fun identify(appUserId: String, targetingKey: String) {}
        }

        CoproductPaywall.prefetchPlacements(
            client = reader,
            flagKeys = listOf("f.paid", "f.also", "f.empty"),
            sdkKey = "cpk_test",
            envSlug = "production",
            paywallClient = paywallClient,
        )

        assertEquals(listOf("pw_pfa1"), fetched) // deduped, empty skipped

        val served = snapshotCache.resolve(snapshotCacheKey("pw_pfa1", "production")) { null }
        assertEquals("pw_pfa1", served?.paywallId) // warmed into the shared cache
    }
}
