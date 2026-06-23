import Foundation

public enum Coproduct {
    // Future public initializer shape once host Transport / SecureStore
    // protocols are exposed by the Swift wrapper.
    //
    // public static func initialize(
    //     sdkKey: String,
    //     transport: HostTransport,
    //     secureStore: HostSecureStore
    // ) async throws -> CoproductClient { ... }

    public static func initialize(sdkKey: String) async throws -> CoproductClient {
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .path

        return try await initializeFfiClient(
            sdkKey: sdkKey,
            cacheDir: cacheDir,
            transport: MockTransport(),
            secureStore: MockSecureStore()
        )
    }

    // Internal bucketing accessor exposed for cross-platform parity
    // verification. Customer-facing bucket access, if added, belongs on
    // FlagEvaluationDetails.
    public static func computeBucket(
        ruleId: String,
        targetingKey: String,
        suffix: String
    ) -> UInt32 {
        ffiComputeBucket(ruleId: ruleId, targetingKey: targetingKey, suffix: suffix)
    }
}

private func initializeFfiClient(
    sdkKey: String,
    cacheDir: String,
    transport: HostTransport,
    secureStore: HostSecureStore
) async throws -> CoproductClient {
    try await initialize(
        sdkKey: sdkKey,
        cacheDir: cacheDir,
        transport: transport,
        secureStore: secureStore
    )
}

private func ffiComputeBucket(
    ruleId: String,
    targetingKey: String,
    suffix: String
) -> UInt32 {
    computeBucket(ruleId: ruleId, targetingKey: targetingKey, suffix: suffix)
}

public protocol Cancellable: Sendable {
    func cancel()
}

public extension CoproductClient {
    func getBool(_ key: String, default defaultValue: Bool) -> Bool {
        getBool(key: key, defaultValue: defaultValue)
    }

    // Low-level observer primitive returning a cancellation handle. Higher-level
    // Swift bindings can layer on top of this cancellation primitive.
    func observe(
        _ key: String,
        default _: Bool,
        _ handler: @escaping @Sendable (Bool) -> Void
    ) -> Cancellable {
        let observer = ClosureFlagObserver(handler: handler)
        let subscription = observeKey(key: key, observer: observer)
        return CoproductSubscription(subscription: subscription, observer: observer)
    }
}

// Validation transport used by the current convenience initializer. The public
// initializer shape above shows where host transport injection will connect.
public final class MockTransport: HostTransport, @unchecked Sendable {
    nonisolated(unsafe) public private(set) static var requestCount = 0

    public init() {}

    public func request(req _: HttpRequest) async throws -> HttpResponse {
        Self.requestCount += 1
        return HttpResponse(status: 200, body: Data(), headers: [])
    }
}

// Validation secure store used by the current convenience initializer.
public final class MockSecureStore: HostSecureStore, @unchecked Sendable {
    nonisolated(unsafe) public private(set) static var readCount = 0
    nonisolated(unsafe) public private(set) static var writeCount = 0
    nonisolated(unsafe) private static var values: [String: String] = [:]

    public static var completedHandshake: Bool {
        readCount >= 1 && writeCount >= 1
    }

    public init() {}

    public func read(key: String) async throws -> String? {
        Self.readCount += 1
        return Self.values[key]
    }

    public func write(key: String, value: String) async throws {
        Self.writeCount += 1
        Self.values[key] = value
    }
}

private final class ClosureFlagObserver: FlagObserver, @unchecked Sendable {
    private let handler: @Sendable (Bool) -> Void

    init(handler: @escaping @Sendable (Bool) -> Void) {
        self.handler = handler
    }

    func onChange(key _: String, value: FlagValue) async throws {
        // The convenience boolean observer reports only boolean changes. Other
        // typed values are ignored by this low-level hook.
        if case let .bool(value) = value {
            handler(value)
        }
    }
}

private final class CoproductSubscription: Cancellable, @unchecked Sendable {
    private let lock = NSLock()
    private var subscription: Subscription?
    private let observer: ClosureFlagObserver

    init(subscription: Subscription, observer: ClosureFlagObserver) {
        self.subscription = subscription
        self.observer = observer
    }

    func cancel() {
        // Idempotent: dropping the inner Subscription reference releases the
        // UniFFI handle. Repeated cancel() calls are no-ops.
        lock.lock()
        subscription = nil
        lock.unlock()
    }

    deinit {
        // No lock needed: deinit runs after the last strong reference is gone.
        subscription = nil
    }
}
