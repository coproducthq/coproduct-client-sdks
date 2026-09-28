import Flutter

/// Streams network_type to Dart. Every listen starts a fresh monitor, which
/// produces the current value, so the Dart side rechecks by listening again
/// rather than by asking. All state is main-thread only: the channel has no
/// task queue and the monitor delivers on the main queue
final class NetworkTypeObserver: NSObject, FlutterStreamHandler {
    static let invalidEpoch = "invalid-epoch"

    /// One listen. Only the observer holds it, so a cancelled or replaced
    /// listen is released and its late updates find nothing. The identity
    /// check also drops an update delivered while the listen is being
    /// cancelled, which an iOS event sink would otherwise accept
    private final class Listening {
        let epoch: Int64
        let sink: FlutterEventSink
        let source: NetworkPathSource

        init(epoch: Int64, sink: @escaping FlutterEventSink, source: NetworkPathSource) {
            self.epoch = epoch
            self.sink = sink
            self.source = source
        }
    }

    private let makeSource: () -> NetworkPathSource
    private var active: Listening?

    init(makeSource: @escaping () -> NetworkPathSource = { NWPathSource() }) {
        self.makeSource = makeSource
        super.init()
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        // Replacing a listen that is still active is this observer's own
        // guarantee. A hot restart relistens without a Dart cancel, and the
        // observer does not rely on the embedding cancelling first
        cancel()
        guard let epoch = Self.epoch(from: arguments) else {
            // Sent on the stream rather than returned, the one path the Dart
            // side reads observation failures from
            events(FlutterError(
                code: Self.invalidEpoch,
                message: "network_type listen needs an integer epoch",
                details: nil
            ))
            return nil
        }
        let listening = Listening(epoch: epoch, sink: events, source: makeSource())
        active = listening
        listening.source.start { [weak self, weak listening] facts in
            // Debug builds only, so a threading slip cannot crash a release app
            assert(Thread.isMainThread, "network path updates must arrive on the main thread")
            guard let self, let listening, self.active === listening else { return }
            listening.sink([
                "epoch": NSNumber(value: listening.epoch),
                "value": NetworkTypeClassifier.classify(facts),
            ])
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        cancel()
        return nil
    }

    /// Idempotent, so a cancel and an engine detachment in either order are safe
    func cancel() {
        guard let listening = active else { return }
        active = nil
        listening.source.cancel()
    }

    /// The standard codec delivers a Dart int as an integer NSNumber. A Bool
    /// or a fractional number is not an epoch
    static func epoch(from arguments: Any?) -> Int64? {
        guard let number = arguments as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number) else { return nil }
        return number.int64Value
    }
}
