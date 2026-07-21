import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart'
    show ExternalLibrary;
import 'package:path_provider/path_provider.dart';

import 'src/rust/api.dart' as frb;
import 'src/rust/frb_generated.dart';

export 'src/rust/api.dart' show HttpRequest, HttpResponse, HttpHeader, HttpMethod;

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

class CoproductClient {
  CoproductClient(this._handle);

  final frb.CoproductClientHandle _handle;

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
