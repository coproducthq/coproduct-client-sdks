package app.coproduct.paywall

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PackagesJsonTest {
    @Test
    fun `encodes price, explicit null intro, and title when present`() {
        val json = JSONObject(packagesJson(mapOf("annual" to PaywallPackageRuntime("$39.99", null, "Pro Annual"))))
            .getJSONObject("annual")

        assertEquals("$39.99", json.getString("price"))
        assertTrue(json.has("intro") && json.isNull("intro"))
        assertEquals("Pro Annual", json.getString("title"))
    }

    @Test
    fun `omits title when null so the page keeps its fallback`() {
        val json = JSONObject(packagesJson(mapOf("annual" to PaywallPackageRuntime("$39.99", null))))
            .getJSONObject("annual")

        assertFalse(json.has("title"))
    }

    @Test
    fun `encodes an eligible intro`() {
        val json = JSONObject(
            packagesJson(mapOf("annual" to PaywallPackageRuntime("$39.99", PaywallIntroOffer(true, "1 week free")))),
        ).getJSONObject("annual").getJSONObject("intro")

        assertTrue(json.getBoolean("eligible"))
        assertEquals("1 week free", json.getString("label"))
    }
}
