import Combine
import SwiftUI

/// A SwiftUI property wrapper that binds a view to a flag: `@CoproductFlag("key",
/// default: false) var newCheckout: Bool`. The view re-renders whenever the flag
/// changes. Supports `Bool`, `String`, `Int`, and `Double`. Until the SDK is
/// initialized and ready it serves the supplied default. The projected value
/// (`$newCheckout`) is an `AnyPublisher` of the same stream.
///
/// Delivery is hopped to the main queue internally, so it is safe to read in a
/// view body.
@propertyWrapper
public struct CoproductFlag<Value: CoproductFlagValue>: DynamicProperty {
    @StateObject private var holder: Holder

    /// Create a flag binding for `key`, serving `defaultValue` until a resolved
    /// value is available.
    public init(_ key: String, default defaultValue: Value) {
        _holder = StateObject(wrappedValue: Holder(key: key, defaultValue: defaultValue))
    }

    /// The current flag value.
    public var wrappedValue: Value { holder.value }

    /// A Combine publisher of the flag value, accessed through the `$` projection,
    /// that emits the current value and every change.
    public var projectedValue: AnyPublisher<Value, Never> { holder.$value.eraseToAnyPublisher() }

    final class Holder: ObservableObject {
        @Published var value: Value
        private let key: String
        private let defaultValue: Value
        private var cancellable: AnyCancellable?
        private var readyObserver: NSObjectProtocol?
        private var shutdownObserver: NSObjectProtocol?

        // True once the holder has an active flag subscription
        var isSubscribed: Bool { cancellable != nil }

        init(key: String, defaultValue: Value) {
            self.key = key
            self.defaultValue = defaultValue
            self.value = defaultValue
            // SwiftUI constructs property wrappers before a view's .task runs, so a
            // @CoproductFlag is routinely created before initialize. Listen for a
            // ready default instance so the wrapper attaches on first launch and
            // re-attaches after a shutdown plus initialize, and detach when the
            // instance shuts down so it never holds a dead subscription. The gate
            // is instance existence rather than provider state because the
            // instance can exist while the first snapshot is still loading. Until
            // attached the wrapper serves the supplied default
            readyObserver = NotificationCenter.default.addObserver(
                forName: .coproductDefaultInstanceReady,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.subscribe()
            }
            shutdownObserver = NotificationCenter.default.addObserver(
                forName: .coproductDefaultInstanceShutdown,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.detach()
            }
            // Attach now if an instance already exists. Registering the observers
            // first means a concurrent initialize is caught either by the observer
            // or by this check, with no missed signal
            if Instances.shared.defaultInstance() != nil {
                subscribe()
            }
        }

        // Attach to the current default instance, replacing any prior
        // subscription so a reinitialized client takes over
        private func subscribe() {
            // The ready notification is delivered on the main queue, so a shutdown
            // can null the default instance between the post and this call. Bail
            // out quietly in that case rather than trapping in requireDefault. A
            // later ready notification re-attaches
            guard Instances.shared.defaultInstance() != nil else { return }
            // Use the weak-binding sink rather than assign(to:on:). The keypath
            // assign form retains self, and since the cancellable lives on self
            // that would form a Holder to cancellable to Holder cycle that never
            // releases. The sink form captures self weakly
            cancellable = Value.observe(key: key, defaultValue: defaultValue)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newValue in
                    self?.value = newValue
                }
        }

        // Drop the subscription when the instance shuts down. The wrapper keeps
        // serving its last value and re-attaches if a new instance initializes
        private func detach() {
            cancellable = nil
        }

        deinit {
            if let token = readyObserver {
                NotificationCenter.default.removeObserver(token)
            }
            if let token = shutdownObserver {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }
}

// Type-erased dispatch so the wrapper works for Bool, String, Int, and Double.
// Named CoproductFlagValue to avoid colliding with the generated FlagValue enum.
//
// These resolve the default instance once and observe against it directly rather
// than routing through Coproduct.observe, whose requireDefault would trap if a
// shutdown landed between the holder's guard and the call. With no instance they
// return a non-emitting stream so the holder keeps serving its default. The
// signature keeps the generated client out of the public surface
public protocol CoproductFlagValue: Sendable {
    static func observe(key: String, defaultValue: Self) -> AnyPublisher<Self, Never>
}

extension Bool: CoproductFlagValue {
    public static func observe(key: String, defaultValue: Bool) -> AnyPublisher<Bool, Never> {
        guard let client = Instances.shared.defaultInstance() else {
            return Empty(completeImmediately: false).eraseToAnyPublisher()
        }
        return client.observeBool(key: key, defaultValue: defaultValue).publisher
    }
}

extension String: CoproductFlagValue {
    public static func observe(key: String, defaultValue: String) -> AnyPublisher<String, Never> {
        guard let client = Instances.shared.defaultInstance() else {
            return Empty(completeImmediately: false).eraseToAnyPublisher()
        }
        return client.observeString(key: key, defaultValue: defaultValue).publisher
    }
}

extension Int: CoproductFlagValue {
    public static func observe(key: String, defaultValue: Int) -> AnyPublisher<Int, Never> {
        guard let client = Instances.shared.defaultInstance() else {
            return Empty(completeImmediately: false).eraseToAnyPublisher()
        }
        return client.observeInt(key: key, defaultValue: defaultValue).publisher
    }
}

extension Double: CoproductFlagValue {
    public static func observe(key: String, defaultValue: Double) -> AnyPublisher<Double, Never> {
        guard let client = Instances.shared.defaultInstance() else {
            return Empty(completeImmediately: false).eraseToAnyPublisher()
        }
        return client.observeNumber(key: key, defaultValue: defaultValue).publisher
    }
}
