// react-native-webview's WebView and react-native-iap both resolve native
// modules via TurboModuleRegistry.getEnforcing (or an equivalent strict
// check), which throws synchronously at import time when no native binary
// is present. This smoke test only confirms the module graph loads and
// exports resolve -- it never renders a WebView or calls a store API -- so
// trivial stubs are enough. react-native-iap has no official Jest mock, so
// this mock is hand-written.
jest.mock('react-native-webview', () => ({ WebView: () => null }));
jest.mock('react-native-iap', () => ({
  ErrorCode: { UserCancelled: 'user-cancelled', Pending: 'pending' },
  requestPurchase: jest.fn(),
  finishTransaction: jest.fn(),
  fetchProducts: jest.fn(),
  getAvailablePurchases: jest.fn(),
  purchaseUpdatedListener: jest.fn(() => ({ remove: jest.fn() })),
  purchaseErrorListener: jest.fn(() => ({ remove: jest.fn() })),
}));

import {
  CoproductPaywall,
  HttpPaywallClient,
  IapPaywallBridge,
} from '../index';

describe('paywall module smoke test', () => {
  it('exports CoproductPaywall as a function component with a static loadPlatformScript', () => {
    expect(typeof CoproductPaywall).toBe('function');
    expect(typeof CoproductPaywall.loadPlatformScript).toBe('function');
  });

  it('loadPlatformScript resolves to the bundled platform script string', async () => {
    const script = await CoproductPaywall.loadPlatformScript();
    expect(typeof script).toBe('string');
  });

  it('exports HttpPaywallClient and IapPaywallBridge', () => {
    expect(typeof HttpPaywallClient).toBe('function');
    expect(typeof IapPaywallBridge).toBe('function');
  });
});
