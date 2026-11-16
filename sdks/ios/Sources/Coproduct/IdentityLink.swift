import CoproductFFI
import Foundation

// The secure-store key the Rust core persists the anonymous id under. The core
// owns this string (ANONYMOUS_ID_STORAGE_KEY in identity.rs) and every SDK
// shares it, so it is deliberately not namespaced per platform
let anonymousIdStorageKey = "coproduct.anonymous_id"

/// Wraps the host secure store handed to the core and remembers the anonymous
/// id as it passes through. The core exposes no getter for the id, but every
/// read and write of it goes through this store: an existing id arrives as a
/// read result, and a generated or overridden id arrives as a write. A write is
/// remembered even when the wrapped store then fails, because the core keeps
/// using that id for the session
final class AnonymousIdCapturingSecureStore: HostSecureStore, @unchecked Sendable {
    private let inner: any HostSecureStore
    private let lock = NSLock()
    private var captured: String?

    init(inner: any HostSecureStore) {
        self.inner = inner
    }

    /// The last anonymous id read from or written to the store, or nil if the
    /// core has not touched the key yet
    var anonymousId: String? {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    // Synchronous so the lock is never taken inside an async body
    private func capture(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        captured = value
    }

    func read(key: String) async throws -> String? {
        let value = try await inner.read(key: key)
        // The core treats an empty stored id as missing and generates a fresh
        // one, which then arrives through write
        if key == anonymousIdStorageKey, let value, !value.isEmpty {
            capture(value)
        }
        return value
    }

    func write(key: String, value: String) async throws {
        if key == anonymousIdStorageKey {
            capture(value)
        }
        try await inner.write(key: key, value: value)
    }
}

/// Tells the server which app user id an install's anonymous id belongs to, so
/// purchases and entitlements recorded against the anonymous id follow the
/// signed-in user. Best-effort: a failure is logged and never reaches the
/// caller of identify
final class IdentityLinker: @unchecked Sendable {
    private let client: any PaywallClient
    private let anonymousId: @Sendable () -> String?

    // The pair most recently sent, kept for the life of the process so a repeat
    // identify of the same user does not post again, including across a
    // shutdown and re-initialize
    private static var _lastLinked: (anonymousId: String, userId: String)?
    private static let lock = NSLock()

    // Test seam consulted at initialize: when set, the link request goes
    // through this session instead of URLSession.shared. Lock-guarded for the
    // same reason as NetworkMonitor.sourceOverrideForTesting
    private static var _sessionOverrideForTesting: URLSession?

    static var sessionOverrideForTesting: URLSession? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _sessionOverrideForTesting
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _sessionOverrideForTesting = newValue
        }
    }

    init(client: any PaywallClient, anonymousId: @escaping @Sendable () -> String?) {
        self.client = client
        self.anonymousId = anonymousId
    }

    // Claims the pair for sending. Returns false when it is the pair already sent
    private static func claim(anonymousId: String, userId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let last = _lastLinked, last.anonymousId == anonymousId, last.userId == userId {
            return false
        }
        _lastLinked = (anonymousId, userId)
        return true
    }

    // Forgets a pair whose request failed so a later identify can try again
    private static func release(anonymousId: String, userId: String) {
        lock.lock()
        defer { lock.unlock() }
        if let last = _lastLinked, last.anonymousId == anonymousId, last.userId == userId {
            _lastLinked = nil
        }
    }

    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        _lastLinked = nil
    }

    /// Posts the anonymous id and `userId` to `/v1/identify` on a detached task.
    /// Skipped when `linkAnonymous` is false, when the anonymous id is unknown
    /// or equal to `userId`, and when this pair was the last one sent. Returns
    /// the task so a test can await it, or nil when nothing was sent
    @discardableResult
    func link(userId: String, linkAnonymous: Bool) -> Task<Void, Never>? {
        guard linkAnonymous, let anonymousId = anonymousId(), anonymousId != userId else { return nil }
        guard Self.claim(anonymousId: anonymousId, userId: userId) else { return nil }
        return Task.detached { [client] in
            do {
                try await client.identify(appUserId: anonymousId, targetingKey: userId)
            } catch {
                Self.release(anonymousId: anonymousId, userId: userId)
                NSLog("[Coproduct] identify could not link the anonymous id on the server: \(error)")
            }
        }
    }
}
