package app.coproduct.onboarding.models

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

data class OnboardingFlowGraph(
    val startScreenId: String,
    val screens: List<Screen>,
) {
    fun screenById(id: String): Screen? = screens.firstOrNull { it.id == id }

    companion object {
        fun fromJson(json: JsonObject): OnboardingFlowGraph = OnboardingFlowGraph(
            startScreenId = json["startScreenId"]!!.jsonPrimitive.content,
            screens = (json["screens"] as JsonArray).map { Screen.fromJson(it as JsonObject) },
        )
    }
}
