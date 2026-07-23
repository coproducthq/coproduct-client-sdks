import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart'
    show ExternalLibrary;
import 'package:path_provider/path_provider.dart';

import 'src/attribute_value.dart';
import 'src/config.dart';
import 'src/errors.dart';
import 'src/identity_error_translation.dart';
import 'src/mock_host.dart';
import 'src/provider_state.dart';
import 'src/rust/api.dart' as frb;
import 'src/rust/frb_generated.dart';
import 'src/sdk_version.dart';
import 'src/serial_queue.dart';

export 'src/attribute_value.dart' show AttributeValue;
export 'src/invalid_targeting_key.dart' show InvalidTargetingKey;
export 'src/config.dart' show CoproductConfig;
export 'src/provider_state.dart' show ProviderState;
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
}

class Coproduct {
  static bool _rustInitialized = false;

  static Future<CoproductClient> initialize({
    required String sdkKey,
    CoproductConfig config = const CoproductConfig(),
  }) async {
    final validated = validateConfig(config);
    // Reset the validation mocks so a hot-restart or repeated initialize re-runs
    // the cold-start handshake from a clean slate. initialize does not poll, so
    // the secure-store reset is what matters, for the identity read and write
    mockTransport.reset();
    mockSecureStore.reset();

    if (!_rustInitialized) {
      if (Platform.isIOS || Platform.isMacOS) {
        // cargokit force-loads the Rust static library into the app executable,
        // so the symbols live in the process, not a <stem>.framework bundle that
        // FRB's default Apple loader looks for.
        await RustLib.init(
          externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
        );
      } else {
        await RustLib.init();
      }
      _rustInitialized = true;
    }
    // The Rust core reads and writes {cacheDir}/coproduct/snapshot.json itself.
    final cacheDir = (await getApplicationCacheDirectory()).path;
    final frb.CoproductClientHandle handle;
    try {
      handle = await frb.initialize(
        sdkKey: sdkKey,
        userAgent: coproductUserAgent,
        config: frb.FfiConfig(
          pollIntervalUs: validated.pollInterval.inMicroseconds,
          startupTimeoutUs: validated.startupTimeout.inMicroseconds,
          endpoint: validated.endpoint?.toString(),
        ),
        cacheDir: cacheDir,
        transportRequest: mockTransport.request,
        secureRead: mockSecureStore.read,
        secureWrite: mockSecureStore.write,
      );
    } on frb.InitError catch (error) {
      throw translateInitError(error);
    }
    return CoproductClient(handle);
  }
}
