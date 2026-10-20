package app.coproduct.compose

import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.coproduct.Coproduct
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RememberFlagTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun rememberBoolFlagShowsTheInitialDefaultWhenNotReady() = runBlocking {
        // Shutting down any instance from a prior test keeps this test
        // isolated; a fresh process normally has none
        Coproduct.shutdown()
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
        val client = Coproduct.initialize(sdkKey = "cpk_mob_test", context = context)

        composeRule.setContent {
            val enabled by client.rememberBoolFlag("not-a-real-flag", default = false)
            Text(if (enabled) "ON" else "OFF")
        }

        composeRule.onNodeWithText("OFF").assertExists()
        Coproduct.shutdown()
    }
}
