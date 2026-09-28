import Foundation
import Network

/// Connectivity facts one path update carries, apart from NWPath so a test can
/// fabricate them without the Network framework
struct NetworkPathFacts: Equatable {
    let satisfied: Bool
    let wifi: Bool
    let cellular: Bool
    let ethernet: Bool
}

/// Maps path facts to the network_type vocabulary with the same precedence as
/// the iOS SDK, so one physical network maps the same way in both. A VPN
/// surfaces through the interface beneath it, so it needs no rule of its own
enum NetworkTypeClassifier {
    static func classify(_ facts: NetworkPathFacts) -> String {
        guard facts.satisfied else { return "none" }
        if facts.wifi { return "wifi" }
        if facts.cellular { return "cellular" }
        if facts.ethernet { return "ethernet" }
        // Connected through something else, which is not offline
        return "other"
    }
}

/// One path monitor's lifetime: started once, cancelled once, never restarted
protocol NetworkPathSource: AnyObject {
    /// Delivers every path update on the main queue, which in practice starts
    /// with the current path
    func start(onUpdate: @escaping (NetworkPathFacts) -> Void)
    func cancel()
}

/// The framework adapter, kept to forwarding. A cancelled NWPathMonitor cannot
/// be restarted, so every listen gets a new one of these
final class NWPathSource: NetworkPathSource {
    private let monitor = NWPathMonitor()

    // A source released without a cancel still stops its monitor. Cancelling
    // twice is safe, so an explicit cancel before release costs nothing
    deinit {
        cancel()
    }

    func start(onUpdate: @escaping (NetworkPathFacts) -> Void) {
        monitor.pathUpdateHandler = { path in
            onUpdate(NetworkPathFacts(
                satisfied: path.status == .satisfied,
                wifi: path.usesInterfaceType(.wifi),
                cellular: path.usesInterfaceType(.cellular),
                ethernet: path.usesInterfaceType(.wiredEthernet)
            ))
        }
        // The main queue, which owns all of the observer's state
        monitor.start(queue: .main)
    }

    func cancel() {
        monitor.pathUpdateHandler = nil
        monitor.cancel()
    }
}
