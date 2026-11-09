package app.coproduct.onboarding.models

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OnboardingFlowGraphTest {
    private fun parse(json: String): OnboardingFlowGraph =
        OnboardingFlowGraph.fromJson(Json.parseToJsonElement(json) as JsonObject)

    @Test
    fun parsesAMinimalOneScreenGraphFromWireJson() {
        val graph = parse(
            """{"startScreenId":"welcome","screens":[{"id":"welcome","html":"<p>Hi</p>","transitions":[],"defaultNext":{"type":"complete"}}]}"""
        )
        assertEquals("welcome", graph.startScreenId)
        assertEquals(1, graph.screens.size)
        assertEquals("welcome", graph.screens[0].id)
        assertEquals(NextTarget.CompleteTarget, graph.screens[0].defaultNext)
    }

    @Test
    fun parsesATransitionWithAnAnswerConditionKeepingItAsRawJson() {
        val graph = parse(
            """{"startScreenId":"goal","screens":[{"id":"goal","html":"<p>?</p>","transitions":[{"condition":{"type":"answer","questionKey":"goal","operator":"equals","values":["lose_weight"]},"next":{"type":"screen","screenId":"s3a"}}],"defaultNext":{"type":"complete"}}]}"""
        )
        val transition = graph.screens[0].transitions[0]
        assertEquals("answer", transition.condition["type"]!!.jsonPrimitive.content)
        assertEquals(NextTarget.ScreenTarget("s3a"), transition.next)
    }

    @Test
    fun screenByIdFindsAScreenByIdAndReturnsNullOtherwise() {
        val graph = parse(
            """{"startScreenId":"welcome","screens":[{"id":"welcome","html":"<p>Hi</p>","transitions":[],"defaultNext":{"type":"complete"}}]}"""
        )
        assertEquals("welcome", graph.screenById("welcome")?.id)
        assertNull(graph.screenById("missing"))
    }
}
