package app.coproduct

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import uniffi.coproduct_ffi_uniffi.ProviderState

/** How long [Instances.waitForFirstPoll] sleeps between readiness checks */
private const val WAIT_FOR_FIRST_POLL_INTERVAL_NANOS = 25_000_000L

private const val NANOS_PER_SECOND = 1_000_000_000L

/**
 * Holds the single default Coproduct client and serializes initialize and
 * shutdown against it.
 *
 * Generic over [T], the public `CoproductClient` wrapper in production, so
 * the registry's concurrency and generation-fence logic is unit-testable
 * with a fake client and no Android or FFI dependency. Every read and write
 * of the default instance, the in-flight initialize, and the generation
 * counter happens under [lock]. Two concurrent [initialize] calls dedupe
 * onto a single in-flight build, and only the caller who claimed the slot
 * runs the build and the post-build publication; a later caller just awaits
 * the same result. The whole initialize, including the build, is fenced by
 * a generation counter: [shutdown] bumps it, so a build that finishes after
 * a shutdown raced it cannot resurrect the instance or overwrite whatever
 * instance (if any) exists afterward
 */
internal class Instances<T : Any>(
    private val stateOf: (T) -> ProviderState,
    private val shutdownClient: suspend (T) -> Unit,
    private val logWarning: (String) -> Unit = {},
    private val nowNanos: () -> Long = { System.nanoTime() },
    private val sleepNanos: suspend (Long) -> Unit = { nanos -> delay(nanos / 1_000_000) },
) {
    private val lock = Any()

    private data class Stored<T>(val client: T, val sdkKey: String)

    private var defaultStored: Stored<T>? = null
    private var inFlight: Deferred<T>? = null
    private var inFlightKey: String? = null
    private var inFlightScope: CoroutineScope? = null
    private var generation = 0

    /** The current default instance, or `null` before the first successful initialize */
    fun defaultInstance(): T? = synchronized(lock) { defaultStored?.client }

    /**
     * Resolves to an existing default instance, joins an in-flight
     * initialize for the same slot, or claims the slot and runs [build] to
     * construct a fresh one.
     *
     * [build] receives the per-instance [CoroutineScope] the caller should
     * hand to its host timer and identity serializer, so cancelling that
     * scope on [shutdown] tears both down with it. Once [build] returns,
     * the result is published only if no [shutdown] raced it since this
     * call was claimed. [waitForFirstPoll] then bounds how long this call
     * waits for the instance to become ready before returning it anyway,
     * because a slow or unreachable first poll never fails initialize
     */
    suspend fun initialize(
        sdkKey: String,
        startupTimeoutSecs: Long,
        scopeFactory: () -> CoroutineScope,
        build: suspend (CoroutineScope) -> T,
    ): T =
        when (val claim = claimInit(sdkKey, scopeFactory, build)) {
            is InitClaim.Existing -> claim.client
            is InitClaim.Pending -> claim.deferred.await().also { waitForFirstPoll(it, startupTimeoutSecs) }
        }

    /**
     * Clears the default instance if [client] is still the one stored,
     * without cancelling an in-flight initialize or bumping the generation.
     * Used so a direct `CoproductClient.shutdown()` call keeps the registry
     * in sync without going through the heavier [shutdown] path, which also
     * tears the client down itself
     */
    fun clearIfCurrent(client: T) {
        synchronized(lock) {
            if (defaultStored?.client === client) {
                defaultStored = null
            }
        }
    }

    /** Tears down the default instance, if any, and cancels an in-flight initialize, if any */
    suspend fun shutdown() {
        val (stored, pendingScope) = teardownLocked()
        pendingScope?.cancel()
        stored?.let { shutdownClient(it.client) }
    }

    /** Test-only seam: registers [client] as the current default instance without the full initialize flow */
    internal fun storeForTesting(client: T, sdkKey: String = "test"): Boolean =
        synchronized(lock) { storeIfCurrentLocked(client, sdkKey, generation) }

    private sealed class InitClaim<T> {
        data class Existing<T>(val client: T) : InitClaim<T>()

        data class Pending<T>(val deferred: Deferred<T>) : InitClaim<T>()
    }

    private fun claimInit(
        sdkKey: String,
        scopeFactory: () -> CoroutineScope,
        build: suspend (CoroutineScope) -> T,
    ): InitClaim<T> =
        synchronized(lock) {
            defaultStored?.let { stored ->
                if (stored.sdkKey != sdkKey) {
                    logWarning("initialize called with a different sdkKey; returning the existing instance")
                }
                return InitClaim.Existing(stored.client)
            }
            inFlight?.let { pending ->
                if (inFlightKey != sdkKey) {
                    logWarning(
                        "initialize called with a different sdkKey while initialization is in progress; " +
                            "joining the in-flight initialize",
                    )
                }
                return InitClaim.Pending(pending)
            }
            val claimedGeneration = generation
            val scope = scopeFactory()
            val deferred = scope.async { runInitialize(sdkKey, scope, claimedGeneration, build) }
            inFlight = deferred
            inFlightKey = sdkKey
            inFlightScope = scope
            InitClaim.Pending(deferred)
        }

    /**
     * Runs inside the [Deferred] claimed by [claimInit]: builds the client,
     * then publishes it only if this generation is still current. A build
     * that throws, or one that finishes after a shutdown already bumped the
     * generation, clears the in-flight slot (if it is still this call's) and
     * never publishes the result, so a later caller is not stuck joining
     * dead work or resurrecting a torn-down instance
     */
    private suspend fun runInitialize(
        sdkKey: String,
        scope: CoroutineScope,
        claimedGeneration: Int,
        build: suspend (CoroutineScope) -> T,
    ): T {
        val client =
            try {
                build(scope)
            } catch (error: Throwable) {
                if (!finishInFlight(claimedGeneration)) {
                    throw CancellationException("initialize cancelled by shutdown", error)
                }
                throw error
            }
        if (!storeIfCurrent(client, sdkKey, claimedGeneration)) {
            // A shutdown raced the build and already bumped the generation.
            // The orphaned client was never published, so it is torn down
            // here rather than left running with nothing holding it
            shutdownClient(client)
            throw CancellationException("initialize cancelled by shutdown")
        }
        return client
    }

    /**
     * Waits for [client] to leave [ProviderState.NOT_READY] before a
     * monotonic deadline [startupTimeoutSecs] seconds in the future.
     * Returns immediately (`true`) when [startupTimeoutSecs] is not
     * positive. Returns `false` immediately if a shutdown has already made
     * [client] no longer the default instance, and `false` if the deadline
     * passes while the state is still [ProviderState.NOT_READY]. A
     * monotonic clock is used so a wall-clock jump during launch cannot
     * stretch or truncate the wait. The return value does not fail
     * initialize either way: reads served during and after the wait fall
     * back to cache or developer defaults until the first poll lands
     */
    internal suspend fun waitForFirstPoll(client: T, startupTimeoutSecs: Long): Boolean {
        if (startupTimeoutSecs <= 0) return true
        val deadline = nowNanos() + startupTimeoutSecs * NANOS_PER_SECOND
        while (stateOf(client) == ProviderState.NOT_READY && nowNanos() < deadline) {
            if (!isCurrent(client)) return false
            sleepNanos(WAIT_FOR_FIRST_POLL_INTERVAL_NANOS)
        }
        return stateOf(client) != ProviderState.NOT_READY && isCurrent(client)
    }

    private fun isCurrent(client: T): Boolean = synchronized(lock) { defaultStored?.client === client }

    private fun storeIfCurrent(client: T, sdkKey: String, claimedGeneration: Int): Boolean =
        synchronized(lock) { storeIfCurrentLocked(client, sdkKey, claimedGeneration) }

    // Caller must hold `lock`
    private fun storeIfCurrentLocked(client: T, sdkKey: String, claimedGeneration: Int): Boolean {
        if (claimedGeneration != generation) return false
        inFlight = null
        inFlightKey = null
        inFlightScope = null
        defaultStored = Stored(client, sdkKey)
        return true
    }

    private fun finishInFlight(claimedGeneration: Int): Boolean =
        synchronized(lock) {
            if (claimedGeneration == generation) {
                inFlight = null
                inFlightKey = null
                inFlightScope = null
                true
            } else {
                false
            }
        }

    private fun teardownLocked(): Pair<Stored<T>?, CoroutineScope?> =
        synchronized(lock) {
            generation += 1
            val stored = defaultStored
            defaultStored = null
            val scope = inFlightScope
            inFlight = null
            inFlightKey = null
            inFlightScope = null
            stored to scope
        }
}
