package app.coproduct.paywall.models

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PaywallSnapshotTest {
    @Test
    fun `parses a full snapshot, including packages with explicit kind`() {
        val json = JSONObject(
            """
            {
              "paywallId": "p-1",
              "version": 2,
              "templateType": "hero_single_offer",
              "content": {
                "offeringKey": "default",
                "ctas": [{"packageKey": "monthly", "label": "Subscribe monthly"}],
                "html": "<div>paywall</div>"
              },
              "packages": {
                "monthly": {"iosProductId": "premium_monthly_ios", "androidProductId": "premium_monthly_android", "kind": "subscription"},
                "points_pack": {"androidProductId": "points_pack_300", "kind": "consumable"},
                "remove_ads": {"androidProductId": "remove_ads", "kind": "lifetime"}
              },
              "html": "<div>paywall</div>"
            }
            """.trimIndent()
        )
        val snapshot = parsePaywallSnapshot(json)

        assertEquals("p-1", snapshot.paywallId)
        assertEquals(2, snapshot.version)
        assertEquals("hero_single_offer", snapshot.templateType)
        assertEquals("default", snapshot.content.offeringKey)
        assertEquals(1, snapshot.content.ctas.size)
        assertEquals("monthly", snapshot.content.ctas[0].packageKey)
        assertEquals("premium_monthly_android", snapshot.packages["monthly"]?.androidProductId)
        assertEquals(PackageKind.SUBSCRIPTION, snapshot.packages["monthly"]?.kind)
        assertEquals(PackageKind.CONSUMABLE, snapshot.packages["points_pack"]?.kind)
        assertEquals(PackageKind.LIFETIME, snapshot.packages["remove_ads"]?.kind)
    }

    @Test
    fun `defaults kind to SUBSCRIPTION when absent, for a server that predates consumable support`() {
        val json = JSONObject(
            """{"paywallId":"p-1","version":1,"templateType":"hero_single_offer","content":{"offeringKey":"default","ctas":[],"html":"<div/>"},"packages":{"monthly":{"androidProductId":"m"}},"html":"<div/>"}"""
        )
        val snapshot = parsePaywallSnapshot(json)

        assertEquals(PackageKind.SUBSCRIPTION, snapshot.packages["monthly"]?.kind)
    }

    @Test
    fun `a package with no androidProductId has a null value, not a missing key`() {
        val json = JSONObject(
            """{"paywallId":"p-1","version":1,"templateType":"hero_single_offer","content":{"offeringKey":"default","ctas":[],"html":"<div/>"},"packages":{"monthly":{"iosProductId":"ios-only","kind":"subscription"}},"html":"<div/>"}"""
        )
        val snapshot = parsePaywallSnapshot(json)

        assertNull(snapshot.packages["monthly"]?.androidProductId)
    }
}
