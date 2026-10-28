import 'dart:async' show unawaited;

import 'models/paywall_snapshot.dart';

/// Hard cap on how stale a cached paywall snapshot may be served. Beyond it, an
/// open block-fetches fresh content rather than serving from cache.
const Duration snapshotTtl = Duration(hours: 6);

typedef SnapshotFetch = Future<PaywallSnapshot?> Function();

String snapshotCacheKey(String paywallId, String? envSlug) =>
    '$paywallId|${envSlug ?? 'api'}';

class _Entry {
  _Entry(this.snapshot, this.fetchedAt);
  final PaywallSnapshot snapshot;
  final DateTime fetchedAt;
}

/// Process-level warm cache of fetched snapshots. A snapshot is the paywall's
/// html plus its product-id map -- never a price, which is resolved live from
/// the store on every open -- so a stale entry only risks stale content, not a
/// stale price. Reads are stale-while-revalidate: a fresh entry renders now and
/// refetches in the background; an entry past the TTL block-fetches. Mirrors
/// sdks/react-native/coproduct/src/paywall/snapshotCache.ts.
class SnapshotCache {
  SnapshotCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, _Entry> _entries = {};
  final Set<String> _inFlight = {};

  Future<PaywallSnapshot?> resolve(String key, SnapshotFetch fetchFn) async {
    final entry = _entries[key];
    if (entry != null) {
      if (_now().difference(entry.fetchedAt) < snapshotTtl) {
        // Fresh: serve immediately, refresh for next open.
        unawaited(_revalidate(key, fetchFn));
        return entry.snapshot;
      }
      // Stale: try to refresh, but fall back to the stale snapshot rather than
      // failing the open if the refetch errors or returns nothing.
      final refreshed = await _safeFetch(fetchFn);
      if (refreshed != null) {
        _entries[key] = _Entry(refreshed, _now());
        return refreshed;
      }
      return entry.snapshot;
    }
    // Cold miss: let the error/null surface so the caller reports it.
    final fetched = await fetchFn();
    if (fetched != null) _entries[key] = _Entry(fetched, _now());
    return fetched;
  }

  Future<void> warm(String key, SnapshotFetch fetchFn) async {
    final fetched = await _safeFetch(fetchFn);
    if (fetched != null) _entries[key] = _Entry(fetched, _now());
  }

  Future<void> _revalidate(String key, SnapshotFetch fetchFn) async {
    if (_inFlight.contains(key)) return;
    _inFlight.add(key);
    try {
      final refreshed = await _safeFetch(fetchFn);
      if (refreshed != null) _entries[key] = _Entry(refreshed, _now());
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<PaywallSnapshot?> _safeFetch(SnapshotFetch fetchFn) async {
    try {
      return await fetchFn();
    } catch (_) {
      return null;
    }
  }
}

/// One warm cache shared across every paywall mount and the prefetch statics.
final SnapshotCache snapshotCache = SnapshotCache();
