// A build without the SDK's native code, such as Expo Go: the TurboModule
// lookup returns null rather than throwing
jest.mock('../NativeCoproduct', () => ({ __esModule: true, default: null }));
jest.mock('../NativeCoproductStorage', () => ({
  __esModule: true,
  default: null,
}));

// Expo Go ships netinfo, async-storage, and react-native-webview, so they
// load there
jest.mock('@react-native-community/netinfo', () => ({
  __esModule: true,
  default: { addEventListener: jest.fn(() => jest.fn()) },
}));
jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock')
);
jest.mock('react-native-webview', () => ({ WebView: () => null }));

// Expo Go does not ship these native peers, so loading any of them would throw
jest.mock('react-native-device-info', () => {
  throw new Error('react-native-device-info: NativeModule is null');
});
jest.mock('react-native-keychain', () => {
  throw new Error('react-native-keychain: NativeModule is null');
});
jest.mock('react-native-permissions', () => {
  throw new Error("TurboModuleRegistry.getEnforcing(...): 'RNPermissions'");
});

describe('the SDK in a build without its native module', () => {
  it('imports without throwing', () => {
    expect(() => require('../index')).not.toThrow();
  });

  it('rejects initialize with a message that names Expo Go and the fix', async () => {
    const { default: Coproduct } = require('../index');

    const initializing = Coproduct.initialize(
      'cpk_mob_0123456789abcdefghijklmnopqrstuv'
    );

    await expect(initializing).rejects.toThrow('not in Expo Go');
    await expect(initializing).rejects.toThrow('npx expo prebuild');
  });

  it('imports the onboarding and paywall entry points without throwing', () => {
    expect(() => require('../onboarding')).not.toThrow();
    expect(() => require('../paywall')).not.toThrow();
  });
});
