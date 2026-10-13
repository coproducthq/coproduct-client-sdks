import { HttpPaywallClient } from '../httpPaywallClient';

function paywallJson() {
  return {
    paywallId: 'p-1',
    version: 1,
    templateType: 'hero_single_offer',
    content: {
      offeringKey: 'default',
      ctas: [{ packageKey: 'monthly', label: 'Subscribe' }],
      html: '<section><h1>Go Premium</h1></section>',
    },
    packages: { monthly: { iosProductId: 'premium_monthly' } },
    html: '<section></section>',
  };
}

function fakeResponse(ok: boolean, status: number, body: unknown) {
  return { ok, status, json: async () => body };
}

describe('HttpPaywallClient', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it('fetchPaywall sends the Bearer sdk key and parses the paywall field', async () => {
    const mockFetch = jest
      .fn()
      .mockResolvedValue(fakeResponse(true, 200, { paywall: paywallJson() }));
    global.fetch = mockFetch as unknown as typeof fetch;

    const client = new HttpPaywallClient({ sdkKey: 'cpk_mob_test' });
    const snapshot = await client.fetchPaywall('p-1');

    expect(mockFetch).toHaveBeenCalledWith(
      'https://sdk.coproduct.app/v1/paywalls/p-1',
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: 'Bearer cpk_mob_test',
        }),
      })
    );
    expect(snapshot?.paywallId).toBe('p-1');
  });

  it('fetchPaywall returns undefined on a 404', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue(
        fakeResponse(false, 404, { error: 'not found' })
      ) as unknown as typeof fetch;

    const client = new HttpPaywallClient({ sdkKey: 'cpk_mob_test' });
    expect(await client.fetchPaywall('missing')).toBeUndefined();
  });

  it('fetchPaywall fetches straight from the content CDN when envSlug is set, bypassing the api entirely', async () => {
    const mockFetch = jest
      .fn()
      .mockResolvedValue(fakeResponse(true, 200, paywallJson()));
    global.fetch = mockFetch as unknown as typeof fetch;

    const client = new HttpPaywallClient({
      sdkKey: 'cpk_mob_test',
      envSlug: 'production',
    });
    const snapshot = await client.fetchPaywall('p-1');

    expect(mockFetch).toHaveBeenCalledWith(
      'https://content.coproduct.app/paywalls/p-1/production/latest.json'
    );
    expect(snapshot?.paywallId).toBe('p-1');
    expect(snapshot?.version).toBe(1);
    expect(snapshot?.html).toBe('<section></section>');
  });

  it('fetchPaywall from the content CDN returns undefined on a 404 -- not deployed to this environment yet', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue(
        fakeResponse(false, 404, 'not found')
      ) as unknown as typeof fetch;

    const client = new HttpPaywallClient({
      sdkKey: 'cpk_mob_test',
      envSlug: 'production',
    });
    expect(await client.fetchPaywall('missing')).toBeUndefined();
  });

  it('fetchPaywall from the content CDN returns undefined on any failure, with no fallback to the api', async () => {
    const mockFetch = jest
      .fn()
      .mockResolvedValue(fakeResponse(false, 500, 'server error'));
    global.fetch = mockFetch as unknown as typeof fetch;

    const client = new HttpPaywallClient({
      sdkKey: 'cpk_mob_test',
      envSlug: 'production',
    });
    expect(await client.fetchPaywall('p-1')).toBeUndefined();
    expect(mockFetch).toHaveBeenCalledTimes(1);
    expect(mockFetch).toHaveBeenCalledWith(
      'https://content.coproduct.app/paywalls/p-1/production/latest.json'
    );
  });

  it('recordPurchase posts the snake_case transaction body and returns entitlements', async () => {
    const mockFetch = jest.fn().mockResolvedValue(
      fakeResponse(true, 200, {
        appUserId: 'user-1',
        entitlements: [
          {
            entitlementId: 'premium',
            isActive: true,
            expiresAt: null,
            willRenew: true,
            source: 'PURCHASE',
          },
        ],
      })
    );
    global.fetch = mockFetch as unknown as typeof fetch;

    const client = new HttpPaywallClient({ sdkKey: 'cpk_mob_test' });
    const entitlements = await client.recordPurchase({
      appUserId: 'user-1',
      platform: 'IOS',
      storeProductId: 'premium_monthly',
      storeTransactionId: 'tx-1',
      purchaseDate: new Date('2026-01-01T00:00:00.000Z'),
    });

    expect(mockFetch).toHaveBeenCalledWith(
      'https://api.coproduct.app/v1/purchases',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({
          app_user_id: 'user-1',
          platform: 'IOS',
          store_product_id: 'premium_monthly',
          transaction: {
            store_transaction_id: 'tx-1',
            purchase_date: '2026-01-01T00:00:00.000Z',
          },
        }),
      })
    );
    expect(entitlements[0]?.entitlementId).toBe('premium');
  });

  it("recordPurchase throws PaywallServerError with the server's code on rejection", async () => {
    global.fetch = jest.fn().mockResolvedValue(
      fakeResponse(false, 404, {
        error: 'Unknown product for this platform.',
        code: 'unknown_product',
      })
    ) as unknown as typeof fetch;

    const client = new HttpPaywallClient({ sdkKey: 'cpk_mob_test' });
    await expect(
      client.recordPurchase({
        appUserId: 'user-1',
        platform: 'IOS',
        storeProductId: 'nonexistent',
        storeTransactionId: 'tx-1',
        purchaseDate: new Date('2026-01-01T00:00:00.000Z'),
      })
    ).rejects.toMatchObject({ code: 'unknown_product' });
  });

  it('getEntitlements sends the appUserId query param and parses the entitlements list', async () => {
    const mockFetch = jest.fn().mockResolvedValue(
      fakeResponse(true, 200, {
        appUserId: 'user-1',
        entitlements: [
          {
            entitlementId: 'premium',
            isActive: true,
            expiresAt: null,
            willRenew: true,
            source: 'PURCHASE',
          },
        ],
      })
    );
    global.fetch = mockFetch as unknown as typeof fetch;

    const client = new HttpPaywallClient({ sdkKey: 'cpk_mob_test' });
    const entitlements = await client.getEntitlements('user-1');

    expect(mockFetch).toHaveBeenCalledWith(
      'https://api.coproduct.app/v1/entitlements?appUserId=user-1',
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: 'Bearer cpk_mob_test',
        }),
      })
    );
    expect(entitlements[0]?.entitlementId).toBe('premium');
  });

  it('getEntitlements throws PaywallServerError on a non-2xx response', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue(
        fakeResponse(false, 401, { error: 'Invalid or expired SDK key.' })
      ) as unknown as typeof fetch;

    const client = new HttpPaywallClient({ sdkKey: 'cpk_mob_test' });
    await expect(client.getEntitlements('user-1')).rejects.toMatchObject({
      statusCode: 401,
    });
  });

  it('identify posts the snake_case body', async () => {
    const mockFetch = jest.fn().mockResolvedValue(
      fakeResponse(true, 200, {
        appUserId: 'user-1',
        targetingKey: 'alice@example.com',
      })
    );
    global.fetch = mockFetch as unknown as typeof fetch;

    const client = new HttpPaywallClient({ sdkKey: 'cpk_mob_test' });
    await client.identify({
      appUserId: 'user-1',
      targetingKey: 'alice@example.com',
    });

    expect(mockFetch).toHaveBeenCalledWith(
      'https://api.coproduct.app/v1/identify',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({
          app_user_id: 'user-1',
          targeting_key: 'alice@example.com',
        }),
      })
    );
  });

  it('identify throws PaywallServerError on a non-2xx response', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue(
        fakeResponse(false, 400, { error: 'app_user_id is required.' })
      ) as unknown as typeof fetch;

    const client = new HttpPaywallClient({ sdkKey: 'cpk_mob_test' });
    await expect(
      client.identify({ appUserId: '', targetingKey: 'alice@example.com' })
    ).rejects.toMatchObject({ statusCode: 400 });
  });
});
