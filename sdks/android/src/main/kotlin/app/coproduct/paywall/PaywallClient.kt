package app.coproduct.paywall

import app.coproduct.paywall.models.Entitlement
import app.coproduct.paywall.models.PaywallSnapshot

/**
 * Thrown by any PaywallClient method whose HTTP response is not 2xx.
 * Carries the server's own error code when the response body has one, so
 * PaywallRuntime can distinguish e.g. unknown_product from an unrelated
 * failure. Mirrors sdks/flutter/coproduct/lib/src/paywall/paywall_client.dart's
 * PaywallServerError and sdks/react-native/coproduct/src/paywall/paywallClient.ts's.
 */
class PaywallServerError(
    val statusCode: Int,
    val code: String?,
    message: String,
) : Exception(message)

/**
 * The HTTP contract CoproductPaywall/PaywallRuntime drive. An interface, not
 * a concrete HTTP client, so PaywallRuntime stays unit-testable against a
 * fake -- the same testability property onboarding's CoproductClient gives
 * FlowRuntime.
 */
interface PaywallClient {
    /** Returns null when the paywall isn't resolved for this environment (404) -- the caller decides the fallback UI. */
    suspend fun fetchPaywall(paywallId: String): PaywallSnapshot?

    /** POST /v1/purchases. Throws PaywallServerError on a non-2xx response. */
    suspend fun recordPurchase(
        appUserId: String,
        platform: String,
        storeProductId: String,
        storeTransactionId: String,
        purchaseDateIso: String,
        expiresDateIso: String?,
    ): List<Entitlement>

    /** GET /v1/entitlements. Throws PaywallServerError on a non-2xx response. */
    suspend fun getEntitlements(appUserId: String): List<Entitlement>

    /** POST /v1/identify. Throws PaywallServerError on a non-2xx response. */
    suspend fun identify(appUserId: String, targetingKey: String)
}
