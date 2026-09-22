import 'package:flutter/services.dart';

/// Raised when the host-context plugin is not reachable. Distinct from a value
/// the device declined to supply: this one means the plugin class was never
/// registered, which leaves targeting on the affected attributes silently
/// falling through until it is fixed
class HostContextUnavailable implements Exception {
  const HostContextUnavailable();

  @override
  String toString() =>
      'Coproduct: the host-context plugin is not registered on channel '
      'app.coproduct.flutter/host_context, so device_type cannot be populated. '
      'Rules targeting it will not match on this device';
}

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
