package app.coproduct.onboarding

import org.junit.Assert.assertNotNull
import org.junit.Test

// CoproductOnboardingFlow owns a real android.webkit.WebView, which cannot
// run under a plain JVM unit test (not even under Robolectric's WebView
// shadow reliably) -- matching Flutter's and RN's own precedent of leaving
// their top-level onboarding widget/component untested beyond a
// compile/export check, this test only verifies the class exists with the
// expected shape, via reflection, without instantiating it.
class CoproductOnboardingFlowSmokeTest {
    @Test
    fun theClassExistsWithAPrimaryConstructor() {
        val ctor = CoproductOnboardingFlow::class.constructors.firstOrNull()
        assertNotNull(ctor)
    }
}
