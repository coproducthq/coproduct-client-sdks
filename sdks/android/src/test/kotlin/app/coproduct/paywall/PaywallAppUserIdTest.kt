package app.coproduct.paywall

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PaywallAppUserIdTest {
    @Test
    fun `the paywall uses the anonymous id when appUserId is omitted`() {
        assertEquals("anon-1", resolvePaywallAppUserId(null) { "anon-1" })
    }

    @Test
    fun `the paywall uses an explicit appUserId when given`() {
        assertEquals("user-1", resolvePaywallAppUserId("user-1") { "anon-1" })
    }

    @Test
    fun `no id is resolved when appUserId is omitted and the SDK has no anonymous id`() {
        assertNull(resolvePaywallAppUserId(null) { null })
        // The default source is the shared client, which is absent in a unit test.
        assertNull(resolvePaywallAppUserId(null))
    }
}
