import 'package:flutter/services.dart';

import 'errors.dart';

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
}
