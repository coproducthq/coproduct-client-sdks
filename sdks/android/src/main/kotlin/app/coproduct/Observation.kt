package app.coproduct

import android.util.Log
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean

private const val LOG_TAG = "Coproduct"

/** Cancellation handle for an active flag observation. `cancel()` is idempotent. */
class Cancellable internal constructor(
    private val onCancel: () -> Unit,
) {
    private val cancelled = AtomicBoolean(false)

    fun cancel() {
        if (!cancelled.compareAndSet(false, true)) return
        onCancel()
    }
}

/**
 * Generalizes the seed+drain+cancel+destroy loop shared by every typed
 * observation (BoolObservation, StringObservation, IntObservation,
 * NumberObservation, JsonObservation). [key] is used only for log messages.
 * The drain runs off the core delivery lane, so a handler that calls back
 * into the SDK cannot stall delivery. A key with no usable value, at the
 * seed or in any delivery, resolves to [defaultValue].
 */
internal fun <T, D> observeDrain(
    key: String,
    defaultValue: T,
    seed: () -> T?,
    pollNext: suspend () -> D,
    valueOf: (D) -> T?,
    isClosed: (D) -> Boolean,
    cancelNative: () -> Unit,
    destroyNative: () -> Unit,
    mainDispatcher: CoroutineDispatcher = Dispatchers.Main.immediate,
    handler: (T) -> Unit,
): Cancellable {
    val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    scope.launch {
        val initial = try {
            seed()
        } catch (error: Throwable) {
            // A cancel racing this launch can destroy the observation before
            // the seed read runs. There is nothing left to drain
            Log.e(LOG_TAG, "flag observation seed failed for $key", error)
            return@launch
        }
        deliver(mainDispatcher, handler, initial ?: defaultValue)
        while (true) {
            val delivery = try {
                pollNext()
            } catch (error: Throwable) {
                // The observation was destroyed underneath the loop, or the
                // bridge failed. Either way there is nothing left to drain
                Log.e(LOG_TAG, "flag observation drain ended for $key", error)
                return@launch
            }
            if (isClosed(delivery)) return@launch
            deliver(mainDispatcher, handler, valueOf(delivery) ?: defaultValue)
        }
    }
    // Cancelling closes the mailbox, so a pollNext parked right now resolves
    // to Closed. The loop may still be between that resolution and its return
    // when destroy runs, which is why the drain treats a throw from pollNext
    // as a normal end rather than an error to surface
    return Cancellable {
        cancelNative()
        scope.cancel()
        destroyNative()
    }
}

// A handler failure is the developer's, not the SDK's. It is reported through
// the platform log and swallowed so one bad callback cannot end delivery for
// an observation that is still live
private suspend fun <T> deliver(dispatcher: CoroutineDispatcher, handler: (T) -> Unit, value: T) {
    withContext(dispatcher) {
        try {
            handler(value)
        } catch (error: Throwable) {
            Log.e(LOG_TAG, "flag observation handler threw", error)
        }
    }
}
