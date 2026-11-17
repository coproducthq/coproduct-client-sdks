package app.coproduct

import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
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

/**
 * Tells the server that this install's anonymous id now belongs to an
 * identified user, so purchases recorded against the anonymous id follow the
 * user. Best-effort: the request runs on [scope], a failure is logged and
 * never reaches the caller, and an identical pair is sent at most once (a
 * failed send may be retried by a later identify).
 */
internal class IdentifyLinker(
    private val scope: CoroutineScope,
    private val anonymousId: () -> String?,
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
            try {
                post(anonymous, userId)
            } catch (cancelled: CancellationException) {
                synchronized(sent) { sent.remove(pair) }
                throw cancelled
            } catch (error: Throwable) {
                synchronized(sent) { sent.remove(pair) }
                try {
                    Log.w("Coproduct", "identify could not be sent to the server", error)
                } catch (_: Throwable) {
                    // Log.w is unmocked under plain JUnit; logging must never fail the link.
                }
            }
        }
    }
}
