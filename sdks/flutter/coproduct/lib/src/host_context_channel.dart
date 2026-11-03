import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'errors.dart';
import 'session.dart';

/// The Dart side of the host-context plugin. Request and response only, with no
/// state of its own
class HostContextChannel {
  const HostContextChannel();

  static const _channel = MethodChannel('app.coproduct.flutter/host_context');
  static const _networkChannelName = 'app.coproduct.flutter/network_type';
  static const _networkCodec = StandardMethodCodec();
  static const _networkMethods = MethodChannel(
    _networkChannelName,
    _networkCodec,
  );

  Future<String?> readDeviceType() async {
    try {
      return await _channel.invokeMethod<String>('readDeviceType');
    } on MissingPluginException {
      throw const HostContextUnavailable();
    }
  }

  /// Reads the OS version, app version, and build number in one round trip,
  /// because each channel call pays the platform-channel cost against the
  /// shared startup budget. A native failure propagates so the caller can retry
  Future<HostInfo> readHostInfo() async {
    final Object? raw;
    try {
      raw = await _channel.invokeMethod<Object?>('readHostInfo');
    } on MissingPluginException {
      throw const HostContextUnavailable();
    }
    return HostInfo.fromChannel(raw);
  }

  /// Runs the native session transaction. Side-effecting, since it may count a
  /// session, so the caller runs it at most once per runtime build
  Future<SessionPair> beginSession() async {
    final Object? raw;
    try {
      raw = await _channel.invokeMethod<Object?>('beginSession');
    } on MissingPluginException {
      throw const HostContextUnavailable();
    } on PlatformException {
      // A native store that threw has failed as surely as one that reported
      // failure, and the developer should see the same diagnostic for both
      throw const SessionAttributesUnavailable(
        SessionAttributesUnavailableCause.storageFailure,
      );
    }
    if (raw == null) {
      throw const SessionAttributesUnavailable(
        SessionAttributesUnavailableCause.storageFailure,
      );
    }
    return SessionPair.fromChannel(raw);
  }

  /// Starts one native observation tagged with [epoch], which every event
  /// echoes. Each call is a fresh listen, and its first event is the current
  /// value
  ///
  /// The wire protocol is the event channel's own, so the platform side is a
  /// standard event channel. Unlike the framework's broadcast stream, a failed
  /// listen arrives on the stream rather than through FlutterError: a missing
  /// plugin as [HostContextUnavailable], which the caller reports once, and a
  /// native failure as the [PlatformException], which the caller retries
  Stream<Object?> networkTypeEvents(int epoch) {
    // The same messenger a method channel uses by default, so the handler and
    // the listen and cancel calls share one connection to the platform
    final messenger = _networkMethods.binaryMessenger;
    var missingPlugin = false;
    late final StreamController<Object?> controller;
    controller = StreamController<Object?>.broadcast(
      onListen: () async {
        // Installed before the listen is sent, so the first event cannot
        // arrive ahead of its handler
        messenger.setMessageHandler(_networkChannelName, (message) async {
          if (message == null) {
            unawaited(controller.close());
          } else {
            try {
              controller.add(_networkCodec.decodeEnvelope(message));
            } on PlatformException catch (error, stack) {
              controller.addError(error, stack);
            }
          }
          return null;
        });
        try {
          await _networkMethods.invokeMethod<void>('listen', epoch);
        } on MissingPluginException {
          missingPlugin = true;
          controller.addError(const HostContextUnavailable());
        } catch (error, stack) {
          controller.addError(error, stack);
        }
      },
      onCancel: () async {
        // Cleared before anything is awaited, because a replacement listen
        // installs its own handler as soon as this returns and a later clear
        // would remove it
        messenger.setMessageHandler(_networkChannelName, null);
        if (missingPlugin) return;
        try {
          await _networkMethods.invokeMethod<void>('cancel', epoch);
        } on MissingPluginException {
          // The listen reports a missing plugin, and once is enough
        } catch (error) {
          _debugLog('cancelling network_type observation failed: $error');
        }
      },
    );
    return controller.stream;
  }
}

/// The host's OS and app version strings as the platform reports them. Each is
/// null when the platform has no value, and none is normalized here, so a
/// targeting rule sees the platform's own string
@immutable
class HostInfo {
  const HostInfo({this.osVersion, this.appVersion, this.appBuild});

  /// A malformed answer is all absent rather than a failure, and a wrong-typed
  /// entry is dropped on its own, so one bad field cannot cost the others
  factory HostInfo.fromChannel(Object? raw) {
    if (raw is! Map) return const HostInfo();
    String? read(String key) {
      final value = raw[key];
      return value is String ? value : null;
    }

    return HostInfo(
      osVersion: read('os_version'),
      appVersion: read('app_version'),
      appBuild: read('app_build'),
    );
  }

  final String? osVersion;
  final String? appVersion;
  final String? appBuild;

  @override
  bool operator ==(Object other) =>
      other is HostInfo &&
      other.osVersion == osVersion &&
      other.appVersion == appVersion &&
      other.appBuild == appBuild;

  @override
  int get hashCode => Object.hash(osVersion, appVersion, appBuild);

  @override
  String toString() =>
      'HostInfo(osVersion: $osVersion, appVersion: $appVersion, '
      'appBuild: $appBuild)';
}

/// Debug builds only, so a release build carries no log noise
void _debugLog(String message) {
  assert(() {
    debugPrint('coproduct: $message');
    return true;
  }());
}
