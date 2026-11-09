package app.coproduct

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CoproductConfigTest {
    @Test
    fun defaultsMatchTheDocumentedContract() {
        val config = CoproductConfig()
        assertEquals(60L, config.pollIntervalSeconds)
        assertEquals(3L, config.startupTimeoutSeconds)
        assertNull(config.anonymousId)
        assertNull(config.transport)
        assertNull(config.secureStore)
        assertNull(config.endpoint)
        assertTrue(config.pollOnForeground)
    }
}
