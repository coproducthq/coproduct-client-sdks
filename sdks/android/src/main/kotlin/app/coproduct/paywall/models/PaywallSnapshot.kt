package app.coproduct.paywall.models

import org.json.JSONObject

/**
 * What kind of store product a packageKey resolves to. Determines both the
 * Play Billing product type (SUBSCRIPTION -> SUBS, CONSUMABLE/LIFETIME ->
 * INAPP) and whether a successful purchase is consumed or acknowledged.
 * Mirrors the Coproduct platform's own Product.kind
 * (packages/db/src/schema/paywalls.ts's product_kind enum) and RN's
 * PackageKind (sdks/react-native/coproduct/src/paywall/nativePaywallBridge.ts).
 */
enum class PackageKind(val wireValue: String) {
    SUBSCRIPTION("subscription"),
    CONSUMABLE("consumable"),
    LIFETIME("lifetime"),
}

private fun parsePackageKind(value: String?): PackageKind =
    when (value) {
        "consumable" -> PackageKind.CONSUMABLE
        "lifetime" -> PackageKind.LIFETIME
        else -> PackageKind.SUBSCRIPTION
    }

/**
 * One purchase option a paywall offers, e.g. monthly or annual. packageKey
 * matches the backend's abstract key; native resolves it to a real store
 * product id via the sibling PaywallPackageRef map, never from this type
 * directly.
 */
data class PaywallCta(
    val packageKey: String,
    val label: String,
)

private fun parsePaywallCta(json: JSONObject): PaywallCta = PaywallCta(
    packageKey = json.getString("packageKey"),
    label = json.getString("label"),
)

/** A paywall's authored content. html is author-written markup, not assembled from structured fields. */
data class PaywallContent(
    val offeringKey: String,
    val ctas: List<PaywallCta>,
    val html: String,
)

private fun parsePaywallContent(json: JSONObject): PaywallContent {
    val ctasJson = json.getJSONArray("ctas")
    val ctas = (0 until ctasJson.length()).map { parsePaywallCta(ctasJson.getJSONObject(it)) }
    return PaywallContent(
        offeringKey = json.getString("offeringKey"),
        ctas = ctas,
        html = json.getString("html"),
    )
}

/**
 * One packageKey's store product ids, as resolved server-side from the
 * offering the paywall's content.offeringKey points at. Every product id
 * field is optional -- an offering may only have some platforms configured.
 * kind is absent on a server that predates consumable support, which
 * defaults it to SUBSCRIPTION, preserving this feature's original
 * subscription-only behavior exactly.
 */
data class PaywallPackageRef(
    val iosProductId: String?,
    val androidProductId: String?,
    val webProductId: String?,
    val kind: PackageKind,
)

private fun parsePaywallPackageRef(json: JSONObject): PaywallPackageRef = PaywallPackageRef(
    iosProductId = json.optString("iosProductId").takeIf { it.isNotEmpty() },
    androidProductId = json.optString("androidProductId").takeIf { it.isNotEmpty() },
    webProductId = json.optString("webProductId").takeIf { it.isNotEmpty() },
    kind = parsePackageKind(if (json.has("kind")) json.optString("kind") else null),
)

/**
 * The resolved paywall a device fetches, mirroring
 * sdks/flutter/coproduct/lib/src/paywall/models/paywall_snapshot.dart and
 * sdks/react-native/coproduct/src/paywall/models/paywallSnapshot.ts field
 * for field, including the packages map the resolve step projects from the
 * offering alongside content and html.
 */
data class PaywallSnapshot(
    val paywallId: String,
    val version: Int,
    val templateType: String,
    val content: PaywallContent,
    val packages: Map<String, PaywallPackageRef>,
    val html: String,
)

fun parsePaywallSnapshot(json: JSONObject): PaywallSnapshot {
    val packagesJson = json.getJSONObject("packages")
    val packages = packagesJson.keys().asSequence().associateWith { key ->
        parsePaywallPackageRef(packagesJson.getJSONObject(key))
    }
    return PaywallSnapshot(
        paywallId = json.getString("paywallId"),
        version = json.getInt("version"),
        templateType = json.getString("templateType"),
        content = parsePaywallContent(json.getJSONObject("content")),
        packages = packages,
        html = json.getString("html"),
    )
}
