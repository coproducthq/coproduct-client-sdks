package app.coproduct.onboarding

import app.coproduct.onboarding.models.NativeOnLoadRequest
import app.coproduct.onboarding.models.NextTarget
import app.coproduct.onboarding.models.OnboardingFlowGraph
import app.coproduct.onboarding.models.Screen
import app.coproduct.onboarding.models.Transition
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import uniffi.coproduct_ffi_uniffi.ContextValue

// Assembles every screen's html fragment, plus the injected data blob and
// the platform script, into the single shell document the WebView loads
// once per flow-start. Mirrors
// sdks/flutter/coproduct/lib/src/onboarding/shell_assembler.dart and
// sdks/react-native/coproduct/src/onboarding/shellAssembler.ts.
object ShellAssembler {
    private val TEMPLATE = """
        |<!doctype html>
        |<html>
        |<head>
        |<meta charset="utf-8" />
        |<meta name="viewport" content="width=device-width, initial-scale=1" />
        |<style>
        |  html, body { margin: 0; padding: 0; height: 100%; }
        |  [data-screen-id] { height: 100%; }
        |  [data-screen-id][hidden] { display: none; }
        |</style>
        |</head>
        |<body>
        |{{SECTIONS}}
        |<script type="application/json" id="coproduct-data">{{DATA_JSON}}</script>
        |<script>{{PLATFORM_SCRIPT}}</script>
        |</body>
        |</html>
    """.trimMargin()

    fun assemble(
        graph: OnboardingFlowGraph,
        sdkContextAttributes: Map<String, ContextValue>,
        sdkContextSegmentKeys: Set<String>,
        initialAnswers: Map<String, List<String>>,
        initialScreenId: String,
        platformScriptJs: String,
    ): String {
        val sections = graph.screens.joinToString("\n") { screen ->
            """<section data-screen-id="${escapeAttr(screen.id)}" hidden>${screen.html}</section>"""
        }

        val data = buildJsonObject {
            put("initialScreenId", initialScreenId)
            put("screens", buildJsonArray { graph.screens.forEach { add(screenToJson(it)) } })
            put("sdkContext", buildJsonObject {
                put("attributes", buildJsonObject {
                    sdkContextAttributes.forEach { (key, value) -> put(key, value.toJsonElement()) }
                })
                put("segmentKeys", buildJsonArray { sdkContextSegmentKeys.forEach { add(it) } })
            })
            put("initialAnswers", buildJsonObject {
                initialAnswers.forEach { (key, values) ->
                    put(key, buildJsonArray { values.forEach { add(it) } })
                }
            })
        }

        // JSON can legally contain a literal "</script" substring (inside a
        // string value), which would terminate the surrounding <script> tag
        // early if left unescaped -- escaping the forward slash keeps the
        // browser's HTML parser from ever seeing "</script"
        val dataJson = data.toString().replace("</", "<\\/")

        return TEMPLATE
            .replaceFirst("{{SECTIONS}}", sections)
            .replaceFirst("{{DATA_JSON}}", dataJson)
            .replaceFirst("{{PLATFORM_SCRIPT}}", platformScriptJs)
    }

    private fun screenToJson(screen: Screen): JsonObject = buildJsonObject {
        put("id", screen.id)
        put("transitions", buildJsonArray { screen.transitions.forEach { add(transitionToJson(it)) } })
        put("defaultNext", nextTargetToJson(screen.defaultNext))
        screen.onLoad?.let { put("onLoad", onLoadToJson(it)) }
    }

    private fun transitionToJson(transition: Transition): JsonObject = buildJsonObject {
        put("condition", transition.condition)
        put("next", nextTargetToJson(transition.next))
    }

    private fun nextTargetToJson(target: NextTarget): JsonObject = when (target) {
        is NextTarget.ScreenTarget -> buildJsonObject {
            put("type", "screen")
            put("screenId", target.screenId)
        }
        is NextTarget.DismissTarget -> buildJsonObject { put("type", "dismiss") }
        is NextTarget.CompleteTarget -> buildJsonObject { put("type", "complete") }
    }

    private fun onLoadToJson(onLoad: NativeOnLoadRequest): JsonObject = buildJsonObject {
        put("operation", onLoad.operation)
        put("params", buildJsonObject { onLoad.params.forEach { (k, v) -> put(k, v) } })
        put("resultKey", onLoad.resultKey)
        put("timeoutMs", onLoad.timeoutMs)
    }

    private fun escapeAttr(value: String): String = value.replace("\"", "&quot;")

    private fun ContextValue.toJsonElement(): JsonElement = when (this) {
        is ContextValue.String -> JsonPrimitive(value)
        is ContextValue.Number -> JsonPrimitive(value)
        is ContextValue.Bool -> JsonPrimitive(value)
        is ContextValue.StringList -> JsonArray(values.map { JsonPrimitive(it) })
        is ContextValue.Null -> JsonNull
    }
}
