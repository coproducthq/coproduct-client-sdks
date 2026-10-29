import 'package:coproduct/src/attribute_value.dart';
import 'package:coproduct/src/client_backend.dart';
import 'package:coproduct/src/coproduct_client.dart';
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
    'persists the capture and publishes it to the automatic layer',
    () async {
      final backend = _RecordingBackend();
      final client = createClientForBackend(
        backend,
        utmStore: UtmStore(
          parse: _fakeParser({
            'https://a.test': {'utm_source': 'google'},
          }),
        ),
      );

      await client.captureAttribution('https://a.test');

      expect(backend.publishedAttributes, {
        'utm_source': const AttributeValue.string('google'),
        'utm_source_last': const AttributeValue.string('google'),
      });

      // A fresh store over the same persisted prefs sees what was captured,
      // so a torn-down or early client still leaves the value for the next
      // initialize fold to pick up
      final reader = UtmStore(parse: _fakeParser(const {}));
      expect(
        await reader.readAttributes(),
        containsPair('utm_source', const AttributeValue.string('google')),
      );
    },
  );

  test('skips the backend call when nothing has ever been captured', () async {
    final backend = _RecordingBackend();
    final client = createClientForBackend(
      backend,
      utmStore: UtmStore(parse: _fakeParser(const {})),
    );

    await client.captureAttribution('https://bare.test');

    expect(backend.publishCallCount, 0);
  });
}

/// Records the automatic-layer publishes a test can assert on. Routes
/// everything else through `noSuchMethod`, since these tests only exercise
/// `captureAttribution`
final class _RecordingBackend implements CoproductClientBackend {
  Map<String, AttributeValue>? publishedAttributes;
  int publishCallCount = 0;

  @override
  Future<void> setAutoPopulatedAttributes(
    Map<String, AttributeValue> attributes,
  ) async {
    publishCallCount++;
    publishedAttributes = Map<String, AttributeValue>.of(attributes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
