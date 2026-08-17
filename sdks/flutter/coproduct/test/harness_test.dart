import 'package:coproduct/coproduct.dart';
import 'package:coproduct/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a flag change rebuilds the widget', (tester) async {
    final harness = CoproductTestHarness()..setBool('new-checkout', false);
    addTearDown(harness.shutdown);

    await tester.pumpWidget(MaterialApp(
      home: CoproductScope(
        client: harness.client,
        child: CoproductFlagBuilder.boolFlag(
          flagKey: 'new-checkout',
          defaultValue: false,
          builder: (context, enabled, child) => Text(enabled ? 'new' : 'old'),
        ),
      ),
    ));
    expect(find.text('old'), findsOneWidget);

    harness.setBool('new-checkout', true);
    await tester.pumpAndSettle();
    expect(find.text('new'), findsOneWidget);
  });

  testWidgets('the widget serves its default until a value is set',
      (tester) async {
    final harness = CoproductTestHarness();
    addTearDown(harness.shutdown);

    await tester.pumpWidget(MaterialApp(
      home: CoproductScope(
        client: harness.client,
        child: CoproductFlagBuilder.stringFlag(
          flagKey: 'greeting',
          defaultValue: 'hi',
          builder: (context, value, child) => Text(value),
        ),
      ),
    ));
    expect(find.text('hi'), findsOneWidget);

    harness.setString('greeting', 'hello');
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);

    harness.removeFlag('greeting');
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsOneWidget);
  });

  test('a fresh harness reports ready', () {
    expect(CoproductTestHarness().client.state, ProviderState.ready);
  });

  test('setProviderState is visible to client.state synchronously', () {
    final harness = CoproductTestHarness();
    expect(ProviderState.values, hasLength(5));
    for (final state in ProviderState.values) {
      harness.setProviderState(state);
      expect(harness.client.state, state);
    }
  });

  test('the client reads what the harness sets, through every getter', () {
    final harness = CoproductTestHarness()
      ..setBool('b', true)
      ..setString('s', 'x')
      ..setNumber('n', 42.75)
      ..setJson('j', {'a': 1});

    expect(harness.client.getBool('b', false), isTrue);
    expect(harness.client.getString('s', 'd'), 'x');
    expect(harness.client.getInt('n', 0), 42);
    expect(harness.client.getNumber('n', 0), 42.75);
    expect(harness.client.getJson('j', const <String, Object?>{}), {'a': 1});
  });

  test('replacing a JSON integer with a float updates the public getter', () {
    // The adopter-facing symptom of the storage-equality defect: a test author
    // set 1.0 and the genuine client kept serving the previous int
    final harness = CoproductTestHarness()..setJson('k', 1);
    addTearDown(harness.shutdown);

    expect(harness.client.getJson('k', null), isA<int>());

    harness.setJson('k', 1.0);

    expect(harness.client.getJson('k', null), isA<double>());
    expect(harness.client.getJson('k', null), 1.0);
  });

  test('setNumber rejects a non-finite value', () {
    expect(() => CoproductTestHarness().setNumber('k', double.nan),
        throwsArgumentError);
  });

  test('setJson rejects a value outside the JSON domain', () {
    expect(() => CoproductTestHarness().setJson('k', Object()),
        throwsArgumentError);
  });

  test('a setter after shutdown throws StateError', () async {
    final harness = CoproductTestHarness();
    await harness.shutdown();
    expect(() => harness.setBool('k', true), throwsStateError);
  });

  test('identity is inspectable and does not change flag values', () async {
    final harness = CoproductTestHarness()..setBool('k', true);
    expect(harness.targetingKey, 'test-anonymous-id');

    await harness.client.identify(
      userId: 'u1',
      attributes: {'plan': const AttributeValue.string('pro')},
    );

    expect(harness.targetingKey, 'u1');
    expect(harness.developerAttributes,
        {'plan': const AttributeValue.string('pro')});
    expect(harness.client.previousAnonymousId, 'test-anonymous-id');
    expect(harness.client.getBool('k', false), isTrue);
  });

  test('developerAttributes is unmodifiable', () async {
    final harness = CoproductTestHarness();
    await harness.client
        .updateAttributes({'a': const AttributeValue.string('1')});
    expect(() => harness.developerAttributes['b'] = const AttributeValue.string('2'),
        throwsUnsupportedError);
  });
}
