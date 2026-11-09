import type { PaywallSnapshot } from './models/paywallSnapshot';

// Hard cap on how stale a cached paywall snapshot may be served. Beyond it,
// an open block-fetches fresh content rather than serving from cache.
export const SNAPSHOT_TTL_MS = 6 * 60 * 60 * 1000;

export type SnapshotFetch = () => Promise<PaywallSnapshot | undefined>;

interface SnapshotCacheEntry {
  snapshot: PaywallSnapshot;
  fetchedAtMs: number;
}

export function snapshotCacheKey(paywallId: string, envSlug?: string): string {
  return `${paywallId}|${envSlug ?? 'api'}`;
}

// Process-level warm cache of fetched snapshots. A snapshot is the paywall's
// html plus its product-id map -- never a price, which is resolved live from
// the store on every open -- so a stale entry only risks stale content, not a
// stale price. Reads are stale-while-revalidate: a fresh entry renders now and
// refetches in the background; an entry past the TTL block-fetches.
export class SnapshotCache {
  private readonly entries = new Map<string, SnapshotCacheEntry>();
  private readonly inFlight = new Set<string>();
  private readonly now: () => number;

  constructor(now: () => number = () => Date.now()) {
    this.now = now;
  }

  async resolve(
    key: string,
    fetchFn: SnapshotFetch
  ): Promise<PaywallSnapshot | undefined> {
    const entry = this.entries.get(key);
    if (entry != null) {
      if (this.now() - entry.fetchedAtMs < SNAPSHOT_TTL_MS) {
        // Fresh: serve immediately, refresh for next open.
        void this.revalidate(key, fetchFn);
        return entry.snapshot;
      }
      // Stale: try to refresh, but fall back to the stale snapshot rather than
      // failing the open if the refetch errors or returns nothing.
      const refreshed = await this.safeFetch(fetchFn);
      if (refreshed != null) {
        this.entries.set(key, { snapshot: refreshed, fetchedAtMs: this.now() });
        return refreshed;
      }
      return entry.snapshot;
    }
    // Cold miss: let the error/undefined surface so the caller reports it.
    const fetched = await fetchFn();
    if (fetched != null) {
      this.entries.set(key, { snapshot: fetched, fetchedAtMs: this.now() });
    }
    return fetched;
  }

  async warm(key: string, fetchFn: SnapshotFetch): Promise<void> {
    const fetched = await this.safeFetch(fetchFn);
    if (fetched != null) {
      this.entries.set(key, { snapshot: fetched, fetchedAtMs: this.now() });
    }
  }

  private async revalidate(key: string, fetchFn: SnapshotFetch): Promise<void> {
    if (this.inFlight.has(key)) return;
    this.inFlight.add(key);
    try {
      const refreshed = await this.safeFetch(fetchFn);
      if (refreshed != null) {
        this.entries.set(key, { snapshot: refreshed, fetchedAtMs: this.now() });
      }
    } finally {
      this.inFlight.delete(key);
    }
  }

  private async safeFetch(
    fetchFn: SnapshotFetch
  ): Promise<PaywallSnapshot | undefined> {
    try {
      return await fetchFn();
    } catch {
      return undefined;
    }
  }
}

// One warm cache shared across every paywall mount and the prefetch statics.
export const snapshotCache = new SnapshotCache();
