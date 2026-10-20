package app.coproduct.paywall

/**
 * The native-capability actions the paywall platform-script can trigger by
 * navigating to a coproduct-action: URL, intercepted by the WebView's
 * shouldOverrideUrlLoading and never actually navigated. Mirrors
 * sdks/flutter/coproduct/lib/src/paywall/paywall_action.dart and
 * sdks/react-native/coproduct/src/paywall/paywallAction.ts.
 */
sealed class PaywallAction {
    data class Purchase(val packageKey: String) : PaywallAction()
    object Restore : PaywallAction()
    object Dismiss : PaywallAction()
}

private const val SCHEME = "coproduct-action:"

fun parsePaywallAction(url: String): PaywallAction? {
    if (!url.startsWith(SCHEME)) return null

    val withoutScheme = url.removePrefix(SCHEME)
    val parts = withoutScheme.split("?", limit = 2)
    val action = parts[0]
    val query = parts.getOrNull(1).orEmpty()
    val params = query.split("&")
        .filter { it.isNotEmpty() }
        .map { it.split("=", limit = 2) }
        .associate { it[0] to it.getOrElse(1) { "" } }

    return when (action) {
        "purchase" -> {
            val packageKey = params["packageKey"]
            if (packageKey.isNullOrEmpty()) null else PaywallAction.Purchase(packageKey)
        }
        "restore" -> PaywallAction.Restore
        "dismiss" -> PaywallAction.Dismiss
        else -> null
    }
}
