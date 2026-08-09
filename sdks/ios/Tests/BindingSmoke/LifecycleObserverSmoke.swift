// Compiled (not executed) to prove the lifecycle handler, evaluation hook, and
// evaluation listener traits exported over UniFFI can be satisfied from Swift,
// and that the registration entry points, the typed and bundle observations, and
// shutdown are reachable with the expected call shapes and case spellings. If
// this typechecks, the lifecycle handler, evaluation hook, evaluation listener,
// and observation binding surface is correct

import Foundation

private final class SmokeLifecycleHandler: LifecycleHandler, @unchecked Sendable {
    func onEvent(event: LifecycleEvent) async {
        switch event {
        case .ready: break
        case .configurationChanged: break
        case .contextChanged: break
        case .reconciling: break
        case .retrying: break
        case .stale: break
        case .fatal: break
        }
    }
}

private final class SmokeEvaluationHook: EvaluationHook, @unchecked Sendable {
    func onStage(stage: EvaluationStage, ctx: HookContext) {
        switch stage {
        case .before: break
        case .after: break
        case .error: break
        case .finally: break
        }
        let _: String = ctx.flagKey
        let _: FlagType = ctx.flagType
        let _: FlagValue = ctx.defaultValue
        let _: FlagValue? = ctx.value
        let _: String? = ctx.errorCode
    }
}

private final class SmokeEvaluationListener: EvaluationListener, @unchecked Sendable {
    func onEvaluation(event: EvaluationEvent) {
        let _: String = event.flagKey
        let _: FlagType = event.flagType
        let _: FlagValue = event.value
        let _: FlagValue = event.defaultValue
        let _: String? = event.variant
        let _: EvaluationReason = event.reason
        let _: String? = event.ruleId
        let _: String? = event.errorCode
        let _: String = event.evaluatedAt
    }
}

func proveLifecycleObserverSurfaceCompiles(client: CoproductClient) async {
    let handle: HandlerHandle = client.addHandler(
        event: .ready,
        handler: SmokeLifecycleHandler()
    )
    let _: UInt64 = handle.id()
    let _: Bool = handle.isCancelled()
    handle.cancel()

    let hookHandle: HookHandle = client.addEvaluationHook(hook: SmokeEvaluationHook())
    let _: UInt64 = hookHandle.id()
    let _: Bool = hookHandle.isCancelled()
    hookHandle.cancel()

    client.setEvaluationListener(listener: SmokeEvaluationListener())

    let single: BoolObservation = client.observeBool(key: "flag")
    let _: Bool? = single.seed()
    switch await single.pollNext() {
    case let .value(revision, value):
        let _: UInt64 = revision
        let _: Bool? = value
    case .closed: break
    }
    let _: [String] = single.keys()
    let _: Bool = single.isCancelled()
    single.cancel()

    let bundle: BundleObservation = client.observeBundle(keys: ["a", "b"])
    let _: [String: FlagValue?] = bundle.seed()
    switch await bundle.pollNext() {
    case let .value(revision, values):
        let _: UInt64 = revision
        let _: [String: FlagValue?] = values
    case .closed: break
    }
    bundle.cancel()

    await client.shutdown()
}
