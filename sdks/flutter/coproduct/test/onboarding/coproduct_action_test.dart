import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct/src/onboarding/coproduct_action.dart';

void main() {
  group('CoproductAction.parse', () {
    test('parses requestPermission', () {
      final action = CoproductAction.parse('coproduct-action:requestPermission?permission=notifications');
      expect(action, isA<RequestPermissionAction>());
      expect((action as RequestPermissionAction).permission, 'notifications');
    });

    test('parses openUrl', () {
      final action = CoproductAction.parse('coproduct-action:openUrl?url=https%3A%2F%2Fexample.com');
      expect(action, isA<OpenUrlAction>());
      expect((action as OpenUrlAction).url, 'https://example.com');
    });

    test('parses dismiss and complete', () {
      expect(CoproductAction.parse('coproduct-action:dismiss'), isA<DismissAction>());
      expect(CoproductAction.parse('coproduct-action:complete'), isA<CompleteAction>());
    });

    test('parses showPaywall', () {
      final action = CoproductAction.parse('coproduct-action:showPaywall?paywallId=premium_offer');
      expect(action, isA<ShowPaywallAction>());
      expect((action as ShowPaywallAction).paywallId, 'premium_offer');
    });

    test('parses track with the JSON-encoded answers payload', () {
      final answers = {'goal': ['lose_weight']};
      final url = 'coproduct-action:track?event=action_tapped&screenId=goal&answers=${Uri.encodeQueryComponent(jsonEncode(answers))}';
      final action = CoproductAction.parse(url);
      expect(action, isA<TrackAction>());
      final track = action as TrackAction;
      expect(track.event, 'action_tapped');
      expect(track.screenId, 'goal');
      expect(track.answers, {'goal': ['lose_weight']});
    });

    test('returns null for a non-coproduct-action URL', () {
      expect(CoproductAction.parse('https://example.com'), isNull);
    });

    test('parses request with operation, requestId, and param_-prefixed params', () {
      final action = CoproductAction.parse(
        'coproduct-action:request?operation=requestPermission&requestId=abc123&param_permission=camera',
      );
      expect(action, isA<RequestAction>());
      final request = action as RequestAction;
      expect(request.operation, 'requestPermission');
      expect(request.requestId, 'abc123');
      expect(request.params, {'permission': 'camera'});
    });

    test('parses request with no params at all', () {
      final action = CoproductAction.parse('coproduct-action:request?operation=fetchPlan&requestId=xyz');
      expect(action, isA<RequestAction>());
      expect((action as RequestAction).params, <String, String>{});
    });
  });
}
