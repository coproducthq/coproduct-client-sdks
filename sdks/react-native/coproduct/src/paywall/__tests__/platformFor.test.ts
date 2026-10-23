// CoproductPaywall.tsx imports react-native-webview at module load time;
// mocked the same way createBridge.missingIap.test.ts mocks it, so this
// file-level import doesn't require a real WebView native module.
jest.mock('react-native-webview', () => ({ WebView: () => null }));

import { platformFor } from '../CoproductPaywall';

describe('platformFor', () => {
  it('maps android to ANDROID', () => {
    expect(platformFor('android')).toBe('ANDROID');
  });

  it('maps every non-android OS name to IOS', () => {
    expect(platformFor('ios')).toBe('IOS');
    expect(platformFor('windows')).toBe('IOS');
    expect(platformFor('macos')).toBe('IOS');
  });
});
