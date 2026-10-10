import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct/src/onboarding/models/next_target.dart';

void main() {
  group('NextTarget', () {
    test('parses a screen target', () {
      final target = NextTarget.fromJson({'type': 'screen', 'screenId': 's2'});
      expect(target, isA<ScreenTarget>());
      expect((target as ScreenTarget).screenId, 's2');
    });

    test('parses dismiss and complete', () {
      expect(NextTarget.fromJson({'type': 'dismiss'}), isA<DismissTarget>());
      expect(NextTarget.fromJson({'type': 'complete'}), isA<CompleteTarget>());
    });

    test('throws on an unknown type', () {
      expect(() => NextTarget.fromJson({'type': 'explode'}), throwsFormatException);
    });
  });
}
