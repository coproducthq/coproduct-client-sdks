import Foundation

/// Wraps a resolved paywall's html fragment and the platform script into
/// the single document the paywall's WebView loads once per session.
/// Simpler than onboarding's `ShellAssembler`: no screen sections, no JSON
/// data blob -- just the author's whole-paywall html and the script.
enum PaywallShellAssembler {
    private static let template = """
    <!doctype html>
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
    </html>
    """

    static func assemble(bodyHtml: String, platformScriptJs: String) -> String {
        template
            .replacingFirstOccurrence(of: "{{BODY}}", with: bodyHtml)
            .replacingFirstOccurrence(of: "{{PLATFORM_SCRIPT}}", with: platformScriptJs)
    }
}
