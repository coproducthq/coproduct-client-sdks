package app.coproduct

import android.content.Context
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.coproduct_ffi_uniffi.BoolDelivery
import uniffi.coproduct_ffi_uniffi.BoolObservation
import uniffi.coproduct_ffi_uniffi.CoproductClient as NativeCoproductClient
import uniffi.coproduct_ffi_uniffi.FfiConfig
import uniffi.coproduct_ffi_uniffi.HostSecureStore
import uniffi.coproduct_ffi_uniffi.HostTransport
import uniffi.coproduct_ffi_uniffi.HttpResponse
import uniffi.coproduct_ffi_uniffi.initialize

// Validation transport used by the current convenience initializer. The public
// initializer shape below shows where host transport injection will connect.
object MockTransport {
    var requestCount: Int = 0
        private set
    var completedHandshake: Boolean = false
        private set

    fun reset() {
        requestCount = 0
        completedHandshake = false
    }

    suspend fun request(): HttpResponse {
        requestCount += 1
        completedHandshake = true
        return HttpResponse(
            status = 200u,
            body = "{}".encodeToByteArray(),
            headers = emptyList(),
        )
    }
}

// Validation secure store used by the current convenience initializer.
object MockSecureStore {
    var readCount: Int = 0
        private set
    var writeCount: Int = 0
        private set
    var completedHandshake: Boolean = false
        private set

    private val values = mutableMapOf<String, String>()

    fun reset() {
        readCount = 0
        writeCount = 0
        completedHandshake = false
        values.clear()
    }

    suspend fun read(key: String): String? {
        readCount += 1
        completedHandshake = true
        return values[key]
    }

    suspend fun write(key: String, value: String) {
        writeCount += 1
        completedHandshake = true
        values[key] = value
    }
}

object Coproduct {
    // User agent identifying this platform wrapper to the Coproduct backend
    private const val USER_AGENT = "coproduct-android/0.0.1-dev"

    // Future public initializer shape once host Transport / SecureStore
    // interfaces are exposed by the Android wrapper.
    //
    // suspend fun initialize(
    //     sdkKey: String,
    //     context: Context,
    //     transport: HostTransport,
    //     secureStore: HostSecureStore,
    // ): CoproductClient { ... }

    suspend fun initialize(sdkKey: String, context: Context): CoproductClient {
        val cacheDir = context.cacheDir.absolutePath
        val nativeClient = initialize(
            sdkKey = sdkKey,
            userAgent = USER_AGENT,
            cacheDir = cacheDir,
            config = FfiConfig(
                pollIntervalSecs = 60u,
                startupTimeoutSecs = 3u,
                anonymousId = null,
                endpoint = null,
                pollOnForeground = true,
            ),
            transport = AndroidHostTransport,
            secureStore = AndroidHostSecureStore,
        )
        return CoproductClient(nativeClient)
    }
}

class CoproductClient internal constructor(
    private val inner: NativeCoproductClient,
) {
    fun getBool(key: String, defaultValue: Boolean): Boolean {
        return inner.getBool(key, defaultValue)
    }

    // Low-level observation hook used by current demos. Higher-level UI bindings
    // can layer on top of this cancellation primitive. The handler is invoked
    // once with the value at subscription and then on every change. A key with no
    // usable value resolves to defaultValue
    fun observe(
        key: String,
        defaultValue: Boolean,
        handler: (Boolean) -> Unit,
    ): Cancellable {
        val observation = inner.observeBool(key)
        val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
        // The drain runs off the core delivery lane, so a handler that calls back
        // into the SDK cannot stall delivery
        scope.launch {
            val seed = try {
                observation.seed()
            } catch (error: Throwable) {
                // A cancel racing this launch can destroy the observation before
                // the seed read runs. There is nothing left to drain
                Log.e(LOG_TAG, "flag observation seed failed for $key", error)
                return@launch
            }
            deliver(handler, seed ?: defaultValue)
            while (true) {
                val delivery = try {
                    observation.pollNext()
                } catch (error: Throwable) {
                    // The observation was destroyed underneath the loop, or the
                    // bridge failed. Either way there is nothing left to drain
                    Log.e(LOG_TAG, "flag observation drain ended for $key", error)
                    return@launch
                }
                when (delivery) {
                    is BoolDelivery.Value -> deliver(handler, delivery.value ?: defaultValue)
                    is BoolDelivery.Closed -> return@launch
                }
            }
        }
        return Cancellable(observation, scope)
    }

    // A handler failure is the developer's, not the SDK's. It is reported through
    // the platform log and swallowed so one bad callback cannot end delivery for
    // an observation that is still live
    private suspend fun deliver(handler: (Boolean) -> Unit, value: Boolean) {
        withContext(Dispatchers.Main.immediate) {
            try {
                handler(value)
            } catch (error: Throwable) {
                Log.e(LOG_TAG, "flag observation handler threw", error)
            }
        }
    }
}

private const val LOG_TAG = "Coproduct"

class Cancellable internal constructor(
    private val observation: BoolObservation,
    private val scope: CoroutineScope,
) {
    private val cancelled = AtomicBoolean(false)

    // Idempotent. A second call must not reach the generated object: `destroy`
    // itself is idempotent, but any exported method called after it throws
    // IllegalStateException from the generated call counter
    fun cancel() {
        if (!cancelled.compareAndSet(false, true)) {
            return
        }
        // Cancelling closes the mailbox, so a pollNext parked right now resolves
        // to Closed. The loop may still be between that resolution and its return
        // when destroy runs, which is why the drain treats a throw from pollNext
        // as a normal end rather than an error to surface
        observation.cancel()
        scope.cancel()
        observation.destroy()
    }
}

private object AndroidHostTransport : HostTransport {
    override suspend fun request(req: uniffi.coproduct_ffi_uniffi.HttpRequest): HttpResponse {
        return MockTransport.request()
    }
}

private object AndroidHostSecureStore : HostSecureStore {
    override suspend fun read(key: String): String? {
        return MockSecureStore.read(key)
    }

    override suspend fun write(key: String, value: String) {
        MockSecureStore.write(key, value)
    }
}
