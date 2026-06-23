// Compiled (not executed) to prove the typed observer, lifecycle handler,
// evaluation hook, and evaluation listener traits exported over UniFFI can be
// satisfied from Swift, and that the registration entry points and shutdown are
// reachable with the expected call shapes and case spellings. If this
// typechecks, the lifecycle and observer binding surface is correct

import Foundation

private final class SmokeFlagObserver: FlagObserver, @unchecked Sendable {
    func onChange(key: String, value: FlagValue) async throws {
        switch value {
        case let .bool(value): _ = value
        case let .string(value): _ = value
        case let .int(value): _ = value
        case let .number(value): _ = value
        case let .json(value): _ = value
        }
        _ = key
    }
}

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
    let observer = SmokeFlagObserver()
    let single: Subscription = client.observeKey(key: "flag", observer: observer)
    let multi: Subscription = client.observeKeys(keys: ["a", "b"], observer: observer)
    let _: UInt64 = single.id()
    let _: [String] = multi.keys()
    let _: Bool = single.isCancelled()
    single.cancel()
    multi.cancel()

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

    await client.shutdown()
}
