import 'package:coproduct/src/client_backend.dart';
import 'package:coproduct/src/coproduct_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('getJson returns a deeply unmodifiable structure', () {
    final client = createClientForBackend(_StubBackend('{"nested":{"x":1},"list":[1]}'));
    final value = client.getJson('config', const <String, Object?>{}) as Map;

    expect(() => value['added'] = 1, throwsUnsupportedError);
    expect(() => (value['nested'] as Map)['x'] = 2, throwsUnsupportedError);
    expect(() => (value['list'] as List).add(2), throwsUnsupportedError);
  });

  test('a caller default JSON cannot encode is returned exactly as supplied', () {
    final cyclic = <String, Object?>{};
    cyclic['self'] = cyclic;
    final client = createClientForBackend(_StubBackend('null'));

    expect(identical(client.getJson('any', cyclic), cyclic), isTrue);
  });
}

final class _StubBackend implements CoproductClientBackend {
  _StubBackend(this.json);
  final String json;

  @override
  String getJson(String key, String defaultValueJson) => json;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
