package app.coproduct.paywall

import org.junit.Assert.assertEquals
import org.junit.Test

class IntroOfferLabelTest {
    @Test
    fun `a free trial reads as the period free, then the regular price`() {
        val label = composeIntroLabel(
            kind = IntroOfferKind.FREE_TRIAL,
            offerPeriod = "1 week",
            offerPrice = "Free",
            regularPrice = "$9.99/mo",
        )

        assertEquals("1 week free, then $9.99/mo", label)
    }

    @Test
    fun `a pay-as-you-go offer reads as the discounted price for the period, then the regular price`() {
        val label = composeIntroLabel(
            kind = IntroOfferKind.PAY_AS_YOU_GO,
            offerPeriod = "2 months",
            offerPrice = "$1.99",
            regularPrice = "$9.99/mo",
        )

        assertEquals("$1.99 for 2 months, then $9.99/mo", label)
    }

    @Test
    fun `a pay-up-front offer reads the same shape as pay-as-you-go`() {
        val label = composeIntroLabel(
            kind = IntroOfferKind.PAY_UP_FRONT,
            offerPeriod = "3 months",
            offerPrice = "$0.99",
            regularPrice = "$9.99/mo",
        )

        assertEquals("$0.99 for 3 months, then $9.99/mo", label)
    }
}
