import 'errors.dart';

/// Options for `Coproduct.initialize`.
///
/// Every field has a default, so pass only the ones you want to change. An
/// invalid value makes `initialize` throw [InvalidConfig] rather than being
/// silently corrected. Immutable and const-constructible:
///
/// ```dart
/// final client = await Coproduct.initialize(
///   sdkKey: 'cpk_mob_...',
///   config: const CoproductConfig(
///     pollInterval: Duration(seconds: 30),
///     startupTimeout: Duration(seconds: 3),
///   ),
/// );
/// ```
final class CoproductConfig {
  /// Creates a configuration. Any field you leave out takes its default
  const CoproductConfig({
    this.pollInterval = const Duration(seconds: 60),
    this.startupTimeout = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 30),
    this.endpoint,
    this.pollOnForeground = true,
  });

  /// How often the SDK checks Coproduct for updated flags.
  ///
  /// Defaults to 60 seconds and must be at least 30 seconds. After five failed
  /// checks in a row the SDK checks every five intervals until one succeeds
  final Duration pollInterval;

  /// The longest `Coproduct.initialize` waits before it returns.
  ///
  /// Defaults to 5 seconds and must be positive. It limits the wait for two
  /// things: the first download of your flags, and the automatic attributes.
  /// On a launch that finds flags saved on an earlier launch, `initialize`
  /// does not wait for the network. When the limit passes, `initialize`
  /// returns without throwing, and it can return slightly after the limit.
  /// Work the limit cuts short carries on in the background
  final Duration startupTimeout;

  /// The longest a single request for flags can take.
  ///
  /// Defaults to 30 seconds and must be positive. A request that runs out of
  /// time counts as a failed check
  final Duration requestTimeout;

  /// The Coproduct endpoint the SDK downloads flags from.
  ///
  /// Leave it null to use Coproduct's endpoint. An override must use `http`
  /// or `https`, include a host, and have no query or fragment. Trailing
  /// slashes are removed
  final Uri? endpoint;

  /// Whether returning the app to the foreground triggers an immediate check
  /// for updated flags.
  ///
  /// Defaults to true. No check is triggered while one is already running,
  /// while the SDK is backing off, or after checks have stopped
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
