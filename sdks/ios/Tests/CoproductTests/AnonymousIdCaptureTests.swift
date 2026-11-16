import XCTest
@testable import Coproduct

// The core exposes no getter for the anonymous id, so the SDK learns it by
// watching the secure store the core reads and writes it through
final class AnonymousIdCaptureTests: XCTestCase {
    // An isolated in-memory store whose writes can be made to fail.
    // TestSecureStore shares one static dictionary across the process, which
    // would leak an id between these tests
    private final class ScriptedStore: HostSecureStore, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String]
        private let failWrites: Bool

        init(values: [String: String] = [:], failWrites: Bool = false) {
            self.values = values
            self.failWrites = failWrites
        }

        private func get(_ key: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return values[key]
        }

        private func set(_ key: String, _ value: String) {
            lock.lock()
            defer { lock.unlock() }
            values[key] = value
        }

        func read(key: String) async throws -> String? { get(key) }

        func write(key: String, value: String) async throws {
            if failWrites { throw SecureStoreError.WriteFailed }
            set(key, value)
        }
    }

    func testNilUntilTheCoreTouchesTheKey() {
        XCTAssertNil(AnonymousIdCapturingSecureStore(inner: ScriptedStore()).anonymousId)
    }

    func testCapturesFromAStoreRead() async throws {
        let store = AnonymousIdCapturingSecureStore(inner: ScriptedStore(values: [anonymousIdStorageKey: "anon-read"]))
        let value = try await store.read(key: anonymousIdStorageKey)
        XCTAssertEqual(value, "anon-read")
        XCTAssertEqual(store.anonymousId, "anon-read")
    }

    func testCapturesFromAStoreWrite() async throws {
        let inner = ScriptedStore()
        let store = AnonymousIdCapturingSecureStore(inner: inner)
        try await store.write(key: anonymousIdStorageKey, value: "anon-written")
        XCTAssertEqual(store.anonymousId, "anon-written")
        // The write still reaches the wrapped store
        let persisted = try await inner.read(key: anonymousIdStorageKey)
        XCTAssertEqual(persisted, "anon-written")
    }

    func testCapturesFromAFailingWrite() async {
        let store = AnonymousIdCapturingSecureStore(inner: ScriptedStore(failWrites: true))
        do {
            try await store.write(key: anonymousIdStorageKey, value: "anon-session")
            XCTFail("expected the wrapped store's failure to propagate")
        } catch {}
        // The core keeps using the id for the session even though it was not
        // persisted, so the accessor must report it
        XCTAssertEqual(store.anonymousId, "anon-session")
    }

    func testALaterWriteReplacesAnEarlierRead() async throws {
        let store = AnonymousIdCapturingSecureStore(inner: ScriptedStore(values: [anonymousIdStorageKey: "anon-old"]))
        _ = try await store.read(key: anonymousIdStorageKey)
        try await store.write(key: anonymousIdStorageKey, value: "anon-override")
        XCTAssertEqual(store.anonymousId, "anon-override")
    }

    func testIgnoresOtherKeysAndEmptyReads() async throws {
        let store = AnonymousIdCapturingSecureStore(
            inner: ScriptedStore(values: [anonymousIdStorageKey: "", "other": "value"])
        )
        _ = try await store.read(key: "other")
        try await store.write(key: "other", value: "value-2")
        // The core treats an empty stored id as missing and generates a new one
        _ = try await store.read(key: anonymousIdStorageKey)
        XCTAssertNil(store.anonymousId)
    }
}
