package app.coproduct.onboarding

import android.content.Context
import android.content.SharedPreferences
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

data class FlowProgress(
    val version: Int,
    val screenId: String,
    val answers: Map<String, List<String>>,
)

// Persists onboarding progress to local device storage, keyed by flowId, so
// an app crash or restart resumes on the last known screen of the same
// version the device started on, rather than restarting from
// startScreenId. Mirrors
// sdks/flutter/coproduct/lib/src/onboarding/local_progress_store.dart and
// sdks/react-native/coproduct/src/onboarding/localProgressStore.ts.
class LocalProgressStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("coproduct_onboarding_progress", Context.MODE_PRIVATE)

    private fun key(flowId: String) = "coproduct_onboarding_progress_$flowId"

    fun save(flowId: String, version: Int, screenId: String, answers: Map<String, List<String>>) {
        val json = buildJsonObject {
            put("version", version)
            put("screenId", screenId)
            put("answers", buildJsonObject {
                answers.forEach { (k, v) -> put(k, buildJsonArray { v.forEach { add(JsonPrimitive(it)) } }) }
            })
        }
        prefs.edit().putString(key(flowId), json.toString()).apply()
    }

    fun load(flowId: String): FlowProgress? {
        val raw = prefs.getString(key(flowId), null) ?: return null
        val json = Json.parseToJsonElement(raw) as JsonObject
        val answers = (json["answers"] as JsonObject).mapValues { (_, v) ->
            (v as JsonArray).map { it.jsonPrimitive.content }
        }
        return FlowProgress(
            version = json["version"]!!.jsonPrimitive.int,
            screenId = json["screenId"]!!.jsonPrimitive.content,
            answers = answers,
        )
    }

    fun clear(flowId: String) {
        prefs.edit().remove(key(flowId)).apply()
    }
}
