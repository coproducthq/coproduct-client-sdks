import 'config.dart';
import 'rust/api.dart' as frb;

/// The single-flight key for an initialize: the SDK key together with the
/// normalized effective config. Two initialize calls join only when both match,
/// so a second call with a different key or config is rejected rather than
/// silently joined. Equality is by value over both fields, never the key alone.
class InitIdentity {
  const InitIdentity(this.sdkKey, this.config);

  final String sdkKey;
  final CoproductConfig config;

  @override
  bool operator ==(Object other) =>
      other is InitIdentity &&
      other.sdkKey == sdkKey &&
      other.config == config;

  @override
  int get hashCode => Object.hash(sdkKey, config);
}

/// Maps the validated public config to the FRB/core config. Durations cross as
/// microseconds and the endpoint as its canonical string, or null for the core
/// default. Request timeout and foreground polling are host behavior and do not
/// cross into the core config.
frb.FfiConfig ffiConfigFor(CoproductConfig config) => frb.FfiConfig(
      pollIntervalUs: config.pollInterval.inMicroseconds,
      startupTimeoutUs: config.startupTimeout.inMicroseconds,
      endpoint: config.endpoint?.toString(),
    );
