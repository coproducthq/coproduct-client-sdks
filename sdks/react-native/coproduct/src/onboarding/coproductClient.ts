import type { OnboardingFlowGraph } from './models/onboardingFlowGraph';

// This package needs flag evaluation, sdkContext, and an onboarding-flow
// fetch from the base Coproduct React Native SDK. This contract defines
// that minimum surface.
//
// The base SDK's CoproductClient (in '@coproduct/react-native-sdk') has typed
// flag getters like getString and getJson. It has no onboarding-flow
// fetch. It has no direct read of device attributes or segment
// memberships.
//
// A host app bridges the gap with an adapter implementing this interface
// using the base SDK's public API. fetchOnboardingFlow can call
// HttpOnboardingClient (this same package) or a host's own edge-worker
// endpoint. sdkContextAttributes and sdkContextSegmentKeys are left to the
// host's own tracking -- the base SDK does not expose a read-back of its
// full evaluated context.
//
// This type's name matches the base SDK's CoproductClient class. Both
// describe the same concept from a different vantage point. A file that
// imports both needs an import alias, such as
// `import { CoproductClient as BaseCoproductClient } from '@coproduct/react-native-sdk';`.
// Mirrors sdks/flutter/coproduct/lib/src/onboarding/coproduct_client.dart.
export interface CoproductClient {
  // Resolves an ordinary flag to its current variation value for this
  // device, exactly the way any other flag resolves. For an onboarding
  // flow's pointing flag (a STRING flag), this returns the flowId --
  // nothing more. A flag never carries flow content, only this pointer.
  resolveStringFlag(flagKey: string): string | undefined;

  // Fetches the onboarding flow graph for a given flowId, independently of
  // flag resolution. Returns undefined if the flow can't be resolved for
  // this environment or the fetch fails.
  fetchOnboardingFlow(flowId: string): Promise<OnboardingFlowGraph | undefined>;

  // Device attribute values for targeting/transition evaluation (platform,
  // country, custom attributes, and so on).
  readonly sdkContextAttributes: Record<string, string | number | boolean>;

  // Segment keys this device currently matches.
  readonly sdkContextSegmentKeys: Set<string>;

  // Polls the server immediately and waits for that poll to settle, ahead
  // of the base SDK's own scheduled cadence. CoproductOnboardingFlow's
  // debug "Refresh" control calls this before re-fetching via
  // fetchOnboardingFlow, so a content edit is guaranteed visible on
  // refresh rather than only eventually.
  refresh(): Promise<void>;
}
