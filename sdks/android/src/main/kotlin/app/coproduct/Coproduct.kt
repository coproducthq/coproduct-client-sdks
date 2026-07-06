package app.coproduct

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.coproduct_ffi_uniffi.CoproductClient as NativeCoproductClient
import uniffi.coproduct_ffi_uniffi.FfiConfig
import uniffi.coproduct_ffi_uniffi.FlagObserver
import uniffi.coproduct_ffi_uniffi.FlagValue
import uniffi.coproduct_ffi_uniffi.HostSecureStore
import uniffi.coproduct_ffi_uniffi.HostTransport
import uniffi.coproduct_ffi_uniffi.HttpResponse
import uniffi.coproduct_ffi_uniffi.Subscription
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

    // Low-level observer hook used by current demos. Higher-level UI bindings can
    // layer on top of this cancellation primitive.
    fun observe(
        key: String,
        @Suppress("UNUSED_PARAMETER") defaultValue: Boolean,
        handler: (Boolean) -> Unit,
    ): Cancellable {
        val observer = object : FlagObserver {
            override suspend fun onChange(key: String, value: FlagValue) {
                val boolValue = (value as? FlagValue.Bool)?.value ?: return
                withContext(Dispatchers.Main.immediate) {
                    handler(boolValue)
                }
            }
        }
        return Cancellable(inner.observeKey(key, observer))
    }
}

class Cancellable internal constructor(
    private val subscription: Subscription,
) {
    fun cancel() {
        subscription.destroy()
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
