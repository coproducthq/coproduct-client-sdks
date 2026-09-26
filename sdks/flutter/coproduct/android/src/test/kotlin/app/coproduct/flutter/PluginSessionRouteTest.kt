package app.coproduct.flutter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Test

/** Records how the plugin answered a single call */
private class RecordingResult : MethodChannel.Result {
    var answer: String? = null
    var value: Any? = null

    override fun success(result: Any?) {
        answer = "success:$result"
        value = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        answer = "error:$errorCode"
    }

    override fun notImplemented() {
        answer = "notImplemented"
    }
}

class PluginSessionRouteTest {
    @Test fun twoEnginesThroughTheRouteShareOnePairAndOneCommit() {
        // The whole production path, from the channel method through the real
        // preferences adapter to the default shared state, as two engines'
        // plugin instances reach it. The shared state outlives the test in this
        // JVM, so this must stay the only test that uses it
        val prefs = FakePreferences()
        val answers = List(2) {
            val plugin = CoproductHostContextPlugin().apply { context = prefs.context() }
            RecordingResult().also { plugin.onMethodCall(MethodCall("beginSession", null), it) }.value
        }
        assertEquals(answers[0], answers[1])
        assertEquals(
            mapOf("first_seen_at" to prefs.values[SessionStore.FIRST_SEEN_AT_KEY], "session_count" to 1L),
            answers[0],
        )
        assertEquals(1, prefs.commits)
    }

    @Test fun beginSessionIsHandledAndADetachedEngineAnswersNull() {
        // A plugin never attached has no context, which is the null a failed
        // store also produces. Without the route the Dart side would see a
        // missing method instead, and only a device run would notice
        val result = RecordingResult()
        CoproductHostContextPlugin().onMethodCall(MethodCall("beginSession", null), result)
        assertEquals("success:null", result.answer)
    }
}
