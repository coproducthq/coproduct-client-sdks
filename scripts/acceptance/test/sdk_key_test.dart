import 'package:coproduct_acceptance/sdk_key.dart';
import 'package:test/test.dart';

void main() {
  test('generates a 40-character cpk_mob_ Crockford key', () {
    final key = generateSdkKey();
    expect(key.length, 40);
    expect(key.startsWith('cpk_mob_'), isTrue);
    final body = key.substring('cpk_mob_'.length);
    expect(body.length, 32);
    expect(RegExp(r'^[0-9a-hjkmnp-tv-z]{32}$').hasMatch(body), isTrue,
        reason: 'Crockford lowercase excludes i, l, o, u');
  });

  test('does not repeat across many invocations', () {
    final keys = {for (var i = 0; i < 2000; i++) generateSdkKey()};
    expect(keys.length, 2000);
  });
}
