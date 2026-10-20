package app.coproduct.onboarding.models

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class NextTargetTest {
    private fun parse(json: String): NextTarget =
        NextTarget.fromJson(Json.parseToJsonElement(json) as JsonObject)

    @Test
    fun parsesAScreenTarget() {
        val target = parse("""{"type":"screen","screenId":"s2"}""")
        assertEquals(NextTarget.ScreenTarget("s2"), target)
    }

    @Test
    fun parsesDismissAndComplete() {
        assertEquals(NextTarget.DismissTarget, parse("""{"type":"dismiss"}"""))
        assertEquals(NextTarget.CompleteTarget, parse("""{"type":"complete"}"""))
    }

    @Test
    fun throwsOnAnUnknownType() {
        val error = assertThrows(IllegalArgumentException::class.java) {
            parse("""{"type":"explode"}""")
        }
        assertEquals("Unknown NextTarget type: explode", error.message)
    }
}
