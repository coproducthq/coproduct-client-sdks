import Combine
import CoproductFFI
import Foundation

/// The Coproduct SDK. Every entry point is static: initialize once, then read
/// flags, identify users, and observe changes through this type.
public enum Coproduct {
    // MARK: - Initialize

    /// Initialize the SDK with the default configuration.
    ///
    /// Returns once the client is built from cache and the first poll has either
    /// made the provider ready or `startupTimeout` has elapsed, whichever comes
    /// first. Polling then continues in the background, and reads serve cached
    /// values or the supplied defaults until the provider is ready.
    ///
    /// Calling this a second time returns the existing instance, even with a
    /// different sdk key (a warning is logged); call ``shutdown()`` first to
    /// switch environments.
    ///
    /// - Throws: ``CoproductError`` for every launch failure: an out-of-range or
    ///   unrepresentable config value, a missing or malformed sdk key, an
    ///   unsupported snapshot schema, or a shutdown that races startup. A slow or
    ///   unreachable first poll does not throw.
    public static func initialize(sdkKey: String) async throws {
        _ = try await Instances.shared.initialize(sdkKey: sdkKey, config: CoproductConfig())
    }

    /// Initialize the SDK with a custom ``CoproductConfig``. See
    /// ``initialize(sdkKey:)`` for the readiness and error contract.
    public static func initialize(sdkKey: String, config: CoproductConfig) async throws {
        _ = try await Instances.shared.initialize(sdkKey: sdkKey, config: config)
    }

    // MARK: - Identity

    /// Identify the current user, optionally attaching targeting attributes.
    ///
    /// Fire-and-forget: it returns immediately and is applied in the background
    /// in call order. A failure is logged, not thrown. Called before
    /// ``initialize(sdkKey:)`` it logs and does nothing.
    ///
    /// - Parameters:
    ///   - userId: A stable identifier for the user.
    ///   - attributes: Targeting attributes to attach. Defaults to none.
    ///   - linkAnonymous: Carry the pre-identify anonymous identity forward.
    ///     Defaults to `true`.
    public static func identify(
        userId: String,
        attributes: [String: AttributeValue] = [:],
        linkAnonymous: Bool = true
    ) {
        guard let client = Instances.shared.defaultInstance() else {
            logIdentityBeforeInitialize("identify")
            return
        }
        client.identify(userId: userId, attributes: attributes, linkAnonymous: linkAnonymous)
    }

    /// Clear the identified user and return to an anonymous identity.
    /// Fire-and-forget; a call before initialize logs and does nothing.
    public static func signOut() {
        guard let client = Instances.shared.defaultInstance() else {
            logIdentityBeforeInitialize("signOut")
            return
        }
        client.signOut()
    }

    /// Merge targeting attributes into the current context.
    /// Fire-and-forget; a call before initialize logs and does nothing.
    public static func updateAttributes(_ attributes: [String: AttributeValue]) {
        guard let client = Instances.shared.defaultInstance() else {
            logIdentityBeforeInitialize("updateAttributes")
            return
        }
        client.updateAttributes(attributes: attributes)
    }

    /// Remove targeting attributes by key from the current context.
    /// Fire-and-forget; a call before initialize logs and does nothing.
    public static func removeAttributes(_ keys: [String]) {
        guard let client = Instances.shared.defaultInstance() else {
            logIdentityBeforeInitialize("removeAttributes")
            return
        }
        client.removeAttributes(keys: keys)
    }

    /// Replace the targeting key and attributes for the current context.
    /// Fire-and-forget; a call before initialize logs and does nothing.
    public static func setContext(targetingKey: String, attributes: [String: AttributeValue] = [:]) {
        guard let client = Instances.shared.defaultInstance() else {
            logIdentityBeforeInitialize("setContext")
            return
        }
        client.setContext(targetingKey: targetingKey, attributes: attributes)
    }

    /// The anonymous id from before the most recent identify, or `nil` if there
    /// is none, including before initialize.
    public static var previousAnonymousId: String? {
        Instances.shared.defaultInstance().flatMap { $0.previousAnonymousId() }
    }

    // The identity calls are fire-and-forget, so a call before initialize logs
    // and no-ops rather than trapping, matching the graceful reads. observe and
    // handler registration still require initialize because they return a live
    // handle the caller uses
    private static func logIdentityBeforeInitialize(_ method: String) {
        NSLog("[Coproduct] \(method) called before initialize; ignoring")
    }

    // MARK: - Evaluation getters

    // Reads never throw or trap. Before initialize, or when the SDK is not ready,
    // they return the supplied default, so a flag read never crashes the app

    /// Evaluate a boolean flag, returning `defaultValue` if the flag is missing,
    /// the wrong type, or the SDK is not ready.
    public static func getBool(_ key: String, default defaultValue: Bool) -> Bool {
        Instances.shared.defaultInstance()?.getBool(key: key, defaultValue: defaultValue) ?? defaultValue
    }

    /// Evaluate a string flag, returning `defaultValue` if the flag is missing,
    /// the wrong type, or the SDK is not ready.
    public static func getString(_ key: String, default defaultValue: String) -> String {
        Instances.shared.defaultInstance()?.getString(key: key, defaultValue: defaultValue) ?? defaultValue
    }

    /// Evaluate an integer flag, returning `defaultValue` if the flag is missing,
    /// the wrong type, or the SDK is not ready. Integers travel as the numeric
    /// flag type, so a fractional value is truncated toward zero.
    public static func getInt(_ key: String, default defaultValue: Int) -> Int {
        Int(Instances.shared.defaultInstance()?.getInt(key: key, defaultValue: Int64(defaultValue)) ?? Int64(defaultValue))
    }

    /// Evaluate a numeric flag, returning `defaultValue` if the flag is missing,
    /// the wrong type, or the SDK is not ready.
    public static func getNumber(_ key: String, default defaultValue: Double) -> Double {
        Instances.shared.defaultInstance()?.getNumber(key: key, defaultValue: defaultValue) ?? defaultValue
    }

    /// Evaluate a JSON flag and decode it into `T`, returning `defaultValue` if
    /// the flag is missing, cannot be decoded, or the SDK is not ready.
    public static func getJSON<T: Codable>(_ key: String, default defaultValue: T) -> T {
        guard let client = Instances.shared.defaultInstance() else { return defaultValue }
        let raw = client.getJson(key: key, defaultValueJson: encodeJSONDefault(defaultValue))
        let data = Data(raw.utf8)
        return (try? JSONDecoder().decode(T.self, from: data)) ?? defaultValue
    }

    // MARK: - Detail getters

    // Like the plain getters but return the resolved value plus its reason,
    // variant, and error code. Before initialize the details carry the supplied
    // default and a PROVIDER_NOT_READY error code

    /// Evaluate a boolean flag and return full ``FlagEvaluationDetails``.
    public static func getBoolDetails(_ key: String, default defaultValue: Bool) -> FlagEvaluationDetails {
        guard let client = Instances.shared.defaultInstance() else {
            return notReadyDetails(value: .bool(defaultValue), flagKey: key)
        }
        return FlagEvaluationDetails(client.getBoolDetails(key: key, defaultValue: defaultValue))
    }

    /// Evaluate a string flag and return full ``FlagEvaluationDetails``.
    public static func getStringDetails(_ key: String, default defaultValue: String) -> FlagEvaluationDetails {
        guard let client = Instances.shared.defaultInstance() else {
            return notReadyDetails(value: .string(defaultValue), flagKey: key)
        }
        return FlagEvaluationDetails(client.getStringDetails(key: key, defaultValue: defaultValue))
    }

    /// Evaluate an integer flag and return full ``FlagEvaluationDetails``.
    public static func getIntDetails(_ key: String, default defaultValue: Int) -> FlagEvaluationDetails {
        guard let client = Instances.shared.defaultInstance() else {
            return notReadyDetails(value: .int(Int64(defaultValue)), flagKey: key)
        }
        return FlagEvaluationDetails(client.getIntDetails(key: key, defaultValue: Int64(defaultValue)))
    }

    /// Evaluate a numeric flag and return full ``FlagEvaluationDetails``.
    public static func getNumberDetails(_ key: String, default defaultValue: Double) -> FlagEvaluationDetails {
        guard let client = Instances.shared.defaultInstance() else {
            return notReadyDetails(value: .number(defaultValue), flagKey: key)
        }
        return FlagEvaluationDetails(client.getNumberDetails(key: key, defaultValue: defaultValue))
    }

    /// Evaluate a JSON flag and return full ``FlagEvaluationDetails``, with the
    /// value carried as its JSON-encoded string.
    public static func getJSONDetails<T: Codable>(_ key: String, default defaultValue: T) -> FlagEvaluationDetails {
        guard let client = Instances.shared.defaultInstance() else {
            return notReadyDetails(value: .json(encodeJSONDefault(defaultValue)), flagKey: key)
        }
        return FlagEvaluationDetails(client.getJsonDetails(key: key, defaultValueJson: encodeJSONDefault(defaultValue)))
    }

    // Details returned before initialize, carrying the supplied default plus
    // provider-not-ready metadata so a reader can tell the SDK was not ready
    private static func notReadyDetails(value: FlagDetailValue, flagKey: String) -> FlagEvaluationDetails {
        FlagEvaluationDetails(
            value: value,
            variant: nil,
            reason: "ERROR",
            errorCode: "PROVIDER_NOT_READY",
            errorMessage: "the SDK has not been initialized",
            flagKey: flagKey
        )
    }

    // MARK: - Observe

    // The observe surface backs the reactive wrappers (@CoproductFlag, the
    // Combine publisher, the async sequence). Unlike the getters it requires an
    // initialized instance and traps otherwise, because it returns a live
    // observation the caller subscribes to

    /// Observe a boolean flag. The observation seeds with the current value and
    /// emits every subsequent change. Requires an initialized instance.
    public static func observe(_ key: String, default defaultValue: Bool) -> FlagObservation<Bool> {
        Instances.shared.requireDefault().observeBool(key: key, defaultValue: defaultValue)
    }

    /// Observe a string flag. Requires an initialized instance.
    public static func observe(_ key: String, default defaultValue: String) -> FlagObservation<String> {
        Instances.shared.requireDefault().observeString(key: key, defaultValue: defaultValue)
    }

    /// Observe a numeric flag. Requires an initialized instance.
    public static func observe(_ key: String, default defaultValue: Double) -> FlagObservation<Double> {
        Instances.shared.requireDefault().observeNumber(key: key, defaultValue: defaultValue)
    }

    /// Observe an integer flag. Requires an initialized instance.
    public static func observe(_ key: String, default defaultValue: Int) -> FlagObservation<Int> {
        Instances.shared.requireDefault().observeInt(key: key, defaultValue: defaultValue)
    }

    /// Observe several keys at once as a ``FlagBundleObservation``. The current
    /// values are seeded at subscription time. Requires an initialized instance.
    public static func observe(keys: [String]) -> FlagBundleObservation {
        Instances.shared.requireDefault().observeMany(keys: keys)
    }

    // MARK: - Handlers / hooks

    /// Register a lifecycle handler. Retain the returned AnyCancellable for as
    /// long as the handler should stay active. Releasing it, or calling cancel,
    /// removes the handler. The result is not discardable because dropping it
    /// cancels the registration immediately, so the handler would never fire.
    ///
    /// Keep the handler fast. Handlers for an event fire serially, and identity
    /// mutations await their lifecycle events inline on the identity queue, so a
    /// slow handler delays every later identify, setContext, or signOut. Hop a
    /// queue for anything heavy rather than blocking in the handler
    public static func addHandler(
        event: LifecycleEvent,
        handler: @escaping @Sendable (LifecycleEvent) -> Void
    ) -> AnyCancellable {
        let wrapped = ClosureLifecycleHandler(closure: handler)
        let handle = Instances.shared.requireDefault().addHandler(event: event, handler: wrapped)
        return AnyCancellable { handle.cancel() }
    }

    /// Register an evaluation hook for a single stage. Retain the returned
    /// AnyCancellable for as long as the hook should stay active. Releasing it,
    /// or calling cancel, removes the hook. Not discardable for the same reason
    /// as addHandler: dropping the result cancels the hook immediately
    public static func addEvaluationHook(
        _ stage: EvaluationHookStage,
        handler: @escaping @Sendable (EvaluationHookContext) -> Void
    ) -> AnyCancellable {
        let wrapped = ClosureEvaluationHook(stage: stage, closure: handler)
        let handle = Instances.shared.requireDefault().addEvaluationHook(hook: wrapped)
        return AnyCancellable { handle.cancel() }
    }

    // MARK: - State / snapshot / shutdown

    /// The current provider lifecycle state. Reports `.notReady` before initialize.
    public static var state: ProviderState {
        Instances.shared.defaultInstance()?.state() ?? .notReady
    }

    /// A diagnostic snapshot summary (version, flag count, environment). Before
    /// initialize this reports an empty snapshot with version 0; use ``state`` to
    /// tell not-ready apart from a genuinely loaded snapshot.
    public static var snapshot: CoproductSnapshot {
        Instances.shared.defaultInstance()?.snapshotView()
            ?? CoproductSnapshot(version: 0, flagCount: 0, environment: "")
    }

    /// Tear down the instance: stop polling, cancel handlers and observations,
    /// and release the client. Reactive surfaces re-attach if you initialize
    /// again. The on-disk snapshot cache is preserved for the next launch.
    public static func shutdown() async {
        await Instances.shared.shutdown()
    }
}

public enum EvaluationHookStage: Sendable, Equatable {
    case before
    case after
    case error
    case finally
}

/// Bridges a caller-supplied closure to the generated LifecycleHandler protocol.
/// UniFFI does not auto-bridge Swift closures to Rust traits, so this wrapper is needed
final class ClosureLifecycleHandler: LifecycleHandler, @unchecked Sendable {
    private let closure: @Sendable (LifecycleEvent) -> Void

    init(closure: @escaping @Sendable (LifecycleEvent) -> Void) {
        self.closure = closure
    }

    func onEvent(event: LifecycleEvent) async {
        closure(event)
    }
}

/// Bridges a stage plus closure to the generated EvaluationHook protocol.
/// The caller registers a hook for a single stage, and the wrapper dispatches
/// the closure only when the matching stage fires. The hook fires
/// synchronously around each typed getter
final class ClosureEvaluationHook: EvaluationHook, @unchecked Sendable {
    private let stage: EvaluationHookStage
    private let closure: @Sendable (EvaluationHookContext) -> Void

    init(stage: EvaluationHookStage, closure: @escaping @Sendable (EvaluationHookContext) -> Void) {
        self.stage = stage
        self.closure = closure
    }

    func onStage(stage: EvaluationStage, ctx: HookContext) {
        guard stage == bridge(self.stage) else { return }
        closure(EvaluationHookContext(ctx, stage: self.stage))
    }

    private func bridge(_ wrapper: EvaluationHookStage) -> EvaluationStage {
        switch wrapper {
        case .before: return .before
        case .after: return .after
        case .error: return .error
        case .finally: return .finally
        }
    }
}

/// Safely convert a TimeInterval (seconds) to UInt64 seconds for FFI. Throws on
/// NaN, +/-Infinity, negatives, and values that do not fit in UInt64 as a
/// finite Double. The Rust core's validate_config then enforces business-range
/// checks on the safe value. This helper exists because UInt64(Double) traps on
/// the failure modes above instead of returning an optional
func safeUInt64Seconds(_ value: TimeInterval, field: String) throws -> UInt64 {
    guard value.isFinite, value >= 0,
          let truncated = UInt64(exactly: value.rounded(.towardZero)) else {
        throw CoproductError.invalidConfig(
            field: field,
            reason: "must be a finite non-negative number of seconds that fits in UInt64"
        )
    }
    return truncated
}

/// The single error family ``Coproduct/initialize(sdkKey:config:)`` throws. Every
/// launch failure funnels through this type, including failures the Rust core
/// detects after the FFI boundary, so a caller catches one Swift error rather
/// than a generated FFI type. Reads and fire-and-forget identity calls never throw.
public enum CoproductError: Error, Sendable {
    /// A configuration value is out of range or cannot be represented. Covers both
    /// wrapper guards (NaN, infinities, negatives, values that do not fit UInt64)
    /// and core range checks (for example a pollInterval below 30 or a
    /// non-positive startupTimeout)
    case invalidConfig(field: String, reason: String)

    /// The sdk key is missing or is not a well-formed mobile key
    case invalidSdkKey(reason: String)

    /// shutdown was called while this initialize was still in flight, so the
    /// initialize was abandoned rather than resurrecting a torn-down instance.
    /// Callers may retry initialization
    case cancelledByShutdown

    /// A launch failure with no more specific case. The reason carries the
    /// underlying description. Present so a future core failure stays catchable as
    /// CoproductError rather than surfacing as a generated type
    case launchFailed(reason: String)
}

extension CoproductError {
    /// Fold any error thrown during initialize into the single public family. A
    /// CoproductError passes through, a core InitError maps to the matching case,
    /// and anything else becomes launchFailed
    static func from(_ error: Error) -> CoproductError {
        if let wrapper = error as? CoproductError { return wrapper }
        guard let initError = error as? InitError else {
            return .launchFailed(reason: String(describing: error))
        }
        switch initError {
        case let .InvalidKeyType(prefix):
            return .invalidSdkKey(reason: "unexpected key prefix `\(prefix)`")
        case let .MalformedSdkKey(reason):
            return .invalidSdkKey(reason: reason)
        case .MissingSdkKey:
            return .invalidSdkKey(reason: "the sdk key is empty")
        case let .InvalidConfig(field, reason):
            return .invalidConfig(field: field, reason: reason)
        case let .UnsupportedSchemaVersion(actual, supported):
            // A schema mismatch does not reach here: a too-old cached snapshot is
            // dropped at initialize (comes up not ready) and a live schema
            // mismatch moves the provider to a fatal state after
            // initialize returns. Mapped for exhaustiveness in case that changes
            return .launchFailed(
                reason: "snapshot schema version \(actual) is not supported (this SDK supports \(supported))"
            )
        @unknown default:
            return .launchFailed(reason: String(describing: initError))
        }
    }
}

/// Holds the single default client and serializes initialize and shutdown.
///
/// Concurrency contract. Every read and write of defaultInstance, inFlight, and
/// generation happens under lock. Two concurrent initialize calls dedup to a
/// single core init, and the owning task alone runs the post-init side effects
/// (timer, store, ready), so waiters just receive the same client. The whole
/// initialize, including those side effects, runs inside the claimed task and is
/// fenced by generation: a shutdown during initialize bumps the generation so a
/// late completion cannot resurrect the instance. The stored instance also
/// remembers the sdk key it was initialized with so a re-init with a different
/// key can warn without exporting the secret back over FFI
final class Instances: @unchecked Sendable {
    static let shared = Instances()
    private let lock = NSLock()

    /// A client paired with the sdk key it was initialized with. The key is
    /// kept in Swift only and never crosses FFI again. The host-driven polling
    /// timer and the network monitor are retained here so they live exactly as
    /// long as the instance and are cancelled when the instance shuts down
    private struct Stored {
        let client: CoproductClient
        let sdkKey: String
        let timer: HostTimer?
        let networkMonitor: NetworkMonitor?
    }

    private var _defaultInstance: Stored?
    private var inFlight: Task<CoproductClient, Error>?

    // The sdk key of the in-flight initialize, kept so a concurrent initialize
    // that joins it can warn on a key mismatch, matching the post-init warning
    private var inFlightKey: String?

    // Bumped by every shutdown. An initialize captures the generation it was
    // claimed under, so a completion whose generation no longer matches knows a
    // shutdown intervened and must not store or resurrect the instance
    private var generation = 0

    func defaultInstance() -> CoproductClient? {
        lock.lock()
        defer { lock.unlock() }
        return _defaultInstance?.client
    }

    func requireDefault() -> CoproductClient {
        guard let inner = defaultInstance() else {
            fatalError("[Coproduct] Coproduct API called before initialize(sdkKey:). Call initialize first.")
        }
        return inner
    }

    func initialize(sdkKey: String, config: CoproductConfig) async throws -> CoproductClient {
        // Resolve under the lock in a synchronous helper: an existing instance or
        // the single claimed Task. Owner and waiters both just await that task,
        // which owns the full initialize, so the side effects run exactly once
        switch claimInit(sdkKey: sdkKey, config: config) {
        case let .existing(client):
            // Accepted behavior: a second caller that arrives after the instance
            // is stored returns immediately without repeating the readiness wait,
            // so two racing callers can see different freshness (one waited for
            // the first poll, this one did not). The instance genuinely exists,
            // and either caller can consult state or observe for readiness
            return client
        case let .pending(task):
            return try await task.value
        }
    }

    // The full initialize, run inside the claimed task so it executes once no
    // matter how many callers await it. Builds the client (fast, cache-backed),
    // installs it, starts the host timer whose first tick polls immediately, then
    // waits up to startupTimeout for that first poll to make the provider ready
    // before returning. It never throws on a slow poll: launch is bounded by
    // startupTimeout, and reads serve cache or defaults until the poll lands
    private func runInitialize(
        sdkKey: String,
        config: CoproductConfig,
        generation claimedGeneration: Int
    ) async throws -> CoproductClient {
        let inner: CoproductClient
        do {
            inner = try await Self.doInitialize(sdkKey: sdkKey, config: config)
        } catch {
            // If a shutdown ran during this init, always report the same
            // cancelled error instead of whatever the cancelled work threw, so
            // the result is predictable
            guard finishInFlight(generation: claimedGeneration) else {
                throw CoproductError.cancelledByShutdown
            }
            // Fold core InitError (and anything else) into the single public error
            // family so a caller never catches a generated FFI type
            throw CoproductError.from(error)
        }

        // Drive polling from the host. The core does not poll during initialize,
        // so the timer's immediate first tick owns the first fetch as well as the
        // recurring schedule. The foreground fast path re-polls when the app
        // returns to the foreground. A weak capture avoids the timer keeping a
        // shut-down client alive
        let timer = HostTimer(
            interval: config.pollInterval,
            pollOnForeground: config.pollOnForeground
        ) { [weak inner] in
            // The poll outcome drives the timer's next fire, so a 429 retry-after
            // and a stale back-off are honored. A deallocated client polls nothing
            guard let inner else { return .dedupedSkipped }
            return await inner.pollNow()
        }

        // Live network classification through the injectable source seam. The
        // attribute is absent until the first path callback. Each change is
        // enqueued in identity order. A weak capture keeps the monitor from
        // retaining a shut-down client
        let networkMonitor = NetworkMonitor(
            source: NetworkMonitor.sourceOverrideForTesting ?? NWPathSource(),
            onChange: { [weak inner] type in
                inner?.setAutoPopulated(attributes: ["network_type": .string(type)])
            }
        )

        guard storeIfCurrent(
            Stored(client: inner, sdkKey: sdkKey, timer: timer, networkMonitor: networkMonitor),
            generation: claimedGeneration
        ) else {
            // A shutdown ran during the brief construct before the instance was
            // stored. Do not resurrect it: tear the orphan down and report the
            // cancellation so the caller never sees initialize succeed against a
            // torn-down SDK
            networkMonitor.cancel()
            await inner.shutdown()
            throw CoproductError.cancelledByShutdown
        }

        timer.start()
        networkMonitor.start()
        // Signal reactive surfaces that subscribed before a default instance
        // existed (such as @CoproductFlag on a view built before its .task runs)
        // so they can attach now
        NotificationCenter.default.post(name: .coproductDefaultInstanceReady, object: nil)

        // A shutdown during the readiness wait reports the same cancellation as a
        // shutdown during the construct, so the shutdown-race contract is a single
        // rule regardless of which phase it lands in
        guard await waitForFirstPoll(inner, startupTimeout: config.startupTimeout) else {
            throw CoproductError.cancelledByShutdown
        }
        return inner
    }

    // Waits up to startupTimeout for the first poll to move the provider off
    // NotReady, so a fast network resolves initialize as ready while a slow or
    // unreachable one still returns within the deadline. Returns false when a
    // shutdown replaced or cleared the instance during the wait. Uses a monotonic
    // deadline so a wall-clock jump during launch does not stretch or truncate it.
    // Reads served during and after the wait fall back to cache or developer defaults
    private func waitForFirstPoll(_ client: CoproductClient, startupTimeout: TimeInterval) async -> Bool {
        guard startupTimeout > 0, startupTimeout.isFinite else { return true }
        let deadline = DispatchTime.now() + startupTimeout
        while client.state() == .notReady, DispatchTime.now() < deadline {
            guard defaultInstance() === client else { return false }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return defaultInstance() === client
    }

    // Builds the core client. The core returns a cache-backed client without
    // touching the network, so this resolves quickly and startupTimeout only
    // bounds the host-side wait for the first poll in runInitialize. Pure function
    // so concurrent initialize callers can share a single Task
    private static func doInitialize(
        sdkKey: String,
        config: CoproductConfig
    ) async throws -> CoproductClient {
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .path

        // The default transport fallback wires config.requestTimeout through so
        // the caller's setting actually reaches URLSession
        let transport: any HostTransport = config.transport
            ?? URLSessionTransport(requestTimeout: config.requestTimeout)
        let secureStore: any HostSecureStore = config.secureStore ?? KeychainSecureStore()

        let client = try await coreInitialize(
            sdkKey: sdkKey,
            cacheDir: cacheDir,
            config: config,
            transport: transport,
            secureStore: secureStore
        )

        if let listener = config.evaluationListener {
            client.setEvaluationListener(listener: listener)
        }

        // Publish the SDK-owned device and session attributes before initialize
        // resolves, so the first synchronous read evaluates against them. The
        // live network fact arrives later through NetworkMonitor
        var autoAttributes = DeviceContext.staticAttributes()
        for (key, value) in SessionStore().sessionAttributes() {
            autoAttributes[key] = value
        }
        await client.setAutoPopulatedNow(attributes: autoAttributes)

        return client
    }

    // Caller must hold lock. Returns the existing instance if any. The sdk-key
    // mismatch warning is informational only, re-initialize with a different key
    // returns the original instance. The comparison uses the stored Swift-side
    // key, never an FFI call
    private func lookupLocked(sdkKey: String) -> CoproductClient? {
        guard let existing = _defaultInstance else { return nil }
        if existing.sdkKey != sdkKey {
            NSLog("[Coproduct] initialize called with different sdkKey; returning existing instance")
        }
        return existing.client
    }

    // Result of claiming the initialize slot under the lock
    private enum InitClaim {
        case existing(CoproductClient)
        case pending(Task<CoproductClient, Error>)
    }

    // Synchronous, lock-held resolution of an initialize call: an existing
    // instance, or the single in-flight Task (the one already running, or a fresh
    // one this caller claims). Synchronous so the lock is never taken inside an
    // async method
    private func claimInit(sdkKey: String, config: CoproductConfig) -> InitClaim {
        lock.lock()
        defer { lock.unlock() }
        if let existing = lookupLocked(sdkKey: sdkKey) {
            return .existing(existing)
        }
        if let pending = inFlight {
            // Joining an in-flight initialize means this caller's key and config
            // are ignored in favor of the one already running. Warn on a key
            // mismatch so the behavior matches the post-init warning
            if inFlightKey != sdkKey {
                NSLog("[Coproduct] initialize called with a different sdkKey while initialization is in progress; joining the in-flight initialize")
            }
            return .pending(pending)
        }
        // Constructing the Task while holding the lock is safe: it only enqueues
        // the closure to the cooperative pool, it does not run it here. The task
        // captures the current generation so its completion can tell whether a
        // shutdown intervened
        let claimedGeneration = generation
        let task = Task {
            try await self.runInitialize(sdkKey: sdkKey, config: config, generation: claimedGeneration)
        }
        inFlight = task
        inFlightKey = sdkKey
        return .pending(task)
    }

    // Store the initialized instance and clear the in-flight Task, but only if no
    // shutdown has bumped the generation since this initialize was claimed.
    // Returns whether the instance was stored
    private func storeIfCurrent(_ stored: Stored, generation claimedGeneration: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard claimedGeneration == generation else { return false }
        inFlight = nil
        inFlightKey = nil
        _defaultInstance = stored
        return true
    }

    // Clear a failed in-flight Task if it is still the current one, and report
    // whether it was. Returns false when a shutdown superseded this init since it
    // was claimed, in which case the task has already been cleared and replaced
    private func finishInFlight(generation claimedGeneration: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard claimedGeneration == generation else { return false }
        inFlight = nil
        inFlightKey = nil
        return true
    }

    // Bump the generation to fence any in-flight initialize, then take the stored
    // instance and the in-flight task so the caller can tear them down
    private func teardownLocked() -> (stored: Stored?, pending: Task<CoproductClient, Error>?) {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        let stored = _defaultInstance
        _defaultInstance = nil
        let pending = inFlight
        inFlight = nil
        inFlightKey = nil
        return (stored, pending)
    }

    func shutdown() async {
        let (stored, pending) = teardownLocked()

        // Cancel any in-flight initialize. The generation bump already fences a
        // late completion from storing, this just stops the work sooner
        pending?.cancel()

        // Tell reactive surfaces bound to the default instance to detach before
        // the client is torn down, so a later initialize re-attaches them
        NotificationCenter.default.post(name: .coproductDefaultInstanceShutdown, object: nil)

        // Cancel the recurring poll before tearing down the client so no fire
        // closure races against the in-flight shutdown
        stored?.timer?.stop()
        stored?.networkMonitor?.cancel()
        await stored?.client.shutdown()
    }
}

// User agent sent on every snapshot fetch, identifying the
// platform. The version is a development version token
let coproductUserAgent = "coproduct-ios/0.0.1-dev"

// Free functions rather than members of the Coproduct namespace so the
// unqualified initialize call resolves to the generated module-level
// initialize(sdkKey:userAgent:cacheDir:config:transport:secureStore:) free
// function rather than the public static initialize overloads on Coproduct
private func coreInitialize(
    sdkKey: String,
    cacheDir: String,
    config: CoproductConfig,
    transport: any HostTransport,
    secureStore: any HostSecureStore
) async throws -> CoproductClient {
    try await initialize(
        sdkKey: sdkKey,
        userAgent: coproductUserAgent,
        cacheDir: cacheDir,
        config: try toFfiConfig(config),
        transport: transport,
        secureStore: secureStore
    )
}

/// Encode a caller-supplied JSON flag default to the JSON string the core
/// expects. A value that cannot be encoded falls back to a JSON null, which the
/// core treats as an absent default. Top-level objects and arrays always encode
func encodeJSONDefault<T: Encodable>(_ value: T) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let json = String(data: data, encoding: .utf8) else {
        return "null"
    }
    return json
}

extension Notification.Name {
    // Posted once a default Coproduct instance becomes available. Reactive surfaces
    // built before initialize observe this to attach as soon as the SDK is ready
    static let coproductDefaultInstanceReady = Notification.Name("app.coproduct.defaultInstanceReady")

    // Posted when the default Coproduct instance is shut down. Reactive surfaces
    // detach so they do not keep a subscription to a torn-down client
    static let coproductDefaultInstanceShutdown = Notification.Name("app.coproduct.defaultInstanceShutdown")
}

private func toFfiConfig(_ config: CoproductConfig) throws -> FfiConfig {
    try FfiConfig(
        pollIntervalSecs: safeUInt64Seconds(config.pollInterval, field: "pollInterval"),
        startupTimeoutSecs: safeUInt64Seconds(config.startupTimeout, field: "startupTimeout"),
        anonymousId: config.anonymousId,
        endpoint: config.endpoint,
        pollOnForeground: config.pollOnForeground
    )
}

// MARK: - Synchronous identity bridges

/// Serializes identity mutations so they apply in the order they were called.
/// The public identity API is synchronous and fire-and-forget, so without a
/// single ordered queue two rapid calls could reach the core out of order and
/// leave the wrong final state. Each call appends to a chain that awaits the
/// previous mutation before running its own
final class IdentitySerializer: @unchecked Sendable {
    static let shared = IdentitySerializer()
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    func enqueue(_ operation: @escaping @Sendable () async -> Void) {
        lock.lock()
        let previous = tail
        tail = Task {
            await previous?.value
            await operation()
        }
        lock.unlock()
    }

    // Reads the current tail under the lock. Synchronous so the lock is never
    // taken inside an async body
    private func currentTail() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return tail
    }

    // Awaits the work enqueued so far. Used by tests to observe the settled
    // state after a burst of fire-and-forget identity calls
    func drain() async {
        await currentTail()?.value
    }
}

// The identity API is exposed on the static Coproduct surface. These bridges are
// internal on purpose: the generated CoproductClient is reachable if a consumer
// imports the CoproductFFI target directly, and a public extension here would
// hand them a blessed-looking API that bypasses the registry, the ordered
// identity queue, and the host timer. Each call is enqueued on a single ordered
// queue and any thrown error is logged, so it is fire-and-forget yet still
// applied in call order
extension CoproductClient {
    func identify(userId: String, attributes: [String: AttributeValue], linkAnonymous: Bool) {
        let context = attributes.contextValues
        IdentitySerializer.shared.enqueue { [self] in
            do {
                try await identify(userId: userId, attributes: context, linkAnonymous: linkAnonymous)
            } catch {
                NSLog("[Coproduct] identify failed: \(error)")
            }
        }
    }

    func signOut() {
        IdentitySerializer.shared.enqueue { [self] in
            // await selects the generated async signOut, not this same-named
            // wrapper. The other identity methods differ by argument type
            await signOut()
        }
    }

    func updateAttributes(attributes: [String: AttributeValue]) {
        let context = attributes.contextValues
        IdentitySerializer.shared.enqueue { [self] in
            await updateAttributes(attributes: context)
        }
    }

    func removeAttributes(keys: [String]) {
        IdentitySerializer.shared.enqueue { [self] in
            await removeAttributes(names: keys)
        }
    }

    func setContext(targetingKey: String, attributes: [String: AttributeValue]) {
        let context = attributes.contextValues
        IdentitySerializer.shared.enqueue { [self] in
            do {
                try await setContext(targetingKey: targetingKey, attributes: context)
            } catch {
                NSLog("[Coproduct] setContext failed: \(error)")
            }
        }
    }

    // Awaited variant used once during initialize, before the instance is
    // published, so the first synchronous read already evaluates against the
    // static device attributes
    func setAutoPopulatedNow(attributes: [String: AttributeValue]) async {
        await setAutoPopulatedAttributes(attributes: attributes.contextValues)
    }

    // Ordered variant for live updates after initialize. Enqueued on the same
    // serializer as the identity mutators so a network change and an identify
    // apply in call order
    func setAutoPopulated(attributes: [String: AttributeValue]) {
        let context = attributes.contextValues
        IdentitySerializer.shared.enqueue { [self] in
            await setAutoPopulatedAttributes(attributes: context)
        }
    }
}
