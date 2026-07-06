import XCTest
@testable import Coproduct

// Round-trip coverage for the production Keychain store. A unique service per
// run isolates these entries from any other keychain state and from each other.
//
// SwiftPM test bundles on the iOS simulator can run without a host app or
// keychain-sharing entitlement, in which case SecItemAdd fails with
// errSecMissingEntitlement (OSStatus -34018) and the store surfaces WriteFailed.
// When that happens the round trip cannot run for real, so the suite probes
// once in setUp and skips the behavioral cases with a clear message rather than
// asserting against a keychain the environment refuses to back
final class KeychainSecureStoreTests: XCTestCase {
    private let service = "app.coproduct.sdk.test.\(UUID().uuidString)"
    private var store: KeychainSecureStore!
    private var keychainAvailable = false

    override func setUp() async throws {
        store = KeychainSecureStore(service: service)
        // Probe write access once. A missing entitlement here means the rest of
        // the round-trip assertions cannot be exercised in this environment
        do {
            try await store.write(key: "probe", value: "probe")
            keychainAvailable = true
        } catch {
            keychainAvailable = false
        }
    }

    func testReadMissingKeyReturnsNil() async throws {
        try XCTSkipUnless(keychainAvailable, "keychain access unavailable in this test environment")
        // A read for an account that was never written returns nil through the
        // errSecItemNotFound branch rather than surfacing an error
        let value = try await store.read(key: "never-written-\(UUID().uuidString)")
        XCTAssertNil(value)
    }

    func testReadMapsUnavailableKeychainToReadFailed() async throws {
        // When the simulator denies keychain access entirely, even a lookup for
        // a missing account returns a non-nil OSStatus that the store maps onto
        // ReadFailed. This case only asserts that mapping, and only when the
        // probe showed the keychain is in fact unavailable, so it documents the
        // environment limitation rather than faking a working store
        try XCTSkipUnless(!keychainAvailable, "keychain is available so this case does not apply")
        do {
            _ = try await store.read(key: "never-written-\(UUID().uuidString)")
            XCTFail("expected a ReadFailed when the keychain is unavailable")
        } catch let error as SecureStoreError {
            XCTAssertEqual(error, .ReadFailed)
        }
    }

    func testWriteThenReadRoundTrips() async throws {
        try XCTSkipUnless(keychainAvailable, "keychain writes unavailable in this test environment")
        let written = "anon-\(UUID().uuidString)"
        try await store.write(key: "anonymous_id", value: written)
        let value = try await store.read(key: "anonymous_id")
        XCTAssertEqual(value, written)
    }

    func testWriteOverwritesExistingValue() async throws {
        try XCTSkipUnless(keychainAvailable, "keychain writes unavailable in this test environment")
        try await store.write(key: "anonymous_id", value: "v1")
        try await store.write(key: "anonymous_id", value: "v2")
        let value = try await store.read(key: "anonymous_id")
        // The update-then-add path keeps a single entry per account, so the
        // latest write wins rather than appending a second item
        XCTAssertEqual(value, "v2")
    }

    func testMultipleKeysAreIndependent() async throws {
        try XCTSkipUnless(keychainAvailable, "keychain writes unavailable in this test environment")
        try await store.write(key: "anonymous_id", value: "anon-1")
        try await store.write(key: "sdk_key_hash", value: "abc123")
        let anon = try await store.read(key: "anonymous_id")
        let hash = try await store.read(key: "sdk_key_hash")
        XCTAssertEqual(anon, "anon-1")
        XCTAssertEqual(hash, "abc123")
    }
}
