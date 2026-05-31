import Coproduct
import OSLog
import SwiftUI

private let consumerLogger = Logger(
    subsystem: "app.coproduct.consumer.ios",
    category: "ConsumerStatus"
)

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
            Text("Coproduct iOS scaffold")
                .font(.title)
            Text("SDK ready: \(ready ? "yes" : "no")")
            Text("Host callbacks: \(hostCallbacks ? "yes" : "no")")
            Text("Loaded from cache: \(loadedFromCache ? "yes" : "no")")
            Text("getBool: \(flagValue ? "true" : "false")")
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
            let statusLine = "COPRODUCT_IOS_CONSUMER_STATUS ready=\(ready) hostCallbacks=\(hostCallbacks) loadedFromCache=\(loadedFromCache) getBool=\(flagValue) observerFired=\(observerFired)"
            consumerLogger.notice("\(statusLine, privacy: .public)")
        }
    }
}

#Preview {
    ContentView()
}
