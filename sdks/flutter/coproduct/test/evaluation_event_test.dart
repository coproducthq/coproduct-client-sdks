import 'dart:async';

import 'package:coproduct/src/client_backend.dart';
import 'package:coproduct/src/coproduct_client.dart';
import 'package:coproduct/src/evaluation_event.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evaluationEventFromFrb', () {
    test('maps every field and the FlagValue variant for a matched rule', () {
      const generated = frb.FrbEvaluationEvent(
        flagKey: 'show_paywall',
        flagType: frb.FrbFlagType.bool,
        value: frb.FrbFlagValue.bool(value: true),
        defaultValue: frb.FrbFlagValue.bool(value: false),
        variant: 'treatment',
        reason: frb.FrbEvaluationReason.targetingMatch,
        ruleId: 'rule-1',
        errorCode: null,
        evaluatedAt: '2026-10-29T12:00:00Z',
      );

      final event = evaluationEventFromFrb(generated);

      expect(event.flagKey, 'show_paywall');
      expect(event.flagType, FlagType.bool);
      expect(event.value, const FlagValue.bool(true));
      expect(event.defaultValue, const FlagValue.bool(false));
      expect(event.variant, 'treatment');
      expect(event.reason, EvaluationReason.targetingMatch);
      expect(event.ruleId, 'rule-1');
      expect(event.errorCode, isNull);
      expect(event.evaluatedAt, '2026-10-29T12:00:00Z');
    });

    test('maps an errored JSON evaluation, including a null variant/ruleId', () {
      const generated = frb.FrbEvaluationEvent(
        flagKey: 'config',
        flagType: frb.FrbFlagType.json,
        value: frb.FrbFlagValue.json(value: '{"a":1}'),
        defaultValue: frb.FrbFlagValue.json(value: '{}'),
        variant: null,
        reason: frb.FrbEvaluationReason.error,
        ruleId: null,
        errorCode: 'provider_not_ready',
        evaluatedAt: '2026-10-29T12:01:00Z',
      );

      final event = evaluationEventFromFrb(generated);

      expect(event.flagType, FlagType.json);
      expect(event.value, const FlagValue.json('{"a":1}'));
      expect(event.defaultValue, const FlagValue.json('{}'));
      expect(event.variant, isNull);
      expect(event.reason, EvaluationReason.error);
      expect(event.ruleId, isNull);
      expect(event.errorCode, 'provider_not_ready');
    });

    test('maps the string, int, and number FlagValue variants', () {
      expect(
        flagValueFromFrb(const frb.FrbFlagValue.string(value: 'x')),
        const FlagValue.string('x'),
      );
      expect(
        flagValueFromFrb(const frb.FrbFlagValue.int(value: 42)),
        const FlagValue.int(42),
      );
      expect(
        flagValueFromFrb(const frb.FrbFlagValue.number(value: 1.5)),
        const FlagValue.number(1.5),
      );
    });
  });

  group('CoproductClient.setEvaluationListener', () {
    test('forwards an event delivered on the backend stream', () async {
      final backend = _FakeEvaluationBackend();
      final client = createClientForBackend(backend);

      final received = <EvaluationEvent>[];
      client.setEvaluationListener(received.add);

      const generated = frb.FrbEvaluationEvent(
        flagKey: 'show_paywall',
        flagType: frb.FrbFlagType.bool,
        value: frb.FrbFlagValue.bool(value: true),
        defaultValue: frb.FrbFlagValue.bool(value: false),
        variant: null,
        reason: frb.FrbEvaluationReason.fallthrough,
        ruleId: null,
        errorCode: null,
        evaluatedAt: '2026-10-29T12:02:00Z',
      );
      backend.controller.add(evaluationEventFromFrb(generated));
      await pumpEventQueue();

      expect(received, [evaluationEventFromFrb(generated)]);
    });

    test('a second registration replaces the first', () async {
      final backend = _FakeEvaluationBackend();
      final client = createClientForBackend(backend);

      final first = <EvaluationEvent>[];
      final second = <EvaluationEvent>[];
      client.setEvaluationListener(first.add);
      client.setEvaluationListener(second.add);

      const generated = frb.FrbEvaluationEvent(
        flagKey: 'k',
        flagType: frb.FrbFlagType.bool,
        value: frb.FrbFlagValue.bool(value: true),
        defaultValue: frb.FrbFlagValue.bool(value: false),
        variant: null,
        reason: frb.FrbEvaluationReason.off,
        ruleId: null,
        errorCode: null,
        evaluatedAt: '2026-10-29T12:03:00Z',
      );
      backend.controller.add(evaluationEventFromFrb(generated));
      await pumpEventQueue();

      expect(first, isEmpty);
      expect(second, hasLength(1));
    });
  });
}

/// Instrumented value source matching the `_FakeBackend` idiom used by the
/// observation tests: only `evaluationEvents` is implemented, and everything
/// else routes through `noSuchMethod` since nothing else is under test here
class _FakeEvaluationBackend implements CoproductClientBackend {
  final StreamController<EvaluationEvent> controller =
      StreamController<EvaluationEvent>.broadcast();

  @override
  Stream<EvaluationEvent> evaluationEvents() => controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
