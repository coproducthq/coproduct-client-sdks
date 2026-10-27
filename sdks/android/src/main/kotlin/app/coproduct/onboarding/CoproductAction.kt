package app.coproduct.onboarding

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.URLDecoder

// The native-capability actions the platform script can trigger by
// navigating to a coproduct-action: URL, intercepted by the WebView's
// WebViewClient.shouldOverrideUrlLoading and never actually navigated.
// Mirrors sdks/flutter/coproduct/lib/src/onboarding/coproduct_action.dart
// and sdks/react-native/coproduct/src/onboarding/coproductAction.ts.
sealed class CoproductAction {
    data class RequestPermissionAction(val permission: String) : CoproductAction()
    data class OpenUrlAction(val url: String) : CoproductAction()
    object DismissAction : CoproductAction()
    object CompleteAction : CoproductAction()
    data class ShowPaywallAction(val paywallId: String) : CoproductAction()
    data class RequestAction(
        val operation: String,
        val requestId: String,
        val params: Map<String, String>,
    ) : CoproductAction()
    data class TrackAction(
        val event: String,
        val screenId: String,
        val answers: Map<String, List<String>>,
    ) : CoproductAction()

    companion object {
        private const val SCHEME = "coproduct-action:"

        fun parse(url: String): CoproductAction? {
            if (!url.startsWith(SCHEME)) return null
            val withoutScheme = url.substring(SCHEME.length)
            val parts = withoutScheme.split("?", limit = 2)
            val action = parts[0]
            val params = if (parts.size > 1) parseQuery(parts[1]) else emptyMap()

            return when (action) {
                "requestPermission" -> RequestPermissionAction(params["permission"] ?: "")
                "openUrl" -> OpenUrlAction(params["url"] ?: "")
                "dismiss" -> DismissAction
                "complete" -> CompleteAction
                "showPaywall" -> ShowPaywallAction(params["paywallId"] ?: "")
                "request" -> {
                    val requestParams = params.entries
                        .filter { it.key.startsWith("param_") }
                        .associate { it.key.removePrefix("param_") to it.value }
                    RequestAction(
                        operation = params["operation"] ?: "",
                        requestId = params["requestId"] ?: "",
                        params = requestParams,
                    )
                }
                "track" -> TrackAction(
                    event = params["event"] ?: "",
                    screenId = params["screenId"] ?: "",
                    answers = params["answers"]?.let { parseAnswers(it) } ?: emptyMap(),
                )
                else -> null
            }
        }

        private fun parseQuery(query: String): Map<String, String> =
            query.split("&")
                .filter { it.isNotEmpty() }
                .associate { pair ->
                    val idx = pair.indexOf("=")
                    if (idx == -1) {
                        URLDecoder.decode(pair, "UTF-8") to ""
                    } else {
                        URLDecoder.decode(pair.substring(0, idx), "UTF-8") to
                            URLDecoder.decode(pair.substring(idx + 1), "UTF-8")
                    }
                }

        private fun parseAnswers(raw: String): Map<String, List<String>> {
            val json = Json.parseToJsonElement(raw) as JsonObject
            return json.mapValues { (_, v) -> (v as JsonArray).map { it.jsonPrimitive.content } }
        }
    }
}
