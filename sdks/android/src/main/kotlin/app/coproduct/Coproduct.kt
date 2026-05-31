package app.coproduct

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.coproduct_ffi_uniffi.CoproductClient as NativeCoproductClient
import uniffi.coproduct_ffi_uniffi.FlagObserver
import uniffi.coproduct_ffi_uniffi.HostSecureStore
import uniffi.coproduct_ffi_uniffi.HostTransport
import uniffi.coproduct_ffi_uniffi.HttpResponse
import uniffi.coproduct_ffi_uniffi.Subscription
import uniffi.coproduct_ffi_uniffi.computeBucket as ffiComputeBucket
import uniffi.coproduct_ffi_uniffi.initialize

// SCAFFOLD-ONLY: replaced by real Transport wiring in M1.
// M1 door: Coproduct.initialize(sdkKey, context, transport, secureStore) overload below.
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

// SCAFFOLD-ONLY: replaced by real SecureStore wiring in M1.
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
    // M1 door (commented out so the scaffold still compiles against the mocks).
    // M1 fills in the real Transport / SecureStore interfaces and removes the
    // two-arg overload below in favor of this one.
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
            cacheDir = cacheDir,
            transport = AndroidHostTransport,
            secureStore = AndroidHostSecureStore,
        )
        return CoproductClient(nativeClient)
    }

    // SCAFFOLD-ONLY: replaced by an internal bucketForVectors accessor in the production SDK.
    fun computeBucket(ruleId: String, targetingKey: String, suffix: String): UInt {
        return ffiComputeBucket(ruleId, targetingKey, suffix)
    }
}

class CoproductClient internal constructor(
    private val inner: NativeCoproductClient,
) {
    fun getBool(key: String, defaultValue: Boolean): Boolean {
        return inner.getBool(key, defaultValue)
    }

    // SCAFFOLD-ONLY: low-level callback API. The production SDK layers Coproduct.rememberFlag composable on top.
    fun observe(
        key: String,
        @Suppress("UNUSED_PARAMETER") defaultValue: Boolean,
        handler: (Boolean) -> Unit,
    ): Cancellable {
        val observer = object : FlagObserver {
            override suspend fun onChangeBool(value: Boolean) {
                withContext(Dispatchers.Main.immediate) {
                    handler(value)
                }
            }
        }
        return Cancellable(inner.observe(key, observer))
    }

    // SCAFFOLD-ONLY: the Coproduct.snapshot accessor and the provider state machine replace this in the production SDK.
    fun wasLoadedFromCache(): Boolean {
        return inner.wasLoadedFromCache()
    }

    // SCAFFOLD-ONLY: real polling-driven snapshot updates plus the setOverride test API replace this in the production SDK.
    suspend fun simulateChange(key: String, newValue: Boolean) {
        inner.simulateChange(key, newValue)
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
