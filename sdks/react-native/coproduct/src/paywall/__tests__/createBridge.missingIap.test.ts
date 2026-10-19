// An app without the optional react-native-iap peer, as in
// iapPaywallBridge.missingIap.test.ts, now seen from the paywall component
jest.mock('react-native-webview', () => ({ WebView: () => null }));
jest.mock('react-native-iap', () => {
  throw new Error("Cannot find module 'react-native-iap'");
});

import { createBridge } from '../CoproductPaywall';
import { MISSING_IAP_MESSAGE } from '../iapPaywallBridge';
import type { NativePaywallBridge } from '../nativePaywallBridge';

describe('createBridge without react-native-iap installed', () => {
  beforeEach(() => jest.spyOn(console, 'error').mockImplementation(() => {}));
  afterEach(() => jest.restoreAllMocks());

  it('reports the install command through onLoadError and logs it', () => {
    const onLoadError = jest.fn();
    expect(createBridge(undefined, onLoadError)).toBeUndefined();
    expect(onLoadError).toHaveBeenCalledWith({ message: MISSING_IAP_MESSAGE });
    expect(console.error).toHaveBeenCalledWith(MISSING_IAP_MESSAGE);
  });

  it('still logs when the app passes no onLoadError', () => {
    expect(createBridge(undefined, undefined)).toBeUndefined();
    expect(console.error).toHaveBeenCalledWith(MISSING_IAP_MESSAGE);
  });

  it('uses an injected bridge without loading react-native-iap', () => {
    const override = {} as NativePaywallBridge;
    expect(createBridge(override, jest.fn())).toBe(override);
  });
});
