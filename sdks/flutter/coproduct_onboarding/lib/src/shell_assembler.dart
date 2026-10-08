import 'dart:convert';
import 'models/onboarding_flow_graph.dart';

/// Assembles every screen's html fragment, plus the injected data blob and
/// the platform script, into the single shell document the WebView loads
/// once per flow-start.
class ShellAssembler {
  static const _template = '''
<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<style>
  html, body { margin: 0; padding: 0; height: 100%; }
  [data-screen-id] { height: 100%; }
  [data-screen-id][hidden] { display: none; }
</style>
</head>
<body>
{{SECTIONS}}
<script type="application/json" id="coproduct-data">{{DATA_JSON}}</script>
<script>{{PLATFORM_SCRIPT}}</script>
</body>
</html>''';

  static String assemble({
    required OnboardingFlowGraph graph,
    required Map<String, Object> sdkContextAttributes,
    required Set<String> sdkContextSegmentKeys,
    required Map<String, List<String>> initialAnswers,
    required String initialScreenId,
    required String platformScriptJs,
  }) {
    final sections = graph.screens
        .map((s) => '<section data-screen-id="${_escapeAttr(s.id)}" hidden>${s.html}</section>')
        .join('\n');

    final data = {
      'initialScreenId': initialScreenId,
      'screens': graph.screens
          .map((s) => {
                'id': s.id,
                'transitions': s.transitions.map((t) => t.toJson()).toList(),
                'defaultNext': s.defaultNext.toJson(),
                if (s.onLoad != null) 'onLoad': s.onLoad!.toJson(),
              })
          .toList(),
      'sdkContext': {
        'attributes': sdkContextAttributes,
        'segmentKeys': sdkContextSegmentKeys.toList(),
      },
      'initialAnswers': initialAnswers,
    };

    // JSON can legally contain a literal "</script" substring (inside a
    // string value), which would terminate the surrounding <script> tag
    // early if left unescaped — escaping the forward slash keeps the
    // browser's HTML parser from ever seeing "</script"
    final dataJson = jsonEncode(data).replaceAll('</', '<\\/');

    return _template
        .replaceFirst('{{SECTIONS}}', sections)
        .replaceFirst('{{DATA_JSON}}', dataJson)
        .replaceFirst('{{PLATFORM_SCRIPT}}', platformScriptJs);
  }

  static String _escapeAttr(String value) => value.replaceAll('"', '&quot;');
}
