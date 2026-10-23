import type { OnboardingFlowGraph } from './models/onboardingFlowGraph';

export interface AssembleShellArgs {
  graph: OnboardingFlowGraph;
  sdkContextAttributes: Record<string, string | number | boolean>;
  sdkContextSegmentKeys: Set<string>;
  initialAnswers: Record<string, string[]>;
  initialScreenId: string;
  platformScriptJs: string;
}

const TEMPLATE = `<!doctype html>
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
</html>`;

function escapeAttr(value: string): string {
  return value.replaceAll('"', '&quot;');
}

// Assembles every screen's html fragment, plus the injected data blob and
// the platform script, into the single shell document the WebView loads
// once per flow-start. Mirrors
// sdks/flutter/coproduct/lib/src/onboarding/shell_assembler.dart.
export function assembleShell(args: AssembleShellArgs): string {
  const {
    graph,
    sdkContextAttributes,
    sdkContextSegmentKeys,
    initialAnswers,
    initialScreenId,
    platformScriptJs,
  } = args;

  const sections = graph.screens
    .map(
      (s) =>
        `<section data-screen-id="${escapeAttr(s.id)}" hidden>${s.html}</section>`
    )
    .join('\n');

  const data = {
    initialScreenId,
    screens: graph.screens.map((s) => ({
      id: s.id,
      transitions: s.transitions,
      defaultNext: s.defaultNext,
      ...(s.onLoad ? { onLoad: s.onLoad } : {}),
    })),
    sdkContext: {
      attributes: sdkContextAttributes,
      segmentKeys: Array.from(sdkContextSegmentKeys),
    },
    initialAnswers,
  };

  // JSON can legally contain a literal "</script" substring (inside a
  // string value), which would terminate the surrounding <script> tag
  // early if left unescaped -- escaping the forward slash keeps the
  // browser's HTML parser from ever seeing "</script"
  const dataJson = JSON.stringify(data).replaceAll('</', '<\\/');

  // A function replacer, not a plain string, because String.replace
  // interprets $-prefixed sequences ($&, $`, $', $$) in a string
  // replacement as special patterns. The bundled platform script is
  // large enough to contain these incidentally (e.g. from a bundled
  // semver implementation's regex source), which silently corrupts the
  // assembled shell when passed as a plain string.
  return TEMPLATE.replace('{{SECTIONS}}', () => sections)
    .replace('{{DATA_JSON}}', () => dataJson)
    .replace('{{PLATFORM_SCRIPT}}', () => platformScriptJs);
}
