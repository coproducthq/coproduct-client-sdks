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
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsBool
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsInt
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsJson
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsNumber
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsString
import uniffi.coproduct_ffi_uniffi.ProviderState
import uniffi.coproduct_ffi_uniffi.initialize

/**
 * The Coproduct SDK. [initialize] once, then read flags, identify users, and
 * observe changes through the returned [CoproductClient]. The static
 * identity methods on this object resolve the default instance so a caller
 * that does not hold on to the client can still identify, sign out, or
 * update targeting attributes from anywhere in the app
 */
object Coproduct {
    // User agent identifying this platform wrapper to the Coproduct backend
    private const val USER_AGENT = "coproduct-android/0.0.1-dev"

    private val instances =
        Instances<CoproductClient>(
            stateOf = { it.state() },
            shutdownClient = { it.shutdown() },
            logWarning = { message -> Log.w(LOG_TAG, message) },
        )

    /**
     * Initialize the SDK.
     *
     * Returns as soon as flags are available from the on-device cache, the
     * first poll succeeds or fails, or [CoproductConfig.startupTimeoutSecs]
     * elapses, whichever comes first. Polling then continues in the
     * background, and reads serve cached values or the supplied defaults
     * until flags arrive.
     *
     * Calling this a second time returns the existing instance, even with a
     * different sdk key (a warning is logged); call [CoproductClient.shutdown]
     * first to switch environments.
     */
    suspend fun initialize(
        sdkKey: String,
        context: Context,
        config: CoproductConfig = CoproductConfig(),
    ): CoproductClient {
        val appContext = context.applicationContext
        return instances.initialize(
            sdkKey = sdkKey,
            startupTimeoutSecs = config.startupTimeoutSecs,
            scopeFactory = { CoroutineScope(SupervisorJob() + Dispatchers.Default) },
            build = { scope -> doInitialize(sdkKey, appContext, config, scope) },
        )
    }

    // The full build: constructs the core client (fast, cache-backed, never
    // touches the network), folds the SDK-owned device and session
    // attributes into the auto-populated context before the client is
    // published so the first synchronous read already evaluates against
    // them, then starts the host timer (immediate first poll) and the
    // network monitor. The core does not poll during initialize, so the
    // timer's immediate first tick owns the first fetch as well as the
    // recurring schedule
    private suspend fun doInitialize(
        sdkKey: String,
        context: Context,
        config: CoproductConfig,
        scope: CoroutineScope,
    ): CoproductClient {
        val transport = config.transport ?: HttpUrlConnectionTransport(requestTimeoutMs = config.requestTimeoutMs)
        val secureStore = config.secureStore ?: EncryptedSecureStore.default(context)

        val nativeClient =
            initialize(
                sdkKey = sdkKey,
                userAgent = USER_AGENT,
                cacheDir = context.cacheDir.absolutePath,
                config = config.toFfiConfig(),
                transport = transport,
                secureStore = secureStore,
            )

        val serializer = IdentitySerializer(scope)
        val client = CoproductClient(nativeClient, scope, serializer)

        val autoAttributes =
            DeviceContext.staticAttributes(context) +
                SessionStore(SharedPreferencesSessionStorage(context)).begin()
        client.setAutoPopulatedNow(autoAttributes)

        val timer =
            HostTimer(
                intervalSecs = config.pollIntervalSecs,
                pollOnForeground = config.pollOnForeground,
                scope = scope,
                poll = { nativeClient.pollNow() },
            )
        val networkMonitor =
            NetworkMonitor(
                source = ConnectivityManagerPathSource(context),
                onChange = { type -> client.setAutoPopulated(mapOf("network_type" to AttributeValue.String(type))) },
            )
        client.attachLifecycle(timer, networkMonitor) { instances.clearIfCurrent(client) }
        timer.start()
        networkMonitor.start()
        return client
    }

    // Identity
    // Fire-and-forget: each call returns immediately and is applied in the
    // background in call order. A failure is logged, not thrown. Called
    // before initialize it logs and does nothing

    /**
     * Identify the current user, optionally attaching targeting attributes.
     * Called before [initialize] it logs and does nothing
     */
    fun identify(
        userId: String,
        attributes: Map<String, AttributeValue> = emptyMap(),
        linkAnonymous: Boolean = true,
    ) {
        val client = instances.defaultInstance() ?: return logIdentityBeforeInitialize("identify")
        client.identify(userId, attributes, linkAnonymous)
    }

    /**
     * Clear the identified user and return to an anonymous identity. Called
     * before [initialize] it logs and does nothing
     */
    fun signOut() {
        val client = instances.defaultInstance() ?: return logIdentityBeforeInitialize("signOut")
        client.signOut()
    }

    /**
     * Replace the targeting key and attributes for the current context.
     * Called before [initialize] it logs and does nothing
     */
    fun setContext(targetingKey: String, attributes: Map<String, AttributeValue> = emptyMap()) {
        val client = instances.defaultInstance() ?: return logIdentityBeforeInitialize("setContext")
        client.setContext(targetingKey, attributes)
    }

    /**
     * Merge targeting attributes into the current context. Called before
     * [initialize] it logs and does nothing
     */
    fun updateAttributes(attributes: Map<String, AttributeValue>) {
        val client = instances.defaultInstance() ?: return logIdentityBeforeInitialize("updateAttributes")
        client.updateAttributes(attributes)
    }

    /**
     * Remove targeting attributes by key from the current context. Called
     * before [initialize] it logs and does nothing
     */
    fun removeAttributes(keys: List<String>) {
        val client = instances.defaultInstance() ?: return logIdentityBeforeInitialize("removeAttributes")
        client.removeAttributes(keys)
    }

    private fun logIdentityBeforeInitialize(method: String) {
        Log.w(LOG_TAG, "$method called before initialize; ignoring")
    }
}

/**
 * The public per-instance handle returned by [Coproduct.initialize]. Reads
 * never throw: a missing flag, a wrong type, or a not-ready SDK serves the
 * caller-supplied default. The identity mutators are fire-and-forget and
 * apply in call order through a dedicated [IdentitySerializer]
 */
class CoproductClient internal constructor(
    private val inner: NativeCoproductClient,
    private val scope: CoroutineScope,
    private val serializer: IdentitySerializer = IdentitySerializer(scope),
) {
    private var timer: HostTimer? = null
    private var networkMonitor: NetworkMonitor? = null
    private var unregister: (() -> Unit)? = null
    private val shuttingDown = AtomicBoolean(false)

    /**
     * Wires the host-driven polling timer, the network monitor, and the
     * registry unregister hook built around this client. Called once, right
     * after construction, by [Coproduct.initialize]: these collaborators call
     * back into this client, so they cannot be built before it exists
     */
    internal fun attachLifecycle(timer: HostTimer, networkMonitor: NetworkMonitor, unregister: () -> Unit) {
        this.timer = timer
        this.networkMonitor = networkMonitor
        this.unregister = unregister
    }

    // Evaluation getters
    // Reads never throw or trap. A missing flag, a wrong type, or a
    // not-ready SDK serves defaultValue

    fun getBool(key: String, defaultValue: Boolean): Boolean = inner.getBool(key, defaultValue)

    fun getString(key: String, defaultValue: String): String = inner.getString(key, defaultValue)

    /** Integers travel as the numeric flag type under the hood */
    fun getInt(key: String, defaultValue: Long): Long = inner.getInt(key, defaultValue)

    fun getNumber(key: String, defaultValue: Double): Double = inner.getNumber(key, defaultValue)

    /**
     * Returns the JSON flag value as a JSON-encoded string. [defaultValueJson]
     * is the caller's JSON-encoded default, where `"null"` is a valid
     * fallback
     */
    fun getJson(key: String, defaultValueJson: String): String = inner.getJson(key, defaultValueJson)

    // Detail getters
    // Like the plain getters but return the resolved value plus its reason,
    // variant, and error code

    fun getBoolDetails(key: String, defaultValue: Boolean): FlagEvaluationDetailsBool =
        inner.getBoolDetails(key, defaultValue)

    fun getStringDetails(key: String, defaultValue: String): FlagEvaluationDetailsString =
        inner.getStringDetails(key, defaultValue)

    fun getIntDetails(key: String, defaultValue: Long): FlagEvaluationDetailsInt =
        inner.getIntDetails(key, defaultValue)

    fun getNumberDetails(key: String, defaultValue: Double): FlagEvaluationDetailsNumber =
        inner.getNumberDetails(key, defaultValue)

    fun getJsonDetails(key: String, defaultValueJson: String): FlagEvaluationDetailsJson =
        inner.getJsonDetails(key, defaultValueJson)

    // Identity
    // Fire-and-forget: each call returns immediately and is applied in the
    // background in the order it was called, through the shared
    // IdentitySerializer. A failure is logged by the serializer and
    // swallowed, never thrown

    fun identify(
        userId: String,
        attributes: Map<String, AttributeValue> = emptyMap(),
        linkAnonymous: Boolean = true,
    ) {
        val context = attributes.toContextValues()
        serializer.enqueue { inner.identify(userId, context, linkAnonymous) }
    }

    fun signOut() {
        serializer.enqueue { inner.signOut() }
    }

    fun setContext(targetingKey: String, attributes: Map<String, AttributeValue> = emptyMap()) {
        val context = attributes.toContextValues()
        serializer.enqueue { inner.setContext(targetingKey, context) }
    }

    fun updateAttributes(attributes: Map<String, AttributeValue>) {
        val context = attributes.toContextValues()
        serializer.enqueue { inner.updateAttributes(context) }
    }

    fun removeAttributes(keys: List<String>) {
        serializer.enqueue { inner.removeAttributes(keys) }
    }

    // Auto-populated context
    // Internal surface for the platform wrapper to publish SDK-owned device,
    // session, and network attributes into the auto-populated context layer.
    // Not a developer API: developer attributes go through identify,
    // setContext, or updateAttributes

    /**
     * Awaited variant used once during initialize, before this client is
     * published, so the first synchronous read already evaluates against
     * the static device and session attributes
     */
    internal suspend fun setAutoPopulatedNow(attributes: Map<String, AttributeValue>) {
        inner.setAutoPopulatedAttributes(attributes.toContextValues())
    }

    /**
     * Ordered variant for live updates after initialize, enqueued on the
     * same serializer as the identity mutators so a network change and an
     * identify apply in call order
     */
    internal fun setAutoPopulated(attributes: Map<String, AttributeValue>) {
        val context = attributes.toContextValues()
        serializer.enqueue { inner.setAutoPopulatedAttributes(context) }
    }

    // State / lifecycle

    /** The current provider lifecycle state */
    fun state(): ProviderState = inner.state()

    /**
     * Tears this instance down: unregisters it as the default instance if it
     * still is one, stops the host polling timer and the network monitor,
     * cancels the per-instance coroutine scope (which also ends the identity
     * serializer's queue), and calls the generated `shutdown`. The on-disk
     * snapshot cache is preserved for the next launch. Idempotent: a second
     * call is a no-op
     */
    suspend fun shutdown() {
        if (!shuttingDown.compareAndSet(false, true)) return
        unregister?.invoke()
        timer?.stop()
        networkMonitor?.stop()
        scope.cancel()
        inner.shutdown()
    }

    // Observe

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
        val observeScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
        // The drain runs off the core delivery lane, so a handler that calls back
        // into the SDK cannot stall delivery
        observeScope.launch {
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
        return Cancellable(observation, observeScope)
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
