package app.coproduct

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.coproduct_ffi_uniffi.PollOutcome

/**
 * [nextDelay] and [isBackoff] are pure, so they are tested directly without
 * any Android dependency, mirroring the iOS HostTimerTests scheduling cases
 */
class HostTimerLogicTest {
    private val interval = 60L

    @Test
    fun nextDelayHonorsRetryAfterAndBacksOff() {
        // A success or a retry polls again after the normal interval
        assertEquals(60L, nextDelay(PollOutcome.Updated, interval))
        assertEquals(60L, nextDelay(PollOutcome.NotModified, interval))
        assertEquals(60L, nextDelay(PollOutcome.Retrying, interval))
        assertEquals(60L, nextDelay(PollOutcome.DedupedSkipped, interval))

        // A 429 honors the server's retry-after, but never faster than normal
        assertEquals(300L, nextDelay(PollOutcome.RateLimited(retryAfterSecs = 300u), interval))
        assertEquals(60L, nextDelay(PollOutcome.RateLimited(retryAfterSecs = 5u), interval))

        // Only a stale provider backs off, to the stale interval (5x)
        assertEquals(300L, nextDelay(PollOutcome.Stale, interval))

        // A fatal provider stops polling
        assertNull(nextDelay(PollOutcome.Fatal, interval))
    }

    @Test
    fun isBackoffGatesForeground() {
        // These outcomes open a window a foreground event must wait out
        assertTrue(isBackoff(PollOutcome.RateLimited(retryAfterSecs = 30u)))
        assertTrue(isBackoff(PollOutcome.Stale))

        // These do not, so a foreground refreshes immediately. Retrying is
        // normal cadence, so a foreground refreshes during it as well
        assertFalse(isBackoff(PollOutcome.Retrying))
        assertFalse(isBackoff(PollOutcome.Updated))
        assertFalse(isBackoff(PollOutcome.NotModified))
        assertFalse(isBackoff(PollOutcome.DedupedSkipped))
        assertFalse(isBackoff(PollOutcome.Fatal))
    }
}
