import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;

import 'attribute_value.dart';
import 'client_backend.dart';
import 'config.dart';
import 'errors.dart';
import 'flag_observation.dart';
import 'foreground.dart';
import 'frb_backend.dart';
import 'host.dart';
import 'host_context_channel.dart';
import 'isolate_probe.dart';
import 'http_transport.dart';
import 'json_value.dart';
import 'native_bridge.dart';
import 'platform_metadata.dart';
import 'provider_state.dart';
import 'rust/api.dart' as frb;
import 'secure_identity_store.dart';
import 'sdk_version.dart';
import 'serial_queue.dart';

/// Builds a client over a backend.
///
/// Package-internal: exported from neither barrel, so the backend contract stays
/// out of the public surface and can change without a breaking release. The
/// constructor is private so the contract is not part of an exported class's
/// signature
CoproductClient createClientForBackend(
  CoproductClientBackend backend, {
  SerialQueue? identityQueue,
}) => CoproductClient._(backend, identityQueue ?? SerialQueue());

/// Reads flags and sets who they are evaluated for. Get one from
/// [Coproduct.initialize], or from `CoproductTestHarness` in a widget test.
///
/// Reads never throw. Each one is an in-memory lookup against the flags the
/// SDK has downloaded, so it makes no network request. When the SDK cannot
/// resolve a flag, a read returns the default value you pass.
///
/// The identity calls ([identify], [setContext], [updateAttributes],
/// [removeAttributes], and [signOut]) make no network request either. They
/// re-evaluate the flags the SDK already has, apply in the order you call
/// them, and update observations. Await them: when the future completes,
/// getters, observations, and [previousAnonymousId] reflect the change, and
/// an ignored future that fails becomes an unhandled asynchronous error.
/// Identity is not saved between launches, so call [identify] again after
/// `initialize` on each launch
final class CoproductClient {
  CoproductClient._(this._backend, this._identityQueue);

  final CoproductClientBackend _backend;
  // Supplied by the host so machine-initiated writes to the automatic layer
  // order against the identity mutators instead of racing them. A second queue
  // would reintroduce exactly the interleaving this one exists to prevent
  final SerialQueue _identityQueue;

  /// Reads a boolean flag.
  ///
  /// Returns the value Coproduct serves for the current user: the value of the
  /// targeting rule the user matches, the flag's fallthrough value when no
  /// rule matches, or its off value when the flag is switched off or paused,
  /// its prerequisite is not met, or its rules use a condition this SDK
  /// version does not understand. Returns
  /// [defaultValue] when the SDK cannot resolve the flag: it has no flags
  /// yet, no flag with [key] exists, the flag is not a boolean, the SDK key was
  /// rejected, or the SDK was shut down. Never throws.
  ///
  /// This reads the value at this moment and nothing more. Called inside
  /// `build`, it does not rebuild your widget when the flag changes. Use
  /// `CoproductFlagBuilder.boolFlag` or [observeBool] for that
  bool getBool(String key, {required bool defaultValue}) =>
      _backend.getBool(key, defaultValue: defaultValue);

  /// Reads a string flag.
  ///
  /// Returns [defaultValue] when the SDK cannot resolve the flag, including
  /// when the flag is not a string. See [getBool] for what a read serves.
  /// Never throws, and does not rebuild a widget when the flag changes
  String getString(String key, {required String defaultValue}) =>
      _backend.getString(key, defaultValue: defaultValue);

  /// Reads a number flag as an integer.
  ///
  /// There is no separate integer flag type, so create a number flag. A
  /// fractional value is truncated toward zero, and a value outside the signed
  /// 64-bit range returns [defaultValue]. Returns [defaultValue] when the SDK
  /// cannot resolve the flag, including when the flag is not a number. See
  /// [getBool] for what a read serves. Never throws, and does not rebuild a
  /// widget when the flag changes
  int getInt(String key, {required int defaultValue}) =>
      _backend.getInt(key, defaultValue: defaultValue);

  /// Reads a number flag.
  ///
  /// Returns [defaultValue] when the SDK cannot resolve the flag, including
  /// when the flag is not a number. See [getBool] for what a read serves.
  /// Never throws, and does not rebuild a widget when the flag changes
  double getNumber(String key, {required double defaultValue}) =>
      _backend.getNumber(key, defaultValue: defaultValue);

  /// Reads a JSON flag as a Dart value: a map, list, string, number, bool, or
  /// null.
  ///
  /// The result is deeply unmodifiable, so copy it before changing it. Returns
  /// [defaultValue] when the SDK cannot resolve the flag, including when the
  /// flag is not a JSON flag. See [getBool] for what a read serves.
  ///
  /// Pass a JSON-encodable [defaultValue]: null, a number, string, or bool, or
  /// lists and string-keyed maps of those. A default value that cannot be
  /// encoded is returned exactly as you passed it, and is then the one result
  /// that is not unmodifiable. Never throws
  Object? getJson(String key, {required Object? defaultValue}) {
    final String defaultValueJson;
    try {
      defaultValueJson = jsonEncode(defaultValue);
    } catch (_) {
      return defaultValue;
    }
    final resultJson = _backend.getJson(
      key,
      defaultValueJson: defaultValueJson,
    );
    try {
      return unmodifiableJson(jsonDecode(resultJson));
    } catch (_) {
      return defaultValue;
    }
  }

  /// Reads [flowId]'s onboarding flow graph from the cached snapshot as a
  /// native Dart value (deeply unmodifiable, matching [getJson]).
  ///
  /// Unlike [getJson] this is a direct snapshot lookup with no caller default:
  /// a null result is a real "not present" case (not-ready, wrong [flowId], or
  /// malformed cached JSON) that the caller must handle rather than a value to
  /// paper over
  Object? getOnboardingFlowGraph(String flowId) {
    final resultJson = _backend.getOnboardingFlowGraph(flowId);
    if (resultJson == null) return null;
    try {
      return unmodifiableJson(jsonDecode(resultJson));
    } catch (_) {
      return null;
    }
  }

  /// Identifies the evaluated context by [userId] and replaces its developer
  /// attributes with [attributes], so an attribute not in the map is cleared.
  /// [linkAnonymous] (default true) carries the pre-identify anonymous id forward,
  /// readable via [previousAnonymousId]. Reserved keys `user_id` and `targetingKey`
  /// in [attributes] are ignored, so set identity through [userId]. Throws
  /// `InvalidTargetingKey` if [userId] is empty. Awaiting settles the in-memory
  /// transition, lifecycle notifications, and observer fan-out, and performs no
  /// persistence
  Future<void> identify({
    required String userId,
    Map<String, AttributeValue> attributes = const {},
    bool linkAnonymous = true,
  }) {
    // Snapshotted synchronously, before the operation is queued, so a later
    // mutation of the caller's map cannot change an operation already in flight
    final snapshot = Map<String, AttributeValue>.unmodifiable(attributes);
    return _identityQueue.add(
      () => _backend.identify(
        userId: userId,
        attributes: snapshot,
        linkAnonymous: linkAnonymous,
      ),
    );
  }

  /// Returns to this installation's anonymous id, and clears your attributes
  /// and [previousAnonymousId].
  ///
  /// The anonymous id is the same one used before sign-in, so an anonymous
  /// rollout places the device in the same group as before. The automatic
  /// attributes are never cleared
  Future<void> signOut() => _identityQueue.add(_backend.signOut);

  /// Sets the targeting key flags are evaluated for directly, and replaces
  /// your attributes with [attributes].
  ///
  /// Use it when what you target is not a signed-in account, such as a team
  /// or a device. A rule on `user_id` matches [targetingKey]. Like [identify],
  /// an attribute missing from [attributes] is cleared, the reserved keys
  /// `user_id` and `targetingKey` are ignored, and the automatic attributes
  /// are never cleared. Unlike [identify], it leaves [previousAnonymousId]
  /// unchanged. Throws [InvalidTargetingKey] if [targetingKey] is empty
  Future<void> setContext({
    required String targetingKey,
    Map<String, AttributeValue> attributes = const {},
  }) {
    final snapshot = Map<String, AttributeValue>.unmodifiable(attributes);
    return _identityQueue.add(
      () =>
          _backend.setContext(targetingKey: targetingKey, attributes: snapshot),
    );
  }

  /// Merges [attributes] into the attributes you set earlier. Keys you leave
  /// out stay as they are.
  ///
  /// The reserved keys `user_id` and `targetingKey` are ignored. An attribute
  /// with the same name as an automatic attribute overrides it while it is set
  Future<void> updateAttributes(Map<String, AttributeValue> attributes) {
    final snapshot = Map<String, AttributeValue>.unmodifiable(attributes);
    return _identityQueue.add(() => _backend.updateAttributes(snapshot));
  }

  /// Removes the named attributes you set earlier.
  ///
  /// If an automatic attribute has the same name, its value applies again
  Future<void> removeAttributes(List<String> keys) {
    final snapshot = snapshotKeys(keys);
    return _identityQueue.add(() => _backend.removeAttributes(snapshot));
  }

  /// The anonymous id captured when someone signed in, or null.
  ///
  /// Pass it to your own analytics or backend alongside the signed-in id to
  /// join activity from before sign-in to the account. The SDK does not send
  /// it anywhere. [identify] captures it only when none is stored, so a later
  /// [identify] does not overwrite it. [signOut], and [identify] with
  /// `linkAnonymous: false`, clear it. Read it after awaiting the call that
  /// should have changed it
  String? get previousAnonymousId => _backend.previousAnonymousId;

  /// What the SDK is doing: whether it has flags, and whether its checks for
  /// updates are succeeding. See [ProviderState] for each value.
  ///
  /// Most apps never need it, because reads serve your default value whenever
  /// the SDK cannot resolve a flag. This is a plain getter with no listener.
  /// A getter can return newly downloaded values a moment before this reports
  /// [ProviderState.ready], so to react when flags arrive, observe the flag you
  /// care about instead
  ProviderState get state => _backend.state;

  /// Observes a boolean flag, returning a [FlagObservation] that holds its
  /// current value and notifies listeners when it changes.
  ///
  /// The value starts as what [getBool] returns right now, so it is available
  /// immediately. It updates when new flags arrive, when you change the
  /// identity or attributes, or when an automatic attribute such as
  /// `network_type` changes. When the SDK cannot resolve the flag, the value is
  /// [defaultValue].
  ///
  /// You own the observation: call [FlagObservation.dispose] when you are
  /// done. `CoproductFlagBuilder` creates and disposes one for you, and is the
  /// easier choice for a widget
  FlagObservation<bool> observeBool(String key, {required bool defaultValue}) {
    final handle = _backend.observeBool(key);
    return boolObservation(
      defaultValue: defaultValue,
      seed: handle.seed,
      events: handle.events,
      cancel: handle.cancel,
    );
  }

  /// Observes a string flag, returning a [FlagObservation] that notifies
  /// listeners when its value changes.
  ///
  /// The value starts as what [getString] returns right now. See [observeBool]
  /// for when it updates and why you must dispose it
  FlagObservation<String> observeString(
    String key, {
    required String defaultValue,
  }) {
    final handle = _backend.observeString(key);
    return stringObservation(
      defaultValue: defaultValue,
      seed: handle.seed,
      events: handle.events,
      cancel: handle.cancel,
    );
  }

  /// Observes a number flag as an integer, returning a [FlagObservation] that
  /// notifies listeners when its value changes.
  ///
  /// The value starts as what [getInt] returns right now. As with [getInt], a
  /// fractional value is truncated toward zero, and a value outside the signed
  /// 64-bit range serves [defaultValue]. See [observeBool] for when it updates
  /// and why you must dispose it
  FlagObservation<int> observeInt(String key, {required int defaultValue}) {
    final handle = _backend.observeInt(key);
    return intObservation(
      defaultValue: defaultValue,
      seed: handle.seed,
      events: handle.events,
      cancel: handle.cancel,
    );
  }

  /// Observes a number flag, returning a [FlagObservation] that notifies
  /// listeners when its value changes.
  ///
  /// The value starts as what [getNumber] returns right now. See [observeBool]
  /// for when it updates and why you must dispose it
  FlagObservation<double> observeNumber(
    String key, {
    required double defaultValue,
  }) {
    final handle = _backend.observeNumber(key);
    return numberObservation(
      defaultValue: defaultValue,
      seed: handle.seed,
      events: handle.events,
      cancel: handle.cancel,
    );
  }

  /// Observes a JSON flag as a Dart value, returning a [FlagObservation] that
  /// notifies listeners when its value changes.
  ///
  /// The value starts as what [getJson] returns right now, and is deeply
  /// unmodifiable. A flag that serves the JSON document `null` gives Dart
  /// `null`, which is a real value, distinct from the flag being unresolved.
  /// An unresolved flag gives [defaultValue], like every other type.
  ///
  /// Pass a JSON-encodable [defaultValue]. A default value that cannot be
  /// encoded is served exactly as you passed it rather than throwing. See
  /// [observeBool] for when it updates and why you must dispose it
  FlagObservation<Object?> observeJson(
    String key, {
    required Object? defaultValue,
  }) {
    final handle = _backend.observeJson(key);
    return jsonObservation(
      defaultValue: defaultValue,
      seed: handle.seed,
      events: handle.events,
      cancel: handle.cancel,
    );
  }
}

/// Starts and stops the SDK. There is one SDK instance per Flutter engine.
///
/// Call [initialize] once at startup, then read flags and set the identity on
/// the [CoproductClient] it returns
final class Coproduct {
  Coproduct._();

  static final CoproductHost<frb.CoproductClientHandle, CoproductClient> _host =
      CoproductHost<frb.CoproductClientHandle, CoproductClient>(
        bridge: FrbNativeBridge(),
        userAgent: coproductUserAgent,
        createTransport: (requestTimeout) =>
            HttpTransport(requestTimeout: requestTimeout),
        secureStore: SecureIdentityStore(
          operationTimeout: const Duration(seconds: 1),
        ),
        metadataProviders: platformMetadataProviders(),
        createClient: (handle, identityQueue) => createClientForBackend(
          FrbBackend(handle),
          identityQueue: identityQueue,
        ),
        bindForeground: appLifecycleForegroundBinder,
        reportError: _reportError,
        isRootIsolate: isRootIsolateNow,
        beginSession: const HostContextChannel().beginSession,
        networkTypeEvents: const HostContextChannel().networkTypeEvents,
        bindNetworkResume: appLifecycleForegroundBinder,
      );

  /// Starts the SDK and returns a client for reading flags.
  ///
  /// [sdkKey] is a mobile SDK key from Coproduct, `cpk_mob_` followed by 32
  /// characters. Call `WidgetsFlutterBinding.ensureInitialized()` first, and
  /// call this from your app's main isolate.
  ///
  /// It checks the key and [config], loads any flags saved on an earlier
  /// launch, collects the automatic attributes, and starts checking for
  /// updates. On a first launch it waits up to
  /// [CoproductConfig.startupTimeout] for the first download, then returns
  /// whether or not the flags arrived, and reads serve your default values
  /// until they do. On a later launch it starts from the saved flags and does
  /// not wait for the network. It can return slightly after
  /// [CoproductConfig.startupTimeout].
  ///
  /// Calling it again with the same key and config returns the same client.
  /// A different key or config throws [CoproductAlreadyInitialized], so call
  /// [shutdown] first to change either.
  ///
  /// Throws a [CoproductException] only for a mistake in your code, or when
  /// [shutdown] interrupts it, never for a network problem. The mistakes are
  /// [MissingSdkKey], [InvalidKeyType], [MalformedSdkKey], [InvalidConfig],
  /// [CoproductAlreadyInitialized], and [CoproductUnsupportedIsolate]. A
  /// [shutdown] that runs before this finishes throws
  /// [CoproductInitializationCancelled]. A well-formed key that Coproduct
  /// rejects, such as a revoked one, does not throw. The first check is
  /// rejected, [CoproductClient.state] becomes [ProviderState.fatal], and
  /// reads serve your default values. On a launch with saved flags, those are
  /// served until that first check completes
  static Future<CoproductClient> initialize({
    required String sdkKey,
    CoproductConfig config = const CoproductConfig(),
  }) => _host.initialize(sdkKey: sdkKey, config: config);

  /// Stops the SDK: ends checks for updates and closes its network
  /// connection.
  ///
  /// Afterward, getters on an existing client return your default values,
  /// observations keep their last value and stop updating, and identity calls
  /// complete without effect. Safe to call more than once, and does nothing
  /// when the SDK is not running. A later [initialize] returns a new client,
  /// so replace any client you stored. Most apps call this only at final
  /// teardown, if at all
  static Future<void> shutdown() => _host.shutdown();
}

void _reportError(Object error, StackTrace stack) {
  FlutterError.reportError(
    FlutterErrorDetails(exception: error, stack: stack, library: 'coproduct'),
  );
}
