import Foundation

/// The flag-resolution, identity-context, and flow-fetch surface
/// `CoproductOnboardingFlow`/`FlowRuntime` drive. A protocol, not a
/// concrete type, so a host app with its own targeting-attribute or
/// segment tracking can supply a custom implementation; ``DefaultCoproductClient``
/// is the implementation most apps need, requiring no adapter code.
public protocol CoproductClient: Sendable {
    /// Resolves an ordinary string flag to its current variation value for
    /// this device, exactly the way any other flag resolves. For an
    /// onboarding flow's pointing flag, this returns the flowId -- nothing
    /// more. Returns `nil` when the flag is missing, errored, or the SDK is
    /// not ready.
    func resolveStringFlag(_ flagKey: String) -> String?

    /// Fetches the onboarding flow graph for a given flowId, independently
    /// of flag resolution. Returns `nil` if the flow can't be resolved for
    /// this environment or the fetch fails.
    func fetchOnboardingFlow(_ flowId: String) async -> OnboardingFlowGraph?

    /// Device attribute values for targeting/transition evaluation.
    var sdkContextAttributes: [String: AttributeValue] { get }

    /// Segment keys this device currently matches.
    var sdkContextSegmentKeys: Set<String> { get }

    /// Polls the server immediately and waits for that poll to settle,
    /// ahead of the SDK's own scheduled cadence. The debug "Refresh"
    /// control calls this before re-fetching, so a content edit is
    /// guaranteed visible on refresh rather than only eventually.
    func refresh() async
}
