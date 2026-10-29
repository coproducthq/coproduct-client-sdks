package app.coproduct

import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Applies fire-and-forget identity mutations in the order they were
 * enqueued, independent of how long any single mutation takes. Each call
 * chains onto the previous one's completion rather than running
 * concurrently, so a slow earlier mutation cannot let a faster later one
 * land out of order. [scope] defaults to a dedicated scope so the
 * serializer's own lifetime is independent of the caller's
 */
internal class IdentitySerializer(
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
    // Injectable so a JVM unit test can exercise the error-swallowing path
    // without reaching the real android.util.Log, which throws when not
    // mocked outside an instrumented test
    private val logError: (Throwable) -> Unit = { e -> Log.e(LOG_TAG, "identity mutation failed", e) },
) {
    private val lock = Any()
    private var tail: Job? = null

    /**
     * Enqueues [block] to run after every previously enqueued block has
     * completed. A thrown error is logged and swallowed so one failing
     * mutation never crashes the caller or blocks the queue for later calls
     */
    fun enqueue(block: suspend () -> Unit) {
        synchronized(lock) {
            val previous = tail
            tail =
                scope.launch {
                    previous?.join()
                    try {
                        block()
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Throwable) {
                        logError(error)
                    }
                }
        }
    }

    /**
     * Awaits every block enqueued so far. Used by tests to observe the
     * settled state after a burst of fire-and-forget identity calls
     */
    internal suspend fun drain() {
        currentTail()?.join()
    }

    /** Reads the current tail under the lock. Synchronous so the lock is never held across a suspension */
    private fun currentTail(): Job? = synchronized(lock) { tail }

    companion object {
        /** The ordered queue the Android wrapper's identity bridges enqueue onto */
        val shared = IdentitySerializer()
    }
}

private const val LOG_TAG = "Coproduct"
