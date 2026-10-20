package app.coproduct

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import uniffi.coproduct_ffi_uniffi.PollOutcome

/**
 * Android polling trigger, porting HostTimer.swift's state machine. Owns a
 * self-rescheduling coroutine loop plus an optional foreground-active signal.
 * Each poll returns a PollOutcome that decides when the next poll fires: a
 * success or a retry polls again after the normal interval, a 429 waits out
 * the server's retry-after, and only a stale provider backs off. The
 * foreground fast path refreshes on return to the foreground during normal
 * cadence, but respects an active back-off window rather than bypassing it.
 */
internal class HostTimer(
    private val intervalMillis: Long,
    private val pollOnForeground: Boolean = true,
    private val scope: CoroutineScope,
    private val foregroundEvents: Flow<Unit> = MutableSharedFlow(),
    private val poll: suspend () -> PollOutcome,
) {
    private val lock = Any()
    private var stopped = false
    private var pollInFlight = false
    private var scheduledJob: Job? = null
    private var foregroundJob: Job? = null

    // Earliest time a foreground event may trigger an off-schedule poll. In
    // the past during normal cadence, so a foreground refreshes immediately;
    // in the future while backing off, so a foreground waits out the window
    private var earliestForegroundPollAt = 0L

    fun start() {
        synchronized(lock) {
            if (stopped || scheduledJob != null) return
            // Poll immediately on start: the core does not poll during
            // initialize, so the host owns the first fetch as well as the
            // recurring schedule
            scheduleLocked(0)
            if (pollOnForeground) {
                foregroundJob = scope.launch {
                    foregroundEvents.collect { foregroundFired() }
                }
            }
        }
    }

    fun stop() {
        synchronized(lock) {
            stopped = true
            scheduledJob?.cancel()
            scheduledJob = null
            foregroundJob?.cancel()
            foregroundJob = null
        }
    }

    private fun scheduleLocked(delayMs: Long) {
        scheduledJob?.cancel()
        scheduledJob = scope.launch {
            if (delayMs > 0) delay(delayMs)
            triggerPoll()
        }
    }

    private fun foregroundFired() {
        val allowed = synchronized(lock) {
            !stopped && !pollInFlight && System.currentTimeMillis() >= earliestForegroundPollAt
        }
        if (allowed) scope.launch { triggerPoll() }
    }

    // Run one poll, unless one is already in flight, and reschedule from its
    // outcome once it completes
    private suspend fun triggerPoll() {
        val shouldPoll = synchronized(lock) {
            if (stopped || pollInFlight) {
                false
            } else {
                pollInFlight = true
                true
            }
        }
        if (!shouldPoll) return
        val outcome = poll()
        rescheduleAfterPoll(outcome)
    }

    private fun rescheduleAfterPoll(outcome: PollOutcome) {
        synchronized(lock) {
            pollInFlight = false
            if (stopped) return
            val delayMs = nextDelay(outcome, intervalMillis)
            if (delayMs == null) {
                // A fatal provider is terminal. Mark stopped and drop the
                // foreground listener so a later foreground event cannot
                // start another poll, matching stop()
                stopped = true
                scheduledJob?.cancel()
                scheduledJob = null
                foregroundJob?.cancel()
                foregroundJob = null
                return
            }
            // A foreground bypasses the wait during normal cadence, but must
            // wait out an active back-off window
            earliestForegroundPollAt = if (isBackoff(outcome)) {
                System.currentTimeMillis() + delayMs
            } else {
                System.currentTimeMillis()
            }
            scheduleLocked(delayMs)
        }
    }

    companion object {
        private const val BACKOFF_MULTIPLIER = 5

        /**
         * The delay before the next poll for a given outcome. A `null` result
         * stops polling. A 429 honors the server's retry-after but never polls
         * faster than the normal interval. Retrying stays at the normal
         * cadence; only a stale provider backs off.
         */
        fun nextDelay(outcome: PollOutcome, intervalMillis: Long): Long? = when (outcome) {
            is PollOutcome.Updated, is PollOutcome.NotModified,
            is PollOutcome.Retrying, is PollOutcome.DedupedSkipped,
            -> intervalMillis
            is PollOutcome.RateLimited -> maxOf(outcome.retryAfterSecs.toLong() * 1000, intervalMillis)
            is PollOutcome.Stale -> intervalMillis * BACKOFF_MULTIPLIER
            is PollOutcome.Fatal -> null
        }

        /** Whether an outcome opens a back-off window a foreground event must wait out. */
        fun isBackoff(outcome: PollOutcome): Boolean = when (outcome) {
            is PollOutcome.RateLimited, is PollOutcome.Stale -> true
            is PollOutcome.Updated, is PollOutcome.NotModified,
            is PollOutcome.Retrying, is PollOutcome.DedupedSkipped, is PollOutcome.Fatal,
            -> false
        }
    }
}
