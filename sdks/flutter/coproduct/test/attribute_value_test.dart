import 'package:coproduct/src/attribute_value.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each variant converts to the matching FrbContextValue', () {
    expect(toFrbContextValue(const AttributeValue.string('x')),
        const frb.FrbContextValue.string('x'));
    expect(toFrbContextValue(const AttributeValue.bool(true)),
        const frb.FrbContextValue.bool(true));
    expect(toFrbContextValue(AttributeValue.stringList(['a', 'b'])),
        const frb.FrbContextValue.stringList(['a', 'b']));
    expect(toFrbContextValue(const AttributeValue.nullValue()),
        const frb.FrbContextValue.null_());
  });

  test('every single-value factory is const constructible', () {
    // A compile-time proof: if any of these stopped being a const factory this
    // list would not compile. The asymmetry it guards against is real, since
    // reaching for const beside a string attribute is the natural thing to write
    const values = <AttributeValue>[
      AttributeValue.string('a'),
      AttributeValue.number(5),
      AttributeValue.bool(true),
      AttributeValue.nullValue(),
    ];

    expect(values, hasLength(4));
    expect(values[1], AttributeValue.number(5.0));
  });

  test('number(num) normalizes an integer to a double', () {
    expect(toFrbContextValue(AttributeValue.number(42)),
        const frb.FrbContextValue.number(42.0));
    expect(toFrbContextValue(AttributeValue.number(3.5)),
        const frb.FrbContextValue.number(3.5));
  });

  test('an empty string list stays a string list', () {
    expect(toFrbContextValue(AttributeValue.stringList(const [])),
        const frb.FrbContextValue.stringList([]));
  });

  test('value equality compares by value', () {
    expect(const AttributeValue.string('x'), const AttributeValue.string('x'));
    expect(AttributeValue.number(1), AttributeValue.number(1.0));
    expect(AttributeValue.stringList(['a']), AttributeValue.stringList(['a']));
    expect(const AttributeValue.string('x') == const AttributeValue.bool(true),
        isFalse);
  });

  test('stringList stores an unmodifiable copy so later mutation is inert', () {
    final source = ['a'];
    final value = AttributeValue.stringList(source);
    source.add('b');
    expect(toFrbContextValue(value), const frb.FrbContextValue.stringList(['a']));
  });

  test('toFrbAttributes snapshots the map so later source mutation is inert', () {
    final source = {'plan': const AttributeValue.string('pro')};
    final snapshot = toFrbAttributes(source);
    source['plan'] = const AttributeValue.string('team');
    source['extra'] = const AttributeValue.bool(true);
    source.remove('plan');
    expect(snapshot, {'plan': const frb.FrbContextValue.string('pro')});
  });

  test('snapshotKeys copies the list so later source mutation is inert', () {
    final source = ['a'];
    final snapshot = snapshotKeys(source);
    source.add('b');
    expect(snapshot, ['a']);
    expect(() => snapshot.add('c'), throwsUnsupportedError);
  });
}
