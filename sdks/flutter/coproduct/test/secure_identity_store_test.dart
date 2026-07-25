import 'dart:async';

import 'package:coproduct/src/secure_identity_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStore implements KeyValueStore {
  _FakeStore({this.gate, this.throwOnRead = false, this.throwOnWrite = false});
  final Map<String, String> values = {};
  // When set, read and write await this before completing, so a never-completing
  // gate exercises the timeout without a real wall-clock delay
  final Future<void>? gate;
  final bool throwOnRead;
  final bool throwOnWrite;

  @override
  Future<String?> read(String key) async {
    if (gate != null) await gate;
    if (throwOnRead) throw StateError('boom');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (gate != null) await gate;
    if (throwOnWrite) throw StateError('boom');
    values[key] = value;
  }
}

void main() {
  test('reads and writes through the backing store', () async {
    final backing = _FakeStore();
    final store = SecureIdentityStore(
        backing: backing, operationTimeout: const Duration(seconds: 1));
    await store.write('coproduct.anonymous_id', 'anon-1');
    expect(backing.values['coproduct.anonymous_id'], 'anon-1');
    expect(await store.read('coproduct.anonymous_id'), 'anon-1');
  });

  test('a read that outruns the timeout throws TimeoutException', () async {
    // The gate never completes, so only the timeout resolves the read, and the
    // core falls back to a session-only id
    final store = SecureIdentityStore(
        backing: _FakeStore(gate: Completer<void>().future),
        operationTimeout: const Duration(milliseconds: 20));
    await expectLater(store.read('k'), throwsA(isA<TimeoutException>()));
  });

  test('a failing read propagates as an error', () async {
    final store = SecureIdentityStore(
        backing: _FakeStore(throwOnRead: true),
        operationTimeout: const Duration(seconds: 1));
    await expectLater(store.read('k'), throwsA(isA<StateError>()));
  });

  test('a write that outruns the timeout throws TimeoutException', () async {
    // The core stops awaiting durability and proceeds session-only, though the
    // underlying platform write is not cancelled and may still land later
    final store = SecureIdentityStore(
        backing: _FakeStore(gate: Completer<void>().future),
        operationTimeout: const Duration(milliseconds: 20));
    await expectLater(store.write('k', 'v'), throwsA(isA<TimeoutException>()));
  });

  test('a failing write propagates as an error', () async {
    final store = SecureIdentityStore(
        backing: _FakeStore(throwOnWrite: true),
        operationTimeout: const Duration(seconds: 1));
    await expectLater(store.write('k', 'v'), throwsA(isA<StateError>()));
  });
}
