import Combine
import CoproductFFI
import Foundation

/// Reference-typed observation handle for a single key. Releasing the last
/// strong reference cancels the underlying subscription
public final class FlagObservation<T: Sendable>: @unchecked Sendable {
    /// The flag key this observation tracks
    public let key: String

    private let lock = NSLock()
    private var _current: T
    private let subject: CurrentValueSubject<T, Never>
    // Ends the native observation. Held as a closure so this type does not name a
    // per-type generated observation
    private var cancelNative: (@Sendable () -> Void)?
    private var drain: Task<Void, Never>?

    /// Latest projected value seen for this key
    public var current: T {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    /// Combine stream of projected values, seeded with the current value. Keeps
    /// the observation, and so its core subscription, alive while a subscriber
    /// holds the stream, so keeping only the publisher still receives changes
    public var publisher: AnyPublisher<T, Never> {
        subject
            .map { [observation = self] value -> T in withExtendedLifetime(observation) { value } }
            .eraseToAnyPublisher()
    }

    init(key: String, initial: T) {
        self.key = key
        self._current = initial
        self.subject = CurrentValueSubject<T, Never>(initial)
    }

    /// Attach the native session's teardown and its drain task. The observation
    /// owns both and ends them on deinit
    func attach(cancelNative: @escaping @Sendable () -> Void, drain: Task<Void, Never>) {
        lock.lock()
        self.cancelNative = cancelNative
        self.drain = drain
        lock.unlock()
    }

    // A delivery from the drain task. Deliveries for one observation arrive on a
    // single task, in revision order, so no separate delivery lock is needed
    func push(_ value: T) {
        lock.lock()
        _current = value
        lock.unlock()
        subject.send(value)
    }

    deinit {
        // Cancelling the native observation closes its mailbox, which resolves the
        // drain's pending pollNext to closed and lets the task finish. The task
        // holds only a weak reference here, so this deinit is reachable
        cancelNative?()
        drain?.cancel()
    }
}

/// Reference-typed observation handle for a set of keys. Each key's value is
/// provided as a FlagDetailValue so integer and JSON flags keep their type
/// rather than collapsing to a double or a string. Releasing the last strong
/// reference cancels the underlying subscription
public final class FlagBundleObservation: @unchecked Sendable {
    /// The flag keys this bundle observation tracks
    public let keys: [String]

    private let lock = NSLock()
    private var _current: [String: FlagDetailValue]
    private let subject: CurrentValueSubject<[String: FlagDetailValue], Never>
    // Ends the native observation. Held as a closure so this type does not name a
    // per-type generated observation
    private var cancelNative: (@Sendable () -> Void)?
    private var drain: Task<Void, Never>?

    /// Latest snapshot of all observed keys
    public var current: [String: FlagDetailValue] {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    /// Combine stream of the observed keys, seeded with the current snapshot.
    /// Keeps the observation alive while a subscriber holds the stream
    public var publisher: AnyPublisher<[String: FlagDetailValue], Never> {
        subject
            .map { [observation = self] snapshot -> [String: FlagDetailValue] in
                withExtendedLifetime(observation) { snapshot }
            }
            .eraseToAnyPublisher()
    }

    init(keys: [String], initial: [String: FlagDetailValue]) {
        self.keys = keys
        self._current = initial
        self.subject = CurrentValueSubject<[String: FlagDetailValue], Never>(initial)
    }

    /// Attach the native session's teardown and its drain task. The observation
    /// owns both and ends them on deinit
    func attach(cancelNative: @escaping @Sendable () -> Void, drain: Task<Void, Never>) {
        lock.lock()
        self.cancelNative = cancelNative
        self.drain = drain
        lock.unlock()
    }

    // A delivery carries the complete current state of every subscribed key, so
    // it replaces the snapshot wholesale. A key whose value is unavailable is
    // absent from `snapshot`, which is how it leaves `current`, consistent with
    // currentFlagValues omitting unavailable keys
    func replace(with snapshot: [String: FlagDetailValue]) {
        lock.lock()
        _current = snapshot
        lock.unlock()
        subject.send(snapshot)
    }

    deinit {
        // Cancelling the native observation closes its mailbox, which resolves the
        // drain's pending pollNext to closed and lets the task finish. The task
        // holds only a weak reference here, so this deinit is reachable
        cancelNative?()
        drain?.cancel()
    }
}

// Internal, not public: the observe surface is exposed on the static Coproduct
// API. Keeping these off CoproductClient avoids offering a second, registry
// bypassing API to anyone who reaches the generated client directly
extension CoproductClient {
    /// Observe a boolean flag. The session's seed is evaluated atomically with the
    /// registration, so there is no separate seed read that could disagree with a
    /// delivery. Unavailable, at the seed or in any delivery, resolves to the
    /// caller's default
    func observeBool(key: String, defaultValue: Bool) -> FlagObservation<Bool> {
        let native: BoolObservation = self.observeBool(key: key)
        let observation = FlagObservation<Bool>(key: key, initial: native.seed() ?? defaultValue)
        // The drain runs off the core delivery lane, so a handler that re-enters
        // the SDK cannot deadlock delivery. It holds the observation weakly, so
        // the observation's deinit stays reachable while the loop is parked
        let drain = Task { [weak observation] in
            while true {
                switch await native.pollNext() {
                case let .value(_, value):
                    guard let observation else { return }
                    observation.push(value ?? defaultValue)
                case .closed:
                    return
                }
            }
        }
        observation.attach(cancelNative: { native.cancel() }, drain: drain)
        return observation
    }

    /// Observe a string flag. Unavailable resolves to the caller's default
    func observeString(key: String, defaultValue: String) -> FlagObservation<String> {
        let native: StringObservation = self.observeString(key: key)
        let observation = FlagObservation<String>(key: key, initial: native.seed() ?? defaultValue)
        let drain = Task { [weak observation] in
            while true {
                switch await native.pollNext() {
                case let .value(_, value):
                    guard let observation else { return }
                    observation.push(value ?? defaultValue)
                case .closed:
                    return
                }
            }
        }
        observation.attach(cancelNative: { native.cancel() }, drain: drain)
        return observation
    }

    /// Observe a numeric flag. Unavailable resolves to the caller's default
    func observeNumber(key: String, defaultValue: Double) -> FlagObservation<Double> {
        let native: NumberObservation = self.observeNumber(key: key)
        let observation = FlagObservation<Double>(key: key, initial: native.seed() ?? defaultValue)
        let drain = Task { [weak observation] in
            while true {
                switch await native.pollNext() {
                case let .value(_, value):
                    guard let observation else { return }
                    observation.push(value ?? defaultValue)
                case .closed:
                    return
                }
            }
        }
        observation.attach(cancelNative: { native.cancel() }, drain: drain)
        return observation
    }

    /// Observe an integer flag. The shared projector truncates on the native
    /// side, so a value that is not usable as an integer arrives unavailable and
    /// resolves to the caller's default
    func observeInt(key: String, defaultValue: Int) -> FlagObservation<Int> {
        let native: IntObservation = self.observeInt(key: key)
        let observation = FlagObservation<Int>(
            key: key,
            initial: native.seed().map(Int.init) ?? defaultValue
        )
        let drain = Task { [weak observation] in
            while true {
                switch await native.pollNext() {
                case let .value(_, value):
                    guard let observation else { return }
                    observation.push(value.map(Int.init) ?? defaultValue)
                case .closed:
                    return
                }
            }
        }
        observation.attach(cancelNative: { native.cancel() }, drain: drain)
        return observation
    }

    /// Observe a set of keys. The session seeds the complete map atomically, and
    /// every delivery carries the complete current state, so a key that becomes
    /// unavailable leaves `current` rather than lingering at a stale value
    func observeMany(keys: [String]) -> FlagBundleObservation {
        let native = observeBundle(keys: keys)
        let observation = FlagBundleObservation(
            keys: keys,
            initial: CoproductClient.snapshot(from: native.seed())
        )
        let drain = Task { [weak observation] in
            while true {
                switch await native.pollNext() {
                case let .value(_, values):
                    guard let observation else { return }
                    observation.replace(with: CoproductClient.snapshot(from: values))
                case .closed:
                    return
                }
            }
        }
        observation.attach(cancelNative: { native.cancel() }, drain: drain)
        return observation
    }

    // The transport carries a complete map in which an unavailable key is present
    // with a nil value. The public dictionary omits those keys instead, matching
    // currentFlagValues
    private static func snapshot(from values: [String: FlagValue?]) -> [String: FlagDetailValue] {
        values.compactMapValues { $0?.detailValue }
    }
}
