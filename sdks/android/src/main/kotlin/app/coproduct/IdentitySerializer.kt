package app.coproduct

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

    fun enqueue(operation: suspend () -> Unit) {
        synchronized(lock) {
            val previous = tail
            tail = scope.async {
                previous?.await()
                operation()
            }
        }
    }

    /** Awaits the work enqueued so far. Used during initialize and by tests. */
    suspend fun drain() {
        val current = synchronized(lock) { tail }
        current?.await()
    }
}
