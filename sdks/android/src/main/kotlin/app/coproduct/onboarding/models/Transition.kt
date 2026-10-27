package app.coproduct.onboarding.models

import kotlinx.serialization.json.JsonObject

// A screen's ordered transition: a condition (kept as raw JSON, evaluated
// client-side by the platform script running inside the WebView, never by
// this SDK) and where it leads.
data class Transition(
    val condition: JsonObject,
    val next: NextTarget,
) {
    companion object {
        fun fromJson(json: JsonObject): Transition = Transition(
            condition = json["condition"] as JsonObject,
            next = NextTarget.fromJson(json["next"] as JsonObject),
        )
    }
}
