import Coproduct
import SwiftUI

struct ContentView: View {
    @State private var client: CoproductClient?
    @State private var subscription: Cancellable?
    @State private var ready = false
    @State private var hostCallbacks = false
    @State private var loadedFromCache = false
    @State private var flagValue = false
    @State private var observerFired = false

    var body: some View {
        VStack(spacing: 12) {
            Text("SDK ready: \(ready ? "yes" : "no")")
            Text("Host callbacks: \(hostCallbacks ? "yes" : "no")")
            Text("Loaded from cache: \(loadedFromCache ? "yes" : "no")")
            Text("getBool('test-flag'): \(flagValue ? "true" : "false")")
            Text("Observer fired: \(observerFired ? "yes" : "no")")
        }
        .padding()
        .task {
            guard client == nil else {
                return
            }

            let c = try? await Coproduct.initialize(sdkKey: "cpk_mob_test_scaffold")
            client = c
            ready = c != nil
            hostCallbacks = MockTransport.requestCount == 1 && MockSecureStore.completedHandshake
            loadedFromCache = c?.wasLoadedFromCache() ?? false
            flagValue = c?.getBool("test-flag", default: false) ?? false
            subscription = c?.observe("test-flag", default: false) { _ in
                Task { @MainActor in
                    observerFired = true
                }
            }

            await c?.simulateChange(key: "test-flag", newValue: true)
            await Task.yield()
            NSLog(
                "COPRODUCT_IOS_DEMO_STATUS ready=\(ready) hostCallbacks=\(hostCallbacks) loadedFromCache=\(loadedFromCache) flagValue=\(flagValue) observerFired=\(observerFired)"
            )
        }
    }
}

#Preview {
    ContentView()
}
