import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart'
    show ExternalLibrary;
import 'package:path_provider/path_provider.dart';

import 'src/rust/api.dart' as frb;
import 'src/rust/frb_generated.dart';

export 'src/rust/api.dart' show HttpRequest, HttpResponse, HttpHeader, HttpMethod;

/// Scaffold mock Transport. Counts calls so the demo can prove Rust invoked
/// the Dart-hosted capability. Returns a stub 200 with an empty JSON body.
///
/// SCAFFOLD-ONLY: replaced by real Transport wiring in M1.
/// M1 door: Coproduct.initialize(sdkKey: ..., transport: ..., secureStore: ...) overload.
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

/// Scaffold mock SecureStore. Identity-only: write then read back, no delete.
///
/// SCAFFOLD-ONLY: replaced by real SecureStore wiring in M1.
class MockSecureStore {
  int readCount = 0;
  int writeCount = 0;
  final Map<String, String> _values = {};

  bool get completedHandshake =>
      writeCount > 0 && readCount > 0 && _values['scaffold-handshake-id'] == 'ok';

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

/// Handle to a live observer registration. M1 makes this a real cancellation.
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

  bool wasLoadedFromCache() => frb.wasLoadedFromCache(client: _handle);

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

  Future<void> simulateChange(String key, bool newValue) =>
      frb.simulateChange(client: _handle, key: key, newValue: newValue);
}

class Coproduct {
  static bool _rustInitialized = false;

  // M1 door (commented out so the scaffold still compiles against the mocks).
  // M1 fills in the real Transport / SecureStore interfaces and removes the
  // single-arg overload below in favor of this one.
  //
  // static Future<CoproductClient> initialize({
  //   required String sdkKey,
  //   required Transport transport,
  //   required SecureStore secureStore,
  // }) async { ... }

  static Future<CoproductClient> initialize({required String sdkKey}) async {
    // Reset scaffold mocks so a hot-restart or repeated initialize re-runs the
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

  static int computeBucket({
    required String ruleId,
    required String targetingKey,
    required String suffix,
  }) => frb.computeBucket(
        ruleId: ruleId,
        targetingKey: targetingKey,
        suffix: suffix,
      );
}
