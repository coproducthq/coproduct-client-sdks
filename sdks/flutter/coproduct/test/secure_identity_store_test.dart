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

/// A store whose reads can be made to fail after it was written to
class _SwitchableStore implements KeyValueStore {
  final Map<String, String> values = {};
  bool throwOnRead = false;

  @override
  Future<String?> read(String key) async {
    if (throwOnRead) throw StateError('boom');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test('reads and writes through the backing store', () async {
    final backing = _FakeStore();
    final store = SecureIdentityStore(
      backing: backing,
      operationTimeout: const Duration(seconds: 1),
    );
    await store.write('coproduct.anonymous_id', 'anon-1');
    expect(backing.values['coproduct.anonymous_id'], 'anon-1');
    expect(await store.read('coproduct.anonymous_id'), 'anon-1');
  });

  test('a read that outruns the timeout throws TimeoutException', () async {
    // The gate never completes, so only the timeout resolves the read, and the
    // core falls back to a session-only id
    final store = SecureIdentityStore(
      backing: _FakeStore(gate: Completer<void>().future),
      operationTimeout: const Duration(milliseconds: 20),
    );
    await expectLater(store.read('k'), throwsA(isA<TimeoutException>()));
  });

  test('a failing read propagates as an error', () async {
    final store = SecureIdentityStore(
      backing: _FakeStore(throwOnRead: true),
      operationTimeout: const Duration(seconds: 1),
    );
    await expectLater(store.read('k'), throwsA(isA<StateError>()));
  });

  test('a write that outruns the timeout throws TimeoutException', () async {
    // The core stops awaiting durability and proceeds session-only, though the
    // underlying platform write is not cancelled and may still land later
    final store = SecureIdentityStore(
      backing: _FakeStore(gate: Completer<void>().future),
      operationTimeout: const Duration(milliseconds: 20),
    );
    await expectLater(store.write('k', 'v'), throwsA(isA<TimeoutException>()));
  });

  test('a failing write propagates as an error', () async {
    final store = SecureIdentityStore(
      backing: _FakeStore(throwOnWrite: true),
      operationTimeout: const Duration(seconds: 1),
    );
    await expectLater(store.write('k', 'v'), throwsA(isA<StateError>()));
  });

  group('anonymous id capture', () {
    test('is null until the key is read or written', () {
      final store = SecureIdentityStore(
        backing: _FakeStore(),
        operationTimeout: const Duration(seconds: 1),
      );
      expect(store.anonymousId, isNull);
    });

    test('is captured from a successful read', () async {
      final backing = _FakeStore()..values[anonymousIdStorageKey] = 'anon-1';
      final store = SecureIdentityStore(
        backing: backing,
        operationTimeout: const Duration(seconds: 1),
      );
      await store.read(anonymousIdStorageKey);
      expect(store.anonymousId, 'anon-1');
    });

    test(
      'a read that finds nothing, or an empty value, captures nothing',
      () async {
        final backing = _FakeStore();
        final store = SecureIdentityStore(
          backing: backing,
          operationTimeout: const Duration(seconds: 1),
        );
        await store.read(anonymousIdStorageKey);
        expect(store.anonymousId, isNull);
        // The core treats an empty stored value as absent and generates a new id
        backing.values[anonymousIdStorageKey] = '';
        await store.read(anonymousIdStorageKey);
        expect(store.anonymousId, isNull);
      },
    );

    test('is captured from a write', () async {
      final store = SecureIdentityStore(
        backing: _FakeStore(),
        operationTimeout: const Duration(seconds: 1),
      );
      await store.write(anonymousIdStorageKey, 'anon-2');
      expect(store.anonymousId, 'anon-2');
    });

    test('is captured from a write that fails', () async {
      // The core keeps using the id for the session even though it was not
      // persisted
      final store = SecureIdentityStore(
        backing: _FakeStore(throwOnWrite: true),
        operationTimeout: const Duration(seconds: 1),
      );
      await expectLater(
        store.write(anonymousIdStorageKey, 'anon-3'),
        throwsA(isA<StateError>()),
      );
      expect(store.anonymousId, 'anon-3');
    });

    test('is captured from a write that times out', () async {
      final store = SecureIdentityStore(
        backing: _FakeStore(gate: Completer<void>().future),
        operationTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        store.write(anonymousIdStorageKey, 'anon-4'),
        throwsA(isA<TimeoutException>()),
      );
      expect(store.anonymousId, 'anon-4');
    });

    test('a later write replaces a value captured from a read', () async {
      final backing = _FakeStore()..values[anonymousIdStorageKey] = 'stored';
      final store = SecureIdentityStore(
        backing: backing,
        operationTimeout: const Duration(seconds: 1),
      );
      await store.read(anonymousIdStorageKey);
      await store.write(anonymousIdStorageKey, 'override');
      expect(store.anonymousId, 'override');
    });

    test('a failing read clears an id captured earlier', () async {
      // The core then generates a session-only id it never passes through the
      // store, so the earlier id would be wrong
      final backing = _SwitchableStore();
      final store = SecureIdentityStore(
        backing: backing,
        operationTimeout: const Duration(seconds: 1),
      );
      await store.write(anonymousIdStorageKey, 'anon-5');
      backing.throwOnRead = true;
      await expectLater(
        store.read(anonymousIdStorageKey),
        throwsA(isA<StateError>()),
      );
      expect(store.anonymousId, isNull);
    });

    test('other keys are ignored', () async {
      final backing = _FakeStore()..values['other'] = 'x';
      final store = SecureIdentityStore(
        backing: backing,
        operationTimeout: const Duration(seconds: 1),
      );
      await store.read('other');
      await store.write('another', 'y');
      expect(store.anonymousId, isNull);
    });
  });
}
