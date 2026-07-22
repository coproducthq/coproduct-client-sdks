import 'package:coproduct/src/identity_error_translation.dart';
import 'package:coproduct/src/invalid_targeting_key.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the generated invalid-targeting-key error becomes InvalidTargetingKey',
      () async {
    await expectLater(
        translateIdentityErrors<void>(
            () async => throw frb.IdentityError.invalidTargetingKey),
        throwsA(isA<InvalidTargetingKey>()));
  });

  test('an unrelated exception is rethrown unchanged with its stack', () async {
    final original = StateError('unexpected');
    final originalStack = StackTrace.current;
    try {
      await translateIdentityErrors<void>(
          () => Future<void>.error(original, originalStack));
      fail('should have rethrown');
    } catch (error, stack) {
      expect(identical(error, original), isTrue);
      expect(stack.toString(), originalStack.toString());
    }
  });

  test('a successful operation returns its value', () async {
    expect(await translateIdentityErrors<int>(() async => 9), 9);
  });
}
