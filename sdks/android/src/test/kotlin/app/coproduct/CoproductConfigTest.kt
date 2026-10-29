package app.coproduct

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class CoproductConfigTest {
    @Test
    fun defaultConfigCarriesSpecDefaults() {
        val config = CoproductConfig()
        assertEquals(60L, config.pollIntervalSecs)
        assertEquals(3L, config.startupTimeoutSecs)
        assertNull(config.anonymousId)
        assertNull(config.endpoint)
        assertEquals(true, config.pollOnForeground)
        assertNull(config.requestTimeoutMs)
        assertNull(config.transport)
        assertNull(config.secureStore)
    }

    @Test
    fun explicitFieldOverrides() {
        val config = CoproductConfig(
            pollIntervalSecs = 30L,
            startupTimeoutSecs = 5L,
            anonymousId = "my-device",
            endpoint = "https://edge.example.com",
            pollOnForeground = false,
            requestTimeoutMs = 90_000L,
        )
        assertEquals(30L, config.pollIntervalSecs)
        assertEquals(5L, config.startupTimeoutSecs)
        assertEquals("my-device", config.anonymousId)
        assertEquals("https://edge.example.com", config.endpoint)
        assertEquals(false, config.pollOnForeground)
        assertEquals(90_000L, config.requestTimeoutMs)
    }

    @Test
    fun toFfiConfigCarriesEveryFieldThroughVerbatim() {
        val config = CoproductConfig(
            pollIntervalSecs = 45L,
            startupTimeoutSecs = 2L,
            anonymousId = "anon-1",
            endpoint = "https://edge.example.com",
            pollOnForeground = false,
        )
        val ffiConfig = config.toFfiConfig()
        assertEquals(45UL, ffiConfig.pollIntervalSecs)
        assertEquals(2UL, ffiConfig.startupTimeoutSecs)
        assertEquals("anon-1", ffiConfig.anonymousId)
        assertEquals("https://edge.example.com", ffiConfig.endpoint)
        assertEquals(false, ffiConfig.pollOnForeground)
    }

    @Test
    fun toFfiConfigRejectsNegativePollInterval() {
        val config = CoproductConfig(pollIntervalSecs = -1L)
        assertThrows(IllegalArgumentException::class.java) { config.toFfiConfig() }
    }

    @Test
    fun toFfiConfigRejectsNegativeStartupTimeout() {
        val config = CoproductConfig(startupTimeoutSecs = -1L)
        assertThrows(IllegalArgumentException::class.java) { config.toFfiConfig() }
    }

    @Test
    fun safeULongSecondsAcceptsZero() {
        assertEquals(0UL, safeULongSeconds(0L, field = "test"))
    }

    @Test
    fun safeULongSecondsAcceptsLargeNonNegativeValue() {
        // A non-negative Long always fits in ULong, so even Long.MAX_VALUE is safe
        assertEquals(Long.MAX_VALUE.toULong(), safeULongSeconds(Long.MAX_VALUE, field = "test"))
    }

    @Test
    fun safeULongSecondsRejectsNegative() {
        val error = assertThrows(IllegalArgumentException::class.java) {
            safeULongSeconds(-5L, field = "pollIntervalSecs")
        }
        assertEquals(true, error.message?.contains("pollIntervalSecs") == true)
    }
}
