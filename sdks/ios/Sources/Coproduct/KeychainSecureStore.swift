import CoproductFFI
import Foundation
import Security

/// Production SecureStore backed by the iOS Keychain so identity tokens survive
/// app restarts and stay outside the snapshot cache. Keychain failures map onto
/// the SecureStoreError categories without an attached message
public final class KeychainSecureStore: HostSecureStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "app.coproduct.sdk") {
        self.service = service
    }

    public func read(key: String) async throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        // A missing item is an empty identity, not an error the core should see
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecureStoreError.ReadFailed
        }
        guard let data = item as? Data else {
            throw SecureStoreError.ReadFailed
        }
        // A stored value that is not utf8 means the keychain entry is unusable
        guard let value = String(data: data, encoding: .utf8) else {
            throw SecureStoreError.Corrupted
        }
        return value
    }

    public func write(key: String, value: String) async throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        // Update first so an existing entry keeps its accessibility attributes
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw SecureStoreError.WriteFailed
        }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        // After first unlock keeps the token readable for background refresh
        // while still protecting it before the device is first unlocked
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureStoreError.WriteFailed
        }
    }
}
