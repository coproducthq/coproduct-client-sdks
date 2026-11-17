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
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// The key the core stores the anonymous id under, matching
/// `ANONYMOUS_ID_STORAGE_KEY` in coproduct-core
const String anonymousIdStorageKey = 'coproduct.anonymous_id';

/// Persists the anonymous id for the core, bounding each operation so a hung
/// platform channel cannot block initialization. The bound is a timeout on the
/// await, not a cancellation, the underlying platform operation is not aborted
/// and may still complete later. A read that times out or fails throws, so the
/// core stops awaiting and generates a session-only id. A write that times out or
/// fails throws, so the core stops awaiting durability and proceeds session-only,
/// though a late platform write may still land. The core supplies its own global
/// storage key, passed through.
///
/// The core has no getter for the anonymous id, so the store remembers the
/// last one that passed through it, see [anonymousId]
class SecureIdentityStore {
  SecureIdentityStore({KeyValueStore? backing, required this.operationTimeout})
    : _backing = backing ?? FlutterSecureKeyValueStore();

  final KeyValueStore _backing;
  final Duration operationTimeout;

  String? _anonymousId;

  /// The anonymous id the core is using, or null while it is not known.
  ///
  /// It is the last value read or written under [anonymousIdStorageKey]. A
  /// value the core asks to write counts even when the write then fails or
  /// times out, because the core keeps using it for the session. A read that
  /// fails clears it: the core then generates an id it never passes through
  /// this store, so the id of an earlier run would be wrong
  String? get anonymousId => _anonymousId;

  Future<String?> read(String key) async {
    final String? value;
    try {
      value = await _backing.read(key).timeout(operationTimeout);
    } catch (_) {
      if (key == anonymousIdStorageKey) _anonymousId = null;
      rethrow;
    }
    // The core treats an empty value as absent and writes a fresh id next
    if (key == anonymousIdStorageKey && value != null && value.isNotEmpty) {
      _anonymousId = value;
    }
    return value;
  }

  Future<void> write(String key, String value) {
    // Recorded before the write is attempted, so a failed or timed-out write
    // still leaves the id the core goes on using
    if (key == anonymousIdStorageKey) _anonymousId = value;
    return _backing.write(key, value).timeout(operationTimeout);
  }
}
