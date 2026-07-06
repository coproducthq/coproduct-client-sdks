import Coproduct
import SwiftUI

// Source-linked demo. Exercises the public surface against the
// default host implementations (URLSessionTransport plus KeychainSecureStore).
// No live server is required to build and link. The demo reads a few flags via
// the typed getters, reflects provider state, and drives the identity lifecycle
struct ContentView: View {
    @CoproductFlag("new-checkout", default: false) var newCheckout: Bool
    @CoproductFlag("welcome-msg", default: "Hello") var welcome: String
    @CoproductFlag("page-size", default: 20) var pageSize: Int

    @State private var ready = false
    @State private var state: ProviderState = .notReady
    @State private var detailReason: String = "-"
    @State private var multiplier: Double = 1.0
    @State private var observerRegistered = false
    @State private var observation: FlagObservation<Bool>?
    @State private var loggedIn = false

    var body: some View {
        VStack(spacing: 12) {
            Text("SDK ready: \(ready ? "yes" : "no")")
            Text("State: \(String(describing: state))").font(.caption)

            Text(welcome).font(.title)

            Toggle("new-checkout (live)", isOn: .constant(newCheckout)).disabled(true)
            Text("page-size: \(pageSize)")
            Text("getNumber('multiplier'): \(multiplier)")
            Text("detail.reason: \(detailReason)")
            Text("Observer registered: \(observerRegistered ? "yes" : "no")")

            Button(loggedIn ? "Sign out" : "Identify as alice") {
                if loggedIn {
                    Coproduct.signOut()
                } else {
                    Coproduct.identify(userId: "alice")
                }
                loggedIn.toggle()
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
                return
            }

            state = Coproduct.state
            let flagValue = Coproduct.getBool("new-checkout", default: false)
            multiplier = Coproduct.getNumber("multiplier", default: 1.0)
            detailReason = String(describing: Coproduct.getBoolDetails("new-checkout", default: false).reason)

            let obs = Coproduct.observe("new-checkout", default: false)
            observation = obs
            observerRegistered = true

            NSLog(
                "COPRODUCT_IOS_DEMO_STATUS ready=\(ready) state=\(String(describing: state)) getBool=\(flagValue) observerRegistered=\(observerRegistered)"
            )
        }
    }
}

#Preview {
    ContentView()
}
