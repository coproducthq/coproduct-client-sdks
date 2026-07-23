import 'package:coproduct/src/config.dart';
import 'package:coproduct/src/errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults and value equality', () {
    const c = CoproductConfig();
    expect(c.pollInterval, const Duration(seconds: 60));
    expect(c.startupTimeout, const Duration(seconds: 3));
    expect(c.requestTimeout, const Duration(seconds: 30));
    expect(c.endpoint, isNull);
    expect(c.pollOnForeground, isTrue);
    expect(const CoproductConfig(), const CoproductConfig());
    expect(const CoproductConfig(pollOnForeground: false),
        isNot(const CoproductConfig()));
  });

  test('validation throws the public InvalidConfig', () {
    expect(
        () => validateConfig(
            const CoproductConfig(pollInterval: Duration(seconds: 29))),
        throwsA(isA<InvalidConfig>()
            .having((e) => e.field, 'field', 'pollInterval')));
    expect(
        () => validateConfig(const CoproductConfig(startupTimeout: Duration.zero)),
        throwsA(isA<InvalidConfig>()));
    expect(
        () => validateConfig(const CoproductConfig(requestTimeout: Duration.zero)),
        throwsA(isA<InvalidConfig>()));
    expect(validateConfig(const CoproductConfig()), const CoproductConfig());
  });

  test('endpoint validation and all-trailing-slash normalization', () {
    for (final bad in ['ftp://h', 'https:///p', 'https://h/p?x=1', 'https://h/p#f']) {
      expect(() => validateConfig(CoproductConfig(endpoint: Uri.parse(bad))),
          throwsA(isA<InvalidConfig>()), reason: bad);
    }
    // All trailing slashes strip to an empty path, so these are equal, matching
    // the core which does trim_end_matches('/')
    final a = validateConfig(CoproductConfig(endpoint: Uri.parse('https://h')));
    final b = validateConfig(CoproductConfig(endpoint: Uri.parse('https://h/')));
    final c = validateConfig(CoproductConfig(endpoint: Uri.parse('https://h///')));
    expect(a.endpoint, b.endpoint);
    expect(a.endpoint, c.endpoint);
    final d = validateConfig(CoproductConfig(endpoint: Uri.parse('https://h/base//')));
    expect(d.endpoint.toString(), 'https://h/base');
  });
}
