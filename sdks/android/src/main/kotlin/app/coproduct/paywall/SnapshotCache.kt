package app.coproduct.paywall

import app.coproduct.paywall.models.PaywallSnapshot
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Hard cap on how stale a cached paywall snapshot may be served. Beyond it, an
 * open block-fetches fresh content rather than serving from cache.
 */
const val SNAPSHOT_TTL_MS: Long = 6L * 60 * 60 * 1000

fun snapshotCacheKey(paywallId: String, envSlug: String?): String =
    "$paywallId|${envSlug ?: "api"}"

typealias SnapshotFetch = suspend () -> PaywallSnapshot?

/**
 * Process-level warm cache of fetched snapshots. A snapshot is the paywall's
 * html plus its product-id map -- never a price, which is resolved live from
 * the store on every open -- so a stale entry only risks stale content, not a
 * stale price. Reads are stale-while-revalidate: a fresh entry renders now and
 * refetches in the background; an entry past the ttl block-fetches. Mirrors
 * sdks/react-native/coproduct/src/paywall/snapshotCache.ts and
 * sdks/flutter/coproduct/lib/src/paywall/snapshot_cache.dart.
 *
 * [now] and [scope] are injectable so a test can step time across the ttl
 * boundary and drive the background revalidation deterministically; production
 * uses the wall clock and an own background scope.
 */
class SnapshotCache(
    private val now: () -> Long = System::currentTimeMillis,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob()),
) {
    private data class Entry(val snapshot: PaywallSnapshot, val fetchedAt: Long)

    private val mutex = Mutex()
    private val entries = mutableMapOf<String, Entry>()

    // A key's in-flight background revalidation, if any. Doubles as the dedup
    // guard -- a second fresh read for the same key while one is running does
    // not start another -- and as the handle [awaitRevalidation] joins.
    private val revalidations = mutableMapOf<String, Job>()

    suspend fun resolve(key: String, fetchFn: SnapshotFetch): PaywallSnapshot? {
        val entry = mutex.withLock { entries[key] }
        if (entry != null) {
            if (now() - entry.fetchedAt < SNAPSHOT_TTL_MS) {
                // Fresh: serve immediately, refresh for next open (at most one
                // revalidation per key in flight).
                mutex.withLock {
                    if (revalidations[key] == null) {
                        revalidations[key] = scope.launch { revalidate(key, fetchFn) }
                    }
                }
                return entry.snapshot
            }
            // Stale: try to refresh, but fall back to the stale snapshot rather
            // than failing the open if the refetch errors or returns nothing.
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

    /**
     * Joins any in-flight background revalidation for [key], so a caller that
     * needs the stale-while-revalidate refresh to have settled can observe it
     * deterministically. Returns immediately when none is running.
     */
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
