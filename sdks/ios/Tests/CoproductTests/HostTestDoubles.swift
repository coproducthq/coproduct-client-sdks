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
// Removes the SessionStore keys an end-to-end initialize writes into the real
// standard defaults, so repeated runs on one simulator do not accumulate
// session counts or freeze the first-seen time across test runs
func clearCoproductSessionDefaults() {
    UserDefaults.standard.removeObject(forKey: SessionStore.firstSeenKey)
    UserDefaults.standard.removeObject(forKey: SessionStore.sessionCountKey)
}

// Deterministic path source shared by the monitor unit tests and the
// end-to-end initialize tests: records lifecycle and lets a test emit
// connectivity facts on demand
final class FakePathSource: NetworkPathSource, @unchecked Sendable {
    private(set) var started = false
    private(set) var cancelled = false
    private var onUpdate: ((NetworkPathFacts) -> Void)?

    func start(onUpdate: @escaping (NetworkPathFacts) -> Void) {
        started = true
        self.onUpdate = onUpdate
    }

    func cancel() { cancelled = true }

    func emit(satisfied: Bool, wifi: Bool = false, cellular: Bool = false, ethernet: Bool = false) {
        onUpdate?(NetworkPathFacts(satisfied: satisfied, wifi: wifi, cellular: cellular, ethernet: ethernet))
    }
}

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
