import { Platform } from 'react-native';
import type DeviceInfoModule from 'react-native-device-info';
import type { AttributeValue } from './attributeValue';

// Required on first use rather than imported: react-native-device-info throws
// at import in a build without its native code, such as Expo Go, and the SDK's
// import must not crash such an app (see NativeCoproduct.ts)
function deviceInfo(): typeof DeviceInfoModule {
  const mod = require('react-native-device-info');
  return (mod.default ?? mod) as typeof DeviceInfoModule;
}

// Static device attributes collected once per initialize. Values are raw
// platform facts; the core normalizes them (version padding, locale
// hyphenation), mirroring DeviceContext.swift's division of responsibility.
export function staticDeviceAttributes(): Record<string, AttributeValue> {
  const attrs: Record<string, AttributeValue> = {
    platform: Platform.OS,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
  };

  const locale = Intl.DateTimeFormat().resolvedOptions().locale;
  if (locale) {
    attrs.locale = locale;
  }

  const DeviceInfo = deviceInfo();
  attrs.os_version = DeviceInfo.getSystemVersion();
  attrs.app_version = DeviceInfo.getVersion();
  attrs.app_build = DeviceInfo.getBuildNumber();

  const deviceType = mapDeviceType(DeviceInfo.getDeviceType());
  if (deviceType) {
    attrs.device_type = deviceType;
  }

  return attrs;
}

// phone and tablet only. An unmapped idiom omits the attribute entirely so
// is_set/is_not_set stay meaningful, matching DeviceContext.swift's
// deviceType(for:) contract: widen the vocabulary only when the platform
// recognizes a new device type, never by inventing values here.
function mapDeviceType(idiom: string): 'phone' | 'tablet' | undefined {
  switch (idiom) {
    case 'Handset':
      return 'phone';
    case 'Tablet':
      return 'tablet';
    default:
      return undefined;
  }
}
