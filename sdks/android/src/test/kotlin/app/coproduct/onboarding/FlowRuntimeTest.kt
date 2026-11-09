package app.coproduct.onboarding

import androidx.test.core.app.ApplicationProvider
import app.coproduct.onboarding.models.NextTarget
import app.coproduct.onboarding.models.OnboardingFlowGraph
import app.coproduct.onboarding.models.Screen
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import uniffi.coproduct_ffi_uniffi.ContextValue

private class FakeClient : CoproductClient {
    override fun resolveStringFlag(flagKey: String): String? = null
    override suspend fun fetchOnboardingFlow(flowId: String): OnboardingFlowGraph? = null
    override val sdkContextAttributes: Map<String, ContextValue> = emptyMap()
    override val sdkContextSegmentKeys: Set<String> = emptySet()
    override suspend fun refresh() {}
}

@RunWith(RobolectricTestRunner::class)
class FlowRuntimeTest {
    private val graph = OnboardingFlowGraph(
        "s1",
        listOf(Screen("s1", "<p/>", emptyList(), NextTarget.CompleteTarget, null)),
    )

    @Test
    fun buildShellHtmlDelegatesToShellAssemblerWithTheClientsSdkContext() {
        val runtime = FlowRuntime(FakeClient(), progressStore = LocalProgressStore(ApplicationProvider.getApplicationContext()), flowId = "f1", flowVersion = 1)
        val html = runtime.buildShellHtml(graph, "f1", "s1", emptyMap(), "")
        assertTrue(html.contains("""data-screen-id="s1""""))
    }

    @Test
    fun trackActionPersistsProgressBeforeTheCallback() = runTest {
        val progressStore = LocalProgressStore(ApplicationProvider.getApplicationContext())
        val order = mutableListOf<String>()
        val runtime = FlowRuntime(
            client = FakeClient(),
            progressStore = progressStore,
            flowId = "f1",
            flowVersion = 1,
            onEvent = { _, _, _ ->
                // If progress weren't persisted yet, this would observe null.
                order.add(if (progressStore.load("f1") != null) "persist-then-callback" else "callback-before-persist")
            },
        )
        runtime.handleNavigationRequest("coproduct-action:track?event=e&screenId=s1")
        assertEquals(listOf("persist-then-callback"), order)
    }

    @Test
    fun trackActionReturnsPreventRegardlessOfCallbackResult() = runTest {
        val runtime = FlowRuntime(FakeClient(), progressStore = LocalProgressStore(ApplicationProvider.getApplicationContext()), flowId = "f1", flowVersion = 1)
        val decision = runtime.handleNavigationRequest("coproduct-action:track?event=e&screenId=s1")
        assertEquals(FlowNavigationDecision.PREVENT, decision)
    }

    @Test
    fun aNonActionUrlReturnsNavigate() = runTest {
        val runtime = FlowRuntime(FakeClient(), progressStore = LocalProgressStore(ApplicationProvider.getApplicationContext()), flowId = "f1", flowVersion = 1)
        assertEquals(FlowNavigationDecision.NAVIGATE, runtime.handleNavigationRequest("https://example.com"))
    }

    @Test
    fun requestPermissionActionInvokesTheRequestPermissionFnAndInjectsTheResponse() = runTest {
        val injected = mutableListOf<Pair<String, Map<String, String>>>()
        val runtime = FlowRuntime(
            client = FakeClient(),
            progressStore = LocalProgressStore(ApplicationProvider.getApplicationContext()),
            requestPermission = { permission -> mapOf("status" to "granted", "permission" to permission) },
        )
        runtime.attachResolver { requestId, response -> injected.add(requestId to response) }
        runtime.handleNavigationRequest("coproduct-action:request?operation=requestPermission&requestId=r1&param_permission=camera")
        assertEquals(listOf("r1" to mapOf("status" to "granted", "permission" to "camera")), injected)
    }

    @Test
    fun anUnhandledRequestOperationInjectsAnErrorResponse() = runTest {
        val injected = mutableListOf<Pair<String, Map<String, String>>>()
        val runtime = FlowRuntime(client = FakeClient(), progressStore = LocalProgressStore(ApplicationProvider.getApplicationContext()))
        runtime.attachResolver { requestId, response -> injected.add(requestId to response) }
        runtime.handleNavigationRequest("coproduct-action:request?operation=fetchCoupon&requestId=r1")
        assertEquals("error", injected.single().second["status"])
    }

    @Test
    fun requestPermissionWithNoRequesterConfiguredInjectsAConfigurationError() = runTest {
        val injected = mutableListOf<Pair<String, Map<String, String>>>()
        val runtime = FlowRuntime(client = FakeClient(), progressStore = LocalProgressStore(ApplicationProvider.getApplicationContext()), requestPermission = null)
        runtime.attachResolver { requestId, response -> injected.add(requestId to response) }
        runtime.handleNavigationRequest("coproduct-action:request?operation=requestPermission&requestId=r1&param_permission=camera")
        assertEquals("No permission requester configured", injected.single().second["message"])
    }

    @Test
    fun aThrowingNativeOperationHandlerInjectsAnErrorResponseInsteadOfPropagating() = runTest {
        val injected = mutableListOf<Pair<String, Map<String, String>>>()
        val runtime = FlowRuntime(
            client = FakeClient(),
            progressStore = LocalProgressStore(ApplicationProvider.getApplicationContext()),
            onNativeOperation = { _, _ -> throw RuntimeException("boom") },
        )
        runtime.attachResolver { requestId, response -> injected.add(requestId to response) }
        runtime.handleNavigationRequest("coproduct-action:request?operation=fetchCoupon&requestId=r1")
        assertEquals("error", injected.single().second["status"])
        assertTrue(injected.single().second["message"]!!.contains("boom"))
    }
}
