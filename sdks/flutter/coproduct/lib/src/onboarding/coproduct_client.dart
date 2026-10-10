import 'models/onboarding_flow_graph.dart';

/// This package needs flag evaluation, sdkContext, and an onboarding-flow
/// fetch from the base Coproduct Flutter SDK. This contract defines that
/// minimum surface.
///
/// The base SDK does not implement this contract. Its `CoproductClient`
/// (in `package:coproduct`) has typed flag getters like `getString` and
/// `getJson`. It has no onboarding-flow fetch. It has no direct read of
/// device attributes or segment memberships.
///
/// A host app bridges the gap with an adapter. The adapter implements
/// [CoproductClient] using the base SDK's public API. For example,
/// [fetchOnboardingFlow] can call edge-worker's
/// `/v1/onboarding-flows/:flowId` over HTTP. It can reuse the base SDK's
/// SDK key and base URL. [sdkContextAttributes] and
/// [sdkContextSegmentKeys] can read from the base SDK's evaluated context.
/// This package does not ship that adapter.
///
/// This type's name matches the base SDK's `CoproductClient` class. Both
/// describe the same concept from a different vantage point. A file that
/// imports both packages needs an import alias, such as
/// `import 'package:coproduct/coproduct.dart' as base;`.
abstract interface class CoproductClient {
  /// Resolves an ordinary flag to its current variation value for this
  /// device, exactly the way any other flag resolves. For an onboarding
  /// flow's pointing flag (a STRING flag), this returns the flowId --
  /// nothing more. A flag never carries flow content, only this pointer.
  String? resolveStringFlag(String flagKey);

  /// Fetches the onboarding flow graph for a given flowId, independently of
  /// flag resolution: this is a live request (edge-worker's
  /// `/v1/onboarding-flows/:flowId`, cached with a short TTL, not pushed on
  /// deploy) resolving to whichever version this environment is pinned to,
  /// or HEAD when unpinned -- the device never needs to know a pin exists.
  /// Returns null if the flow can't be resolved for this environment (not
  /// reachable, not deployed yet) or the fetch fails.
  Future<OnboardingFlowGraph?> fetchOnboardingFlow(String flowId);

  /// Device attribute values for targeting/transition evaluation (platform,
  /// country, custom attributes, and so on).
  Map<String, Object> get sdkContextAttributes;

  /// Segment keys this device currently matches.
  Set<String> get sdkContextSegmentKeys;

  /// Polls the server immediately and waits for that poll to settle, ahead
  /// of the base SDK's own scheduled cadence. [CoproductOnboardingFlow]'s
  /// debug "Refresh" control calls this before re-fetching via
  /// [fetchOnboardingFlow], so a content edit is guaranteed visible on
  /// refresh rather than only eventually, whenever the next scheduled poll
  /// happens to land
  Future<void> refresh();
}
