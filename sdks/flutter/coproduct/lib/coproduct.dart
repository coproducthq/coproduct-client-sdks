import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart'
    show ExternalLibrary;
import 'package:path_provider/path_provider.dart';

import 'src/attribute_value.dart';
import 'src/identity_error_translation.dart';
import 'src/rust/api.dart' as frb;
import 'src/rust/frb_generated.dart';
import 'src/serial_queue.dart';

export 'src/rust/api.dart' show HttpRequest, HttpResponse, HttpHeader, HttpMethod;
export 'src/attribute_value.dart' show AttributeValue;
export 'src/invalid_targeting_key.dart' show InvalidTargetingKey;

/// Validation transport. Counts calls so demos can prove Rust invoked the
/// Dart-hosted capability. Returns a 200 with an empty JSON body.
///
/// The public initializer shape below shows where host transport injection will
/// connect.
class MockTransport {
  int requestCount = 0;

  bool get completedHandshake => requestCount > 0;

  void reset() {
    requestCount = 0;
  }

  Future<frb.HttpResponse> request(frb.HttpRequest req) async {
    requestCount += 1;
    return frb.HttpResponse(
      status: 200,
      body: Uint8List.fromList(utf8.encode('{}')),
      headers: const [frb.HttpHeader(name: 'content-type', value: 'application/json')],
    );
  }
}

/// Validation secure store. Identity-only: write then read back, no delete.
class MockSecureStore {
  int readCount = 0;
  int writeCount = 0;
  final Map<String, String> _values = {};

  // The core's cold-start identity sequence reads the stored anonymous id and
  // writes one when none exists, so a completed round trip means the secure
  // store host bridge was exercised during initialize
  bool get completedHandshake => writeCount > 0 && readCount > 0;

  void reset() {
    readCount = 0;
    writeCount = 0;
    _values.clear();
  }

  Future<String?> read(String key) async {
    readCount += 1;
    return _values[key];
  }

  Future<void> write(String key, String value) async {
    writeCount += 1;
    _values[key] = value;
  }
}

final mockTransport = MockTransport();
final mockSecureStore = MockSecureStore();

/// Handle to a live observer registration.
class Cancellable {
  Cancellable(this._subscription);

  // Held so the Rust-side subscription is not dropped while observing.
  // ignore: unused_field
  final frb.SubscriptionHandle _subscription;
}

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

  /// Low-level observer hook used by current demos.
  Future<Cancellable> observe(
    String key,
    bool defaultValue,
    void Function(bool value) handler,
  ) async {
    final subscription = await frb.observe(
      client: _handle,
      key: key,
      onChange: (value) => handler(value),
    );
    return Cancellable(subscription);
  }
}

class Coproduct {
  static bool _rustInitialized = false;

  // Future public initializer shape once host Transport / SecureStore
  // interfaces are exposed by the Flutter wrapper.
  //
  // static Future<CoproductClient> initialize({
  //   required String sdkKey,
  //   required Transport transport,
  //   required SecureStore secureStore,
  // }) async { ... }

  static Future<CoproductClient> initialize({required String sdkKey}) async {
    // Reset validation mocks so a hot-restart or repeated initialize re-runs the
    // handshake from a clean slate. The integration test asserts requestCount
    // is exactly 1 after initialize returns, which would fail without this.
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
    final handle = await frb.initialize(
      sdkKey: sdkKey,
      cacheDir: cacheDir,
      transportRequest: mockTransport.request,
      secureRead: mockSecureStore.read,
      secureWrite: mockSecureStore.write,
    );
    return CoproductClient(handle);
  }
}
