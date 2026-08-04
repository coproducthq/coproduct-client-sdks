import 'errors.dart';

/// Configuration for Coproduct.initialize. Immutable and const-constructible.
/// [pollInterval] must be at least 30 seconds. [requestTimeout] bounds a single
/// snapshot request. [endpoint] overrides the default Coproduct endpoint.
///
/// [startupTimeout] is one monotonic budget for startup convergence: automatic
/// metadata collection and initial provider readiness. The budget begins with
/// the single-flight initialization attempt, so required native client
/// construction consumes part of it and only the remaining budget is available
/// for metadata and readiness. Metadata and readiness proceed concurrently. At
/// expiry the SDK stops waiting for convergence, freezes the metadata completed
/// within the budget, then proceeds through mandatory publication and
/// finalization before returning the client with its current provider state.
/// Those mandatory operations are not governed by [startupTimeout], so return
/// time can exceed it. Polling continues in the background, and shutdown takes
/// precedence.
class CoproductConfig {
  const CoproductConfig({
    this.pollInterval = const Duration(seconds: 60),
    this.startupTimeout = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 30),
    this.endpoint,
    this.pollOnForeground = true,
  });

  final Duration pollInterval;
  final Duration startupTimeout;
  final Duration requestTimeout;
  final Uri? endpoint;
  final bool pollOnForeground;

  @override
  bool operator ==(Object other) =>
      other is CoproductConfig &&
      other.pollInterval == pollInterval &&
      other.startupTimeout == startupTimeout &&
      other.requestTimeout == requestTimeout &&
      other.endpoint == endpoint &&
      other.pollOnForeground == pollOnForeground;

  @override
  int get hashCode => Object.hash(
      pollInterval, startupTimeout, requestTimeout, endpoint, pollOnForeground);

  CoproductConfig _withEndpoint(Uri? e) => CoproductConfig(
        pollInterval: pollInterval,
        startupTimeout: startupTimeout,
        requestTimeout: requestTimeout,
        endpoint: e,
        pollOnForeground: pollOnForeground,
      );
}

/// The core minimum poll interval, matching coproduct-core MIN_POLL_INTERVAL
const Duration minPollInterval = Duration(seconds: 30);

/// Validates and normalizes a config, throwing InvalidConfig on invalid input.
/// The endpoint rules are a deliberate host-side restriction: the core only
/// requires a valid http(s) URI with an authority, but because the core appends
/// a fixed path a query or fragment on the base would produce a broken URL, so
/// they are rejected here. All trailing slashes are stripped to match the core's
/// trim_end_matches. Returns the config with a normalized endpoint
CoproductConfig validateConfig(CoproductConfig config) {
  if (config.pollInterval < minPollInterval) {
    throw const InvalidConfig('pollInterval', 'must be at least 30 seconds');
  }
  if (config.startupTimeout <= Duration.zero) {
    throw const InvalidConfig('startupTimeout', 'must be positive');
  }
  if (config.requestTimeout <= Duration.zero) {
    throw const InvalidConfig('requestTimeout', 'must be positive');
  }
  final endpoint = config.endpoint;
  if (endpoint == null) {
    return config;
  }
  if (endpoint.scheme != 'http' && endpoint.scheme != 'https') {
    throw const InvalidConfig('endpoint', 'scheme must be http or https');
  }
  if (endpoint.host.isEmpty) {
    throw const InvalidConfig('endpoint', 'must have a host');
  }
  if (endpoint.hasFragment) {
    throw const InvalidConfig('endpoint', 'must not have a fragment');
  }
  if (endpoint.hasQuery) {
    throw const InvalidConfig('endpoint', 'must not have a query');
  }
  var path = endpoint.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return config._withEndpoint(endpoint.replace(path: path));
}
