package app.coproduct.paywall

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class AccountTokenTest {
    @Test
    fun `accountToken matches the cross-SDK and server test vector`() {
        assertEquals("f5765ad4-640f-516d-be70-79ed3a75f5e7", accountToken("user-123"))
    }

    @Test
    fun `accountToken differs per app user id`() {
        assertNotEquals(accountToken("user-123"), accountToken("user-124"))
    }
}
