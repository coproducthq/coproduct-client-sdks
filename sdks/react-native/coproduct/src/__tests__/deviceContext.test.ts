jest.mock('react-native-device-info', () => ({
  getSystemVersion: jest.fn(() => '17.4.1'),
  getVersion: jest.fn(() => '1.2.3'),
  getBuildNumber: jest.fn(() => '45'),
  getDeviceType: jest.fn(() => 'Handset'),
}));

import { Platform } from 'react-native';
import { staticDeviceAttributes } from '../deviceContext';

describe('staticDeviceAttributes', () => {
  it('includes platform, timezone, and the device-info fields', () => {
    const attrs = staticDeviceAttributes();

    expect(attrs.platform).toBe(Platform.OS);
    expect(attrs.os_version).toBe('17.4.1');
    expect(attrs.app_version).toBe('1.2.3');
    expect(attrs.app_build).toBe('45');
    expect(attrs.device_type).toBe('phone');
    expect(typeof attrs.timezone).toBe('string');
  });

  it('maps Tablet to tablet', () => {
    const DeviceInfo = require('react-native-device-info');
    DeviceInfo.getDeviceType.mockReturnValue('Tablet');

    const attrs = staticDeviceAttributes();
    expect(attrs.device_type).toBe('tablet');
  });

  it('omits device_type for an unrecognized idiom rather than inventing a value', () => {
    const DeviceInfo = require('react-native-device-info');
    DeviceInfo.getDeviceType.mockReturnValue('Desktop');

    const attrs = staticDeviceAttributes();
    expect(attrs.device_type).toBeUndefined();
  });
});
