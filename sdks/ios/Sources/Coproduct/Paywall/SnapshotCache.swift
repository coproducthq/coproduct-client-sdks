import Foundation

/// How stale a cached snapshot may be served before an open block-fetches.
let snapshotTtl: TimeInterval = 6 * 60 * 60

/// Cache key for a paywall in an environment. `envSlug` is part of the key
/// because the same paywallId resolves to different content per environment.
func snapshotCacheKey(_ paywallId: String, _ envSlug: String?) -> String {
    "\(paywallId)|\(envSlug ?? "api")"
}

/// Fetches a snapshot, or `nil` when unresolved. Never throws: iOS'
/// `fetchPaywall` already collapses every failure to `nil`.
typealias SnapshotFetch = @Sendable () async -> PaywallSnapshot?

/// Process-level cache of fetched snapshots, with a TTL and stale-while-revalidate
/// reads. A snapshot is html plus a product-id map, never a price, so a stale
/// entry risks stale content, not a stale price.
actor SnapshotCache {
    private struct Entry {
        let snapshot: PaywallSnapshot
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    // A key's in-flight revalidation: both the dedup guard and the handle
    // `awaitRevalidation` awaits.
    private var revalidations: [String: Task<Void, Never>] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func resolve(_ key: String, _ fetchFn: @escaping SnapshotFetch) async -> PaywallSnapshot? {
        if let entry = entries[key] {
            if now().timeIntervalSince(entry.fetchedAt) < snapshotTtl {
                // Fresh: serve now, refresh for the next open (one at a time).
                if revalidations[key] == nil {
                    revalidations[key] = Task { await self.revalidate(key, fetchFn) }
                }
                return entry.snapshot
            }
            // Stale: refresh, but fall back to the stale snapshot if the
            // refetch returns nothing rather than failing the open.
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

    /// Awaits any in-flight revalidation for `key`; returns at once if none runs.
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
