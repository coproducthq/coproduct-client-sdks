package app.coproduct.onboarding.models

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

// A screen's on-load native request: fires the instant the screen becomes
// current, suspending the screen's own reveal until native resolves it.
// Mirrors ZNativeRequest in packages/snapshot-spec/src/onboarding-flow.ts.
data class NativeOnLoadRequest(
    val operation: String,
    val params: Map<String, String>,
    val resultKey: String,
    val timeoutMs: Long,
) {
    companion object {
        fun fromJson(json: JsonObject): NativeOnLoadRequest = NativeOnLoadRequest(
            operation = json["operation"]!!.jsonPrimitive.content,
            params = (json["params"] as JsonObject).mapValues { it.value.jsonPrimitive.content },
            resultKey = json["resultKey"]!!.jsonPrimitive.content,
            timeoutMs = json["timeoutMs"]!!.jsonPrimitive.content.toLong(),
        )
    }
}
