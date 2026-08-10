import 'dart:async';

import 'package:coproduct/coproduct.dart';
import 'package:coproduct/src/coproduct_flag_builder.dart';
import 'package:coproduct/src/flag_observation.dart';
import 'package:coproduct/src/json_value.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<StreamController<String?>> controllers;
  late int creates;
  late int cancels;

  setUp(() {
    controllers = [];
    creates = 0;
    cancels = 0;
  });

  tearDown(() {
    for (final controller in controllers) {
      controller.close();
    }
  });

  FlagObservation<String> createString(String? seed, String defaultValue) {
    creates += 1;
    final controller = StreamController<String?>();
    controllers.add(controller);
    return stringObservation(
      defaultValue: defaultValue,
      seed: seed,
      events: controller.stream,
      cancel: () => cancels += 1,
    );
  }

  Widget host({
    required Object clientIdentity,
    required String flagKey,
    required String defaultValue,
    String? seed,
  }) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: ObservedFlagBuilder<String>(
          clientIdentity: clientIdentity,
          flagKey: flagKey,
          defaultValue: defaultValue,
          create: () => createString(seed, defaultValue),
          unchangedDefault: (a, b) => a == b,
          builder: (context, value, child) => Text(value),
        ),
      );

  testWidgets('serves the seeded value and rebuilds on change', (tester) async {
    final client = Object();
    await tester.pumpWidget(host(
        clientIdentity: client,
        flagKey: 'k',
        defaultValue: 'fallback',
        seed: 'seeded'));

    expect(find.text('seeded'), findsOneWidget);

    controllers.single.add('updated');
    await tester.pumpAndSettle();

    expect(find.text('updated'), findsOneWidget);
  });

  testWidgets('serves the default when the flag is unavailable',
      (tester) async {
    await tester.pumpWidget(host(
        clientIdentity: Object(),
        flagKey: 'k',
        defaultValue: 'fallback',
        seed: null));

    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('creates the observation once across unrelated rebuilds',
      (tester) async {
    final client = Object();
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(host(
          clientIdentity: client,
          flagKey: 'k',
          defaultValue: 'fallback',
          seed: 'seeded'));
    }

    expect(creates, 1,
        reason: 'a rebuild with the same client, key, and default keeps the '
            'live native session');
    expect(cancels, 0);
  });

  testWidgets('re-subscribes when the flag key changes', (tester) async {
    final client = Object();
    await tester.pumpWidget(host(
        clientIdentity: client,
        flagKey: 'first',
        defaultValue: 'fallback',
        seed: 'a'));
    await tester.pumpWidget(host(
        clientIdentity: client,
        flagKey: 'second',
        defaultValue: 'fallback',
        seed: 'b'));

    expect(creates, 2);
    expect(cancels, 1, reason: 'the replaced observation is disposed');
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('re-subscribes when the client changes', (tester) async {
    await tester.pumpWidget(host(
        clientIdentity: Object(),
        flagKey: 'k',
        defaultValue: 'fallback',
        seed: 'a'));
    await tester.pumpWidget(host(
        clientIdentity: Object(),
        flagKey: 'k',
        defaultValue: 'fallback',
        seed: 'b'));

    expect(creates, 2);
    expect(cancels, 1);
  });

  testWidgets('re-subscribes when the default changes', (tester) async {
    final client = Object();
    await tester.pumpWidget(host(
        clientIdentity: client, flagKey: 'k', defaultValue: 'one', seed: null));
    expect(find.text('one'), findsOneWidget);

    await tester.pumpWidget(host(
        clientIdentity: client, flagKey: 'k', defaultValue: 'two', seed: null));

    expect(creates, 2);
    expect(cancels, 1);
    expect(find.text('two'), findsOneWidget);
  });

  testWidgets('disposes its observation when unmounted', (tester) async {
    await tester.pumpWidget(host(
        clientIdentity: Object(),
        flagKey: 'k',
        defaultValue: 'fallback',
        seed: 'a'));
    await tester.pumpWidget(const SizedBox.shrink());

    expect(cancels, 1,
        reason: 'a builder user never disposes, so unmount must');
  });

  testWidgets('a json default that only reorders keys does not re-subscribe',
      (tester) async {
    final client = Object();
    var jsonCreates = 0;
    Widget jsonHost(Map<String, Object?> defaultValue) => Directionality(
          textDirection: TextDirection.ltr,
          child: ObservedFlagBuilder<Object?>(
            clientIdentity: client,
            flagKey: 'k',
            defaultValue: defaultValue,
            create: () {
              jsonCreates += 1;
              final controller = StreamController<String?>();
              controllers.add(controller);
              return jsonObservation(
                defaultValue: defaultValue,
                seed: null,
                events: controller.stream,
                cancel: () => cancels += 1,
              );
            },
            unchangedDefault: jsonDefaultsEqual,
            builder: (context, value, child) => Text('$value'),
          ),
        );

    await tester.pumpWidget(jsonHost({'a': 1, 'b': 2}));
    await tester.pumpWidget(jsonHost({'b': 2, 'a': 1}));

    expect(jsonCreates, 1,
        reason: 'a structurally identical default is not a new default');
  });

  testWidgets('the json facade treats an equivalent default as one default',
      (tester) async {
    // Through the public facade, not the widget directly, because the wiring
    // from jsonFlag to the default comparison is the thing being pinned. The
    // fake client reaches it without a native library
    var creates = 0;
    final client = _FakeClient(() => creates += 1);
    addTearDown(() {
      for (final controller in client.controllers) {
        controller.close();
      }
    });
    Widget host(Object? defaultValue) => Directionality(
          textDirection: TextDirection.ltr,
          child: CoproductFlagBuilder.jsonFlag(
            client: client,
            flagKey: 'k',
            defaultValue: defaultValue,
            builder: (context, value, child) => Text('$value'),
          ),
        );

    // A parent that rebuilds constructs a fresh default object each time. Two
    // that encode to the same document are one default, so the live native
    // session is kept rather than torn down and replaced with an identical one
    await tester.pumpWidget(host(_Encodable()));
    await tester.pumpWidget(host(_Encodable()));
    expect(creates, 1,
        reason: 'the same encoded document is the same default');

    // A default JSON cannot encode is served exactly as supplied, so two of
    // them really are different defaults
    await tester.pumpWidget(host(_Unencodable()));
    expect(creates, 2);
    await tester.pumpWidget(host(_Unencodable()));
    expect(creates, 3,
        reason: 'an unencodable default compares by identity');
  });

  testWidgets('a NaN number default is one default across rebuilds',
      (tester) async {
    // NaN is never equal to itself, so without the NaN rule in the default
    // comparison every parent rebuild would tear down a live native session
    // and register an identical one
    var creates = 0;
    final client = _FakeClient(() => creates += 1);
    addTearDown(() {
      for (final controller in client.numberControllers) {
        controller.close();
      }
    });
    Widget host() => Directionality(
          textDirection: TextDirection.ltr,
          child: CoproductFlagBuilder.numberFlag(
            client: client,
            flagKey: 'k',
            defaultValue: double.nan,
            builder: (context, value, child) => Text('$value'),
          ),
        );

    await tester.pumpWidget(host());
    await tester.pumpWidget(host());

    expect(creates, 1);
  });

  test('every typed entry point keeps its documented signature', () {
    // Each tear-off is assigned to an explicitly typed variable, so a renamed,
    // reordered, or retyped parameter fails to compile here rather than
    // silently breaking a caller. The facade needs a live client, so this is a
    // signature pin, and behavior is proven on device
    final Widget Function({
      Key? key,
      required CoproductClient client,
      required String flagKey,
      required bool defaultValue,
      required ValueWidgetBuilder<bool> builder,
      Widget? child,
    }) boolFlag = CoproductFlagBuilder.boolFlag;
    final Widget Function({
      Key? key,
      required CoproductClient client,
      required String flagKey,
      required String defaultValue,
      required ValueWidgetBuilder<String> builder,
      Widget? child,
    }) stringFlag = CoproductFlagBuilder.stringFlag;
    final Widget Function({
      Key? key,
      required CoproductClient client,
      required String flagKey,
      required int defaultValue,
      required ValueWidgetBuilder<int> builder,
      Widget? child,
    }) intFlag = CoproductFlagBuilder.intFlag;
    final Widget Function({
      Key? key,
      required CoproductClient client,
      required String flagKey,
      required double defaultValue,
      required ValueWidgetBuilder<double> builder,
      Widget? child,
    }) numberFlag = CoproductFlagBuilder.numberFlag;
    final Widget Function({
      Key? key,
      required CoproductClient client,
      required String flagKey,
      required Object? defaultValue,
      required ValueWidgetBuilder<Object?> builder,
      Widget? child,
    }) jsonFlag = CoproductFlagBuilder.jsonFlag;

    expect([boolFlag, stringFlag, intFlag, numberFlag, jsonFlag],
        everyElement(isNotNull));
  });
}

/// Reaches the public facade without a native library. Implementing the client
/// interface and routing everything else through noSuchMethod means only the
/// one method under test has to exist
class _FakeClient implements CoproductClient {
  _FakeClient(this.onCreate);

  final void Function() onCreate;
  final List<StreamController<String?>> controllers = [];
  final List<StreamController<double?>> numberControllers = [];

  @override
  FlagObservation<double> observeNumber(String key, double defaultValue) {
    onCreate();
    final controller = StreamController<double?>();
    numberControllers.add(controller);
    return numberObservation(
      defaultValue: defaultValue,
      seed: null,
      events: controller.stream,
      cancel: () {},
    );
  }

  @override
  FlagObservation<Object?> observeJson(String key, Object? defaultValue) {
    onCreate();
    final controller = StreamController<String?>();
    controllers.add(controller);
    return jsonObservation(
      defaultValue: defaultValue,
      seed: null,
      events: controller.stream,
      cancel: () {},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Encodable {
  Map<String, Object?> toJson() => {'mode': 'same'};
}

class _Unencodable {}
