package app.coproduct.onboarding

import app.coproduct.onboarding.models.NextTarget
import app.coproduct.onboarding.models.OnboardingFlowGraph
import app.coproduct.onboarding.models.Screen
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.coproduct_ffi_uniffi.ContextValue

class ShellAssemblerTest {
    private fun emptyCondition(): JsonObject = Json.parseToJsonElement("{}") as JsonObject

    @Test
    fun embedsEveryScreenAsADataScreenIdSection() {
        val graph = OnboardingFlowGraph(
            startScreenId = "welcome",
            screens = listOf(
                Screen("welcome", "<h1>Hi</h1>", emptyList(), NextTarget.ScreenTarget("goal"), null),
                Screen("goal", "<h1>Goal?</h1>", emptyList(), NextTarget.CompleteTarget, null),
            ),
        )
        val html = ShellAssembler.assemble(graph, emptyMap(), emptySet(), emptyMap(), "welcome", "")

        assertTrue(html.contains("""<section data-screen-id="welcome" hidden><h1>Hi</h1></section>"""))
        assertTrue(html.contains("""<section data-screen-id="goal" hidden><h1>Goal?</h1></section>"""))
    }

    @Test
    fun escapesLiteralClosingScriptTagsInsideTheDataBlob() {
        val graph = OnboardingFlowGraph(
            startScreenId = "s1",
            screens = listOf(Screen("s1", "<p>Hi</p>", emptyList(), NextTarget.CompleteTarget, null)),
        )
        val html = ShellAssembler.assemble(
            graph,
            mapOf("evil" to ContextValue.String("</script><script>alert(1)</script>")),
            emptySet(),
            emptyMap(),
            "s1",
            "",
        )

        assertFalse(html.contains("</script><script>alert(1)"))
        assertTrue(html.contains("<\\/script><script>alert(1)"))
    }

    @Test
    fun includesThePlatformScriptAndSdkContext() {
        val graph = OnboardingFlowGraph("s1", listOf(Screen("s1", "<p/>", emptyList(), NextTarget.CompleteTarget, null)))
        val html = ShellAssembler.assemble(
            graph,
            mapOf("platform" to ContextValue.String("android")),
            setOf("beta_testers"),
            emptyMap(),
            "s1",
            "window.__platform__ = true;",
        )

        assertTrue(html.contains("window.__platform__ = true;"))
        assertTrue(html.contains("\"platform\":\"android\""))
        assertTrue(html.contains("\"beta_testers\""))
    }
}
