// A build that links the SDK's Rust module but not its CoproductStorage
// module, such as a stale native build from before the module was split out
jest.mock('../NativeCoproduct', () => ({
  __esModule: true,
  default: {
    installRustCrate: jest.fn(() => true),
    cleanupRustCrate: jest.fn(() => true),
  },
}));
jest.mock('../NativeCoproductStorage', () => ({
  __esModule: true,
  default: null,
}));

// Without an __esModule flag the whole object is the default export, so the
// crate initialization index.tsx runs at import calls this mock rather than
// the native bindings, which a JS-only test cannot load
jest.mock('../generated/coproduct_ffi_uniffi', () => {
  const actual = jest.requireActual('../generated/coproduct_ffi_uniffi');
  return { ...actual, initialize: jest.fn() };
});

jest.mock('@react-native-community/netinfo', () => ({
  __esModule: true,
  default: { addEventListener: jest.fn(() => jest.fn()) },
}));
jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock')
);
jest.mock('react-native-webview', () => ({ WebView: () => null }));
jest.mock('react-native-device-info', () => ({
  getSystemVersion: jest.fn(() => '17.0'),
  getVersion: jest.fn(() => '1.0.0'),
  getBuildNumber: jest.fn(() => '1'),
  getDeviceType: jest.fn(() => 'Handset'),
}));
jest.mock('react-native-keychain', () => ({
  getGenericPassword: jest.fn().mockResolvedValue(false),
  setGenericPassword: jest.fn().mockResolvedValue(true),
}));
jest.mock('react-native-permissions', () => ({
  PERMISSIONS: { IOS: {}, ANDROID: {} },
  RESULTS: {},
  request: jest.fn(),
  check: jest.fn(),
}));

describe('the SDK in a build without its storage module', () => {
  it('rejects initialize with the rebuild message rather than crashing', async () => {
    const { default: Coproduct } = require('../index');

    const initializing = Coproduct.initialize(
      'cpk_mob_0123456789abcdefghijklmnopqrstuv'
    );

    await expect(initializing).rejects.toThrow('npx expo prebuild');
  });
});
