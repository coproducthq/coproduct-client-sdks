import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A minimal key-value backing the identity store reads and writes. Injected so
/// tests substitute an in-memory store for the platform secure storage
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Backs [KeyValueStore] with flutter_secure_storage (Keychain on Apple,
/// encrypted storage on Android)
class FlutterSecureKeyValueStore implements KeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                  accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Persists the anonymous id for the core, bounding each operation so a hung
/// platform channel cannot block initialization. The bound is a timeout on the
/// await, not a cancellation, the underlying platform operation is not aborted
/// and may still complete later. A read that times out or fails throws, so the
/// core stops awaiting and generates a session-only id. A write that times out or
/// fails throws, so the core stops awaiting durability and proceeds session-only,
/// though a late platform write may still land. The core supplies its own global
/// storage key, passed through
class SecureIdentityStore {
  SecureIdentityStore({
    KeyValueStore? backing,
    required this.operationTimeout,
  }) : _backing = backing ?? FlutterSecureKeyValueStore();

  final KeyValueStore _backing;
  final Duration operationTimeout;

  Future<String?> read(String key) =>
      _backing.read(key).timeout(operationTimeout);

  Future<void> write(String key, String value) =>
      _backing.write(key, value).timeout(operationTimeout);
}
