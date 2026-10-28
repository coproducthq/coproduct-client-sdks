import 'package:coproduct/src/paywall/snapshot_cache.dart';
import 'package:coproduct/src/paywall/models/paywall_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

PaywallSnapshot snap(String id) => PaywallSnapshot(
      paywallId: id,
      version: 1,
      templateType: 'hero_single_offer',
      content: const PaywallContent(offeringKey: 'default', ctas: [], html: '<p/>'),
      packages: const {},
      html: '<p/>',
    );

void main() {
  test('snapshotCacheKey includes env, defaulting to api', () {
    expect(snapshotCacheKey('p1', 'production'), 'p1|production');
    expect(snapshotCacheKey('p1', null), 'p1|api');
  });

  test('cold miss blocks on fetch and stores', () async {
    final cache = SnapshotCache(now: () => DateTime(2026, 1, 1));
    var calls = 0;
    final out = await cache.resolve('p1|api', () async {
      calls++;
      return snap('p1');
    });
    expect(out?.paywallId, 'p1');
    expect(calls, 1);
  });

  test('cold miss propagates a thrown fetch error', () async {
    final cache = SnapshotCache(now: () => DateTime(2026, 1, 1));
    expect(
      () => cache.resolve('p1|api', () async => throw StateError('boom')),
      throwsA(isA<StateError>()),
    );
  });

  test('fresh hit serves cached now and revalidates in background', () async {
    var now = DateTime(2026, 1, 1);
    final cache = SnapshotCache(now: () => now);
    await cache.resolve('p1|api', () async => snap('v1'));

    now = DateTime(2026, 1, 1).add(snapshotTtl - const Duration(seconds: 1));
    final served = await cache.resolve('p1|api', () async => snap('v2'));
    expect(served?.paywallId, 'v1');
    await Future<void>.delayed(Duration.zero); // let revalidate settle

    final after = await cache.resolve('p1|api', () async => snap('v3'));
    expect(after?.paywallId, 'v2'); // background refresh applied
  });

  test('stale hit block-fetches and replaces', () async {
    var now = DateTime(2026, 1, 1);
    final cache = SnapshotCache(now: () => now);
    await cache.resolve('p1|api', () async => snap('v1'));
    now = DateTime(2026, 1, 1).add(snapshotTtl);
    final served = await cache.resolve('p1|api', () async => snap('v2'));
    expect(served?.paywallId, 'v2');
  });

  test('stale hit serves the stale snapshot when refetch fails', () async {
    var now = DateTime(2026, 1, 1);
    final cache = SnapshotCache(now: () => now);
    await cache.resolve('p1|api', () async => snap('v1'));
    now = DateTime(2026, 1, 1).add(snapshotTtl);
    final served =
        await cache.resolve('p1|api', () async => throw StateError('net'));
    expect(served?.paywallId, 'v1');
  });

  test('warm always fetches and stores', () async {
    var now = DateTime(2026, 1, 1);
    final cache = SnapshotCache(now: () => now);
    await cache.resolve('p1|api', () async => snap('v1'));
    now = DateTime(2026, 1, 1).add(const Duration(seconds: 1)); // fresh
    await cache.warm('p1|api', () async => snap('v2'));
    final served = await cache.resolve('p1|api', () async => snap('v3'));
    expect(served?.paywallId, 'v2');
  });
}
