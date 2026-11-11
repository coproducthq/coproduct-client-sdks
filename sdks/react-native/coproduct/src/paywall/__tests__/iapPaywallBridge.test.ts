const purchaseUpdateListeners: Array<(purchase: unknown) => void> = [];
const purchaseErrorListeners: Array<(error: unknown) => void> = [];
const removedUpdateListeners: Array<(purchase: unknown) => void> = [];
const removedErrorListeners: Array<(error: unknown) => void> = [];

const mockRequestPurchase = jest.fn().mockResolvedValue(undefined);
const mockFinishTransaction = jest.fn().mockResolvedValue(undefined);
const mockFetchProducts = jest.fn();
const mockGetAvailablePurchases = jest.fn();
const mockInitConnection = jest.fn().mockResolvedValue(true);

jest.mock('react-native-iap', () => ({
  ErrorCode: { UserCancelled: 'user-cancelled', Pending: 'pending' },
  initConnection: (...args: unknown[]) => mockInitConnection(...args),
  requestPurchase: (...args: unknown[]) => mockRequestPurchase(...args),
  finishTransaction: (...args: unknown[]) => mockFinishTransaction(...args),
  fetchProducts: (...args: unknown[]) => mockFetchProducts(...args),
  getAvailablePurchases: (...args: unknown[]) =>
    mockGetAvailablePurchases(...args),
  purchaseUpdatedListener: (listener: (purchase: unknown) => void) => {
    purchaseUpdateListeners.push(listener);
    return { remove: () => removedUpdateListeners.push(listener) };
  },
  purchaseErrorListener: (listener: (error: unknown) => void) => {
    purchaseErrorListeners.push(listener);
    return { remove: () => removedErrorListeners.push(listener) };
  },
}));

import { IapPaywallBridge } from '../iapPaywallBridge';

beforeEach(() => {
  purchaseUpdateListeners.length = 0;
  purchaseErrorListeners.length = 0;
  removedUpdateListeners.length = 0;
  removedErrorListeners.length = 0;
  mockInitConnection.mockClear();
  mockRequestPurchase.mockClear().mockResolvedValue(undefined);
  mockFinishTransaction.mockClear().mockResolvedValue(undefined);
  mockFetchProducts.mockClear();
  mockGetAvailablePurchases.mockClear();
});

describe('IapPaywallBridge', () => {
  describe('priceFor', () => {
    it("resolves the first matching product's displayPrice for a subscription", async () => {
      mockFetchProducts.mockResolvedValue([
        { id: 'premium_monthly', displayPrice: '$9.99/mo' },
      ]);

      const bridge = new IapPaywallBridge();
      const price = await bridge.priceFor('premium_monthly', 'subscription');

      expect(mockFetchProducts).toHaveBeenCalledWith({
        skus: ['premium_monthly'],
        type: 'subs',
      });
      expect(price).toBe('$9.99/mo');
    });

    it("resolves a consumable product's displayPrice using type:'in-app'", async () => {
      mockFetchProducts.mockResolvedValue([
        { id: 'points_pack_300', displayPrice: '$4.99' },
      ]);

      const bridge = new IapPaywallBridge();
      const price = await bridge.priceFor('points_pack_300', 'consumable');

      expect(mockFetchProducts).toHaveBeenCalledWith({
        skus: ['points_pack_300'],
        type: 'in-app',
      });
      expect(price).toBe('$4.99');
    });

    it("resolves a lifetime product's displayPrice using type:'in-app'", async () => {
      mockFetchProducts.mockResolvedValue([
        { id: 'remove_ads', displayPrice: '$19.99' },
      ]);

      const bridge = new IapPaywallBridge();
      const price = await bridge.priceFor('remove_ads', 'lifetime');

      expect(mockFetchProducts).toHaveBeenCalledWith({
        skus: ['remove_ads'],
        type: 'in-app',
      });
      expect(price).toBe('$19.99');
    });

    it('throws when no product is found', async () => {
      mockFetchProducts.mockResolvedValue([]);

      const bridge = new IapPaywallBridge();
      await expect(bridge.priceFor('unknown', 'subscription')).rejects.toThrow(
        'No product found'
      );
    });
  });

  describe('packageFor', () => {
    it('returns a price-only result, unchanged, when the product reports no subscriptionOffers', async () => {
      mockFetchProducts.mockResolvedValue([
        { id: 'premium_monthly', displayPrice: '$9.99/mo' },
      ]);

      const bridge = new IapPaywallBridge();
      const pkg = await bridge.packageFor('premium_monthly', 'subscription');

      expect(pkg).toEqual({ price: '$9.99/mo', intro: null });
    });

    it('appends the iOS base subscription period to the regular price', async () => {
      mockFetchProducts.mockResolvedValue([
        {
          id: 'premium_annual',
          displayPrice: '$39.99',
          subscriptionPeriodUnitIOS: 'year',
          subscriptionPeriodNumberIOS: '1',
        },
      ]);

      const bridge = new IapPaywallBridge();
      const pkg = await bridge.packageFor('premium_annual', 'subscription');

      expect(pkg).toEqual({ price: '$39.99/yr', intro: null });
    });

    it('builds a free-trial intro label whose "then" price carries the base period', async () => {
      mockFetchProducts.mockResolvedValue([
        {
          id: 'premium_annual',
          displayPrice: '$39.99',
          subscriptionPeriodUnitIOS: 'year',
          subscriptionPeriodNumberIOS: '1',
          subscriptionOffers: [
            {
              id: 'intro-trial',
              type: 'introductory',
              paymentMode: 'free-trial',
              price: 0,
              displayPrice: '',
              period: { unit: 'day', value: 7 },
            },
          ],
        },
      ]);

      const bridge = new IapPaywallBridge();
      const pkg = await bridge.packageFor('premium_annual', 'subscription');

      expect(pkg).toEqual({
        price: '$39.99/yr',
        intro: { eligible: true, label: '7 days free, then $39.99/yr' },
      });
    });

    it('multiplies period by periodCount, so a 3-month intro reads as 3 months, not 1', async () => {
      mockFetchProducts.mockResolvedValue([
        {
          id: 'premium_monthly',
          displayPrice: '$9.99',
          subscriptionPeriodUnitIOS: 'month',
          subscriptionPeriodNumberIOS: '1',
          subscriptionOffers: [
            {
              id: 'intro-discount',
              type: 'introductory',
              paymentMode: 'pay-as-you-go',
              price: 1.99,
              displayPrice: '$1.99',
              period: { unit: 'month', value: 1 },
              periodCount: 3,
            },
          ],
        },
      ]);

      const bridge = new IapPaywallBridge();
      const pkg = await bridge.packageFor('premium_monthly', 'subscription');

      expect(pkg).toEqual({
        price: '$9.99/mo',
        intro: {
          eligible: true,
          label: '$1.99 for 3 months, then $9.99/mo',
        },
      });
    });

    it('derives the Android base period from the final (indefinitely recurring) pricing phase', async () => {
      mockFetchProducts.mockResolvedValue([
        {
          id: 'premium_annual_android',
          displayPrice: '$39.99',
          subscriptionOffers: [
            {
              id: 'base-plan',
              offerTokenAndroid: 'token-abc',
              type: 'introductory',
              paymentMode: 'free-trial',
              price: 0,
              displayPrice: '',
              pricingPhasesAndroid: {
                pricingPhaseList: [
                  {
                    billingPeriod: 'P1W',
                    billingCycleCount: 1,
                    formattedPrice: 'Free',
                    priceAmountMicros: '0',
                    priceCurrencyCode: 'USD',
                    recurrenceMode: 2,
                  },
                  {
                    billingPeriod: 'P1Y',
                    billingCycleCount: 0,
                    formattedPrice: '$39.99',
                    priceAmountMicros: '39990000',
                    priceCurrencyCode: 'USD',
                    recurrenceMode: 1,
                  },
                ],
              },
            },
          ],
        },
      ]);

      const bridge = new IapPaywallBridge();
      const pkg = await bridge.packageFor(
        'premium_annual_android',
        'subscription'
      );

      expect(pkg).toEqual({
        price: '$39.99/yr',
        intro: { eligible: true, label: '1 week free, then $39.99/yr' },
      });
    });

    it('multiplies the Android intro phase by its billingCycleCount when period/periodCount are absent', async () => {
      mockFetchProducts.mockResolvedValue([
        {
          id: 'premium_monthly_android',
          displayPrice: '$9.99',
          subscriptionOffers: [
            {
              id: 'base-plan',
              offerTokenAndroid: 'token-abc',
              type: 'introductory',
              paymentMode: 'pay-as-you-go',
              price: 1.99,
              displayPrice: '$1.99',
              pricingPhasesAndroid: {
                pricingPhaseList: [
                  {
                    billingPeriod: 'P1M',
                    billingCycleCount: 3,
                    formattedPrice: '$1.99',
                    priceAmountMicros: '1990000',
                    priceCurrencyCode: 'USD',
                    recurrenceMode: 2,
                  },
                  {
                    billingPeriod: 'P1M',
                    billingCycleCount: 0,
                    formattedPrice: '$9.99',
                    priceAmountMicros: '9990000',
                    priceCurrencyCode: 'USD',
                    recurrenceMode: 1,
                  },
                ],
              },
            },
          ],
        },
      ]);

      const bridge = new IapPaywallBridge();
      const pkg = await bridge.packageFor(
        'premium_monthly_android',
        'subscription'
      );

      expect(pkg).toEqual({
        price: '$9.99/mo',
        intro: {
          eligible: true,
          label: '$1.99 for 3 months, then $9.99/mo',
        },
      });
    });

    it('reports no intro offer when no entry is typed "introductory", as with a plain Android base-plan offer', async () => {
      mockFetchProducts.mockResolvedValue([
        {
          id: 'premium_monthly',
          displayPrice: '$9.99/mo',
          subscriptionOffers: [
            { id: 'base-plan', offerTokenAndroid: 'token-abc' },
          ],
        },
      ]);

      const bridge = new IapPaywallBridge();
      const pkg = await bridge.packageFor('premium_monthly', 'subscription');

      expect(pkg.intro).toBeNull();
    });

    it('reports no intro offer for an unmapped payment mode, rather than guessing one', async () => {
      mockFetchProducts.mockResolvedValue([
        {
          id: 'premium_monthly',
          displayPrice: '$9.99/mo',
          subscriptionOffers: [
            {
              id: 'intro-unknown',
              type: 'introductory',
              paymentMode: 'unknown',
              price: 0,
              displayPrice: '',
              period: { unit: 'month', value: 1 },
            },
          ],
        },
      ]);

      const bridge = new IapPaywallBridge();
      const pkg = await bridge.packageFor('premium_monthly', 'subscription');

      expect(pkg.intro).toBeNull();
    });

    it('reports no intro offer for a discounted offer with no displayed price', async () => {
      mockFetchProducts.mockResolvedValue([
        {
          id: 'premium_monthly',
          displayPrice: '$9.99/mo',
          subscriptionOffers: [
            {
              id: 'intro-discount',
              type: 'introductory',
              paymentMode: 'pay-up-front',
              price: 0,
              displayPrice: '',
              period: { unit: 'month', value: 1 },
            },
          ],
        },
      ]);

      const bridge = new IapPaywallBridge();
      const pkg = await bridge.packageFor('premium_monthly', 'subscription');

      expect(pkg.intro).toBeNull();
    });

    it('throws when no product is found', async () => {
      mockFetchProducts.mockResolvedValue([]);

      const bridge = new IapPaywallBridge();
      await expect(
        bridge.packageFor('unknown', 'subscription')
      ).rejects.toThrow('No product found');
    });
  });

  describe('priceFor delegating to packageFor', () => {
    it("returns packageFor's period-suffixed price", async () => {
      mockFetchProducts.mockResolvedValue([
        {
          id: 'premium_annual',
          displayPrice: '$39.99',
          subscriptionPeriodUnitIOS: 'year',
          subscriptionPeriodNumberIOS: '1',
        },
      ]);

      const bridge = new IapPaywallBridge();
      const price = await bridge.priceFor('premium_annual', 'subscription');

      expect(price).toBe('$39.99/yr');
    });
  });

  describe('purchase', () => {
    it('resolves success after finishing the transaction, for the matching product only', async () => {
      const bridge = new IapPaywallBridge();
      const resultPromise = bridge.purchase('premium_monthly', 'subscription');

      // An update for a DIFFERENT product first must be ignored
      purchaseUpdateListeners[0]?.({
        productId: 'other_product',
        transactionId: 'tx-0',
        transactionDate: 1700000000000,
      });
      purchaseUpdateListeners[0]?.({
        productId: 'premium_monthly',
        transactionId: 'tx-1',
        transactionDate: 1700000000000,
        expirationDateIOS: 1800000000000,
      });

      const result = await resultPromise;

      expect(mockRequestPurchase).toHaveBeenCalledWith({
        request: {
          apple: { sku: 'premium_monthly' },
          google: { skus: ['premium_monthly'] },
        },
        type: 'subs',
      });
      expect(mockFinishTransaction).toHaveBeenCalledWith({
        purchase: expect.objectContaining({ productId: 'premium_monthly' }),
        isConsumable: false,
      });
      expect(result).toEqual({
        outcome: 'success',
        transactionId: 'tx-1',
        productId: 'premium_monthly',
        purchaseDate: new Date(1700000000000),
        expirationDate: new Date(1800000000000),
      });
      expect(removedUpdateListeners).toHaveLength(1);
      expect(removedErrorListeners).toHaveLength(1);
    });

    it("requests type:'in-app' and finishes as consumable for a consumable product", async () => {
      const bridge = new IapPaywallBridge();
      const resultPromise = bridge.purchase('points_pack_300', 'consumable');

      purchaseUpdateListeners[0]?.({
        productId: 'points_pack_300',
        transactionId: 'tx-1',
        transactionDate: 1700000000000,
      });

      await resultPromise;

      expect(mockRequestPurchase).toHaveBeenCalledWith({
        request: {
          apple: { sku: 'points_pack_300' },
          google: { skus: ['points_pack_300'] },
        },
        type: 'in-app',
      });
      expect(mockFinishTransaction).toHaveBeenCalledWith({
        purchase: expect.objectContaining({ productId: 'points_pack_300' }),
        isConsumable: true,
      });
    });

    it("requests type:'in-app' and finishes as non-consumable for a lifetime product", async () => {
      const bridge = new IapPaywallBridge();
      const resultPromise = bridge.purchase('remove_ads', 'lifetime');

      purchaseUpdateListeners[0]?.({
        productId: 'remove_ads',
        transactionId: 'tx-1',
        transactionDate: 1700000000000,
      });

      await resultPromise;

      expect(mockRequestPurchase).toHaveBeenCalledWith({
        request: {
          apple: { sku: 'remove_ads' },
          google: { skus: ['remove_ads'] },
        },
        type: 'in-app',
      });
      expect(mockFinishTransaction).toHaveBeenCalledWith({
        purchase: expect.objectContaining({ productId: 'remove_ads' }),
        isConsumable: false,
      });
    });

    it('resolves cancelled without finishing a transaction', async () => {
      const bridge = new IapPaywallBridge();
      const resultPromise = bridge.purchase('premium_monthly', 'subscription');

      purchaseErrorListeners[0]?.({
        code: 'user-cancelled',
        message: 'cancelled',
        productId: 'premium_monthly',
      });

      const result = await resultPromise;

      expect(result).toEqual({ outcome: 'cancelled' });
      expect(mockFinishTransaction).not.toHaveBeenCalled();
    });

    it('resolves pending without finishing a transaction', async () => {
      const bridge = new IapPaywallBridge();
      const resultPromise = bridge.purchase('premium_monthly', 'subscription');

      purchaseErrorListeners[0]?.({
        code: 'pending',
        message: 'pending',
        productId: 'premium_monthly',
      });

      const result = await resultPromise;

      expect(result).toEqual({ outcome: 'pending' });
    });

    it('rejects on a genuine purchase error', async () => {
      const bridge = new IapPaywallBridge();
      const resultPromise = bridge.purchase('premium_monthly', 'subscription');

      purchaseErrorListeners[0]?.({
        code: 'network-error',
        message: 'offline',
        productId: 'premium_monthly',
      });

      await expect(resultPromise).rejects.toThrow('offline');
      expect(removedUpdateListeners).toHaveLength(1);
      expect(removedErrorListeners).toHaveLength(1);
    });

    it('removes both listeners on every settled path, so a later purchase never receives a stale event', async () => {
      const bridge = new IapPaywallBridge();
      const first = bridge.purchase('premium_monthly', 'subscription');
      purchaseUpdateListeners[0]?.({
        productId: 'premium_monthly',
        transactionId: 'tx-1',
        transactionDate: 1700000000000,
      });
      await first;

      const listenerCountBefore = purchaseUpdateListeners.length;
      const second = bridge.purchase('premium_annual', 'subscription');
      expect(purchaseUpdateListeners.length).toBe(listenerCountBefore + 1);
      purchaseUpdateListeners[purchaseUpdateListeners.length - 1]?.({
        productId: 'premium_annual',
        transactionId: 'tx-2',
        transactionDate: 1700000000000,
      });
      const result = await second;
      expect(result.transactionId).toBe('tx-2');
    });

    it('resolves an Android subscription offer token into google.subscriptionOffers', async () => {
      mockFetchProducts.mockResolvedValue([
        {
          id: 'premium_monthly',
          displayPrice: '$9.99/mo',
          subscriptionOffers: [
            { id: 'base-plan', offerTokenAndroid: 'token-abc' },
          ],
        },
      ]);

      const bridge = new IapPaywallBridge();
      const resultPromise = bridge.purchase('premium_monthly', 'subscription');
      purchaseUpdateListeners[0]?.({
        productId: 'premium_monthly',
        purchaseState: 'purchased',
        transactionId: 'tx-1',
        transactionDate: 1700000000000,
      });
      await resultPromise;

      expect(mockFetchProducts).toHaveBeenCalledWith({
        skus: ['premium_monthly'],
        type: 'subs',
      });
      expect(mockRequestPurchase).toHaveBeenCalledWith({
        request: {
          apple: { sku: 'premium_monthly' },
          google: {
            skus: ['premium_monthly'],
            subscriptionOffers: [
              { sku: 'premium_monthly', offerToken: 'token-abc' },
            ],
          },
        },
        type: 'subs',
      });
    });

    it('sends a plain google.skus request with no subscriptionOffers when the product has none', async () => {
      mockFetchProducts.mockResolvedValue([
        {
          id: 'premium_monthly',
          displayPrice: '$9.99/mo',
          subscriptionOffers: [],
        },
      ]);

      const bridge = new IapPaywallBridge();
      const resultPromise = bridge.purchase('premium_monthly', 'subscription');
      purchaseUpdateListeners[0]?.({
        productId: 'premium_monthly',
        purchaseState: 'purchased',
        transactionId: 'tx-1',
        transactionDate: 1700000000000,
      });
      await resultPromise;

      expect(mockRequestPurchase).toHaveBeenCalledWith({
        request: {
          apple: { sku: 'premium_monthly' },
          google: { skus: ['premium_monthly'] },
        },
        type: 'subs',
      });
    });

    it('never queries product offers for a one-time (non-subscription) purchase', async () => {
      const bridge = new IapPaywallBridge();
      const resultPromise = bridge.purchase('points_pack_300', 'consumable');
      purchaseUpdateListeners[0]?.({
        productId: 'points_pack_300',
        purchaseState: 'purchased',
        transactionId: 'tx-1',
        transactionDate: 1700000000000,
      });
      await resultPromise;

      expect(mockFetchProducts).not.toHaveBeenCalled();
    });

    it('resolves pending from an Android purchaseState update without finishing the transaction', async () => {
      const bridge = new IapPaywallBridge();
      const resultPromise = bridge.purchase('premium_monthly', 'subscription');

      purchaseUpdateListeners[0]?.({
        productId: 'premium_monthly',
        purchaseState: 'pending',
        transactionId: 'tx-1',
        transactionDate: 1700000000000,
      });

      const result = await resultPromise;

      expect(result).toEqual({ outcome: 'pending' });
      expect(mockFinishTransaction).not.toHaveBeenCalled();
      expect(removedUpdateListeners).toHaveLength(1);
      expect(removedErrorListeners).toHaveLength(1);
    });
  });

  describe('restore', () => {
    it('finishes and maps every available purchase', async () => {
      mockGetAvailablePurchases.mockResolvedValue([
        {
          productId: 'premium_monthly',
          transactionId: 'tx-1',
          transactionDate: 1700000000000,
          expirationDateIOS: null,
        },
      ]);

      const bridge = new IapPaywallBridge();
      const restored = await bridge.restore();

      expect(mockFinishTransaction).toHaveBeenCalledWith({
        purchase: expect.objectContaining({ productId: 'premium_monthly' }),
        isConsumable: false,
      });
      expect(restored).toEqual([
        {
          transactionId: 'tx-1',
          productId: 'premium_monthly',
          purchaseDate: new Date(1700000000000),
          expirationDate: undefined,
        },
      ]);
    });

    it('returns an empty array when nothing is available', async () => {
      mockGetAvailablePurchases.mockResolvedValue([]);

      const bridge = new IapPaywallBridge();
      expect(await bridge.restore()).toEqual([]);
    });
  });
});
