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
  // Share one PackageInfo channel call across app_version and app_build. Both
  // read the same record, and the first call after a cold launch pays the whole
  // platform-channel warm-up, so two calls would double that cost. A failure
  // resets the memo so a later initialize can retry rather than caching it
  Future<PackageInfo>? packageInfo;
  Future<PackageInfo> loadPackageInfo() =>
      packageInfo ??= PackageInfo.fromPlatform().onError((error, stack) {
        packageInfo = null;
        Error.throwWithStackTrace(error!, stack);
      });
  return MetadataProviders(
    platform: () async => _platformName(),
    osVersion: () async {
      if (Platform.isAndroid) {
        return (await deviceInfo.androidInfo).version.release;
      }
      if (Platform.isIOS) return (await deviceInfo.iosInfo).systemVersion;
      return null;
    },
    appVersion: () async => (await loadPackageInfo()).version,
    appBuild: () async => (await loadPackageInfo()).buildNumber,
    locale: () async => PlatformDispatcher.instance.locale.toLanguageTag(),
    timezone: () async => (await FlutterTimezone.getLocalTimezone()).identifier,
  );
}
