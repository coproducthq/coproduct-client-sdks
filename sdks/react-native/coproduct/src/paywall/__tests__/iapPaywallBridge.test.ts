const purchaseUpdateListeners: Array<(purchase: unknown) => void> = [];
const purchaseErrorListeners: Array<(error: unknown) => void> = [];
const removedUpdateListeners: Array<(purchase: unknown) => void> = [];
const removedErrorListeners: Array<(error: unknown) => void> = [];

const mockRequestPurchase = jest.fn().mockResolvedValue(undefined);
const mockFinishTransaction = jest.fn().mockResolvedValue(undefined);
const mockFetchProducts = jest.fn();
const mockGetAvailablePurchases = jest.fn();

jest.mock('react-native-iap', () => ({
  ErrorCode: { UserCancelled: 'user-cancelled', Pending: 'pending' },
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
  mockRequestPurchase.mockClear().mockResolvedValue(undefined);
  mockFinishTransaction.mockClear().mockResolvedValue(undefined);
  mockFetchProducts.mockClear();
  mockGetAvailablePurchases.mockClear();
});

describe('IapPaywallBridge', () => {
  describe('priceFor', () => {
    it("resolves the first matching product's displayPrice", async () => {
      mockFetchProducts.mockResolvedValue([
        { id: 'premium_monthly', displayPrice: '$9.99/mo' },
      ]);

      const bridge = new IapPaywallBridge();
      const price = await bridge.priceFor('premium_monthly');

      expect(mockFetchProducts).toHaveBeenCalledWith({
        skus: ['premium_monthly'],
        type: 'subs',
      });
      expect(price).toBe('$9.99/mo');
    });

    it('throws when no product is found', async () => {
      mockFetchProducts.mockResolvedValue([]);

      const bridge = new IapPaywallBridge();
      await expect(bridge.priceFor('unknown')).rejects.toThrow(
        'No product found'
      );
    });
  });

  describe('purchase', () => {
    it('resolves success after finishing the transaction, for the matching product only', async () => {
      const bridge = new IapPaywallBridge();
      const resultPromise = bridge.purchase('premium_monthly');

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

    it('resolves cancelled without finishing a transaction', async () => {
      const bridge = new IapPaywallBridge();
      const resultPromise = bridge.purchase('premium_monthly');

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
      const resultPromise = bridge.purchase('premium_monthly');

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
      const resultPromise = bridge.purchase('premium_monthly');

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
      const first = bridge.purchase('premium_monthly');
      purchaseUpdateListeners[0]?.({
        productId: 'premium_monthly',
        transactionId: 'tx-1',
        transactionDate: 1700000000000,
      });
      await first;

      const listenerCountBefore = purchaseUpdateListeners.length;
      const second = bridge.purchase('premium_annual');
      expect(purchaseUpdateListeners.length).toBe(listenerCountBefore + 1);
      purchaseUpdateListeners[purchaseUpdateListeners.length - 1]?.({
        productId: 'premium_annual',
        transactionId: 'tx-2',
        transactionDate: 1700000000000,
      });
      const result = await second;
      expect(result.transactionId).toBe('tx-2');
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
