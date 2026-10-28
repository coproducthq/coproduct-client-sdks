import Foundation

/// Hard cap on how stale a cached paywall snapshot may be served. Beyond it,
/// an open block-fetches fresh content rather than serving from cache.
let snapshotTtl: TimeInterval = 6 * 60 * 60

/// Builds the warm-cache key for a paywall in a given environment. `envSlug`
/// is part of the key because the same paywallId resolves to different content
/// on the content-CDN path than on the edge-api path, so the two must not share
/// an entry.
func snapshotCacheKey(_ paywallId: String, _ envSlug: String?) -> String {
    "\(paywallId)|\(envSlug ?? "api")"
}

/// Fetches a paywall snapshot, or `nil` when it is not resolved for this
/// environment. Never throws: on iOS `PaywallClient.fetchPaywall` already
/// collapses every failure to `nil`, so a failed refresh is indistinguishable
/// from an unresolved paywall here and both fall back to the cached entry.
typealias SnapshotFetch = @Sendable () async -> PaywallSnapshot?

/// Process-level warm cache of fetched snapshots. A snapshot is the paywall's
/// html plus its product-id map -- never a price, which is resolved live from
/// the store on every open -- so a stale entry only risks stale content, not a
/// stale price. Reads are stale-while-revalidate: a fresh entry renders now and
/// refetches in the background; an entry past the ttl block-fetches. Mirrors
/// sdks/react-native/coproduct/src/paywall/snapshotCache.ts and
/// sdks/flutter/coproduct/lib/src/paywall/snapshot_cache.dart.
actor SnapshotCache {
    private struct Entry {
        let snapshot: PaywallSnapshot
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    // A key's in-flight background revalidation, if any. Doubles as the dedup
    // guard -- a second fresh read for the same key while one is running does
    // not start another -- and as the handle `awaitRevalidation` awaits.
    private var revalidations: [String: Task<Void, Never>] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func resolve(_ key: String, _ fetchFn: @escaping SnapshotFetch) async -> PaywallSnapshot? {
        if let entry = entries[key] {
            if now().timeIntervalSince(entry.fetchedAt) < snapshotTtl {
                // Fresh: serve immediately, refresh for next open (at most one
                // revalidation per key in flight).
                if revalidations[key] == nil {
                    revalidations[key] = Task { await self.revalidate(key, fetchFn) }
                }
                return entry.snapshot
            }
            // Stale: try to refresh, but fall back to the stale snapshot rather
            // than failing the open if the refetch returns nothing.
            if let refreshed = await fetchFn() {
                entries[key] = Entry(snapshot: refreshed, fetchedAt: now())
                return refreshed
            }
            return entry.snapshot
        }
        // Cold miss: let a nil surface so the caller reports it.
        let fetched = await fetchFn()
        if let fetched {
            entries[key] = Entry(snapshot: fetched, fetchedAt: now())
        }
        return fetched
    }

    func warm(_ key: String, _ fetchFn: @escaping SnapshotFetch) async {
        if let fetched = await fetchFn() {
            entries[key] = Entry(snapshot: fetched, fetchedAt: now())
        }
    }

    /// Awaits any in-flight background revalidation for `key`, so a caller that
    /// needs the stale-while-revalidate refresh to have settled can observe it
    /// deterministically. Returns immediately when none is running.
    func awaitRevalidation(_ key: String) async {
        await revalidations[key]?.value
    }

    private func revalidate(_ key: String, _ fetchFn: @escaping SnapshotFetch) async {
        defer { revalidations[key] = nil }
        if let refreshed = await fetchFn() {
            entries[key] = Entry(snapshot: refreshed, fetchedAt: now())
        }
    }
}

/// One warm cache shared across every paywall mount and the prefetch statics.
let snapshotCache = SnapshotCache()
