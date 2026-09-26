import 'package:flutter/services.dart';

import 'errors.dart';
import 'session.dart';

/// The Dart side of the host-context plugin. Request and response only, with no
/// state of its own
class HostContextChannel {
  const HostContextChannel();

  static const _channel = MethodChannel('app.coproduct.flutter/host_context');

  Future<String?> readDeviceType() async {
    try {
      return await _channel.invokeMethod<String>('readDeviceType');
    } on MissingPluginException {
      throw const HostContextUnavailable();
    }
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
          SessionAttributesUnavailableCause.storageFailure);
    }
    if (raw == null) {
      throw const SessionAttributesUnavailable(
          SessionAttributesUnavailableCause.storageFailure);
    }
    return SessionPair.fromChannel(raw);
  }
}
