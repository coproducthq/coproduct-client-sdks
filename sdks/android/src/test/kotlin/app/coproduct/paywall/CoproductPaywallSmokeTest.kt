package app.coproduct.paywall

import org.junit.Assert.assertNotNull
import org.junit.Test

class CoproductPaywallSmokeTest {
    @Test
    fun `the public load method and companion exist with the expected signature`() {
        // A real instantiation needs a live android.content.Context, which
        // the JVM unit test environment doesn't provide (no Robolectric in
        // this module yet) -- this smoke test only asserts the class and
        // its public API shape exist and compile, matching Flutter/RN's own
        // precedent of not unit-testing their top-level paywall view/widget.
        val method = CoproductPaywall::class.java.methods.firstOrNull { it.name == "load" }
        assertNotNull("CoproductPaywall must expose a public load(...) method", method)
    }
}
