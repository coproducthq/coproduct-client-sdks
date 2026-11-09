package app.coproduct.paywall

import app.coproduct.paywall.models.PaywallSnapshot
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** How stale a cached snapshot may be served before an open block-fetches. */
const val SNAPSHOT_TTL_MS: Long = 6L * 60 * 60 * 1000

fun snapshotCacheKey(paywallId: String, envSlug: String?): String =
    "$paywallId|${envSlug ?: "api"}"

typealias SnapshotFetch = suspend () -> PaywallSnapshot?

/**
 * Process-level cache of fetched snapshots, with a TTL and stale-while-revalidate
 * reads. A snapshot is html plus a product-id map, never a price, so a stale
 * entry risks stale content, not a stale price. [now]/[scope] are injectable for tests.
 */
class SnapshotCache(
    private val now: () -> Long = System::currentTimeMillis,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob()),
) {
    private data class Entry(val snapshot: PaywallSnapshot, val fetchedAt: Long)

    private val mutex = Mutex()
    private val entries = mutableMapOf<String, Entry>()

    // A key's in-flight revalidation: both the dedup guard and the handle
    // awaitRevalidation joins.
    private val revalidations = mutableMapOf<String, Job>()

    suspend fun resolve(key: String, fetchFn: SnapshotFetch): PaywallSnapshot? {
        val entry = mutex.withLock { entries[key] }
        if (entry != null) {
            if (now() - entry.fetchedAt < SNAPSHOT_TTL_MS) {
                // Fresh: serve now, refresh for the next open (one at a time).
                mutex.withLock {
                    if (revalidations[key] == null) {
                        revalidations[key] = scope.launch { revalidate(key, fetchFn) }
                    }
                }
                return entry.snapshot
            }
            // Stale: refresh, but fall back to the stale snapshot if the
            // refetch errors or returns nothing rather than failing the open.
            val refreshed = safeFetch(fetchFn)
            if (refreshed != null) {
                mutex.withLock { entries[key] = Entry(refreshed, now()) }
                return refreshed
            }
            return entry.snapshot
        }
        // Cold miss: let the error/null surface so the caller reports it.
        val fetched = fetchFn()
        if (fetched != null) mutex.withLock { entries[key] = Entry(fetched, now()) }
        return fetched
    }

    suspend fun warm(key: String, fetchFn: SnapshotFetch) {
        val fetched = safeFetch(fetchFn)
        if (fetched != null) mutex.withLock { entries[key] = Entry(fetched, now()) }
    }

    /** Joins any in-flight revalidation for [key]; returns at once if none runs. */
    suspend fun awaitRevalidation(key: String) {
        mutex.withLock { revalidations[key] }?.join()
    }

    private suspend fun revalidate(key: String, fetchFn: SnapshotFetch) {
        try {
            val refreshed = safeFetch(fetchFn)
            if (refreshed != null) mutex.withLock { entries[key] = Entry(refreshed, now()) }
        } finally {
            mutex.withLock { revalidations.remove(key) }
        }
    }

    private suspend fun safeFetch(fetchFn: SnapshotFetch): PaywallSnapshot? =
        try {
            fetchFn()
        } catch (_: Exception) {
            null
        }
}

/** One warm cache shared across every paywall mount and the prefetch statics. */
val snapshotCache = SnapshotCache()
