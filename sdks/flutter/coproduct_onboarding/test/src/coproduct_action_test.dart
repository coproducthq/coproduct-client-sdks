import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct_onboarding/src/coproduct_action.dart';

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
  });
}
