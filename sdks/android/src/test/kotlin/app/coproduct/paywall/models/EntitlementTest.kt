package app.coproduct.paywall.models

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EntitlementTest {
    @Test
    fun `parses an active, renewing entitlement with an expiry`() {
        val json = JSONObject(
            """{"entitlementId":"premium","isActive":true,"expiresAt":"2026-11-01T00:00:00.000Z","willRenew":true,"source":"PURCHASE"}"""
        )
        val entitlement = parseEntitlement(json)

        assertEquals("premium", entitlement.entitlementId)
        assertEquals(true, entitlement.isActive)
        assertEquals("2026-11-01T00:00:00.000Z", entitlement.expiresAt)
        assertEquals(true, entitlement.willRenew)
        assertEquals("PURCHASE", entitlement.source)
    }

    @Test
    fun `parses a never-expiring entitlement`() {
        val json = JSONObject(
            """{"entitlementId":"lifetime","isActive":true,"expiresAt":null,"willRenew":false,"source":"PURCHASE"}"""
        )
        val entitlement = parseEntitlement(json)

        assertNull(entitlement.expiresAt)
    }
}
