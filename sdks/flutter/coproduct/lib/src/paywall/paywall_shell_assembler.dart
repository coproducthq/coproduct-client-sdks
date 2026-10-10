/// Wraps a resolved paywall's html fragment (PaywallSnapshot.html) and the
/// platform script into the single document the paywall's WebView loads
/// once per session. Simpler than coproduct_onboarding's ShellAssembler --
/// a paywall is one static section, not a graph of screens, so there is no
/// sections list or injected data blob to assemble.
class PaywallShellAssembler {
  static const _template = '''
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
</html>''';

  static String assemble({required String bodyHtml, required String platformScriptJs}) {
    return _template
        .replaceFirst('{{BODY}}', bodyHtml)
        .replaceFirst('{{PLATFORM_SCRIPT}}', platformScriptJs);
  }
}
