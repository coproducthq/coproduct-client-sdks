import 'package:coproduct/src/config.dart';
import 'package:coproduct/src/init_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identity is value-equal on the key and the normalized config', () {
    const a = InitIdentity('cpk_mob_a', CoproductConfig());
    const b = InitIdentity('cpk_mob_a', CoproductConfig());
    expect(a == b, isTrue);
    expect(a.hashCode, b.hashCode);
  });

  test('a different key or config is not equal', () {
    const base = InitIdentity('cpk_mob_a', CoproductConfig());
    expect(base == const InitIdentity('cpk_mob_b', CoproductConfig()), isFalse);
    expect(
        base ==
            const InitIdentity(
                'cpk_mob_a', CoproductConfig(pollInterval: Duration(minutes: 2))),
        isFalse);
  });

  test('ffiConfigFor maps durations to microseconds and the endpoint to a string',
      () {
    final config = CoproductConfig(
      pollInterval: const Duration(seconds: 45),
      startupTimeout: const Duration(seconds: 2),
      endpoint: Uri.parse('https://flags.example.com'),
    );
    final ffi = ffiConfigFor(config);
    expect(ffi.pollIntervalUs, 45 * 1000 * 1000);
    expect(ffi.startupTimeoutUs, 2 * 1000 * 1000);
    expect(ffi.endpoint, 'https://flags.example.com');
  });

  test('ffiConfigFor passes a null endpoint through as null', () {
    expect(ffiConfigFor(const CoproductConfig()).endpoint, isNull);
  });
}
