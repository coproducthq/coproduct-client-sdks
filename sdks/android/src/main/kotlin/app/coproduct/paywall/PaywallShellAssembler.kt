package app.coproduct.paywall

/**
 * Wraps a resolved paywall's html fragment and the platform script into the
 * single document the paywall's WebView loads once per session. Mirrors
 * sdks/flutter/coproduct/lib/src/paywall/paywall_shell_assembler.dart and
 * sdks/react-native/coproduct/src/paywall/paywallShellAssembler.ts.
 */
object PaywallShellAssembler {
    private const val TEMPLATE = """<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<style>
  html, body { margin: 0; padding: 0; height: 100%; }
</style>
</head>
<body>
{{BODY}}
<script>{{PLATFORM_SCRIPT}}</script>
</body>
</html>"""

    fun assemble(bodyHtml: String, platformScriptJs: String): String =
        TEMPLATE.replace("{{BODY}}", bodyHtml).replace("{{PLATFORM_SCRIPT}}", platformScriptJs)
}
