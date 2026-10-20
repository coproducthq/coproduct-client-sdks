package app.coproduct

import android.content.SharedPreferences

/** Minimal persistence seam SessionStore needs; production wraps SharedPreferences. */
internal interface KeyValueStore {
    fun getLong(key: String): Long?
    fun putLong(key: String, value: Long)
}

internal class SharedPreferencesKeyValueStore(
    private val prefs: SharedPreferences,
) : KeyValueStore {
    override fun getLong(key: String): Long? =
        if (prefs.contains(key)) prefs.getLong(key, 0) else null

    override fun putLong(key: String, value: Long) {
        prefs.edit().putLong(key, value).apply()
    }
}

/**
 * Persists first_seen_at and session_count, mirroring SessionStore.swift. One
 * session is one process lifetime: the increment guard is process-global, so
 * shutdown plus re-initialize in the same process must not count a new
 * session. first_seen_at is epoch integer seconds UTC.
 */
internal class SessionStore(private val store: KeyValueStore) {
    companion object {
        const val FIRST_SEEN_KEY = "app.coproduct.firstSeenAt"
        const val SESSION_COUNT_KEY = "app.coproduct.sessionCount"

        private val guardLock = Any()
        private var incrementedThisProcess = false

        fun resetProcessGuardForTesting() {
            synchronized(guardLock) { incrementedThisProcess = false }
        }
    }

    fun sessionAttributes(nowEpochSeconds: Long = System.currentTimeMillis() / 1000): Map<String, AttributeValue> {
        synchronized(guardLock) {
            val firstSeen = store.getLong(FIRST_SEEN_KEY) ?: nowEpochSeconds.also {
                store.putLong(FIRST_SEEN_KEY, it)
            }

            var count = store.getLong(SESSION_COUNT_KEY) ?: 0
            if (!incrementedThisProcess) {
                count += 1
                store.putLong(SESSION_COUNT_KEY, count)
                incrementedThisProcess = true
            }

            return mapOf(
                "first_seen_at" to AttributeValue.Num(firstSeen.toDouble()),
                "session_count" to AttributeValue.Num(count.toDouble()),
            )
        }
    }
}
