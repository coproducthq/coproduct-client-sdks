import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct_onboarding/src/models/onboarding_flow_graph.dart';
import 'package:coproduct_onboarding/src/models/next_target.dart';

void main() {
  test('parses a minimal one-screen graph from wire JSON', () {
    final graph = OnboardingFlowGraph.fromJson({
      'startScreenId': 'welcome',
      'splashImage': null,
      'screens': [
        {
          'id': 'welcome',
          'html': '<p>Hi</p>',
          'transitions': [],
          'defaultNext': {'type': 'complete'},
        },
      ],
    });

    expect(graph.startScreenId, 'welcome');
    expect(graph.splashImage, isNull);
    expect(graph.screens, hasLength(1));
    expect(graph.screens.first.id, 'welcome');
    expect(graph.screens.first.defaultNext, isA<CompleteTarget>());
  });

  test('parses a transition with an answer condition, keeping it as raw JSON', () {
    final graph = OnboardingFlowGraph.fromJson({
      'startScreenId': 'goal',
      'splashImage': null,
      'screens': [
        {
          'id': 'goal',
          'html': '<p>?</p>',
          'transitions': [
            {
              'condition': {'type': 'answer', 'questionKey': 'goal', 'operator': 'equals', 'values': ['lose_weight']},
              'next': {'type': 'screen', 'screenId': 's3a'},
            },
          ],
          'defaultNext': {'type': 'complete'},
        },
      ],
    });

    final transition = graph.screens.first.transitions.first;
    expect(transition.condition['type'], 'answer');
    expect(transition.next, isA<ScreenTarget>());
  });

  test('screenById finds a screen by id and returns null otherwise', () {
    final graph = OnboardingFlowGraph.fromJson({
      'startScreenId': 'welcome',
      'splashImage': null,
      'screens': [
        {'id': 'welcome', 'html': '<p>Hi</p>', 'transitions': [], 'defaultNext': {'type': 'complete'}},
      ],
    });

    expect(graph.screenById('welcome')?.id, 'welcome');
    expect(graph.screenById('missing'), isNull);
  });
}
