// An app without the optional react-native-iap peer: requiring it throws, as
// Metro's optional-dependency handling does at runtime when it is absent
jest.mock('react-native-iap', () => {
  throw new Error("Cannot find module 'react-native-iap'");
});

import { IapPaywallBridge, MISSING_IAP_MESSAGE } from '../iapPaywallBridge';

describe('IapPaywallBridge without react-native-iap installed', () => {
  it('fails on construction with the install command', () => {
    expect(() => new IapPaywallBridge()).toThrow(MISSING_IAP_MESSAGE);
    expect(MISSING_IAP_MESSAGE).toContain(
      'npm install react-native-iap react-native-nitro-modules'
    );
  });
});
