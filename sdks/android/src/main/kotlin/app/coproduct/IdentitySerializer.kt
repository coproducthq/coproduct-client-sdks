package app.coproduct

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async

/**
 * Serializes identity mutations so they apply in the order they were called.
 * The public identity API is synchronous and fire-and-forget, so without a
 * single ordered queue two rapid calls could reach the core out of order.
 */
internal class IdentitySerializer(
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Default),
) {
    private val lock = Any()
    private var tail: Deferred<Unit>? = null

    /**
     * Enqueues [operation] to run after every previously enqueued operation has
     * finished, preserving call order. If [operation] throws, the exception is
     * caught and logged internally (tag "Coproduct") — it is never rethrown into
     * the chain and never propagates to the caller's [scope]. Callers do not need
     * their own try/catch around [enqueue]; a failing operation never poisons
     * operations enqueued after it and never cancels the caller's scope.
     */
    fun enqueue(operation: suspend () -> Unit) {
        synchronized(lock) {
            val previous = tail
            tail = scope.async {
                previous?.await()
                try {
                    operation()
                } catch (t: Throwable) {
                    try {
                        Log.e("Coproduct", "Identity operation failed", t)
                    } catch (_: Throwable) {
                        // Log.e itself is unmocked under plain JUnit; never let logging
                        // failure reintroduce the poisoning this catch exists to prevent.
                    }
                }
            }
        }
    }

    /** Awaits the work enqueued so far. Used during initialize and by tests. */
    suspend fun drain() {
        val current = synchronized(lock) { tail }
        current?.await()
    }
}
