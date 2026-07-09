import Foundation
import Network

// Connectivity facts one path update carries, decoupled from NWPath so tests
// can fabricate updates without the Network framework
struct NetworkPathFacts {
    let satisfied: Bool
    let wifi: Bool
    let cellular: Bool
    let ethernet: Bool
}

// Source of connectivity facts. Production wraps NWPathMonitor. Tests inject a
// fake through NetworkMonitor.sourceOverrideForTesting so an integration test
// can drive a live network change through initialize end to end. Implementations
// must deliver updates serially: one at a time, in order, never overlapping or
// reordered. NetworkMonitor's dedup relies on that contract rather than
// synchronizing dedup and delivery as a single atomic step
protocol NetworkPathSource: AnyObject {
    func start(onUpdate: @escaping (NetworkPathFacts) -> Void)
    func cancel()
}

// Thin adapter over NWPathMonitor, deliberately logic-free: everything worth
// testing lives behind the NetworkPathSource seam
final class NWPathSource: NetworkPathSource {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.coproduct.network-monitor")

    func start(onUpdate: @escaping (NetworkPathFacts) -> Void) {
        monitor.pathUpdateHandler = { path in
            onUpdate(NetworkPathFacts(
                satisfied: path.status == .satisfied,
                wifi: path.usesInterfaceType(.wifi),
                cellular: path.usesInterfaceType(.cellular),
                ethernet: path.usesInterfaceType(.wiredEthernet)
            ))
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}

// Maps path facts to the network_type vocabulary. Pure so the vocabulary and
// precedence order are unit-testable in isolation
enum NetworkTypeClassifier {
    static func classify(satisfied: Bool, wifi: Bool, cellular: Bool, ethernet: Bool) -> String {
        guard satisfied else { return "none" }
        if wifi { return "wifi" }
        if cellular { return "cellular" }
        if ethernet { return "ethernet" }
        return "other"
    }
}

// Watches connectivity and reports the classified network_type on every value
// change. The attribute is absent until the first path callback: initialize is
// never blocked on the monitor, reads in that window fall through
// conservatively, and the observer fanout corrects values when the first
// callback lands
final class NetworkMonitor {
    // Test seam consulted at initialize: when set, the wrapper builds the
    // monitor over this source instead of NWPathMonitor. Tests write this from
    // the main actor while initialize can read it from an arbitrary executor,
    // so the storage is lock-guarded rather than a bare static
    private static var _sourceOverrideForTesting: NetworkPathSource?
    private static let overrideLock = NSLock()

    static var sourceOverrideForTesting: NetworkPathSource? {
        get {
            overrideLock.lock()
            defer { overrideLock.unlock() }
            return _sourceOverrideForTesting
        }
        set {
            overrideLock.lock()
            defer { overrideLock.unlock() }
            _sourceOverrideForTesting = newValue
        }
    }

    private let source: NetworkPathSource
    private let onChange: (String) -> Void
    private var lastReported: String?
    private let lock = NSLock()

    init(source: NetworkPathSource, onChange: @escaping (String) -> Void) {
        self.source = source
        self.onChange = onChange
    }

    func start() {
        source.start { [weak self] facts in
            guard let self else { return }
            self.deliver(NetworkTypeClassifier.classify(
                satisfied: facts.satisfied,
                wifi: facts.wifi,
                cellular: facts.cellular,
                ethernet: facts.ethernet
            ))
        }
    }

    func cancel() {
        source.cancel()
    }

    // Deduplicates so path churn that lands on the same classification does not
    // enqueue redundant upserts. The core also stays silent on a no-op, this
    // just avoids the crossing. The dedup check and the onChange call below are
    // not atomic with each other. Correctness depends on the source honoring
    // the NetworkPathSource contract of serial, in-order delivery, so two
    // updates can never race each other into this method
    private func deliver(_ type: String) {
        lock.lock()
        let changed = lastReported != type
        if changed { lastReported = type }
        lock.unlock()
        if changed { onChange(type) }
    }
}
