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
 * One package's introductory offer as resolved natively, or its absence.
 * [eligible] is per-user -- PaywallRuntime only ever sends an intro when the
 * store reports this user eligible, so the WebView can reveal trial copy
 * without re-checking. Encodes to the bridge shape
 * `{ "eligible": Boolean, "label": String }`. Mirrors iOS's
 * PaywallIntroOffer (sdks/ios/Sources/Coproduct/Paywall/PaywallPackageRuntime.swift)
 * and Flutter's PaywallIntroOffer
 * (sdks/flutter/coproduct/lib/src/paywall/native_paywall_bridge.dart).
 */
data class PaywallIntroOffer(val eligible: Boolean, val label: String)

/**
 * One package's live store data for a single paywall render: the regular
 * localized price and its introductory offer (or null). Encodes to the
 * `__coproductSetPackages__` value shape
 * `{ "price": String, "intro": { ... } | null }`.
 */
data class PaywallPackageRuntime(val price: String, val intro: PaywallIntroOffer?)

/**
 * The native-capability contract PaywallRuntime drives. Deliberately not
 * BillingClient-shaped, so PaywallRuntime stays unit-testable against a
 * fake implementation -- the same testability property
 * coproduct_onboarding's CoproductClient gives FlowRuntime.
 */
interface NativePaywallBridge {
    suspend fun priceFor(productId: String, kind: PackageKind): String

    /**
     * Resolves a package's regular price and, when the store offers one and
     * this user is eligible, its introductory offer. Defaults to a
     * price-only result so existing conformers keep working.
     */
    suspend fun packageFor(productId: String, kind: PackageKind): PaywallPackageRuntime =
        PaywallPackageRuntime(price = priceFor(productId, kind), intro = null)

    suspend fun purchase(productId: String, kind: PackageKind): PurchaseResult
    suspend fun restore(): List<RestoredTransaction>
}
