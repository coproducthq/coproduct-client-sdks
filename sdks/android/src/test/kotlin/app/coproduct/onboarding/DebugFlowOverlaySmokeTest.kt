package app.coproduct.onboarding

import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class DebugFlowOverlaySmokeTest {
    @Test
    fun constructsWithoutThrowing() {
        val context = org.robolectric.RuntimeEnvironment.getApplication()
        val overlay = DebugFlowOverlay(context, onRestartFlow = {}, onRefresh = {})
        assertNotNull(overlay)
    }
}
