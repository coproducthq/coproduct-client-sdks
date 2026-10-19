package app.coproduct

import android.content.Context
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import uniffi.coproduct_ffi_uniffi.CoproductClient as NativeCoproductClient
import uniffi.coproduct_ffi_uniffi.FfiConfig
import uniffi.coproduct_ffi_uniffi.HostSecureStore
import uniffi.coproduct_ffi_uniffi.HostTransport
import uniffi.coproduct_ffi_uniffi.InitException
import uniffi.coproduct_ffi_uniffi.ProviderState
import uniffi.coproduct_ffi_uniffi.initialize as nativeInitialize

/** Every config field the SDK exposes, each with its own default. */
data class CoproductConfig(
    val pollIntervalSeconds: Long = 60,
    val startupTimeoutSeconds: Long = 3,
    val anonymousId: String? = null,
    val transport: HostTransport? = null,
    val secureStore: HostSecureStore? = null,
    val endpoint: String? = null,
    val pollOnForeground: Boolean = true,
)

/** The single error family initialize throws. Reads and identity calls never throw. */
sealed class CoproductError : Exception() {
    data class InvalidConfig(val field: String, val reason: String) : CoproductError()
    data class InvalidSdkKey(val reason: String) : CoproductError()
    object CancelledByShutdown : CoproductError()
    data class LaunchFailed(val reason: String) : CoproductError()

    companion object {
        fun from(error: Throwable): CoproductError = when (error) {
            is CoproductError -> error
            is InitException.InvalidKeyType -> InvalidSdkKey("expected a Coproduct mobile SDK key (cpk_mob_)")
            is InitException.MalformedSdkKey -> InvalidSdkKey(error.reason)
            is InitException.MissingSdkKey -> InvalidSdkKey("the sdk key is empty")
            is InitException.InvalidConfig -> InvalidConfig(error.field, error.reason)
            is InitException.UnsupportedSchemaVersion ->
                LaunchFailed("snapshot schema version ${error.actual} is not supported (this SDK supports ${error.supported})")
            else -> LaunchFailed(error.toString())
        }
    }
}

private const val COPRODUCT_USER_AGENT = "coproduct-android/0.0.1-dev"
private const val LOG_TAG = "Coproduct"

/**
 * The Coproduct SDK. Call initialize once, then read flags, identify users,
 * and observe changes through the returned CoproductClient.
 */
object Coproduct {
    private val lock = Any()
    private var defaultInstance: Stored? = null
    private var inFlight: Deferred<CoproductClient>? = null
    private var inFlightKey: String? = null
    private var generation = 0
    private val scope = CoroutineScope(Dispatchers.Default)

    private class Stored(
        val client: CoproductClient,
        val sdkKey: String,
        val timer: HostTimer,
        val networkMonitor: NetworkMonitor,
    ) {
        // Set after registerForegroundListener runs, under lock, once we
        // re-confirm this Stored is still the live defaultInstance. Null
        // means either not registered yet or a race already self-cleaned it
        var foregroundObserver: LifecycleEventObserver? = null
    }

    private sealed class Claim {
        data class Existing(val client: CoproductClient) : Claim()
        data class Pending(val task: Deferred<CoproductClient>) : Claim()
    }

    suspend fun initialize(sdkKey: String, context: Context): CoproductClient =
        initialize(sdkKey, context, CoproductConfig())

    suspend fun initialize(sdkKey: String, context: Context, config: CoproductConfig): CoproductClient {
        val claim = synchronized(lock) {
            val existing = defaultInstance
            if (existing != null) {
                if (existing.sdkKey != sdkKey) {
                    android.util.Log.w(LOG_TAG, "initialize called with different sdkKey; returning existing instance")
                }
                return@synchronized Claim.Existing(existing.client)
            }
            val pending = inFlight
            if (pending != null) {
                if (inFlightKey != sdkKey) {
                    android.util.Log.w(
                        LOG_TAG,
                        "initialize called with a different sdkKey while initialization is in progress; joining the in-flight initialize",
                    )
                }
                return@synchronized Claim.Pending(pending)
            }
            val claimedGeneration = generation
            val task = scope.async { runInitialize(sdkKey, context.applicationContext, config, claimedGeneration) }
            inFlight = task
            inFlightKey = sdkKey
            Claim.Pending(task)
        }
        return when (claim) {
            is Claim.Existing -> claim.client
            is Claim.Pending -> claim.task.await()
        }
    }

    private suspend fun runInitialize(
        sdkKey: String,
        appContext: Context,
        config: CoproductConfig,
        claimedGeneration: Int,
    ): CoproductClient {
        val client: CoproductClient
        try {
            client = doInitialize(sdkKey, appContext, config)
        } catch (error: Throwable) {
            val stillCurrent = synchronized(lock) {
                if (claimedGeneration != generation) return@synchronized false
                inFlight = null
                inFlightKey = null
                true
            }
            if (!stillCurrent) throw CoproductError.CancelledByShutdown
            throw CoproductError.from(error)
        }

        // Drive polling from the host. The core does not poll during
        // initialize, so the timer's immediate first tick owns the first
        // fetch as well as the recurring schedule
        val foregroundEvents = MutableSharedFlow<Unit>()
        val timer = HostTimer(
            intervalMillis = config.pollIntervalSeconds * 1000,
            pollOnForeground = config.pollOnForeground,
            scope = scope,
            foregroundEvents = foregroundEvents,
        ) { client.pollNow() }

        val connectivityManager =
            appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
        val networkMonitor = NetworkMonitor(
            source = ConnectivityManagerSource(connectivityManager),
            onChange = { type -> client.setAutoPopulated(mapOf("network_type" to AttributeValue.Str(type))) },
        )

        val storedOk = synchronized(lock) {
            if (claimedGeneration != generation) return@synchronized false
            inFlight = null
            inFlightKey = null
            defaultInstance = Stored(client, sdkKey, timer, networkMonitor)
            true
        }
        if (!storedOk) {
            // A shutdown ran during the brief construct before the instance
            // was stored. Do not resurrect it: tear the orphan down and
            // report the cancellation
            networkMonitor.cancel()
            client.shutdownInner()
            throw CoproductError.CancelledByShutdown
        }

        timer.start()
        networkMonitor.start()
        val observer = registerForegroundListener(foregroundEvents)

        // Stash the observer onto the Stored instance so shutdown() can
        // remove it later, but only if that Stored is still the live
        // defaultInstance: a shutdown could have raced in since storedOk
        // succeeded above, already torn the old Stored down (with no
        // observer to remove at that time), and cleared defaultInstance. In
        // that case clean up the just-registered observer ourselves
        val observerStoredOk = synchronized(lock) {
            val current = defaultInstance
            if (current?.client === client) {
                current.foregroundObserver = observer
                true
            } else {
                false
            }
        }
        if (!observerStoredOk) {
            ProcessLifecycleOwner.get().lifecycle.removeObserver(observer)
        }

        if (!waitForFirstPoll(client, config.startupTimeoutSeconds)) {
            throw CoproductError.CancelledByShutdown
        }
        return client
    }

    private fun registerForegroundListener(events: MutableSharedFlow<Unit>): LifecycleEventObserver {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START) {
                scope.launch { events.emit(Unit) }
            }
        }
        ProcessLifecycleOwner.get().lifecycle.addObserver(observer)
        return observer
    }

    // Waits up to startupTimeoutSeconds for the first poll to move the
    // provider off NOT_READY. Returns false when a shutdown replaced or
    // cleared the instance during the wait
    private suspend fun waitForFirstPoll(client: CoproductClient, startupTimeoutSeconds: Long): Boolean {
        if (startupTimeoutSeconds <= 0) return true
        val deadline = System.currentTimeMillis() + startupTimeoutSeconds * 1000
        while (client.state() == ProviderState.NOT_READY && System.currentTimeMillis() < deadline) {
            if (synchronized(lock) { defaultInstance?.client } !== client) return false
            delay(25)
        }
        return synchronized(lock) { defaultInstance?.client } === client
    }

    private suspend fun doInitialize(sdkKey: String, appContext: Context, config: CoproductConfig): CoproductClient {
        val cacheDir = appContext.cacheDir.absolutePath
        val transport = config.transport ?: OkHttpTransport()
        val secureStore = config.secureStore ?: EncryptedPreferencesSecureStore(appContext)

        val ffiConfig = FfiConfig(
            pollIntervalSecs = config.pollIntervalSeconds.toULong(),
            startupTimeoutSecs = config.startupTimeoutSeconds.toULong(),
            anonymousId = config.anonymousId,
            endpoint = config.endpoint,
            pollOnForeground = config.pollOnForeground,
        )

        val native: NativeCoproductClient = nativeInitialize(
            sdkKey = sdkKey,
            userAgent = COPRODUCT_USER_AGENT,
            cacheDir = cacheDir,
            config = ffiConfig,
            transport = transport,
            secureStore = secureStore,
        )

        val client = CoproductClient(native)
        val sessionPrefs = appContext.getSharedPreferences("app.coproduct.session", Context.MODE_PRIVATE)
        val attributes = DeviceContext.staticAttributes(appContext) +
            SessionStore(SharedPreferencesKeyValueStore(sessionPrefs)).sessionAttributes()
        // Publish the SDK-owned device and session attributes before
        // initialize resolves, so the first synchronous read evaluates
        // against them
        client.setAutoPopulatedNow(attributes)
        return client
    }

    suspend fun shutdown() {
        val (stored, pending) = synchronized(lock) {
            generation += 1
            val s = defaultInstance
            defaultInstance = null
            val p = inFlight
            inFlight = null
            inFlightKey = null
            s to p
        }
        pending?.cancel()
        stored?.timer?.stop()
        stored?.networkMonitor?.cancel()
        stored?.foregroundObserver?.let { ProcessLifecycleOwner.get().lifecycle.removeObserver(it) }
        stored?.client?.shutdownInner()
    }
}
