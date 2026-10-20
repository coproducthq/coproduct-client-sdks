package app.coproduct.onboarding

import app.coproduct.onboarding.models.OnboardingFlowGraph
import uniffi.coproduct_ffi_uniffi.ContextValue

// This package needs flag evaluation, sdkContext, and an onboarding-flow
// fetch from the base Coproduct Android SDK. This contract defines that
// minimum surface. The base SDK's own CoproductClient (in the parallel
// android-flags-parity plan) has typed flag getters like getString and
// getJson, but no onboarding-flow fetch and no direct read of device
// attributes or segment memberships. A host app bridges the gap with an
// adapter implementing this interface. This package does not ship that
// adapter. Mirrors
// sdks/flutter/coproduct/lib/src/onboarding/coproduct_client.dart and
// sdks/react-native/coproduct/src/onboarding/coproductClient.ts.
interface CoproductClient {
    // Resolves an ordinary flag to its current variation value for this
    // device, exactly the way any other flag resolves. For an onboarding
    // flow's pointing flag (a STRING flag), this returns the flowId --
    // nothing more. A flag never carries flow content, only this pointer.
    fun resolveStringFlag(flagKey: String): String?

    // Fetches the onboarding flow graph for a given flowId, independently
    // of flag resolution. Returns null if the flow can't be resolved for
    // this environment or the fetch fails.
    suspend fun fetchOnboardingFlow(flowId: String): OnboardingFlowGraph?

    // Device attribute values for targeting/transition evaluation.
    val sdkContextAttributes: Map<String, ContextValue>

    // Segment keys this device currently matches.
    val sdkContextSegmentKeys: Set<String>

    // Polls the server immediately and waits for that poll to settle, ahead
    // of the base SDK's own scheduled cadence. CoproductOnboardingFlow's
    // debug "Refresh" control calls this before re-fetching via
    // fetchOnboardingFlow.
    suspend fun refresh()
}
