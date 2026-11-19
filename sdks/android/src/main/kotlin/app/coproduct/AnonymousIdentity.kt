package app.coproduct

import android.util.Log
import app.coproduct.paywall.PaywallServerError
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.coproduct_ffi_uniffi.HostSecureStore

// Owned by the Rust core (core/coproduct-core/src/identity.rs) and shared by
// every SDK, so it is deliberately not app.coproduct namespaced.
internal const val ANONYMOUS_ID_STORAGE_KEY = "coproduct.anonymous_id"

/**
 * Wraps the host secure store so the SDK can expose this install's anonymous
 * id without a core getter: the core reads and writes the id through this
 * store, so the last value seen for [ANONYMOUS_ID_STORAGE_KEY] is the id the
 * core is using. A write is remembered before it is attempted, because the
 * core keeps using that id for the session even when persisting it fails.
 */
internal class AnonymousIdCapturingSecureStore(
    private val delegate: HostSecureStore,
) : HostSecureStore {
    @Volatile
    var anonymousId: String? = null
        private set

    override suspend fun read(key: String): String? {
        val value = delegate.read(key)
        if (key == ANONYMOUS_ID_STORAGE_KEY && !value.isNullOrEmpty()) anonymousId = value
        return value
    }

    override suspend fun write(key: String, value: String) {
        if (key == ANONYMOUS_ID_STORAGE_KEY) anonymousId = value
        delegate.write(key, value)
    }
}

/** The waits before each retry of a link that failed for a reason that can pass: two seconds, ten seconds, then a minute. */
internal val DEFAULT_LINK_RETRY_DELAYS_MS: List<Long> = listOf(2_000L, 10_000L, 60_000L)

/**
 * Tells the server that this install's anonymous id now belongs to an
 * identified user, so purchases recorded against the anonymous id follow the
 * user. Best-effort: the request runs on [scope], a failure is logged and
 * never reaches the caller, and an identical pair is sent at most once.
 *
 * A request that fails because the network is down, times out, or the server
 * is busy is tried again after each of [retryDelaysMs], and only logs if it
 * never gets through. The install limit is expected too. A pair that gave up is
 * forgotten, so a later identify sends it again.
 */
internal class IdentifyLinker(
    private val scope: CoroutineScope,
    private val anonymousId: () -> String?,
    private val retryDelaysMs: List<Long> = DEFAULT_LINK_RETRY_DELAYS_MS,
    private val post: suspend (anonymousId: String, userId: String) -> Unit,
) {
    private val sent = mutableSetOf<Pair<String, String>>()

    /** Returns the launched request, or null when there is nothing to send. */
    fun link(userId: String, linkAnonymous: Boolean): Job? {
        if (!linkAnonymous) return null
        val anonymous = anonymousId()
        if (anonymous.isNullOrEmpty() || anonymous == userId) return null
        val pair = anonymous to userId
        synchronized(sent) { if (!sent.add(pair)) return null }
        return scope.launch {
            var retries = 0
            while (true) {
                val failure = try {
                    post(anonymous, userId)
                    return@launch
                } catch (cancelled: CancellationException) {
                    synchronized(sent) { sent.remove(pair) }
                    throw cancelled
                } catch (error: Throwable) {
                    error
                }
                if (canPass(failure) && retries < retryDelaysMs.size) {
                    try {
                        delay(retryDelaysMs[retries])
                    } catch (cancelled: CancellationException) {
                        synchronized(sent) { sent.remove(pair) }
                        throw cancelled
                    }
                    retries += 1
                    continue
                }
                synchronized(sent) { sent.remove(pair) }
                warn(
                    if (isExpected(failure)) {
                        "could not link this install to the signed-in user yet"
                    } else {
                        "identify could not be sent to the server"
                    },
                    failure,
                )
                return@launch
            }
        }
    }

    private fun warn(message: String, error: Throwable) {
        try {
            Log.w("Coproduct", message, error)
        } catch (_: Throwable) {
            // Log.w is unmocked under plain JUnit; logging must never fail the link.
        }
    }

    companion object {
        /** Whether the same request can succeed later: no network, a timeout, no answer, or a server that is busy or failing. */
        private fun canPass(error: Throwable): Boolean {
            if (error is IOException) return true
            if (error is PaywallServerError) {
                val status = error.statusCode
                return status == 0 || status == 408 || status == 429 || status >= 500
            }
            return false
        }

        /** Failures that are not a bug in the app: the ones above that never got through, and the project's limit on installs linked to one user. */
        private fun isExpected(error: Throwable): Boolean =
            canPass(error) || (error is PaywallServerError && error.code == "install_limit_reached")
    }
}
