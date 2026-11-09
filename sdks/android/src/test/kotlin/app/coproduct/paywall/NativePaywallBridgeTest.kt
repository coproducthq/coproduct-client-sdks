package app.coproduct.paywall

import app.coproduct.paywall.models.PackageKind
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/** A bridge that implements only priceFor, to prove the interface's default
 * packageFor delegates to it with no intro. */
private class PriceOnlyBridge : NativePaywallBridge {
    override suspend fun priceFor(productId: String, kind: PackageKind): String = "$4.99"
    override suspend fun purchase(productId: String, kind: PackageKind): PurchaseResult =
        PurchaseResult(outcome = PurchaseOutcome.CANCELLED)

    override suspend fun restore(): List<RestoredTransaction> = emptyList()
}

class NativePaywallBridgeTest {
    @Test
    fun `packageFor defaults to the price with no intro when a bridge implements only priceFor`() = runTest {
        val result = PriceOnlyBridge().packageFor("p1", PackageKind.SUBSCRIPTION)

        assertEquals(PaywallPackageRuntime(price = "$4.99", intro = null), result)
    }
}
