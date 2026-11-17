import 'package:coproduct/src/config.dart';
import 'package:coproduct/src/errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults and value equality', () {
    const c = CoproductConfig();
    expect(c.pollInterval, const Duration(seconds: 60));
    expect(c.startupTimeout, const Duration(seconds: 5));
    expect(c.requestTimeout, const Duration(seconds: 30));
    expect(c.endpoint, isNull);
    expect(c.pollOnForeground, isTrue);
    expect(c.apiBaseUrl, isNull);
    expect(const CoproductConfig(), const CoproductConfig());
    expect(
      const CoproductConfig(pollOnForeground: false),
      isNot(const CoproductConfig()),
    );
  });

  test('validation throws the public InvalidConfig', () {
    expect(
      () => validateConfig(
        const CoproductConfig(pollInterval: Duration(seconds: 29)),
      ),
      throwsA(
        isA<InvalidConfig>().having((e) => e.field, 'field', 'pollInterval'),
      ),
    );
    expect(
      () =>
          validateConfig(const CoproductConfig(startupTimeout: Duration.zero)),
      throwsA(isA<InvalidConfig>()),
    );
    expect(
      () =>
          validateConfig(const CoproductConfig(requestTimeout: Duration.zero)),
      throwsA(isA<InvalidConfig>()),
    );
    expect(validateConfig(const CoproductConfig()), const CoproductConfig());
  });

  test('apiBaseUrl takes part in equality and is validated', () {
    final a = CoproductConfig(apiBaseUrl: Uri.parse('https://api.example'));
    final b = CoproductConfig(apiBaseUrl: Uri.parse('https://api.example'));
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const CoproductConfig()));
    expect(validateConfig(a), a);
    // Kept when the endpoint is normalized
    expect(
      validateConfig(
        CoproductConfig(
          endpoint: Uri.parse('https://h/'),
          apiBaseUrl: Uri.parse('https://api.example'),
        ),
      ).apiBaseUrl,
      Uri.parse('https://api.example'),
    );
    for (final bad in ['ftp://h', 'https:///p']) {
      expect(
        () => validateConfig(CoproductConfig(apiBaseUrl: Uri.parse(bad))),
        throwsA(
          isA<InvalidConfig>().having((e) => e.field, 'field', 'apiBaseUrl'),
        ),
        reason: bad,
      );
    }
    expect(defaultApiBaseUrl, Uri.parse('https://api.coproduct.app'));
  });

  test('endpoint validation and all-trailing-slash normalization', () {
    for (final bad in [
      'ftp://h',
      'https:///p',
      'https://h/p?x=1',
      'https://h/p#f',
    ]) {
      expect(
        () => validateConfig(CoproductConfig(endpoint: Uri.parse(bad))),
        throwsA(isA<InvalidConfig>()),
        reason: bad,
      );
    }
    // All trailing slashes strip to an empty path, so these are equal, matching
    // the core which does trim_end_matches('/')
    final a = validateConfig(CoproductConfig(endpoint: Uri.parse('https://h')));
    final b = validateConfig(
      CoproductConfig(endpoint: Uri.parse('https://h/')),
    );
    final c = validateConfig(
      CoproductConfig(endpoint: Uri.parse('https://h///')),
    );
    expect(a.endpoint, b.endpoint);
    expect(a.endpoint, c.endpoint);
    final d = validateConfig(
      CoproductConfig(endpoint: Uri.parse('https://h/base//')),
    );
    expect(d.endpoint.toString(), 'https://h/base');
  });
}
