import 'dart:convert';

import 'package:coproduct/src/json_value.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('jsonValuesEqual', () {
    test('treats a map with reordered keys as the same value', () {
      final a = jsonDecode('{"one":1,"two":2}');
      final b = jsonDecode('{"two":2,"one":1}');
      expect(jsonValuesEqual(a, b), isTrue);
    });

    test('compares nested maps and lists structurally', () {
      final a = jsonDecode('{"items":[1,{"deep":["x"]}]}');
      final b = jsonDecode('{"items":[1,{"deep":["x"]}]}');
      final c = jsonDecode('{"items":[1,{"deep":["y"]}]}');
      expect(jsonValuesEqual(a, b), isTrue);
      expect(jsonValuesEqual(a, c), isFalse);
    });

    test('distinguishes maps whose key sets differ in either direction', () {
      // Iteration walks only the left side, so without the length check a left
      // map that is a strict subset of the right compares equal, and a flag
      // that gained a key would read as unchanged and keep serving stale JSON
      expect(jsonValuesEqual({'a': 1}, {'a': 1, 'b': 2}), isFalse,
          reason: 'the left map is missing a key the right one has');
      expect(jsonValuesEqual({'a': 1, 'b': 2}, {'a': 1}), isFalse);
    });

    test('distinguishes a missing key from a null value', () {
      // Same length on both sides, so the length check cannot answer this and
      // the key membership test is what has to. A map that simply lacks the
      // key reads back null, which is indistinguishable from a null value
      // unless membership is checked
      expect(
          jsonValuesEqual(jsonDecode('{"a":null}'), jsonDecode('{"b":null}')),
          isFalse);
      expect(jsonValuesEqual(jsonDecode('{"a":null}'), jsonDecode('{}')),
          isFalse);
    });

    test('distinguishes list order and length', () {
      expect(jsonValuesEqual(jsonDecode('[1,2]'), jsonDecode('[2,1]')), isFalse);
      expect(jsonValuesEqual(jsonDecode('[1]'), jsonDecode('[1,1]')), isFalse);
    });

    test('treats an int and a double of the same value as equal', () {
      expect(jsonValuesEqual(1, 1.0), isTrue);
      expect(jsonValuesEqual(jsonDecode('[1]'), jsonDecode('[1.0]')), isTrue);
      expect(jsonValuesEqual(1, 2), isFalse);
    });

    test('reports two NaN values as the same value', () {
      expect(jsonValuesEqual(double.nan, double.nan), isTrue);
      expect(jsonValuesEqual(0.0 / 0.0, double.infinity - double.infinity),
          isTrue);
      expect(jsonValuesEqual(double.nan, 1.0), isFalse);
      expect(jsonValuesEqual([double.nan], [double.nan]), isTrue);
    });

    test('does not equate different container types or scalars', () {
      expect(jsonValuesEqual(jsonDecode('{}'), jsonDecode('[]')), isFalse);
      expect(jsonValuesEqual('1', 1), isFalse);
      expect(jsonValuesEqual(null, false), isFalse);
      expect(jsonValuesEqual(null, null), isTrue);
    });

    test('compares a value JSON cannot represent by identity alone', () {
      final a = _Opaque();
      final b = _Opaque();
      expect(jsonValuesEqual(a, a), isTrue);
      expect(jsonValuesEqual(a, b), isFalse);
    });

    test('ignores a custom equality on a value JSON cannot represent', () {
      // Two distinct defaults must read as different even when their own
      // operator == says otherwise, or a widget silently keeps observing the
      // old one
      final a = _ValueEqual();
      final b = _ValueEqual();
      expect(a == b, isTrue, reason: 'the type really does define equality');
      expect(jsonValuesEqual(a, b), isFalse);
      expect(jsonValuesEqual(a, a), isTrue);
    });
  });

  group('jsonDefaultsEqual', () {
    test('treats two objects that encode alike as the same default', () {
      // A parent that rebuilds constructs a fresh default every time. If that
      // read as a new default, the widget would tear down a live native
      // session on every frame
      expect(jsonDefaultsEqual(_Encodable(), _Encodable()), isTrue);
    });

    test('treats structurally identical literals as the same default', () {
      expect(
          jsonDefaultsEqual(
              {'a': 1, 'b': 2}, <String, Object?>{'b': 2, 'a': 1}),
          isTrue);
      expect(jsonDefaultsEqual({'a': 1}, {'a': 2}), isFalse);
    });

    test('falls back to identity when a default cannot be encoded', () {
      final opaque = _Opaque();
      expect(jsonDefaultsEqual(opaque, opaque), isTrue);
      expect(jsonDefaultsEqual(_Opaque(), _Opaque()), isFalse);
      expect(jsonDefaultsEqual(_ValueEqual(), _ValueEqual()), isFalse);
      expect(jsonDefaultsEqual(_Opaque(), {'a': 1}), isFalse);
    });
  });

  group('unmodifiableJson', () {
    test('rejects mutation of a decoded map and its nested containers', () {
      final wrapped =
          unmodifiableJson(jsonDecode('{"a":{"b":[1]}}')) as Map<String, Object?>;
      expect(() => wrapped['c'] = 1, throwsUnsupportedError);
      final inner = wrapped['a']! as Map<String, Object?>;
      expect(() => inner['b'] = 2, throwsUnsupportedError);
      expect(() => (inner['b']! as List<Object?>).add(2), throwsUnsupportedError);
    });

    test('preserves the value it wraps', () {
      final source = jsonDecode('{"a":{"b":[1,"two",null,true]}}');
      expect(jsonValuesEqual(unmodifiableJson(source), source), isTrue);
    });

    test('returns scalars and null unchanged', () {
      expect(unmodifiableJson(null), isNull);
      expect(unmodifiableJson(7), 7);
      expect(unmodifiableJson('x'), 'x');
    });

    test('does not reflect later mutation of the source', () {
      // The wrapper is built over a fresh structure, so a caller who keeps a
      // reference to what they passed cannot change what the SDK serves
      final source = <String, Object?>{
        'a': <Object?>[1],
      };
      final nested = source['a']! as List<Object?>;
      final wrapped = unmodifiableJson(source) as Map<String, Object?>;
      source['a'] = 'replaced';
      nested.add(2);
      expect(wrapped['a'], [1]);
    });
  });
}

class _Opaque {}

class _ValueEqual {
  @override
  bool operator ==(Object other) => other is _ValueEqual;

  @override
  int get hashCode => 7;
}

class _Encodable {
  Map<String, Object?> toJson() => {'mode': 'same'};
}
