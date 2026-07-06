import Coproduct
import OSLog
import SwiftUI

private let consumerLogger = Logger(
    subsystem: "app.coproduct.consumer.ios",
    category: "ConsumerStatus"
)

// Artifact-linked consumer test. Exercises the public surface
// against the packaged release fixture, using the default host implementations
// (URLSessionTransport plus KeychainSecureStore). No live server is required.
// The canonical status line is emitted via public OSLog so the build gate and
// manual verification can grep it from the simulator log stream
struct ContentView: View {
    @CoproductFlag("new-checkout", default: false) var newCheckout: Bool

    @State private var ready = false
    @State private var state: ProviderState = .notReady
    @State private var snapshotVersion: UInt64 = 0
    @State private var flagValue = false
    @State private var observerRegistered = false
    @State private var observation: FlagObservation<Bool>?

    var body: some View {
        VStack(spacing: 12) {
            Text("Coproduct iOS consumer")
                .font(.title)
            Text("SDK ready: \(ready ? "yes" : "no")")
            Text("state: \(String(describing: state))")
            Text("snapshot.version: \(snapshotVersion)")
            Text("new-checkout = \(newCheckout ? "on" : "off")")
            Text("getBool: \(flagValue ? "true" : "false")")
            Text("Observer registered: \(observerRegistered ? "yes" : "no")")
            Button("identify('alice')") {
                Coproduct.identify(userId: "alice")
                state = Coproduct.state
            }
        }
        .padding()
        .task {
            guard !ready else { return }

            do {
                try await Coproduct.initialize(sdkKey: "cpk_mob_0123456789abcdefghjkmnpqrstvwxyz")
                ready = true
            } catch {
                state = .fatal
                consumerLogger.notice(
                    "COPRODUCT_IOS_CONSUMER_STATUS ready=false state=fatal getBool=false observerRegistered=false"
                )
                return
            }

            state = Coproduct.state
            snapshotVersion = Coproduct.snapshot.version
            flagValue = Coproduct.getBool("new-checkout", default: false)

            let obs = Coproduct.observe("new-checkout", default: false)
            observation = obs
            observerRegistered = true

            let statusLine = "COPRODUCT_IOS_CONSUMER_STATUS ready=\(ready) state=\(String(describing: state)) getBool=\(flagValue) observerRegistered=\(observerRegistered)"
            consumerLogger.notice("\(statusLine, privacy: .public)")
        }
    }
}

#Preview {
    ContentView()
}
