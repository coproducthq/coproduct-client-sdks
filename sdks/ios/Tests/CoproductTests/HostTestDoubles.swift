import Foundation
@testable import Coproduct

// Removes the on-disk snapshot cache the SDK shares across a test process. The
// core now sets its initial provider state from this cache, so a snapshot left
// by an earlier test would leak into a later one. Call this in setUp before any
// initialize whose starting state or first-poll behavior is asserted
func clearCoproductSnapshotCache() {
    guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        return
    }
    // The cache is scoped per sdk key under coproduct/<key-scope>/, so remove the
    // whole coproduct directory to reset every key's cache between tests
    let root = caches.appendingPathComponent("coproduct")
    try? FileManager.default.removeItem(at: root)
}

// Shared test doubles for the host protocols. These keep initialize off the
// network and off the real Keychain without shipping controllable hosts in the
// SDK source. The default hosts (URLSessionTransport, KeychainSecureStore)
// remain the only ones the SDK exports
final class TestTransport: HostTransport, @unchecked Sendable {
    func request(req _: HttpRequest) async throws -> HttpResponse {
        HttpResponse(status: 200, body: Data(), headers: [])
    }
}

final class TestSecureStore: HostSecureStore, @unchecked Sendable {
    nonisolated(unsafe) private static var values: [String: String] = [:]
    private static let lock = NSLock()

    // Synchronous accessors so the lock is never taken inside an async body,
    // which Swift 6 language mode rejects
    private static func get(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    private static func set(_ key: String, _ value: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func read(key: String) async throws -> String? {
        Self.get(key)
    }

    func write(key: String, value: String) async throws {
        Self.set(key, value)
    }
}
