package app.coproduct.onboarding

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CoproductActionTest {
    @Test
    fun returnsNullForAUrlWithoutTheCoproductActionScheme() {
        assertNull(CoproductAction.parse("https://example.com"))
    }

    @Test
    fun parsesRequestPermission() {
        val action = CoproductAction.parse("coproduct-action:requestPermission?permission=camera")
        assertEquals(CoproductAction.RequestPermissionAction("camera"), action)
    }

    @Test
    fun parsesOpenUrlWithPercentEncoding() {
        val action = CoproductAction.parse("coproduct-action:openUrl?url=https%3A%2F%2Fexample.com%2Fpath")
        assertEquals(CoproductAction.OpenUrlAction("https://example.com/path"), action)
    }

    @Test
    fun parsesDismissAndComplete() {
        assertEquals(CoproductAction.DismissAction, CoproductAction.parse("coproduct-action:dismiss"))
        assertEquals(CoproductAction.CompleteAction, CoproductAction.parse("coproduct-action:complete"))
    }

    @Test
    fun parsesShowPaywall() {
        val action = CoproductAction.parse("coproduct-action:showPaywall?paywallId=pw_123")
        assertEquals(CoproductAction.ShowPaywallAction("pw_123"), action)
    }

    @Test
    fun parsesRequestWithPrefixedParams() {
        val action = CoproductAction.parse(
            "coproduct-action:request?operation=fetchCoupon&requestId=r1&param_code=ABC"
        )
        assertEquals(
            CoproductAction.RequestAction(operation = "fetchCoupon", requestId = "r1", params = mapOf("code" to "ABC")),
            action,
        )
    }

    @Test
    fun parsesTrackWithJsonEncodedAnswers() {
        val action = CoproductAction.parse(
            "coproduct-action:track?event=screen_viewed&screenId=s1&answers=%7B%22q1%22%3A%5B%22a1%22%2C%22a2%22%5D%7D"
        )
        assertEquals(
            CoproductAction.TrackAction(event = "screen_viewed", screenId = "s1", answers = mapOf("q1" to listOf("a1", "a2"))),
            action,
        )
    }

    @Test
    fun parsesTrackWithNoAnswersAsAnEmptyMap() {
        val action = CoproductAction.parse("coproduct-action:track?event=screen_viewed&screenId=s1") as CoproductAction.TrackAction
        assertTrue(action.answers.isEmpty())
    }

    @Test
    fun returnsNullForAnUnknownActionName() {
        assertNull(CoproductAction.parse("coproduct-action:explode"))
    }
}
