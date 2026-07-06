import Combine
import CoproductFFI
import Foundation

/// Reference-typed observation handle for a single key. Releasing the last
/// strong reference cancels the underlying subscription
public final class FlagObservation<T: Sendable>: @unchecked Sendable {
    /// The flag key this observation tracks
    public let key: String

    private let lock = NSLock()
    // Serializes push so two concurrent core fanouts (a poll swap and a context
    // swap can run on independent tasks) cannot interleave their subject.send.
    // Separate from lock so a subscriber reading current during delivery takes
    // lock, which push has already released, rather than deadlocking
    private let deliveryLock = NSLock()
    private var _current: T
    // Set once a real change is delivered through the core subscription. A seed
    // read after this is dropped so it cannot overwrite a delivered value
    private var hasDelivered = false
    private let subject: CurrentValueSubject<T, Never>
    private var subscription: CoproductFFI.Subscription?

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

    /// Attach the core subscription once it has been created. The observation
    /// owns the subscription and cancels it on deinit
    func attach(subscription: CoproductFFI.Subscription) {
        lock.lock()
        self.subscription = subscription
        lock.unlock()
    }

    // A real delivery from the core subscription. Always applies, and records that
    // a value has arrived so a later seed cannot clobber it
    func push(_ value: T) {
        deliveryLock.lock()
        defer { deliveryLock.unlock() }
        lock.lock()
        _current = value
        hasDelivered = true
        lock.unlock()
        subject.send(value)
    }

    // The subscription-time seed. Applies only if no delivery has arrived, so a
    // change that lands during setup (delivered via push once the observer is
    // registered) is never overwritten by the seed's stale read. deliveryLock
    // serializes this against push so the check and write cannot interleave
    func seed(_ value: T) {
        deliveryLock.lock()
        defer { deliveryLock.unlock() }
        lock.lock()
        if hasDelivered {
            lock.unlock()
            return
        }
        _current = value
        lock.unlock()
        subject.send(value)
    }

    deinit {
        subscription?.cancel()
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
    // Serializes merge so concurrent core fanouts cannot interleave their
    // subject.send. Separate from lock so a subscriber reading current during
    // delivery does not deadlock (see FlagObservation for the rationale)
    private let deliveryLock = NSLock()
    private var _current: [String: FlagDetailValue]
    // Keys a real change has been delivered for. A seed skips these so it cannot
    // overwrite a delivered value with a stale read
    private var deliveredKeys: Set<String> = []
    private let subject: CurrentValueSubject<[String: FlagDetailValue], Never>
    private var subscription: CoproductFFI.Subscription?

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

    func attach(subscription: CoproductFFI.Subscription) {
        lock.lock()
        self.subscription = subscription
        lock.unlock()
    }

    // A real delivery for one key. Always applies, and records the key so a later
    // seed cannot clobber it
    func merge(key: String, value: FlagDetailValue) {
        deliveryLock.lock()
        defer { deliveryLock.unlock() }
        lock.lock()
        _current[key] = value
        deliveredKeys.insert(key)
        let snapshot = _current
        lock.unlock()
        subject.send(snapshot)
    }

    // Seed a single key at subscription. Skips a key a delivery already populated,
    // so a change delivered during setup is not overwritten by the seed's stale
    // read. deliveryLock serializes this against merge
    func seed(key: String, value: FlagDetailValue) {
        deliveryLock.lock()
        defer { deliveryLock.unlock() }
        lock.lock()
        if deliveredKeys.contains(key) {
            lock.unlock()
            return
        }
        _current[key] = value
        let snapshot = _current
        lock.unlock()
        subject.send(snapshot)
    }

    deinit {
        subscription?.cancel()
    }
}

/// Bridges the core FlagObserver callback to a typed projection pushed into a
/// FlagObservation. The projection returns nil when a change for an unexpected
/// value shape arrives, in which case the change is ignored
private final class ProjectingFlagObserver<T: Sendable>: FlagObserver, @unchecked Sendable {
    private let project: @Sendable (FlagValue) -> T?
    private let sink: @Sendable (T) -> Void

    init(
        project: @escaping @Sendable (FlagValue) -> T?,
        sink: @escaping @Sendable (T) -> Void
    ) {
        self.project = project
        self.sink = sink
    }

    func onChange(key _: String, value: FlagValue) async throws {
        if let projected = project(value) {
            sink(projected)
        }
    }
}

/// Bridges the core FlagObserver callback for a multi-key observation. Each change
/// carries the key, so the bundle observation can merge it into the current snapshot
private final class BundleFlagObserver: FlagObserver, @unchecked Sendable {
    private let sink: @Sendable (String, FlagDetailValue) -> Void

    init(sink: @escaping @Sendable (String, FlagDetailValue) -> Void) {
        self.sink = sink
    }

    func onChange(key: String, value: FlagValue) async throws {
        sink(key, value.detailValue)
    }
}

// Internal, not public: the observe surface is exposed on the static Coproduct
// API. Keeping these off CoproductClient avoids offering a second, registry
// bypassing API to anyone who reaches the generated client directly
extension CoproductClient {
    /// Observe a boolean flag. Seeds the observation with the current value and
    /// pushes every subsequent boolean change. The observer is registered before
    /// the seed is read so a poll that lands during setup is not missed
    func observeBool(key: String, defaultValue: Bool) -> FlagObservation<Bool> {
        let observation = FlagObservation<Bool>(key: key, initial: defaultValue)
        let observer = ProjectingFlagObserver<Bool>(
            project: { value in
                if case let .bool(inner) = value { return inner }
                return nil
            },
            sink: { [weak observation] in observation?.push($0) }
        )
        observation.attach(subscription: observeKey(key: key, observer: observer))
        observation.seed(getBool(key: key, defaultValue: defaultValue))
        return observation
    }

    /// Observe a string flag
    func observeString(key: String, defaultValue: String) -> FlagObservation<String> {
        let observation = FlagObservation<String>(key: key, initial: defaultValue)
        let observer = ProjectingFlagObserver<String>(
            project: { value in
                if case let .string(inner) = value { return inner }
                return nil
            },
            sink: { [weak observation] in observation?.push($0) }
        )
        observation.attach(subscription: observeKey(key: key, observer: observer))
        observation.seed(getString(key: key, defaultValue: defaultValue))
        return observation
    }

    /// Observe a numeric flag
    func observeNumber(key: String, defaultValue: Double) -> FlagObservation<Double> {
        let observation = FlagObservation<Double>(key: key, initial: defaultValue)
        let observer = ProjectingFlagObserver<Double>(
            project: { value in
                switch value {
                case let .number(inner): return inner
                case let .int(inner): return Double(inner)
                default: return nil
                }
            },
            sink: { [weak observation] in observation?.push($0) }
        )
        observation.attach(subscription: observeKey(key: key, observer: observer))
        observation.seed(getNumber(key: key, defaultValue: defaultValue))
        return observation
    }

    /// Observe an integer flag. Integers travel as the core's number type, so a
    /// change projects through Int64 directly when it arrives as an int and
    /// through a truncated double otherwise. A non-finite or out-of-range double
    /// is ignored rather than trapped
    func observeInt(key: String, defaultValue: Int) -> FlagObservation<Int> {
        let observation = FlagObservation<Int>(key: key, initial: defaultValue)
        let observer = ProjectingFlagObserver<Int>(
            project: { value in
                switch value {
                case let .int(inner): return Int(inner)
                case let .number(inner):
                    guard inner.isFinite,
                          let truncated = Int(exactly: inner.rounded(.towardZero)) else { return nil }
                    return truncated
                default: return nil
                }
            },
            sink: { [weak observation] in observation?.push($0) }
        )
        observation.attach(subscription: observeKey(key: key, observer: observer))
        observation.seed(Int(getInt(key: key, defaultValue: Int64(defaultValue))))
        return observation
    }

    /// Observe a set of keys. Registers the observer, then seeds each key's
    /// current value so the bundle is populated at subscription rather than only
    /// after a key next changes. Registering before the seed read means a change
    /// during setup is delivered, not missed
    func observeMany(keys: [String]) -> FlagBundleObservation {
        let observation = FlagBundleObservation(keys: keys, initial: [:])
        let observer = BundleFlagObserver(
            sink: { [weak observation] key, value in
                observation?.merge(key: key, value: value)
            }
        )
        observation.attach(subscription: observeKeys(keys: keys, observer: observer))
        for (key, value) in currentFlagValues(keys: keys) {
            observation.seed(key: key, value: value.detailValue)
        }
        return observation
    }
}
