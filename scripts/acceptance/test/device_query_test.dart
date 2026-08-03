import 'package:coproduct_acceptance/device_query.dart';
import 'package:test/test.dart';

Map<String, Object?> _dev({
  String id = 'D1',
  bool isSupported = true,
  bool emulator = true,
  String targetPlatform = 'ios',
}) =>
    {
      'id': id,
      'isSupported': isSupported,
      'emulator': emulator,
      'targetPlatform': targetPlatform,
    };

void main() {
  test('accepts a supported iOS simulator', () {
    requireAcceptanceDevice([_dev()], 'ios', 'D1');
  });

  test('accepts a supported Android emulator by family prefix', () {
    requireAcceptanceDevice(
        [_dev(targetPlatform: 'android-arm64')], 'android', 'D1');
  });

  test('rejects a physical device (emulator false)', () {
    expect(
        () => requireAcceptanceDevice([_dev(emulator: false)], 'ios', 'D1'),
        throwsA(predicate((e) =>
            e is AcceptanceDeviceError &&
            e.message.contains('simulator or Android emulator'))));
  });

  test('rejects a cross-platform device', () {
    expect(
        () => requireAcceptanceDevice(
            [_dev(targetPlatform: 'android-x64')], 'ios', 'D1'),
        throwsA(isA<AcceptanceDeviceError>()));
  });

  test('rejects a missing device id', () {
    expect(() => requireAcceptanceDevice([_dev()], 'ios', 'OTHER'),
        throwsA(isA<AcceptanceDeviceError>()));
  });

  test('rejects an unsupported device', () {
    expect(
        () => requireAcceptanceDevice([_dev(isSupported: false)], 'ios', 'D1'),
        throwsA(isA<AcceptanceDeviceError>()));
  });
}
