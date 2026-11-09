package app.coproduct.onboarding.models

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

// A screen's html is a body fragment rendered inside a
// <section data-screen-id="..."> in the assembled shell, not a full
// document. Intentionally narrower than the full wire schema -- name,
// strings, and position are author-tool-only fields the runtime never
// reads, matching Flutter's and RN's Screen models.
data class Screen(
    val id: String,
    val html: String,
    val transitions: List<Transition>,
    val defaultNext: NextTarget,
    val onLoad: NativeOnLoadRequest?,
) {
    companion object {
        fun fromJson(json: JsonObject): Screen = Screen(
            id = json["id"]!!.jsonPrimitive.content,
            html = json["html"]!!.jsonPrimitive.content,
            transitions = (json["transitions"] as JsonArray).map { Transition.fromJson(it as JsonObject) },
            defaultNext = NextTarget.fromJson(json["defaultNext"] as JsonObject),
            onLoad = (json["onLoad"] as? JsonObject)?.let { NativeOnLoadRequest.fromJson(it) },
        )
    }
}
