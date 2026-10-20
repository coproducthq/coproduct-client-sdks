package app.coproduct.paywall.models

import org.json.JSONObject

/**
 * What a purchase unlocks, as resolved server-side and returned by
 * POST /v1/purchases and GET /v1/entitlements. Mirrors
 * sdks/flutter/coproduct/lib/src/paywall/models/entitlement.dart and
 * sdks/react-native/coproduct/src/paywall/models/entitlement.ts.
 *
 * expiresAt is kept as the raw ISO-8601 string rather than parsed into a
 * platform date type -- every caller of this model either re-serializes it
 * (HttpPaywallClient logging/propagation) or compares it as an opaque
 * value; no caller in this feature needs date arithmetic on it.
 */
data class Entitlement(
    val entitlementId: String,
    val isActive: Boolean,
    val expiresAt: String?,
    val willRenew: Boolean,
    val source: String,
)

fun parseEntitlement(json: JSONObject): Entitlement = Entitlement(
    entitlementId = json.getString("entitlementId"),
    isActive = json.getBoolean("isActive"),
    expiresAt = if (json.isNull("expiresAt")) null else json.optString("expiresAt").takeIf { it.isNotEmpty() },
    willRenew = json.getBoolean("willRenew"),
    source = json.getString("source"),
)
