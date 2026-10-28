import { SnapshotCache, snapshotCacheKey, SNAPSHOT_TTL_MS } from '../snapshotCache';
import type { PaywallSnapshot } from '../models/paywallSnapshot';

function snap(id: string): PaywallSnapshot {
  return {
    paywallId: id,
    version: 1,
    templateType: 'hero_single_offer',
    content: { offeringKey: 'default', ctas: [], html: '<p/>' },
    packages: {},
    html: '<p/>',
  };
}

describe('snapshotCacheKey', () => {
  it('includes env, defaulting to api', () => {
    expect(snapshotCacheKey('p1', 'production')).toBe('p1|production');
    expect(snapshotCacheKey('p1')).toBe('p1|api');
  });
});

describe('SnapshotCache', () => {
  it('cold miss blocks on fetch and stores the entry', async () => {
    const cache = new SnapshotCache(() => 1000);
    const fetchFn = jest.fn().mockResolvedValue(snap('p1'));
    const out = await cache.resolve('p1|api', fetchFn);
    expect(out?.paywallId).toBe('p1');
    expect(fetchFn).toHaveBeenCalledTimes(1);
  });

  it('cold miss propagates a thrown fetch error', async () => {
    const cache = new SnapshotCache(() => 1000);
    const fetchFn = jest.fn().mockRejectedValue(new Error('boom'));
    await expect(cache.resolve('p1|api', fetchFn)).rejects.toThrow('boom');
  });

  it('fresh hit serves cached immediately and revalidates in the background', async () => {
    let now = 1000;
    const cache = new SnapshotCache(() => now);
    const first = jest.fn().mockResolvedValue(snap('v1'));
    await cache.resolve('p1|api', first); // stores at t=1000

    now = 1000 + SNAPSHOT_TTL_MS - 1; // still fresh
    const second = jest.fn().mockResolvedValue(snap('v2'));
    const served = await cache.resolve('p1|api', second);
    expect(served?.paywallId).toBe('v1'); // served the cached one
    await Promise.resolve(); // let background revalidate settle
    expect(second).toHaveBeenCalledTimes(1); // revalidate fired

    const third = jest.fn().mockResolvedValue(snap('v3'));
    const after = await cache.resolve('p1|api', third);
    expect(after?.paywallId).toBe('v2'); // background refresh updated the entry
  });

  it('stale hit block-fetches and replaces the entry', async () => {
    let now = 1000;
    const cache = new SnapshotCache(() => now);
    await cache.resolve('p1|api', jest.fn().mockResolvedValue(snap('v1')));
    now = 1000 + SNAPSHOT_TTL_MS; // exactly at cap => stale
    const served = await cache.resolve('p1|api', jest.fn().mockResolvedValue(snap('v2')));
    expect(served?.paywallId).toBe('v2');
  });

  it('stale hit serves the stale snapshot when refetch fails', async () => {
    let now = 1000;
    const cache = new SnapshotCache(() => now);
    await cache.resolve('p1|api', jest.fn().mockResolvedValue(snap('v1')));
    now = 1000 + SNAPSHOT_TTL_MS;
    const served = await cache.resolve('p1|api', jest.fn().mockRejectedValue(new Error('net')));
    expect(served?.paywallId).toBe('v1'); // no throw, stale served
  });

  it('dedups concurrent background revalidations', async () => {
    let now = 1000;
    const cache = new SnapshotCache(() => now);
    await cache.resolve('p1|api', jest.fn().mockResolvedValue(snap('v1')));
    now = 1000 + 1; // fresh
    const fetchFn = jest.fn().mockResolvedValue(snap('v2'));
    await cache.resolve('p1|api', fetchFn);
    await cache.resolve('p1|api', fetchFn);
    await Promise.resolve();
    expect(fetchFn).toHaveBeenCalledTimes(1); // second revalidate deduped
  });

  it('warm always fetches and stores', async () => {
    let now = 1000;
    const cache = new SnapshotCache(() => now);
    await cache.resolve('p1|api', jest.fn().mockResolvedValue(snap('v1')));
    now = 1000 + 1; // fresh
    await cache.warm('p1|api', jest.fn().mockResolvedValue(snap('v2')));
    const served = await cache.resolve('p1|api', jest.fn().mockResolvedValue(snap('v3')));
    expect(served?.paywallId).toBe('v2'); // warm overwrote even while fresh
  });
});
