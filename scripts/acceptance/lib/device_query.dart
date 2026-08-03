/// Raised when the requested device is not an acceptable acceptance target.
class AcceptanceDeviceError implements Exception {
  AcceptanceDeviceError(this.message);
  final String message;
  @override
  String toString() => 'AcceptanceDeviceError: $message';
}

/// Verifies the requested device (from `flutter devices --machine`) is a
/// supported emulator or simulator of the requested platform. Physical devices
/// are rejected: 127.0.0.1 refers to the phone, and 10.0.2.2 is only meaningful
/// to the Android emulator, so the fixture would be unreachable.
void requireAcceptanceDevice(
    List<Object?> devicesJson, String platform, String deviceId) {
  final matches = devicesJson
      .cast<Map<String, Object?>>()
      .where((d) => d['id'] == deviceId)
      .toList();
  if (matches.isEmpty) {
    throw AcceptanceDeviceError(
        'device `$deviceId` not found in flutter devices');
  }
  if (matches.length > 1) {
    throw AcceptanceDeviceError('multiple devices match id `$deviceId`');
  }
  final d = matches.single;
  final target = (d['targetPlatform'] as String?) ?? '';
  final platformOk = platform == 'ios'
      ? target == 'ios'
      : platform == 'android' && target.startsWith('android-');
  if (d['isSupported'] != true || d['emulator'] != true || !platformOk) {
    throw AcceptanceDeviceError(
        'device `$deviceId` (targetPlatform=$target, emulator=${d['emulator']}, '
        'isSupported=${d['isSupported']}) is not a supported $platform '
        'simulator or Android emulator; the acceptance gate accepts an iOS '
        'simulator or Android emulator, not a physical device');
  }
}
