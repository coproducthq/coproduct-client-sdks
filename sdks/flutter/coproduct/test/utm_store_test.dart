import 'package:coproduct/src/attribute_value.dart';
import 'package:coproduct/src/utm_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake parser so a test never reaches the real FRB function, which has no
/// native library loaded under `flutter test`
Map<String, String> Function(String url) _fakeParser(
  Map<String, Map<String, String>> byUrl,
) =>
    (url) => byUrl[url] ?? const {};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'freezes first-touch across two captures with different values',
    () async {
      final store = UtmStore(
        parse: _fakeParser({
          'https://a.test': {'utm_source': 'google'},
          'https://b.test': {'utm_source': 'facebook'},
        }),
      );

      final first = await store.capture('https://a.test');
      expect(first['utm_source'], AttributeValue.string('google'));

      final second = await store.capture('https://b.test');
      expect(second['utm_source'], AttributeValue.string('google'));
    },
  );

  test('overwrites last-touch on every capture', () async {
    final store = UtmStore(
      parse: _fakeParser({
        'https://a.test': {'utm_source': 'google'},
        'https://b.test': {'utm_source': 'facebook'},
      }),
    );

    await store.capture('https://a.test');
    final second = await store.capture('https://b.test');

    expect(second['utm_source_last'], AttributeValue.string('facebook'));
  });

  test('omits an empty value from both first-touch and last-touch', () async {
    final store = UtmStore(
      parse: _fakeParser({
        'https://a.test': {'utm_source': 'google', 'utm_medium': ''},
      }),
    );

    final attributes = await store.capture('https://a.test');

    expect(attributes.containsKey('utm_medium'), isFalse);
    expect(attributes.containsKey('utm_medium_last'), isFalse);
  });

  test('an empty parse persists nothing and is a no-op', () async {
    final store = UtmStore(
      parse: _fakeParser({
        'https://a.test': {'utm_source': 'google'},
        'https://bare.test': {},
      }),
    );

    await store.capture('https://a.test');
    final afterBare = await store.capture('https://bare.test');

    expect(afterBare['utm_source'], AttributeValue.string('google'));
    expect(afterBare['utm_source_last'], AttributeValue.string('google'));

    final fresh = UtmStore(parse: _fakeParser(const {}));
    expect(
      (await fresh.readAttributes())['utm_source'],
      AttributeValue.string('google'),
    );
  });

  test(
    'readAttributes returns the persisted flattened set without capturing',
    () async {
      final store = UtmStore(
        parse: _fakeParser({
          'https://a.test': {'utm_source': 'google'},
        }),
      );
      await store.capture('https://a.test');

      final reader = UtmStore(parse: _fakeParser(const {}));
      final attributes = await reader.readAttributes();

      expect(attributes['utm_source'], AttributeValue.string('google'));
      expect(attributes['utm_source_last'], AttributeValue.string('google'));
    },
  );

  test(
    'persistence survives a fresh UtmStore instance over the same mock prefs',
    () async {
      final writer = UtmStore(
        parse: _fakeParser({
          'https://a.test': {
            'utm_source': 'google',
            'utm_campaign': 'spring_sale',
          },
        }),
      );
      await writer.capture('https://a.test');

      final reader = UtmStore(parse: _fakeParser(const {}));
      final attributes = await reader.readAttributes();

      expect(attributes['utm_source'], AttributeValue.string('google'));
      expect(attributes['utm_campaign'], AttributeValue.string('spring_sale'));
      expect(attributes['utm_source_last'], AttributeValue.string('google'));
    },
  );
}
