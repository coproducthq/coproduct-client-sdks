package app.coproduct.onboarding.models

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

// A screen's resolved next step: another screen, or a terminal action.
// Mirrors ZNextTarget in packages/snapshot-spec/src/onboarding-flow.ts
// (coproduct-platform repo), Flutter's NextTarget (next_target.dart), and
// RN's NextTarget (models/nextTarget.ts).
sealed class NextTarget {
    data class ScreenTarget(val screenId: String) : NextTarget()
    object DismissTarget : NextTarget()
    object CompleteTarget : NextTarget()

    companion object {
        fun fromJson(json: JsonObject): NextTarget {
            val type = json["type"]?.jsonPrimitive?.content
            return when (type) {
                "screen" -> ScreenTarget(json["screenId"]!!.jsonPrimitive.content)
                "dismiss" -> DismissTarget
                "complete" -> CompleteTarget
                else -> throw IllegalArgumentException("Unknown NextTarget type: $type")
            }
        }
    }
}
