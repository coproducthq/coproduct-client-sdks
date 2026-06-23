// Compiled (not executed) to prove the provider-state accessor and the poll
// entry point exported over UniFFI are reachable from Swift with the expected
// call shape, and that the lifecycle enums expose every case. If this
// typechecks, the binding surface is correct

import Foundation

func proveLifecycleSurfaceCompiles(client: CoproductClient) async {
    let state: ProviderState = client.state()
    let outcome: PollOutcome = await client.pollNow()

    switch state {
    case .notReady: break
    case .ready: break
    case .reconciling: break
    case .retrying: break
    case .stale: break
    case .fatal: break
    }

    switch outcome {
    case .updated: break
    case .notModified: break
    case .fatal: break
    case .retrying: break
    case .rateLimited(let retryAfterSecs):
        let _: UInt64 = retryAfterSecs
    case .stale: break
    case .dedupedSkipped: break
    }
}
