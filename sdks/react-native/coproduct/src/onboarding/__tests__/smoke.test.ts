// react-native-webview's WebView resolves its native module via
// TurboModuleRegistry.getEnforcing, which throws synchronously at
// import time when no native binary is present (unlike
// @react-native-community/netinfo's older-style NativeModules access,
// which this package's networkMonitor.test.ts imports without any mock).
// This smoke test only confirms the module graph loads and exports
// resolve -- it never renders a WebView -- so a trivial stub is enough.
jest.mock('react-native-webview', () => ({ WebView: () => null }));
// Same TurboModule issue as react-native-webview above, transitively via
// flowRuntime.ts -> permissions.ts -> react-native-permissions. Reuses the
// library's own documented mock, same as permissions.test.ts/flowRuntime.test.ts.
jest.mock('react-native-permissions', () =>
  require('react-native-permissions/mock')
);
// Same reasoning, transitively via localProgressStore.ts. See
// localProgressStore.test.ts for why this exact subpath.
jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock')
);

import { CoproductOnboardingFlow, HttpOnboardingClient } from '../index';

describe('onboarding module smoke test', () => {
  it('exports CoproductOnboardingFlow as a function component with a static loadPlatformScript', () => {
    expect(typeof CoproductOnboardingFlow).toBe('function');
    expect(typeof CoproductOnboardingFlow.loadPlatformScript).toBe('function');
  });

  it('loadPlatformScript resolves to the bundled platform script string', async () => {
    const script = await CoproductOnboardingFlow.loadPlatformScript();
    expect(typeof script).toBe('string');
  });

  it('exports HttpOnboardingClient', () => {
    expect(typeof HttpOnboardingClient).toBe('function');
  });
});
