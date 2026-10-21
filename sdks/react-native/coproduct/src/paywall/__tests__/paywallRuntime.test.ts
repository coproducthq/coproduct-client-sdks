import { PaywallRuntime, type PaywallPurchaseError } from '../paywallRuntime';
import { PaywallServerError, type PaywallClient } from '../paywallClient';
import type {
  NativePaywallBridge,
  PackageKind,
  PurchaseResult,
  RestoredTransaction,
} from '../nativePaywallBridge';
import type {
  PaywallSnapshot,
  PaywallPackageRef,
} from '../models/paywallSnapshot';
import type { Entitlement } from '../models/entitlement';

class FakeNativePaywallBridge implements NativePaywallBridge {
  pricesByProductId: Record<string, string>;
  productIdsThatThrow: Set<string>;
  nextPurchaseResult: PurchaseResult;
  restoredTransactions: RestoredTransaction[];
  purchaseCalls: string[] = [];
  priceForCalls: Array<{ productId: string; kind: PackageKind }> = [];
  purchaseKinds: Array<{ productId: string; kind: PackageKind }> = [];

  constructor(
    args: {
      pricesByProductId?: Record<string, string>;
      productIdsThatThrow?: Set<string>;
      nextPurchaseResult?: PurchaseResult;
      restoredTransactions?: RestoredTransaction[];
    } = {}
  ) {
    this.pricesByProductId = args.pricesByProductId ?? {};
    this.productIdsThatThrow = args.productIdsThatThrow ?? new Set();
    this.nextPurchaseResult = args.nextPurchaseResult ?? {
      outcome: 'cancelled',
    };
    this.restoredTransactions = args.restoredTransactions ?? [];
  }

  async priceFor(productId: string, kind: PackageKind): Promise<string> {
    this.priceForCalls.push({ productId, kind });
    if (this.productIdsThatThrow.has(productId)) {
      throw new Error(`STOREKIT_ERROR: unknown product ${productId}`);
    }
    const price = this.pricesByProductId[productId];
    if (price == null) throw new Error('PaywallBridgeUnavailable');
    return price;
  }

  async purchase(
    productId: string,
    kind: PackageKind
  ): Promise<PurchaseResult> {
    this.purchaseCalls.push(productId);
    this.purchaseKinds.push({ productId, kind });
    return this.nextPurchaseResult;
  }

  async restore(): Promise<RestoredTransaction[]> {
    return this.restoredTransactions;
  }
}

class FakePaywallClient implements PaywallClient {
  rejectNextPurchase = false;
  throwNetworkErrorNextPurchase = false;
  transactionIdsThatThrow: Set<string> = new Set();
  recordedTransactionIds: string[] = [];
  recordedPlatforms: string[] = [];

  async fetchPaywall(): Promise<PaywallSnapshot | undefined> {
    return undefined;
  }

  async recordPurchase(args: {
    appUserId: string;
    platform: string;
    storeProductId: string;
    storeTransactionId: string;
    purchaseDate: Date;
    expiresDate?: Date;
  }): Promise<Entitlement[]> {
    if (this.rejectNextPurchase) {
      throw new PaywallServerError({
        statusCode: 404,
        code: 'unknown_product',
        message: 'Unknown product.',
      });
    }
    if (
      this.throwNetworkErrorNextPurchase ||
      this.transactionIdsThatThrow.has(args.storeTransactionId)
    ) {
      throw new Error('Connection failed');
    }
    this.recordedTransactionIds.push(args.storeTransactionId);
    this.recordedPlatforms.push(args.platform);
    return [
      {
        entitlementId: 'premium',
        isActive: true,
        willRenew: true,
        source: 'PURCHASE',
      },
    ];
  }

  async getEntitlements(): Promise<Entitlement[]> {
    return [];
  }

  async identify(): Promise<void> {}
}

function buildSnapshot(
  packages: Record<string, PaywallPackageRef> = {}
): PaywallSnapshot {
  return {
    paywallId: 'p-1',
    version: 1,
    templateType: 'hero_single_offer',
    content: {
      offeringKey: 'default',
      ctas: [{ packageKey: 'monthly', label: 'Subscribe' }],
      html: '<section><h1>Go Premium</h1></section>',
    },
    packages,
    html: '<section></section>',
  };
}

describe('PaywallRuntime', () => {
  it('onSnapshotLoaded resolves a price for every cta with a known product id', async () => {
    const bridge = new FakeNativePaywallBridge({
      pricesByProductId: { premium_monthly: '$9.99/mo' },
    });
    const client = new FakePaywallClient();
    let capturedPrices: Record<string, string> | undefined;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async (prices) => {
        capturedPrices = prices;
      },
    });

    await runtime.onSnapshotLoaded(
      buildSnapshot({ monthly: { iosProductId: 'premium_monthly' } })
    );

    expect(capturedPrices).toEqual({ monthly: '$9.99/mo' });
  });

  it("onSnapshotLoaded passes each package's kind through to priceFor, defaulting to subscription when unset", async () => {
    const bridge = new FakeNativePaywallBridge({
      pricesByProductId: {
        premium_monthly: '$9.99/mo',
        points_pack_300: '$4.99',
      },
    });
    const client = new FakePaywallClient();
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async () => {},
    });

    const snapshot: PaywallSnapshot = {
      paywallId: 'p-1',
      version: 1,
      templateType: 'hero_single_offer',
      content: {
        offeringKey: 'default',
        ctas: [
          { packageKey: 'monthly', label: 'Subscribe monthly' },
          { packageKey: 'points_pack', label: 'Buy points' },
        ],
        html: '<section></section>',
      },
      packages: {
        monthly: { iosProductId: 'premium_monthly' },
        points_pack: { iosProductId: 'points_pack_300', kind: 'consumable' },
      },
      html: '<section></section>',
    };

    await runtime.onSnapshotLoaded(snapshot);

    expect(bridge.priceForCalls).toEqual(
      expect.arrayContaining([
        { productId: 'premium_monthly', kind: 'subscription' },
        { productId: 'points_pack_300', kind: 'consumable' },
      ])
    );
  });

  it('onSnapshotLoaded does not call setPrices when no cta resolves a product id', async () => {
    const bridge = new FakeNativePaywallBridge();
    const client = new FakePaywallClient();
    let setPricesCalled = false;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async () => {
        setPricesCalled = true;
      },
    });

    await runtime.onSnapshotLoaded(buildSnapshot());

    expect(setPricesCalled).toBe(false);
  });

  it('onSnapshotLoaded skips a product whose priceFor throws, without aborting the rest', async () => {
    const bridge = new FakeNativePaywallBridge({
      pricesByProductId: { premium_annual: '$89.99/yr' },
      productIdsThatThrow: new Set(['premium_monthly']),
    });
    const client = new FakePaywallClient();
    let capturedPrices: Record<string, string> | undefined;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async (prices) => {
        capturedPrices = prices;
      },
    });

    const snapshot: PaywallSnapshot = {
      paywallId: 'p-1',
      version: 1,
      templateType: 'hero_single_offer',
      content: {
        offeringKey: 'default',
        ctas: [
          { packageKey: 'monthly', label: 'Subscribe monthly' },
          { packageKey: 'annual', label: 'Subscribe annually' },
        ],
        html: '<section><h1>Go Premium</h1></section>',
      },
      packages: {
        monthly: { iosProductId: 'premium_monthly' },
        annual: { iosProductId: 'premium_annual' },
      },
      html: '<section></section>',
    };

    await runtime.onSnapshotLoaded(snapshot);

    expect(capturedPrices).toEqual({ annual: '$89.99/yr' });
  });

  it('a purchase tap resolves the product id, purchases, and reports the result', async () => {
    const bridge = new FakeNativePaywallBridge({
      nextPurchaseResult: {
        outcome: 'success',
        transactionId: 'tx-1',
        productId: 'premium_monthly',
        purchaseDate: new Date('2026-01-01T00:00:00.000Z'),
      },
    });
    const client = new FakePaywallClient();
    let capturedResult: PurchaseResult | undefined;
    let capturedEntitlements: Entitlement[] | undefined;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async () => {},
      onPurchaseResult: (result, entitlements) => {
        capturedResult = result;
        capturedEntitlements = entitlements;
      },
    });
    await runtime.onSnapshotLoaded(
      buildSnapshot({ monthly: { iosProductId: 'premium_monthly' } })
    );

    const decision = await runtime.handleNavigationRequest(
      'coproduct-action:purchase?packageKey=monthly'
    );

    expect(decision).toBe('prevent');
    expect(bridge.purchaseCalls).toEqual(['premium_monthly']);
    expect(client.recordedTransactionIds).toEqual(['tx-1']);
    expect(capturedResult?.outcome).toBe('success');
    expect(capturedEntitlements?.[0]?.entitlementId).toBe('premium');
  });

  it('onSnapshotLoaded resolves a price using androidProductId when platform is ANDROID', async () => {
    const bridge = new FakeNativePaywallBridge({
      pricesByProductId: { premium_monthly_android: '$9.99/mo' },
    });
    const client = new FakePaywallClient();
    let capturedPrices: Record<string, string> | undefined;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      platform: 'ANDROID',
      setPrices: async (prices) => {
        capturedPrices = prices;
      },
    });

    await runtime.onSnapshotLoaded(
      buildSnapshot({
        monthly: {
          iosProductId: 'premium_monthly',
          androidProductId: 'premium_monthly_android',
        },
      })
    );

    expect(capturedPrices).toEqual({ monthly: '$9.99/mo' });
    expect(bridge.priceForCalls).toEqual([
      { productId: 'premium_monthly_android', kind: 'subscription' },
    ]);
  });

  it('a purchase tap on Android resolves androidProductId and records platform ANDROID', async () => {
    const bridge = new FakeNativePaywallBridge({
      nextPurchaseResult: {
        outcome: 'success',
        transactionId: 'tx-1',
        productId: 'premium_monthly_android',
        purchaseDate: new Date('2026-01-01T00:00:00.000Z'),
      },
    });
    const client = new FakePaywallClient();
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      platform: 'ANDROID',
      setPrices: async () => {},
    });
    await runtime.onSnapshotLoaded(
      buildSnapshot({
        monthly: {
          iosProductId: 'premium_monthly',
          androidProductId: 'premium_monthly_android',
        },
      })
    );

    await runtime.handleNavigationRequest(
      'coproduct-action:purchase?packageKey=monthly'
    );

    expect(bridge.purchaseCalls).toEqual(['premium_monthly_android']);
    expect(client.recordedPlatforms).toEqual(['ANDROID']);
  });

  it('a purchase tap for a consumable package passes kind through to bridge.purchase', async () => {
    const bridge = new FakeNativePaywallBridge({
      nextPurchaseResult: {
        outcome: 'success',
        transactionId: 'tx-1',
        productId: 'points_pack_300',
        purchaseDate: new Date('2026-01-01T00:00:00.000Z'),
      },
    });
    const client = new FakePaywallClient();
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async () => {},
    });
    await runtime.onSnapshotLoaded(
      buildSnapshot({
        points_pack: { iosProductId: 'points_pack_300', kind: 'consumable' },
      })
    );

    await runtime.handleNavigationRequest(
      'coproduct-action:purchase?packageKey=points_pack'
    );

    expect(bridge.purchaseKinds).toEqual([
      { productId: 'points_pack_300', kind: 'consumable' },
    ]);
  });

  it('a purchase tap for an unresolved packageKey reports unresolvedProduct without calling native', async () => {
    const bridge = new FakeNativePaywallBridge();
    const client = new FakePaywallClient();
    let capturedError: PaywallPurchaseError | undefined;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async () => {},
      onPurchaseError: (error) => {
        capturedError = error;
      },
    });
    await runtime.onSnapshotLoaded(buildSnapshot());

    await runtime.handleNavigationRequest(
      'coproduct-action:purchase?packageKey=monthly'
    );

    expect(bridge.purchaseCalls).toEqual([]);
    expect(capturedError?.reason).toBe('unresolvedProduct');
  });

  it('a cancelled purchase reports the result without recording a purchase', async () => {
    const bridge = new FakeNativePaywallBridge({
      nextPurchaseResult: { outcome: 'cancelled' },
    });
    const client = new FakePaywallClient();
    let capturedResult: PurchaseResult | undefined;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async () => {},
      onPurchaseResult: (result) => {
        capturedResult = result;
      },
    });
    await runtime.onSnapshotLoaded(
      buildSnapshot({ monthly: { iosProductId: 'premium_monthly' } })
    );

    await runtime.handleNavigationRequest(
      'coproduct-action:purchase?packageKey=monthly'
    );

    expect(capturedResult?.outcome).toBe('cancelled');
    expect(client.recordedTransactionIds).toEqual([]);
  });

  it('a pending purchase reports the result without recording a purchase', async () => {
    const bridge = new FakeNativePaywallBridge({
      nextPurchaseResult: { outcome: 'pending' },
    });
    const client = new FakePaywallClient();
    let capturedResult: PurchaseResult | undefined;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async () => {},
      onPurchaseResult: (result) => {
        capturedResult = result;
      },
    });
    await runtime.onSnapshotLoaded(
      buildSnapshot({ monthly: { iosProductId: 'premium_monthly' } })
    );

    await runtime.handleNavigationRequest(
      'coproduct-action:purchase?packageKey=monthly'
    );

    expect(capturedResult?.outcome).toBe('pending');
    expect(client.recordedTransactionIds).toEqual([]);
  });

  it('a server rejection reports serverRejected with the server code, not onPurchaseResult', async () => {
    const bridge = new FakeNativePaywallBridge({
      nextPurchaseResult: {
        outcome: 'success',
        transactionId: 'tx-1',
        productId: 'premium_monthly',
        purchaseDate: new Date('2026-01-01T00:00:00.000Z'),
      },
    });
    const client = new FakePaywallClient();
    client.rejectNextPurchase = true;
    let capturedResult: PurchaseResult | undefined;
    let capturedError: PaywallPurchaseError | undefined;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async () => {},
      onPurchaseResult: (result) => {
        capturedResult = result;
      },
      onPurchaseError: (error) => {
        capturedError = error;
      },
    });
    await runtime.onSnapshotLoaded(
      buildSnapshot({ monthly: { iosProductId: 'premium_monthly' } })
    );

    await runtime.handleNavigationRequest(
      'coproduct-action:purchase?packageKey=monthly'
    );

    expect(capturedResult).toBeUndefined();
    expect(capturedError?.reason).toBe('serverRejected');
    expect(capturedError?.serverCode).toBe('unknown_product');
  });

  it('a transport failure after a successful charge reports networkError, not onPurchaseResult', async () => {
    const bridge = new FakeNativePaywallBridge({
      nextPurchaseResult: {
        outcome: 'success',
        transactionId: 'tx-1',
        productId: 'premium_monthly',
        purchaseDate: new Date('2026-01-01T00:00:00.000Z'),
      },
    });
    const client = new FakePaywallClient();
    client.throwNetworkErrorNextPurchase = true;
    let capturedResult: PurchaseResult | undefined;
    let capturedError: PaywallPurchaseError | undefined;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async () => {},
      onPurchaseResult: (result) => {
        capturedResult = result;
      },
      onPurchaseError: (error) => {
        capturedError = error;
      },
    });
    await runtime.onSnapshotLoaded(
      buildSnapshot({ monthly: { iosProductId: 'premium_monthly' } })
    );

    await runtime.handleNavigationRequest(
      'coproduct-action:purchase?packageKey=monthly'
    );

    expect(capturedResult).toBeUndefined();
    expect(capturedError?.reason).toBe('networkError');
  });

  it('restore reports each transaction and surfaces a success result', async () => {
    const bridge = new FakeNativePaywallBridge({
      restoredTransactions: [
        {
          transactionId: 'tx-1',
          productId: 'premium_monthly',
          purchaseDate: new Date('2026-01-01T00:00:00.000Z'),
        },
        {
          transactionId: 'tx-2',
          productId: 'premium_annual',
          purchaseDate: new Date('2026-01-01T00:00:00.000Z'),
        },
      ],
    });
    const client = new FakePaywallClient();
    let capturedResult: PurchaseResult | undefined;
    let capturedEntitlements: Entitlement[] | undefined;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async () => {},
      onPurchaseResult: (result, entitlements) => {
        capturedResult = result;
        capturedEntitlements = entitlements;
      },
    });

    const decision = await runtime.handleNavigationRequest(
      'coproduct-action:restore'
    );

    expect(decision).toBe('prevent');
    expect(client.recordedTransactionIds).toEqual(['tx-1', 'tx-2']);
    expect(capturedResult?.outcome).toBe('success');
    expect(capturedEntitlements?.[0]?.entitlementId).toBe('premium');
  });

  it('restore keeps reporting remaining transactions when one throws (server or transport)', async () => {
    const bridge = new FakeNativePaywallBridge({
      restoredTransactions: [
        {
          transactionId: 'tx-1',
          productId: 'premium_monthly',
          purchaseDate: new Date('2026-01-01T00:00:00.000Z'),
        },
        {
          transactionId: 'tx-2',
          productId: 'premium_annual',
          purchaseDate: new Date('2026-01-01T00:00:00.000Z'),
        },
      ],
    });
    const client = new FakePaywallClient();
    client.transactionIdsThatThrow = new Set(['tx-1']);
    let capturedResult: PurchaseResult | undefined;
    let capturedEntitlements: Entitlement[] | undefined;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async () => {},
      onPurchaseResult: (result, entitlements) => {
        capturedResult = result;
        capturedEntitlements = entitlements;
      },
    });

    const decision = await runtime.handleNavigationRequest(
      'coproduct-action:restore'
    );

    expect(decision).toBe('prevent');
    expect(client.recordedTransactionIds).toEqual(['tx-2']);
    expect(capturedResult?.outcome).toBe('success');
    expect(capturedEntitlements?.[0]?.entitlementId).toBe('premium');
  });

  it('restore reports onPurchaseError, not a fabricated success, when every recordPurchase call fails', async () => {
    const bridge = new FakeNativePaywallBridge({
      restoredTransactions: [
        {
          transactionId: 'tx-1',
          productId: 'premium_monthly',
          purchaseDate: new Date('2026-01-01T00:00:00.000Z'),
        },
        {
          transactionId: 'tx-2',
          productId: 'premium_annual',
          purchaseDate: new Date('2026-01-01T00:00:00.000Z'),
        },
      ],
    });
    const client = new FakePaywallClient();
    client.throwNetworkErrorNextPurchase = true;
    let capturedResult: PurchaseResult | undefined;
    let capturedError: PaywallPurchaseError | undefined;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async () => {},
      onPurchaseResult: (result) => {
        capturedResult = result;
      },
      onPurchaseError: (error) => {
        capturedError = error;
      },
    });

    const decision = await runtime.handleNavigationRequest(
      'coproduct-action:restore'
    );

    expect(decision).toBe('prevent');
    expect(client.recordedTransactionIds).toEqual([]);
    expect(capturedResult).toBeUndefined();
    expect(capturedError?.reason).toBe('networkError');
  });

  it('restore with no transactions found reports success with empty entitlements', async () => {
    const bridge = new FakeNativePaywallBridge({ restoredTransactions: [] });
    const client = new FakePaywallClient();
    let capturedResult: PurchaseResult | undefined;
    let capturedEntitlements: Entitlement[] | undefined;
    let capturedError: PaywallPurchaseError | undefined;
    const runtime = new PaywallRuntime({
      bridge,
      client,
      appUserId: 'user-1',
      setPrices: async () => {},
      onPurchaseResult: (result, entitlements) => {
        capturedResult = result;
        capturedEntitlements = entitlements;
      },
      onPurchaseError: (error) => {
        capturedError = error;
      },
    });

    const decision = await runtime.handleNavigationRequest(
      'coproduct-action:restore'
    );

    expect(decision).toBe('prevent');
    expect(capturedError).toBeUndefined();
    expect(capturedResult?.outcome).toBe('success');
    expect(capturedEntitlements).toEqual([]);
  });

  it('dismiss calls onDismiss and returns prevent', async () => {
    let dismissed = false;
    const runtime = new PaywallRuntime({
      bridge: new FakeNativePaywallBridge(),
      client: new FakePaywallClient(),
      appUserId: 'user-1',
      setPrices: async () => {},
      onDismiss: () => {
        dismissed = true;
      },
    });

    const decision = await runtime.handleNavigationRequest(
      'coproduct-action:dismiss'
    );

    expect(decision).toBe('prevent');
    expect(dismissed).toBe(true);
  });

  it('an unparseable URL returns navigate', async () => {
    const runtime = new PaywallRuntime({
      bridge: new FakeNativePaywallBridge(),
      client: new FakePaywallClient(),
      appUserId: 'user-1',
      setPrices: async () => {},
    });

    const decision = await runtime.handleNavigationRequest(
      'https://example.com'
    );

    expect(decision).toBe('navigate');
  });
});
