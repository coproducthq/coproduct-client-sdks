package app.coproduct.flutter

import android.content.Context
import android.util.Log

/** Both session attributes from one transaction, never one without the other */
internal data class SessionPair(val firstSeenAt: Long, val sessionCount: Long) {
    fun toChannel(): Map<String, Long> =
        mapOf("first_seen_at" to firstSeenAt, "session_count" to sessionCount)
}

/**
 * The seam the transaction is written against, so a test can make a write fail
 * or make the store report something other than what was written. read returns
 * the raw stored values under their stored keys, and none of them is trusted
 */
internal interface SessionStorage {
    fun read(): Map<String, Any?>

    /** Writes both values in one transaction and reports whether it committed */
    fun write(firstSeenAt: Long, sessionCount: Long): Boolean
}

/**
 * One named private file, two keys, one editor. The editor applies its whole
 * change set at once, so a crash cannot split the pair, and commit rather than
 * apply is what reports a failed write. A named file keeps SDK state out of the
 * default preferences the host app owns. The file is opened on first use rather
 * than on construction, because opening throws before the user first unlocks
 * the device, and the open has to happen inside the transaction where a
 * failure latches
 */
internal class SharedPreferencesSessionStorage(context: Context) : SessionStorage {
    private val prefs by lazy {
        context.getSharedPreferences(SessionStore.FILE_NAME, Context.MODE_PRIVATE)
    }

    override fun read(): Map<String, Any?> {
        val all = prefs.all
        return mapOf(
            SessionStore.FIRST_SEEN_AT_KEY to all[SessionStore.FIRST_SEEN_AT_KEY],
            SessionStore.SESSION_COUNT_KEY to all[SessionStore.SESSION_COUNT_KEY],
        )
    }

    override fun write(firstSeenAt: Long, sessionCount: Long): Boolean =
        prefs.edit()
            .putLong(SessionStore.FIRST_SEEN_AT_KEY, firstSeenAt)
            .putLong(SessionStore.SESSION_COUNT_KEY, sessionCount)
            .commit()
}

/**
 * What one OS process knows about its session: the pair it counted, or that a
 * write failed. Every plugin instance uses [shared], so every FlutterEngine in
 * the process contends for one lock and receives one pair. Tests build their
 * own, one per simulated process
 */
internal class SessionProcessState {
    internal val lock = Any()
    internal var pair: SessionPair? = null
    internal var failed = false

    companion object {
        val shared = SessionProcessState()
    }
}

/**
 * Counts OS process lifetimes, once per process however many engines ask.
 * [logFailure] receives the exception behind a failed transaction, which the
 * channel answer cannot carry. A test passes its own, because the Log in the
 * JVM unit test stubs throws
 */
internal class SessionStore(
    private val storage: SessionStorage,
    private val process: SessionProcessState = SessionProcessState.shared,
    private val logFailure: (Exception) -> Unit = { e -> Log.w(LOG_TAG, "session store failed", e) },
    private val nowEpochSeconds: () -> Long = { System.currentTimeMillis() / 1000 },
) {
    /**
     * Returns this process's pair, or null when the store failed. The first
     * caller runs the transaction under the lock, so two engines starting
     * together cannot both read the old count
     */
    fun begin(): SessionPair? {
        synchronized(process.lock) {
            // A failure already seen in this process sticks. Without it a second
            // engine would read the value a failed commit left in memory
            if (process.failed) return null
            // Counted already: every later caller gets the same pair without
            // touching the store, so a record cleared or corrupted since cannot
            // start a second transaction or hand two engines different values
            process.pair?.let { return it }
            // A store that throws has failed as surely as one that returns
            // false, and may have advanced its in-memory value just the same,
            // so the latch is set in finally where it also holds for an Error,
            // which is left to propagate rather than caught
            var settled = false
            try {
                val confirmed = transact()
                settled = true
                return confirmed
            } catch (e: Exception) {
                // The Dart side learns only that the store failed, so the cause
                // goes to the platform log where a developer can find it
                logFailure(e)
                return null
            } finally {
                if (!settled) process.failed = true
            }
        }
    }

    /** The transaction body, always called with the process lock held */
    private fun transact(): SessionPair? {
        val stored = validate(storage.read(), maxCount = MAX_EXACT - 1)
        val firstSeenAt = stored?.firstSeenAt ?: nowEpochSeconds()
        val sessionCount = (stored?.sessionCount ?: 0L) + 1
        if (!storage.write(firstSeenAt, sessionCount)) {
            // Never retried in this process, so an ambiguous failure can cost an
            // omission but never a second increment
            process.failed = true
            return null
        }
        // What the store reports holding, not what this method meant to write
        val confirmed = validate(storage.read(), maxCount = MAX_EXACT)
        if (confirmed == null) process.failed = true else process.pair = confirmed
        return confirmed
    }

    companion object {
        const val FILE_NAME = "app.coproduct.flutter.session"
        const val LOG_TAG = "Coproduct"
        const val FIRST_SEEN_AT_KEY = "firstSeenAt"
        const val SESSION_COUNT_KEY = "sessionCount"

        /**
         * The largest integer a double holds exactly. Both values reach the core
         * as a double, so anything larger would publish a different number from
         * the one stored
         */
        const val MAX_EXACT = 9_007_199_254_740_991L

        /**
         * A missing, wrong-typed, negative, zero-count, or out-of-range value
         * means the record is corrupt, and a corrupt record restarts rather than
         * publishing a nonsensical cohort value. A stored count must leave room
         * for the increment, so it is read with a tighter upper bound than the
         * confirmed record is
         */
        private fun validate(raw: Map<String, Any?>, maxCount: Long): SessionPair? {
            val firstSeenAt = raw[FIRST_SEEN_AT_KEY] as? Long ?: return null
            val sessionCount = raw[SESSION_COUNT_KEY] as? Long ?: return null
            if (firstSeenAt !in 0..MAX_EXACT || sessionCount !in 1..maxCount) return null
            return SessionPair(firstSeenAt, sessionCount)
        }
    }
}
