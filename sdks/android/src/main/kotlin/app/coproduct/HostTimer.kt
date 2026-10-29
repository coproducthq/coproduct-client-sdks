package app.coproduct

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.coproduct_ffi_uniffi.PollOutcome

/**
 * A stale provider polls at this multiple of the normal interval, mirroring
 * the core's stale_retry_interval. Retrying stays at the normal cadence so a
 * transient failure recovers promptly within the retry budget
 */
internal const val HOST_TIMER_BACKOFF_MULTIPLIER = 5L

/**
 * The delay in seconds before the next poll for a given outcome. A `null`
 * result stops polling. A 429 honors the server's retry-after but never
 * polls faster than the normal interval. Retrying stays at the normal
 * cadence, which is the core's short recovery window (its retry budget
 * reaches Stale at the intended time), and only a stale provider backs off.
 * Pure so it unit-tests without any Android dependency
 */
internal fun nextDelay(outcome: PollOutcome, intervalSecs: Long): Long? =
    when (outcome) {
        is PollOutcome.Updated,
        is PollOutcome.NotModified,
        is PollOutcome.Retrying,
        is PollOutcome.DedupedSkipped,
        -> intervalSecs
        is PollOutcome.RateLimited -> maxOf(outcome.retryAfterSecs.toLong(), intervalSecs)
        is PollOutcome.Stale -> intervalSecs * HOST_TIMER_BACKOFF_MULTIPLIER
        is PollOutcome.Fatal -> null
    }

/**
 * Whether an outcome opens a back-off window that a foreground event must
 * wait out rather than bypass. Retrying is normal cadence, so a foreground
 * refreshes during it. Pure so it unit-tests without any Android dependency
 */
internal fun isBackoff(outcome: PollOutcome): Boolean =
    when (outcome) {
        is PollOutcome.RateLimited, is PollOutcome.Stale -> true
        is PollOutcome.Updated,
        is PollOutcome.NotModified,
        is PollOutcome.Retrying,
        is PollOutcome.DedupedSkipped,
        is PollOutcome.Fatal,
        -> false
    }

/**
 * Notifies when the app returns to the foreground. Injectable so a test can
 * drive the foreground fast path without the real process lifecycle
 */
internal interface ForegroundSource {
    fun start(onForeground: () -> Unit)

    fun stop()
}

/**
 * Production foreground source backed by [ProcessLifecycleOwner], which
 * reports the whole process moving to the foreground rather than any single
 * activity, matching the app-wide granularity of iOS's
 * didBecomeActiveNotification. [start] and [stop] touch the lifecycle
 * registry, which must only be mutated from the main thread, so both hop
 * onto [Dispatchers.Main.immediate]
 */
internal class ProcessLifecycleForegroundSource : ForegroundSource {
    private var observer: LifecycleEventObserver? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun start(onForeground: () -> Unit) {
        scope.launch {
            val lifecycleObserver =
                LifecycleEventObserver { _, event ->
                    if (event == Lifecycle.Event.ON_START) onForeground()
                }
            observer = lifecycleObserver
            ProcessLifecycleOwner.get().lifecycle.addObserver(lifecycleObserver)
        }
    }

    override fun stop() {
        scope.launch {
            observer?.let { ProcessLifecycleOwner.get().lifecycle.removeObserver(it) }
            observer = null
        }
    }
}

/**
 * Android polling trigger. Owns a self-rescheduling coroutine plus an
 * optional foreground source. Each poll returns a [PollOutcome] that decides
 * when the next poll fires, so the host honors the scheduling signal the
 * core computes: a success or a retry polls again after the normal
 * interval, a 429 waits out the server's retry-after, and only a stale
 * provider backs off. The foreground fast path refreshes on return to the
 * foreground during normal cadence, but respects an active back-off window
 * rather than bypassing it
 */
internal class HostTimer(
    private val intervalSecs: Long,
    private val pollOnForeground: Boolean = true,
    private val foregroundSource: ForegroundSource = ProcessLifecycleForegroundSource(),
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
    private val poll: suspend () -> PollOutcome,
) {
    private val lock = Any()
    private var job: Job? = null
    private var stopped = false
    private var pollInFlight = false

    // Earliest time (nanoTime) a foreground event may trigger an off-schedule
    // poll. Zero during normal cadence, so a foreground refreshes
    // immediately, and in the future while backing off, so a foreground
    // waits out the window
    private var earliestForegroundPollAt = 0L

    /**
     * Starts the timer. Polls immediately: the core does not poll during
     * initialize, so the host owns the first fetch as well as the recurring
     * schedule
     */
    fun start() {
        synchronized(lock) {
            if (stopped || job != null) return
            scheduleLocked(delaySecs = 0)
            if (pollOnForeground) {
                foregroundSource.start { onForeground() }
            }
        }
    }

    fun stop() {
        synchronized(lock) {
            stopped = true
            job?.cancel()
            job = null
        }
        // Idempotent in every implementation, so it is safe to call even when
        // pollOnForeground never started it
        foregroundSource.stop()
    }

    /**
     * Schedules a one-shot fire after [delaySecs]. Callers hold [lock]. The
     * scheduled job only waits out the delay and then launches [triggerPoll]
     * as a separate, untracked job, so a reschedule computed from that same
     * poll's outcome cancels the (already-finished) wait rather than the
     * poll it is still deciding the next delay for
     */
    private fun scheduleLocked(delaySecs: Long) {
        job?.cancel()
        job =
            scope.launch {
                if (delaySecs > 0) delay(delaySecs * 1000)
                scope.launch { triggerPoll() }
            }
    }

    private fun onForeground() {
        val now = System.nanoTime()
        val allowed =
            synchronized(lock) {
                !stopped && !pollInFlight && now >= earliestForegroundPollAt
            }
        if (allowed) {
            scope.launch { triggerPoll() }
        }
    }

    /**
     * Runs one poll, unless one is already in flight, and reschedules from
     * its outcome once it completes
     */
    private suspend fun triggerPoll() {
        val shouldRun =
            synchronized(lock) {
                if (stopped || pollInFlight) {
                    false
                } else {
                    pollInFlight = true
                    true
                }
            }
        if (!shouldRun) return
        val outcome = poll()
        rescheduleAfterPoll(outcome)
    }

    private fun rescheduleAfterPoll(outcome: PollOutcome) {
        // The fatal branch sets stopped under the lock, then stops the
        // foreground source once the lock is released, mirroring stop()
        // without calling it while the lock is held
        val becameFatal =
            synchronized(lock) {
                pollInFlight = false
                if (stopped) return
                val delaySecs = nextDelay(outcome, intervalSecs)
                if (delaySecs == null) {
                    // A fatal provider is terminal. Mark stopped so a later
                    // foreground event cannot start another poll, matching stop
                    stopped = true
                    job?.cancel()
                    job = null
                    true
                } else {
                    // A foreground bypasses the wait during normal cadence, but
                    // must wait out an active back-off window
                    earliestForegroundPollAt =
                        if (isBackoff(outcome)) System.nanoTime() + delaySecs * 1_000_000_000L else 0L
                    scheduleLocked(delaySecs)
                    false
                }
            }
        if (becameFatal) {
            foregroundSource.stop()
        }
    }
}
