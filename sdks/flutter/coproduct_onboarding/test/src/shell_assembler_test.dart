import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct_onboarding/src/shell_assembler.dart';
import 'package:coproduct_onboarding/src/models/onboarding_flow_graph.dart';

void main() {
  test('wraps every screen fragment in a data-screen-id section', () {
    final graph = OnboardingFlowGraph.fromJson({
      'startScreenId': 'welcome',
      'screens': [
        {'id': 'welcome', 'html': '<p>Hi</p>', 'transitions': [], 'defaultNext': {'type': 'complete'}},
        {'id': 'goal', 'html': '<p>?</p>', 'transitions': [], 'defaultNext': {'type': 'complete'}},
      ],
    });

    final html = ShellAssembler.assemble(
      graph: graph,
      sdkContextAttributes: {'platform': 'ios'},
      sdkContextSegmentKeys: {'power-users'},
      initialAnswers: {},
      initialScreenId: 'welcome',
      platformScriptJs: '/* script */',
    );

    // Every section starts hidden — the platform script reveals the
    // current screen on load, avoiding a flash of every screen at once
    expect(html, contains('<section data-screen-id="welcome" hidden>'));
    expect(html, contains('<p>Hi</p>'));
    expect(html, contains('<section data-screen-id="goal" hidden>'));
    expect(html, contains('/* script */'));
  });

  test('embeds the injected data blob as inert JSON, escaping </script sequences', () {
    final graph = OnboardingFlowGraph.fromJson({
      'startScreenId': 'welcome',
      'screens': [
        {'id': 'welcome', 'html': '<p>Hi</p>', 'transitions': [], 'defaultNext': {'type': 'complete'}},
      ],
    });

    final html = ShellAssembler.assemble(
      graph: graph,
      // Device attribute values and in-flow answers are arbitrary strings
      // that never go through server-side HTML sanitization (unlike a
      // screen's own html) — this is the payload path the escaping guards
      sdkContextAttributes: {'evil': '</script><script>alert(1)</script>'},
      sdkContextSegmentKeys: {},
      initialAnswers: {},
      initialScreenId: 'welcome',
      platformScriptJs: '',
    );

    expect(html, isNot(contains('</script><script>alert')));
    expect(html, contains('alert(1)'));
  });
}
