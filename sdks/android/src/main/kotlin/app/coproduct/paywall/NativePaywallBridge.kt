package app.coproduct.paywall

import app.coproduct.paywall.models.PackageKind

/**
 * What the Play Billing Library reported for one purchase attempt.
 * CANCELLED and PENDING are normal outcomes, not errors -- CoproductPaywall
 * surfaces every outcome through onPurchaseResult, reserving onPurchaseError
 * for cases Play Billing never itself reports as "the purchase happened."
 * Mirrors sdks/flutter/coproduct/lib/src/paywall/native_paywall_bridge.dart's
 * PurchaseOutcome and sdks/react-native/coproduct/src/paywall/nativePaywallBridge.ts's.
 */
enum class PurchaseOutcome { SUCCESS, CANCELLED, PENDING }

data class PurchaseResult(
    val outcome: PurchaseOutcome,
    val transactionId: String? = null,
    val productId: String? = null,
    val purchaseDateMillis: Long? = null,
)

/**
 * One purchase Play Billing's queryPurchases reported during a restore.
 * Unlike PurchaseResult, every field is required -- restore only ever
 * reports existing, owned purchases.
 */
data class RestoredTransaction(
    val transactionId: String,
    val productId: String,
    val purchaseDateMillis: Long,
)

/**
 * The native-capability contract PaywallRuntime drives. Deliberately not
 * BillingClient-shaped, so PaywallRuntime stays unit-testable against a
 * fake implementation -- the same testability property
 * coproduct_onboarding's CoproductClient gives FlowRuntime.
 */
interface NativePaywallBridge {
    suspend fun priceFor(productId: String, kind: PackageKind): String
    suspend fun purchase(productId: String, kind: PackageKind): PurchaseResult
    suspend fun restore(): List<RestoredTransaction>
}
