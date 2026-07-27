import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'metadata_collector.dart';

/// The platform token the core expects, or empty on an unsupported host so the
/// collector omits the field rather than sending a null.
String _platformName() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  return '';
}

/// Builds the production metadata providers over the platform plugins. Each is a
/// bounded, fail-closed source the collector runs concurrently. Values are raw,
/// the core normalizes them.
MetadataProviders platformMetadataProviders() {
  final deviceInfo = DeviceInfoPlugin();
  return MetadataProviders(
    platform: () async => _platformName(),
    osVersion: () async {
      if (Platform.isAndroid) {
        return (await deviceInfo.androidInfo).version.release;
      }
      if (Platform.isIOS) return (await deviceInfo.iosInfo).systemVersion;
      return null;
    },
    appVersion: () async => (await PackageInfo.fromPlatform()).version,
    appBuild: () async => (await PackageInfo.fromPlatform()).buildNumber,
    locale: () async => PlatformDispatcher.instance.locale.toLanguageTag(),
    timezone: () async => (await FlutterTimezone.getLocalTimezone()).identifier,
  );
}
