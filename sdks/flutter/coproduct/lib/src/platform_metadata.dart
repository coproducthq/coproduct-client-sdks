import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_timezone/flutter_timezone.dart';

import 'host_context_channel.dart';
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
  // Share one channel call across os_version, app_version, and app_build. All
  // three come from the same answer, and the first call after a cold launch
  // pays the whole platform-channel warm-up, so three calls would triple that
  // cost. A failure resets the memo so a later initialize can retry rather
  // than caching it
  Future<HostInfo>? hostInfo;
  Future<HostInfo> loadHostInfo() => hostInfo ??= const HostContextChannel()
      .readHostInfo()
      .onError((error, stack) {
        hostInfo = null;
        Error.throwWithStackTrace(error!, stack);
      });
  return MetadataProviders(
    deviceType: stringProvider(
      () => const HostContextChannel().readDeviceType(),
    ),
    platform: stringProvider(() async => _platformName()),
    osVersion: stringProvider(() async => (await loadHostInfo()).osVersion),
    appVersion: stringProvider(() async => (await loadHostInfo()).appVersion),
    appBuild: stringProvider(() async => (await loadHostInfo()).appBuild),
    locale: stringProvider(
      () async => PlatformDispatcher.instance.locale.toLanguageTag(),
    ),
    timezone: stringProvider(
      () async => (await FlutterTimezone.getLocalTimezone()).identifier,
    ),
  );
}
