package app.coproduct.paywall

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PaywallActionTest {
    @Test
    fun `parses a purchase action with a packageKey`() {
        val action = parsePaywallAction("coproduct-action:purchase?packageKey=monthly")
        assertEquals(PaywallAction.Purchase("monthly"), action)
    }

    @Test
    fun `parses a restore action`() {
        assertEquals(PaywallAction.Restore, parsePaywallAction("coproduct-action:restore"))
    }

    @Test
    fun `parses a dismiss action`() {
        assertEquals(PaywallAction.Dismiss, parsePaywallAction("coproduct-action:dismiss"))
    }

    @Test
    fun `a purchase action with no packageKey is null`() {
        assertNull(parsePaywallAction("coproduct-action:purchase"))
    }

    @Test
    fun `a purchase action with an empty packageKey is null`() {
        assertNull(parsePaywallAction("coproduct-action:purchase?packageKey="))
    }

    @Test
    fun `an unknown action type is null`() {
        assertNull(parsePaywallAction("coproduct-action:unknown"))
    }

    @Test
    fun `a URL without the coproduct-action scheme is null`() {
        assertNull(parsePaywallAction("https://example.com/purchase"))
    }
}
