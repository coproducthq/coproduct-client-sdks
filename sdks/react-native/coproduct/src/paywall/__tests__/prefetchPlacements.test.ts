jest.mock('react-native-webview', () => ({ WebView: () => null }));

import { CoproductPaywall } from '../CoproductPaywall';
import { snapshotCache, snapshotCacheKey } from '../snapshotCache';
import type { PaywallClient } from '../paywallClient';
import type { PaywallSnapshot } from '../models/paywallSnapshot';

function snap(id: string): PaywallSnapshot {
  return {
    paywallId: id, version: 1, templateType: 't',
    content: { offeringKey: 'default', ctas: [], html: '' }, packages: {}, html: '',
  };
}

describe('CoproductPaywall.prefetchPlacements', () => {
  it('resolves each flag key to a paywallId, warms it, skips empties and dedups', async () => {
    const reader = {
      getString: (key: string, _d: string) =>
        ({ 'f.paid': 'pw1', 'f.also': 'pw1', 'f.empty': '' } as Record<string, string>)[key] ?? '',
    };
    const fetched: string[] = [];
    const paywallClient: PaywallClient = {
      fetchPaywall: async (id: string) => { fetched.push(id); return snap(id); },
      recordPurchase: async () => [],
      getEntitlements: async () => [],
      identify: async () => {},
    };

    await CoproductPaywall.prefetchPlacements({
      client: reader,
      flagKeys: ['f.paid', 'f.also', 'f.empty'],
      sdkKey: 'cpk_test',
      envSlug: 'production',
      paywallClient,
    });

    expect(fetched).toEqual(['pw1']); // deduped, empty skipped
    const served = await snapshotCache.resolve(
      snapshotCacheKey('pw1', 'production'),
      async () => undefined
    );
    expect(served?.paywallId).toBe('pw1'); // warmed into the cache
  });
});
