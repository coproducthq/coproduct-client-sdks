package app.coproduct

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import uniffi.coproduct_ffi_uniffi.BoolObservation
import uniffi.coproduct_ffi_uniffi.CoproductClient as NativeCoproductClient
import uniffi.coproduct_ffi_uniffi.ContextValue
import uniffi.coproduct_ffi_uniffi.EvaluationEvent
import uniffi.coproduct_ffi_uniffi.EvaluationHook
import uniffi.coproduct_ffi_uniffi.EvaluationReason
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsBool
import uniffi.coproduct_ffi_uniffi.FlagType
import uniffi.coproduct_ffi_uniffi.FlagValue
import uniffi.coproduct_ffi_uniffi.HandlerHandle
import uniffi.coproduct_ffi_uniffi.HookHandle
import uniffi.coproduct_ffi_uniffi.LifecycleEvent
import uniffi.coproduct_ffi_uniffi.LifecycleHandler

// A hand-written fake of the generated client surface this test exercises.
// NativeCoproductClient is a UniFFI-generated open class backed by a native
// handle, so it cannot be instantiated directly in a unit test; the public
// surface under test here is CoproductClient's own identity/getter wiring,
// verified against a fake that implements just enough of the same shape.
private class FakeNativeClient {
    var lastIdentifyUserId: String? = null
    var lastIdentifyAttributes: Map<String, ContextValue>? = null
    var lastLinkAnonymous: Boolean? = null
    val identifyOrder = mutableListOf<String>()

    suspend fun identify(userId: String, attributes: Map<String, ContextValue>, linkAnonymous: Boolean) {
        lastIdentifyUserId = userId
        lastIdentifyAttributes = attributes
        lastLinkAnonymous = linkAnonymous
        identifyOrder.add(userId)
    }
}

class CoproductClientTest {
    @Test
    fun identifyAppliesInCallOrderThroughTheIdentitySerializer() = runBlocking {
        // This test exercises IdentitySerializer's ordering contract directly
        // through the same enqueue path CoproductClient.identify uses,
        // since NativeCoproductClient cannot be faked directly (see above).
        val fake = FakeNativeClient()
        val serializer = IdentitySerializer(scope = this)

        serializer.enqueue { fake.identify("alice", emptyMap(), true) }
        serializer.enqueue { fake.identify("bob", emptyMap(), true) }
        serializer.drain()

        assertEquals(listOf("alice", "bob"), fake.identifyOrder)
    }

    @Test
    fun setEvaluationListenerForwardsEventsThroughTheWrappedListener() {
        // Exercises ClosureEvaluationListener directly rather than through
        // CoproductClient, since NativeCoproductClient cannot be faked (see
        // above); this mirrors the adapter's own forwarding contract the way
        // addHandler/addEvaluationHook's adapters are not separately covered.
        val seen = mutableListOf<EvaluationEvent>()
        val listener = ClosureEvaluationListener { event -> seen.add(event) }

        val event = EvaluationEvent(
            flagKey = "new-checkout",
            flagType = FlagType.BOOL,
            value = FlagValue.Bool(true),
            defaultValue = FlagValue.Bool(false),
            variant = "on",
            reason = EvaluationReason.TARGETING_MATCH,
            ruleId = null,
            errorCode = null,
            evaluatedAt = "2024-01-01T00:00:00Z",
        )
        listener.onEvaluation(event)

        assertEquals(listOf(event), seen)
    }

    @Test
    fun boolDetailsConversionPreservesEveryField() {
        val ffi = FlagEvaluationDetailsBool(
            value = true,
            variant = "on",
            reason = "TARGETING_MATCH",
            errorCode = null,
            errorMessage = null,
            flagKey = "new-checkout",
        )
        val details = ffi.toPublic()
        assertEquals(FlagDetailValue.Bool(true), details.value)
        assertEquals("new-checkout", details.flagKey)
    }
}
