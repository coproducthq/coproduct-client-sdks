import 'models/onboarding_flow_graph.dart';

/// The minimum this package needs from the base Coproduct Flutter SDK
/// (flag evaluation, sdkContext, the cached environment snapshot) to drive
/// an onboarding flow.
///
/// The base SDK (`package:coproduct`) does not implement this contract
/// today: its own `CoproductClient` exposes typed flag getters
/// (`getString`, `getJson`, ...) but no onboarding-flow-graph accessor and
/// no direct read of the device's attributes/segment memberships. A host
/// app wires this package to the base SDK through an adapter that
/// implements [CoproductClient] in terms of the base SDK's public API
/// (for example, resolving [onboardingFlowGraph] from a JSON flag payload
/// and reading [sdkContextAttributes]/[sdkContextSegmentKeys] from whatever
/// the base SDK exposes for the evaluated context). That adapter is not
/// built by this package.
///
/// This type's name intentionally matches the base SDK's own
/// `CoproductClient` class, since both describe the same underlying
/// concept from each package's own vantage point. A file importing both
/// packages needs an import alias to disambiguate
/// (`import 'package:coproduct/coproduct.dart' as base;`).
abstract interface class CoproductClient {
  /// Resolves an ordinary flag to its current variation value for this
  /// device, exactly the way any other flag resolves. For an onboarding
  /// flow's pointing flag (a STRING flag), this returns the flowId.
  String? resolveStringFlag(String flagKey);

  /// The onboarding flow graph for a given flowId, already resolved from the
  /// cached environment snapshot to the correct version (HEAD, or an
  /// environment's pin, resolved server-side at snapshot-build time; the
  /// device never needs to know a pin exists).
  OnboardingFlowGraph? onboardingFlowGraph(String flowId);

  /// Device attribute values for targeting/transition evaluation (platform,
  /// country, custom attributes, and so on).
  Map<String, Object> get sdkContextAttributes;

  /// Segment keys this device currently matches.
  Set<String> get sdkContextSegmentKeys;
}
