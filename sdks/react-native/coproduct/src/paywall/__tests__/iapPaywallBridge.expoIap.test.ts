// An Expo app: react-native-iap is absent and expo-iap, the same OpenIAP
// client packaged as an Expo module, is installed instead
jest.mock('react-native-iap', () => {
  throw new Error("Cannot find module 'react-native-iap'");
});

const mockFetchProducts = jest.fn();
const mockInitConnection = jest.fn().mockResolvedValue(true);
const mockRequestPurchase = jest.fn().mockResolvedValue(undefined);
const mockFinishTransaction = jest.fn().mockResolvedValue(undefined);
const updateListeners: Array<(purchase: unknown) => void> = [];

// Virtual, because expo-iap is not installed in this workspace
jest.mock(
  'expo-iap',
  () => ({
    ErrorCode: { UserCancelled: 'user-cancelled', Pending: 'pending' },
    initConnection: (...args: unknown[]) => mockInitConnection(...args),
    fetchProducts: (...args: unknown[]) => mockFetchProducts(...args),
    requestPurchase: (...args: unknown[]) => mockRequestPurchase(...args),
    finishTransaction: (...args: unknown[]) => mockFinishTransaction(...args),
    getAvailablePurchases: jest.fn().mockResolvedValue([]),
    purchaseUpdatedListener: (listener: (purchase: unknown) => void) => {
      updateListeners.push(listener);
      return { remove: () => {} };
    },
    purchaseErrorListener: () => ({ remove: () => {} }),
  }),
  { virtual: true }
);

import { IapPaywallBridge } from '../iapPaywallBridge';

describe('IapPaywallBridge with expo-iap', () => {
  it('prices a package through expo-iap when react-native-iap is absent', async () => {
    mockFetchProducts.mockResolvedValue([
      { id: 'premium_monthly', displayPrice: '$9.99' },
    ]);

    const price = await new IapPaywallBridge().priceFor(
      'premium_monthly',
      'subscription'
    );

    expect(mockInitConnection).toHaveBeenCalled();
    expect(mockFetchProducts).toHaveBeenCalledWith({
      skus: ['premium_monthly'],
      type: 'subs',
    });
    expect(price).toBe('$9.99');
  });

  it('completes a purchase through expo-iap', async () => {
    const result = new IapPaywallBridge().purchase('lifetime', 'lifetime');
    await new Promise((resolve) => setImmediate(resolve));

    expect(mockRequestPurchase).toHaveBeenCalledWith({
      request: { apple: { sku: 'lifetime' }, google: { skus: ['lifetime'] } },
      type: 'in-app',
    });

    updateListeners[0]?.({
      productId: 'lifetime',
      purchaseState: 'purchased',
      transactionId: 't1',
      transactionDate: 1_700_000_000_000,
    });

    await expect(result).resolves.toMatchObject({
      outcome: 'success',
      transactionId: 't1',
      productId: 'lifetime',
    });
    expect(mockFinishTransaction).toHaveBeenCalledWith(
      expect.objectContaining({ isConsumable: false })
    );
  });

  it("hands expo-iap the app user's account token and returns the store proof", async () => {
    // The version 5 UUID the server derives for app user id "user-123"
    const token = 'f5765ad4-640f-516d-be70-79ed3a75f5e7';
    const result = new IapPaywallBridge().purchaseForUser(
      'remove_ads',
      'lifetime',
      'user-123'
    );
    await new Promise((resolve) => setImmediate(resolve));

    expect(mockRequestPurchase).toHaveBeenLastCalledWith({
      request: {
        apple: { sku: 'remove_ads', appAccountToken: token },
        google: { skus: ['remove_ads'], obfuscatedAccountId: token },
      },
      type: 'in-app',
    });

    updateListeners[updateListeners.length - 1]?.({
      productId: 'remove_ads',
      purchaseState: 'purchased',
      transactionId: 't2',
      transactionDate: 1_700_000_000_000,
      store: 'apple',
      purchaseToken: 'signed-jws',
    });

    await expect(result).resolves.toMatchObject({
      outcome: 'success',
      transactionId: 't2',
      signedTransaction: 'signed-jws',
    });
  });
});
