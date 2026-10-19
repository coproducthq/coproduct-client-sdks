package app.coproduct

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.coproduct_ffi_uniffi.PollOutcome
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class HostTimerTest {
    @Test
    fun timerRepollsAfterASuccessfulOutcome() {
        val latch = CountDownLatch(2)
        val scope = CoroutineScope(Dispatchers.Default)
        scope.launch {
            val timer = HostTimer(
                intervalMillis = 50,
                scope = this,
                poll = suspend {
                    latch.countDown()
                    PollOutcome.Updated
                }
            )
            timer.start()
        }
        assertTrue(latch.await(2, TimeUnit.SECONDS))
    }

    @Test
    fun foregroundTriggersAPollDuringNormalCadence() {
        val scope = CoroutineScope(Dispatchers.Default)
        scope.launch {
            val foregroundEvents = MutableSharedFlow<Unit>()
            val count = AtomicInteger(0)
            val firstPollLatch = CountDownLatch(1)
            val foregroundPollLatch = CountDownLatch(1)
            // A long interval means the scheduled timer will not fire again within
            // the test, so the second poll can only come from the foreground event
            val timer = HostTimer(
                intervalMillis = 60_000,
                pollOnForeground = true,
                scope = this,
                foregroundEvents = foregroundEvents,
                poll = suspend {
                    when (count.incrementAndGet()) {
                        1 -> firstPollLatch.countDown()
                        2 -> foregroundPollLatch.countDown()
                    }
                    PollOutcome.Updated
                }
            )
            timer.start()
            assertTrue(firstPollLatch.await(1, TimeUnit.SECONDS))
            // Let the first poll's reschedule settle so the foreground is not deduped
            delay(100)
            foregroundEvents.emit(Unit)
            assertTrue(foregroundPollLatch.await(1, TimeUnit.SECONDS))
            timer.stop()
        }
    }

    @Test
    fun foregroundDoesNotPollAfterFatal() {
        val scope = CoroutineScope(Dispatchers.Default)
        scope.launch {
            val foregroundEvents = MutableSharedFlow<Unit>()
            val count = AtomicInteger(0)
            val firstPollLatch = CountDownLatch(1)
            val timer = HostTimer(
                intervalMillis = 60_000,
                pollOnForeground = true,
                scope = this,
                foregroundEvents = foregroundEvents,
                poll = suspend {
                    if (count.incrementAndGet() == 1) firstPollLatch.countDown()
                    PollOutcome.Fatal
                }
            )
            timer.start()
            assertTrue(firstPollLatch.await(1, TimeUnit.SECONDS))
            delay(100)
            foregroundEvents.emit(Unit)
            delay(200)
            assertEquals(1, count.get())
            timer.stop()
        }
    }

    @Test
    fun nextDelayHonorsRetryAfterAndBacksOff() {
        val interval = 60_000L
        assertEquals(interval, HostTimer.nextDelay(PollOutcome.Updated, interval))
        assertEquals(interval, HostTimer.nextDelay(PollOutcome.NotModified, interval))
        assertEquals(interval, HostTimer.nextDelay(PollOutcome.Retrying, interval))
        assertEquals(300_000L, HostTimer.nextDelay(PollOutcome.RateLimited(300uL), interval))
        assertEquals(interval, HostTimer.nextDelay(PollOutcome.RateLimited(5uL), interval))
        assertEquals(interval * 5, HostTimer.nextDelay(PollOutcome.Stale, interval))
        assertNull(HostTimer.nextDelay(PollOutcome.Fatal, interval))
    }

    @Test
    fun backoffOutcomesGateForeground() {
        assertTrue(HostTimer.isBackoff(PollOutcome.RateLimited(30uL)))
        assertTrue(HostTimer.isBackoff(PollOutcome.Stale))
        assertFalse(HostTimer.isBackoff(PollOutcome.Retrying))
        assertFalse(HostTimer.isBackoff(PollOutcome.Updated))
        assertFalse(HostTimer.isBackoff(PollOutcome.NotModified))
        assertFalse(HostTimer.isBackoff(PollOutcome.Fatal))
    }
}
