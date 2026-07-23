import 'dart:convert';
import 'dart:typed_data';

import 'rust/api.dart' as frb;

// Internal validation transport and secure store used by the scaffold runtime
// kept under lib/src so no generated FRB type appears in the public API

/// Validation transport. Counts calls so tests can prove Rust invoked the
/// Dart-hosted capability. Returns a 200 with an empty JSON body
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
