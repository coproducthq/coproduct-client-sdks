import 'models/onboarding_flow_graph.dart';

/// The minimum this package needs from the base Coproduct Flutter SDK
/// (flag evaluation, sdkContext, an onboarding-flow-content fetch) to drive
/// an onboarding flow.
///
/// The base SDK (`package:coproduct`) does not implement this contract
/// today: its own `CoproductClient` exposes typed flag getters
/// (`getString`, `getJson`, ...) but no onboarding-flow fetch and no direct
/// read of the device's attributes/segment memberships. A host app wires
/// this package to the base SDK through an adapter that implements
/// [CoproductClient] in terms of the base SDK's public API (for example,
/// implementing [fetchOnboardingFlow] as an authenticated HTTP GET against
/// edge-worker's `/v1/onboarding-flows/:flowId`, using whatever SDK key and
/// base URL the base SDK already holds for its own snapshot polling, and
/// reading [sdkContextAttributes]/[sdkContextSegmentKeys] from whatever the
/// base SDK exposes for the evaluated context). That adapter is not built
/// by this package.
///
/// This type's name intentionally matches the base SDK's own
/// `CoproductClient` class, since both describe the same underlying
/// concept from each package's own vantage point. A file importing both
/// packages needs an import alias to disambiguate
/// (`import 'package:coproduct/coproduct.dart' as base;`).
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
