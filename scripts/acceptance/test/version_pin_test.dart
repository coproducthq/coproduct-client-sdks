import 'package:coproduct_acceptance/version_pin.dart';
import 'package:test/test.dart';

void main() {
  test('parses a canonical pinned version and build', () {
    final r = parsePinnedVersion('name: x\nversion: 1.0.0+1\n');
    expect(r.version, '1.0.0');
    expect(r.build, '1');
  });

  test('rejects leading zeros in the version', () {
    expect(() => parsePinnedVersion('version: 01.0.0+1\n'),
        throwsA(isA<FormatException>()));
  });

  test('rejects a non-three-part or pre-release version', () {
    for (final v in ['1.0+1', '1.0.0-rc1+1', '1.0.0.0+1']) {
      expect(() => parsePinnedVersion('version: $v\n'),
          throwsA(isA<FormatException>()),
          reason: v);
    }
  });

  test('rejects a component too large for u64', () {
    expect(
        () => parsePinnedVersion('version: 1.0.18446744073709551616+1\n'),
        throwsA(isA<FormatException>()));
  });

  test('rejects a missing, buildless, or non-canonical build', () {
    expect(() => parsePinnedVersion('version: 1.0.0\n'),
        throwsA(isA<FormatException>()));
    expect(() => parsePinnedVersion('version: 1.0.0+01\n'),
        throwsA(isA<FormatException>()));
    expect(() => parsePinnedVersion('version: 1.0.0+0\n'),
        throwsA(isA<FormatException>()));
  });

  test('rejects a missing or duplicate version key', () {
    expect(() => parsePinnedVersion('name: x\n'),
        throwsA(isA<FormatException>()));
    expect(() => parsePinnedVersion('version: 1.0.0+1\nversion: 2.0.0+2\n'),
        throwsA(isA<FormatException>()));
  });
}
