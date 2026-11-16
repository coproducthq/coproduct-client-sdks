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
    /**
     * StoreKit 2's signed transaction, which the server verifies against
     * Apple's root. Always null on Android; present so the type matches the
     * other SDKs.
     */
    val signedTransaction: String? = null,
    /**
     * Google Play's purchase token, which the server checks with Google.
     * Null on a bridge that does not report it.
     */
    val purchaseToken: String? = null,
)

/**
 * One purchase Play Billing's queryPurchases reported during a restore.
 * Unlike PurchaseResult, the identifying fields are required -- restore only
 * ever reports existing, owned purchases. [signedTransaction] and
 * [purchaseToken] are the store's own proof of the transaction, as on
 * [PurchaseResult], and are null on a bridge that does not report them.
 */
data class RestoredTransaction(
    val transactionId: String,
    val productId: String,
    val purchaseDateMillis: Long,
    val signedTransaction: String? = null,
    val purchaseToken: String? = null,
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
 * localized price, its introductory offer (or null), and the store's
 * localized product name (or null). Encodes to the
 * `__coproductSetPackages__` value shape
 * `{ "price": String, "intro": { ... } | null, "title"?: String }`.
 * [title] fills a paywall's optional `data-cp-title-for` slot; it is omitted
 * when null, so a page keeps the author's fallback text.
 */
data class PaywallPackageRuntime(
    val price: String,
    val intro: PaywallIntroOffer?,
    val title: String? = null,
)

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

    /**
     * Purchases a product on behalf of [appUserId], telling the store which
     * app user the purchase is for. The store keeps a token derived from the
     * id with the transaction (Play's obfuscatedAccountId) and returns it to
     * the server, which uses it to tell whose purchase this is. Defaults to
     * [purchase], whose purchases carry no token, so existing conformers keep
     * working.
     */
    suspend fun purchaseForUser(productId: String, kind: PackageKind, appUserId: String): PurchaseResult =
        purchase(productId, kind)

    suspend fun restore(): List<RestoredTransaction>
}
