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
CoproductClient createClientForBackend(CoproductClientBackend backend) =>
    CoproductClient._(backend);

/// A live Coproduct client for reading flags and setting the evaluation identity.
///
/// The identity mutators (`identify`, `signOut`, `setContext`, `updateAttributes`,
/// `removeAttributes`) share these semantics: they perform no network request,
/// they re-evaluate the currently loaded snapshot locally and may notify
/// observers, and they apply in call order. Await a mutation to observe its
/// completion and errors, or to read settled state such as [previousAnonymousId]
/// afterwards. Ignoring the returned future gives up that observation, and if the
/// operation fails the error surfaces as an unhandled asynchronous error.
/// Identified state is not persisted across launches, so call [identify] again
/// after initialize on each launch. With no snapshot loaded, reads return defaults
final class CoproductClient {
  CoproductClient._(this._backend);

  final CoproductClientBackend _backend;
  final SerialQueue _identityQueue = SerialQueue();

  bool getBool(String key, bool defaultValue) =>
      _backend.getBool(key, defaultValue);

  /// Reads a string flag, returning [defaultValue] if the flag is missing, the
  /// wrong type, or the SDK is not ready
  String getString(String key, String defaultValue) =>
      _backend.getString(key, defaultValue);

  /// Reads an integer flag, returning [defaultValue] if the flag is missing, the
  /// wrong type, or the SDK is not ready. Integers travel as the numeric flag
  /// type, so a fractional value is truncated toward zero
  int getInt(String key, int defaultValue) => _backend.getInt(key, defaultValue);

  /// Reads a numeric flag, returning [defaultValue] if the flag is missing, the
  /// wrong type, or the SDK is not ready
  double getNumber(String key, double defaultValue) =>
      _backend.getNumber(key, defaultValue);

  /// Reads a JSON flag as a native Dart value (map, list, scalar, or null).
  ///
  /// The result is deeply unmodifiable, matching [observeJson], so one ownership
  /// rule covers every JSON value the SDK hands back. Copy it if you need to
  /// mutate.
  ///
  /// [defaultValue] must be JSON-encodable: null, a JSON scalar, a list of
  /// JSON-encodable values, or a string-keyed map of JSON-encodable values. If
  /// encoding or decoding fails, the supplied [defaultValue] is returned
  /// unchanged instead of throwing, matching the "reads do not throw" contract.
  /// A default JSON cannot encode never round-trips, so it comes back exactly as
  /// supplied and is the one result that is not unmodifiable
  Object? getJson(String key, Object? defaultValue) {
    final String defaultValueJson;
    try {
      defaultValueJson = jsonEncode(defaultValue);
    } catch (_) {
      return defaultValue;
    }
    final resultJson = _backend.getJson(key, defaultValueJson);
    try {
      return unmodifiableJson(jsonDecode(resultJson));
    } catch (_) {
      return defaultValue;
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
    return _identityQueue.add(() => _backend.identify(
          userId: userId,
          attributes: snapshot,
          linkAnonymous: linkAnonymous,
        ));
  }

  /// Clears the identified user and reverts to the anonymous identity, clearing
  /// developer attributes. Awaiting settles the transition and the anonymous-id
  /// persistence attempt, not durable storage, since a write failure is logged and
  /// swallowed
  Future<void> signOut() => _identityQueue.add(_backend.signOut);

  /// Replaces the targeting key and developer attributes of the current context,
  /// so an attribute not in [attributes] is cleared. Reserved keys `user_id` and
  /// `targetingKey` are ignored. Throws `InvalidTargetingKey` if [targetingKey]
  /// is empty
  Future<void> setContext({
    required String targetingKey,
    Map<String, AttributeValue> attributes = const {},
  }) {
    final snapshot = Map<String, AttributeValue>.unmodifiable(attributes);
    return _identityQueue.add(() => _backend.setContext(
          targetingKey: targetingKey,
          attributes: snapshot,
        ));
  }

  /// Merges [attributes] into the current developer attributes, so omitted keys
  /// remain. Reserved keys `user_id` and `targetingKey` are ignored
  Future<void> updateAttributes(Map<String, AttributeValue> attributes) {
    final snapshot = Map<String, AttributeValue>.unmodifiable(attributes);
    return _identityQueue.add(() => _backend.updateAttributes(snapshot));
  }

  /// Removes the named developer attributes, which may reveal a lower context
  /// layer's value for those keys
  Future<void> removeAttributes(List<String> keys) {
    final snapshot = snapshotKeys(keys);
    return _identityQueue.add(() => _backend.removeAttributes(snapshot));
  }

  /// The anonymous id captured to link a pre-login session, or null. A linked
  /// identify captures the current anonymous id only when no id is currently
  /// stored, so later linked identifies do not overwrite a stored value. signOut
  /// or an unlinked identify (linkAnonymous false) clears it, after which a later
  /// linked identify can capture it again. Read it after awaiting the identity
  /// mutation that should have changed it
  String? get previousAnonymousId => _backend.previousAnonymousId;

  /// The current provider lifecycle state
  ProviderState get state => _backend.state;

  /// Observes a boolean flag, returning a [FlagObservation] whose value is
  /// already seeded with what [getBool] would return right now.
  ///
  /// The observation updates when a poll, an identity change, or a context
  /// change alters this flag's value, and resolves to [defaultValue] whenever
  /// the flag is unavailable. The caller owns it: call
  /// [FlagObservation.dispose] when the owner goes away, or let
  /// [CoproductFlagBuilder] own one for you
  FlagObservation<bool> observeBool(String key, bool defaultValue) {
    final handle = _backend.observeBool(key);
    return boolObservation(
      defaultValue: defaultValue,
      seed: handle.seed,
      events: handle.events,
      cancel: handle.cancel,
    );
  }

  /// Observes a string flag. See [observeBool] for ownership and update
  /// semantics
  FlagObservation<String> observeString(String key, String defaultValue) {
    final handle = _backend.observeString(key);
    return stringObservation(
      defaultValue: defaultValue,
      seed: handle.seed,
      events: handle.events,
      cancel: handle.cancel,
    );
  }

  /// Observes an integer flag. Integers travel as the numeric flag type, so a
  /// fractional value is truncated toward zero and a value outside the integer
  /// range is unavailable, matching [getInt]. See [observeBool] for ownership
  /// and update semantics
  FlagObservation<int> observeInt(String key, int defaultValue) {
    final handle = _backend.observeInt(key);
    return intObservation(
      defaultValue: defaultValue,
      seed: handle.seed,
      events: handle.events,
      cancel: handle.cancel,
    );
  }

  /// Observes a numeric flag. See [observeBool] for ownership and update
  /// semantics
  FlagObservation<double> observeNumber(String key, double defaultValue) {
    final handle = _backend.observeNumber(key);
    return numberObservation(
      defaultValue: defaultValue,
      seed: handle.seed,
      events: handle.events,
      cancel: handle.cancel,
    );
  }

  /// Observes a JSON flag as a native Dart value (map, list, scalar, or null).
  ///
  /// This is the one observation whose value is legitimately nullable: a flag
  /// serving the JSON document `null` resolves to Dart `null`, which is a real
  /// value and is distinct from the flag being unavailable. An unavailable flag
  /// resolves to [defaultValue] like every other type.
  ///
  /// Decoded values are deeply unmodifiable. [defaultValue] should be
  /// JSON-encodable, and an encodable one is served back in its decoded form so
  /// it matches [getJson]. One that is not encodable is served back exactly as
  /// supplied rather than throwing. See [observeBool] for ownership and update
  /// semantics
  FlagObservation<Object?> observeJson(String key, Object? defaultValue) {
    final handle = _backend.observeJson(key);
    return jsonObservation(
      defaultValue: defaultValue,
      seed: handle.seed,
      events: handle.events,
      cancel: handle.cancel,
    );
  }
}

/// The single process-wide runtime, initialized and shut down through the static
/// entry points. Reads and identity live on the returned [CoproductClient].
final class Coproduct {
  Coproduct._();

  static final CoproductHost<frb.CoproductClientHandle, CoproductClient> _host =
      CoproductHost<frb.CoproductClientHandle, CoproductClient>(
    bridge: FrbNativeBridge(),
    userAgent: coproductUserAgent,
    createTransport: (requestTimeout) =>
        HttpTransport(requestTimeout: requestTimeout),
    secureStore:
        SecureIdentityStore(operationTimeout: const Duration(seconds: 1)),
    metadataProviders: platformMetadataProviders(),
    createClient: (handle) => createClientForBackend(FrbBackend(handle)),
    bindForeground: appLifecycleForegroundBinder,
    reportError: _reportError,
  );

  /// Initializes the SDK: validates the config, constructs the client against the
  /// cache and stored identity, installs automatic context, and starts polling.
  /// Initialization waits for automatic metadata collection and initial provider
  /// readiness against the [CoproductConfig.startupTimeout] convergence budget.
  /// Mandatory native construction runs outside that budget, so the return time
  /// can exceed it. Concurrent or repeated calls with the same key and config
  /// join the same client, a different key or config throws
  /// [CoproductAlreadyInitialized]. The returned client is ready to read, serving
  /// cache or defaults until the first poll lands.
  static Future<CoproductClient> initialize({
    required String sdkKey,
    CoproductConfig config = const CoproductConfig(),
  }) =>
      _host.initialize(sdkKey: sdkKey, config: config);

  /// Tears the runtime down: stops polling, sets the core shutdown latch, and
  /// closes the transport. After shutdown the typed getters on a retained client
  /// return their supplied defaults. Idempotent, and a no-op when nothing is
  /// initialized. A later [initialize] builds a fresh runtime.
  static Future<void> shutdown() => _host.shutdown();
}

void _reportError(Object error, StackTrace stack) {
  FlutterError.reportError(FlutterErrorDetails(
    exception: error,
    stack: stack,
    library: 'coproduct',
  ));
}
