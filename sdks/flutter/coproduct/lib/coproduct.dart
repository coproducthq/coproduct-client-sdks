import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;

import 'src/attribute_value.dart';
import 'src/config.dart';
import 'src/errors.dart';
import 'src/flag_observation.dart';
import 'src/foreground.dart';
import 'src/host.dart';
import 'src/http_transport.dart';
import 'src/identity_error_translation.dart';
import 'src/native_bridge.dart';
import 'src/platform_metadata.dart';
import 'src/provider_state.dart';
import 'src/rust/api.dart' as frb;
import 'src/secure_identity_store.dart';
import 'src/sdk_version.dart';
import 'src/serial_queue.dart';

export 'src/attribute_value.dart' show AttributeValue;
export 'src/invalid_targeting_key.dart' show InvalidTargetingKey;
export 'src/config.dart' show CoproductConfig;
export 'src/provider_state.dart' show ProviderState;
export 'src/flag_observation.dart' show FlagObservation;
export 'src/coproduct_flag_builder.dart' show CoproductFlagBuilder;
export 'src/errors.dart'
    show
        CoproductException,
        MissingSdkKey,
        InvalidKeyType,
        MalformedSdkKey,
        InvalidConfig,
        UnsupportedSchemaVersion,
        CoproductAlreadyInitialized,
        CoproductInitializationCancelled;

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
class CoproductClient {
  CoproductClient(this._handle);

  final frb.CoproductClientHandle _handle;
  final SerialQueue _identityQueue = SerialQueue();

  bool getBool(String key, bool defaultValue) =>
      frb.getBool(client: _handle, key: key, defaultValue: defaultValue);

  /// Reads a string flag, returning [defaultValue] if the flag is missing, the
  /// wrong type, or the SDK is not ready
  String getString(String key, String defaultValue) =>
      frb.getString(client: _handle, key: key, defaultValue: defaultValue);

  /// Reads an integer flag, returning [defaultValue] if the flag is missing, the
  /// wrong type, or the SDK is not ready. Integers travel as the numeric flag
  /// type, so a fractional value is truncated toward zero
  int getInt(String key, int defaultValue) =>
      frb.getInt(client: _handle, key: key, defaultValue: defaultValue);

  /// Reads a numeric flag, returning [defaultValue] if the flag is missing, the
  /// wrong type, or the SDK is not ready
  double getNumber(String key, double defaultValue) =>
      frb.getNumber(client: _handle, key: key, defaultValue: defaultValue);

  /// Reads a JSON flag as a native Dart value (map, list, scalar, or null).
  ///
  /// [defaultValue] must be JSON-encodable: null, a JSON scalar, a list of
  /// JSON-encodable values, or a string-keyed map of JSON-encodable values. If
  /// encoding or decoding fails, the supplied [defaultValue] is returned
  /// unchanged instead of throwing, matching the "reads do not throw" contract
  Object? getJson(String key, Object? defaultValue) {
    final String defaultValueJson;
    try {
      defaultValueJson = jsonEncode(defaultValue);
    } catch (_) {
      return defaultValue;
    }
    final resultJson = frb.getJson(
      client: _handle,
      key: key,
      defaultValueJson: defaultValueJson,
    );
    try {
      return jsonDecode(resultJson);
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
    final frbAttributes = toFrbAttributes(attributes);
    return _identityQueue.add(() => translateIdentityErrors(() => frb.identify(
          handle: _handle,
          userId: userId,
          attributes: frbAttributes,
          linkAnonymous: linkAnonymous,
        )));
  }

  /// Clears the identified user and reverts to the anonymous identity, clearing
  /// developer attributes. Awaiting settles the transition and the anonymous-id
  /// persistence attempt, not durable storage, since a write failure is logged and
  /// swallowed
  Future<void> signOut() =>
      _identityQueue.add(() => frb.signOut(handle: _handle));

  /// Replaces the targeting key and developer attributes of the current context,
  /// so an attribute not in [attributes] is cleared. Reserved keys `user_id` and
  /// `targetingKey` are ignored. Throws `InvalidTargetingKey` if [targetingKey]
  /// is empty
  Future<void> setContext({
    required String targetingKey,
    Map<String, AttributeValue> attributes = const {},
  }) {
    final frbAttributes = toFrbAttributes(attributes);
    return _identityQueue.add(
        () => translateIdentityErrors(() => frb.setContext(
              handle: _handle,
              targetingKey: targetingKey,
              attributes: frbAttributes,
            )));
  }

  /// Merges [attributes] into the current developer attributes, so omitted keys
  /// remain. Reserved keys `user_id` and `targetingKey` are ignored
  Future<void> updateAttributes(Map<String, AttributeValue> attributes) {
    final frbAttributes = toFrbAttributes(attributes);
    return _identityQueue.add(
        () => frb.updateAttributes(handle: _handle, attributes: frbAttributes));
  }

  /// Removes the named developer attributes, which may reveal a lower context
  /// layer's value for those keys
  Future<void> removeAttributes(List<String> keys) {
    final snapshot = snapshotKeys(keys);
    return _identityQueue.add(
        () => frb.removeAttributes(handle: _handle, names: snapshot));
  }

  /// The anonymous id captured to link a pre-login session, or null. A linked
  /// identify captures the current anonymous id only when no id is currently
  /// stored, so later linked identifies do not overwrite a stored value. signOut
  /// or an unlinked identify (linkAnonymous false) clears it, after which a later
  /// linked identify can capture it again. Read it after awaiting the identity
  /// mutation that should have changed it
  String? get previousAnonymousId => frb.previousAnonymousId(handle: _handle);

  /// The current provider lifecycle state. Never returns ProviderState.reconciling
  ProviderState get state => providerStateFromFrb(frb.state(client: _handle));

  /// Observes a boolean flag, returning a [FlagObservation] whose value is
  /// already seeded with what [getBool] would return right now.
  ///
  /// The observation updates when a poll, an identity change, or a context
  /// change alters this flag's value, and resolves to [defaultValue] whenever
  /// the flag is unavailable. The caller owns it: call
  /// [FlagObservation.dispose] when the owner goes away, or let
  /// [CoproductFlagBuilder] own one for you
  FlagObservation<bool> observeBool(String key, bool defaultValue) {
    final session = frb.observeBool(client: _handle, key: key);
    return boolObservation(
      defaultValue: defaultValue,
      seed: frb.observeBoolSeed(session: session),
      events: frb.observeBoolEvents(session: session),
      cancel: () => frb.cancelBoolObservation(session: session),
    );
  }

  /// Observes a string flag. See [observeBool] for ownership and update
  /// semantics
  FlagObservation<String> observeString(String key, String defaultValue) {
    final session = frb.observeString(client: _handle, key: key);
    return stringObservation(
      defaultValue: defaultValue,
      seed: frb.observeStringSeed(session: session),
      events: frb.observeStringEvents(session: session),
      cancel: () => frb.cancelStringObservation(session: session),
    );
  }

  /// Observes an integer flag. Integers travel as the numeric flag type, so a
  /// fractional value is truncated toward zero and a value outside the integer
  /// range is unavailable, matching [getInt]. See [observeBool] for ownership
  /// and update semantics
  FlagObservation<int> observeInt(String key, int defaultValue) {
    final session = frb.observeInt(client: _handle, key: key);
    return intObservation(
      defaultValue: defaultValue,
      seed: frb.observeIntSeed(session: session),
      events: frb.observeIntEvents(session: session),
      cancel: () => frb.cancelIntObservation(session: session),
    );
  }

  /// Observes a numeric flag. See [observeBool] for ownership and update
  /// semantics
  FlagObservation<double> observeNumber(String key, double defaultValue) {
    final session = frb.observeNumber(client: _handle, key: key);
    return numberObservation(
      defaultValue: defaultValue,
      seed: frb.observeNumberSeed(session: session),
      events: frb.observeNumberEvents(session: session),
      cancel: () => frb.cancelNumberObservation(session: session),
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
    final session = frb.observeJson(client: _handle, key: key);
    return jsonObservation(
      defaultValue: defaultValue,
      seed: frb.observeJsonSeed(session: session),
      events: frb.observeJsonEvents(session: session),
      cancel: () => frb.cancelJsonObservation(session: session),
    );
  }
}

/// The single process-wide runtime, initialized and shut down through the static
/// entry points. Reads and identity live on the returned [CoproductClient].
class Coproduct {
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
    createClient: CoproductClient.new,
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
