import 'dart:async';

import 'package:coproduct/coproduct.dart';
import 'package:coproduct/src/client_backend.dart';
import 'package:coproduct/src/coproduct_client.dart';
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
    final client = _FakeBackend(() => creates += 1);
    addTearDown(() {
      for (final controller in client.controllers) {
        controller.close();
      }
    });
    Widget host(Object? defaultValue) => Directionality(
          textDirection: TextDirection.ltr,
          child: CoproductFlagBuilder.jsonFlag(
            client: client.client,
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
    final client = _FakeBackend(() => creates += 1);
    addTearDown(() {
      for (final controller in client.numberControllers) {
        controller.close();
      }
    });
    Widget host() => Directionality(
          textDirection: TextDirection.ltr,
          child: CoproductFlagBuilder.numberFlag(
            client: client.client,
            flagKey: 'k',
            defaultValue: double.nan,
            builder: (context, value, child) => Text('$value'),
          ),
        );

    await tester.pumpWidget(host());
    await tester.pumpWidget(host());

    expect(creates, 1);
  });

  testWidgets('omitting client resolves the nearest scope', (tester) async {
    final scoped = _FakeBackend(() {});

    await tester.pumpWidget(_host(
      scoped.client,
      CoproductFlagBuilder.stringFlag(
        flagKey: 'greeting',
        defaultValue: 'fallback',
        builder: (context, value, child) => Text(value),
      ),
    ));

    expect(scoped.registrations, 1);
    expect(find.text('greeting'), findsOneWidget,
        reason: 'the scoped client is the one that was observed');
  });

  testWidgets('an explicit client works with no scope anywhere',
      (tester) async {
    final explicit = _FakeBackend(() {});

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: CoproductFlagBuilder.stringFlag(
        client: explicit.client,
        flagKey: 'greeting',
        defaultValue: 'fallback',
        builder: (context, value, child) => Text(value),
      ),
    ));

    expect(explicit.registrations, 1);
  });

  testWidgets('an explicit client wins over a surrounding scope',
      (tester) async {
    final scoped = _FakeBackend(() {});
    final explicit = _FakeBackend(() {});

    await tester.pumpWidget(_host(
      scoped.client,
      CoproductFlagBuilder.stringFlag(
        client: explicit.client,
        flagKey: 'greeting',
        defaultValue: 'fallback',
        builder: (context, value, child) => Text(value),
      ),
    ));

    expect(explicit.registrations, 1);
    expect(scoped.registrations, 0);
  });

  testWidgets('an explicit client does not depend on the scope',
      (tester) async {
    final explicit = _FakeBackend(() {});
    final scopedFirst = _FakeBackend(() {});
    final scopedSecond = _FakeBackend(() {});
    var builds = 0;

    // One widget instance, reused beneath both scopes. updateChild skips an
    // identical child, so the ordinary parent-driven rebuild is gone. An
    // inherited notification marks a dependent dirty by a separate path, so if
    // the facade wrongly looked the scope up despite an explicit client, this
    // subtree would rebuild and the count would move
    final flagWidget = CoproductFlagBuilder.stringFlag(
      client: explicit.client,
      flagKey: 'greeting',
      defaultValue: 'fallback',
      builder: (context, value, child) {
        builds += 1;
        return Text(value);
      },
    );

    await tester.pumpWidget(_host(scopedFirst.client, flagWidget));
    expect(builds, 1);

    await tester.pumpWidget(_host(scopedSecond.client, flagWidget));
    expect(builds, 1,
        reason: 'an explicit client registers no scope dependency');
  });

  testWidgets('replacing the scoped client re-registers exactly once',
      (tester) async {
    final first = _FakeBackend(() {});
    final second = _FakeBackend(() {});
    final flagWidget = CoproductFlagBuilder.stringFlag(
      flagKey: 'greeting',
      defaultValue: 'fallback',
      builder: (context, value, child) => Text(value),
    );

    await tester.pumpWidget(_host(first.client, flagWidget));
    expect(first.registrations, 1);

    await tester.pumpWidget(_host(second.client, flagWidget));

    expect(second.registrations, 1);
    expect(first.cancellations, 1,
        reason: 'the observation on the old client is disposed');
    expect(first.registrations, 1,
        reason: 'and the old client is never observed again');
  });

  testWidgets('a keyed reorder moves observations rather than replacing them',
      (tester) async {
    final client = _FakeBackend(() {});
    Widget flag(String flagKey) => CoproductFlagBuilder.stringFlag(
          key: ValueKey<String>(flagKey),
          client: client.client,
          flagKey: flagKey,
          defaultValue: 'fallback',
          builder: (context, value, child) => Text(value),
        );
    final alpha = flag('alpha');
    final beta = flag('beta');

    await tester.pumpWidget(_column([alpha, beta]));
    expect(client.registrations, 2);
    expect(client.cancellations, 0);

    await tester.pumpWidget(_column([beta, alpha]));

    // Lifecycle, not rendered output. With the key on the inner widget the
    // values would still be correct while both observations were torn down and
    // rebuilt, which is exactly what a value-only assertion would miss
    expect(client.registrations, 2,
        reason: 'a keyed reorder moves elements, it does not re-register');
    expect(client.cancellations, 0);
  });

  // The scope fallback and the key placement are written out five times, once
  // per entry point, so a test that exercises one proves nothing about the
  // other four. These three cover all five
  List<Widget> everyEntryPoint({CoproductClient? client}) => [
        CoproductFlagBuilder.boolFlag(
            client: client,
            flagKey: 'b',
            defaultValue: false,
            builder: (context, value, child) => Text('$value')),
        CoproductFlagBuilder.stringFlag(
            client: client,
            flagKey: 's',
            defaultValue: 'd',
            builder: (context, value, child) => Text(value)),
        CoproductFlagBuilder.intFlag(
            client: client,
            flagKey: 'i',
            defaultValue: 0,
            builder: (context, value, child) => Text('$value')),
        CoproductFlagBuilder.numberFlag(
            client: client,
            flagKey: 'n',
            defaultValue: 0,
            builder: (context, value, child) => Text('$value')),
        CoproductFlagBuilder.jsonFlag(
            client: client,
            flagKey: 'j',
            defaultValue: null,
            builder: (context, value, child) => Text('$value')),
      ];

  testWidgets('every entry point resolves the scope when client is omitted',
      (tester) async {
    final scoped = _FakeBackend(() {});

    await tester.pumpWidget(_host(scoped.client, _column(everyEntryPoint())));

    expect(scoped.observedKeys, ['b', 's', 'i', 'n', 'j'],
        reason: 'each entry point must reach the scoped client');
  });

  testWidgets('every entry point accepts an explicit client with no scope',
      (tester) async {
    final explicit = _FakeBackend(() {});

    await tester.pumpWidget(_column(everyEntryPoint(client: explicit.client)));

    expect(explicit.observedKeys, ['b', 's', 'i', 'n', 'j']);
  });

  test('every entry point puts the key on the widget it returns', () {
    // The returned widget is what a parent reconciles, so the key has to be on
    // it rather than on anything it wraps. Constructing does not build, so no
    // observation is registered here
    const key = ValueKey<String>('flag');
    final client = _FakeBackend(() {});
    for (final widget in [
      CoproductFlagBuilder.boolFlag(
          key: key,
          client: client.client,
          flagKey: 'b',
          defaultValue: false,
          builder: (context, value, child) => const SizedBox.shrink()),
      CoproductFlagBuilder.stringFlag(
          key: key,
          client: client.client,
          flagKey: 's',
          defaultValue: 'd',
          builder: (context, value, child) => const SizedBox.shrink()),
      CoproductFlagBuilder.intFlag(
          key: key,
          client: client.client,
          flagKey: 'i',
          defaultValue: 0,
          builder: (context, value, child) => const SizedBox.shrink()),
      CoproductFlagBuilder.numberFlag(
          key: key,
          client: client.client,
          flagKey: 'n',
          defaultValue: 0,
          builder: (context, value, child) => const SizedBox.shrink()),
      CoproductFlagBuilder.jsonFlag(
          key: key,
          client: client.client,
          flagKey: 'j',
          defaultValue: null,
          builder: (context, value, child) => const SizedBox.shrink()),
    ]) {
      expect(widget.key, same(key));
    }
    expect(client.observedKeys, isEmpty);
  });

  test('every typed entry point keeps its documented signature', () {
    // Each tear-off is assigned to an explicitly typed variable, so a renamed,
    // reordered, or retyped parameter fails to compile here rather than
    // silently breaking a caller. The facade needs a live client, so this is a
    // signature pin, and behavior is proven on device
    final Widget Function({
      Key? key,
      CoproductClient? client,
      required String flagKey,
      required bool defaultValue,
      required ValueWidgetBuilder<bool> builder,
      Widget? child,
    }) boolFlag = CoproductFlagBuilder.boolFlag;
    final Widget Function({
      Key? key,
      CoproductClient? client,
      required String flagKey,
      required String defaultValue,
      required ValueWidgetBuilder<String> builder,
      Widget? child,
    }) stringFlag = CoproductFlagBuilder.stringFlag;
    final Widget Function({
      Key? key,
      CoproductClient? client,
      required String flagKey,
      required int defaultValue,
      required ValueWidgetBuilder<int> builder,
      Widget? child,
    }) intFlag = CoproductFlagBuilder.intFlag;
    final Widget Function({
      Key? key,
      CoproductClient? client,
      required String flagKey,
      required double defaultValue,
      required ValueWidgetBuilder<double> builder,
      Widget? child,
    }) numberFlag = CoproductFlagBuilder.numberFlag;
    final Widget Function({
      Key? key,
      CoproductClient? client,
      required String flagKey,
      required Object? defaultValue,
      required ValueWidgetBuilder<Object?> builder,
      Widget? child,
    }) jsonFlag = CoproductFlagBuilder.jsonFlag;

    expect([boolFlag, stringFlag, intFlag, numberFlag, jsonFlag],
        everyElement(isNotNull));
  });
}

/// Instrumented value source behind a genuine client, so these tests exercise
/// the real FlagObservation while registration and cancellation stay countable
/// here. Routing everything else through noSuchMethod means only the methods
/// under test have to exist
class _FakeBackend implements CoproductClientBackend {
  _FakeBackend(this.onCreate);

  /// A genuine client over this backend, so the widgets under test exercise the
  /// real observation implementation while the instrumentation stays here
  late final CoproductClient client = createClientForBackend(this);

  final void Function() onCreate;
  final List<StreamController<String?>> controllers = [];
  final List<StreamController<double?>> numberControllers = [];
  final List<StreamController<bool?>> boolControllers = [];
  final List<StreamController<int?>> intControllers = [];

  /// How many observations this client has handed out, and how many of those
  /// have been cancelled. A reorder that preserves state moves neither
  int registrations = 0;
  int cancellations = 0;

  /// Every flag key observed, in order, so a test can prove which entry point
  /// reached this client rather than only how many did
  final List<String> observedKeys = [];

  @override
  ObservationHandle<bool> observeBool(String key) {
    registrations += 1;
    observedKeys.add(key);
    onCreate();
    final controller = StreamController<bool?>();
    boolControllers.add(controller);
    return ObservationHandle<bool>(
      seed: null,
      events: controller.stream,
      cancel: () => cancellations += 1,
    );
  }

  @override
  ObservationHandle<int> observeInt(String key) {
    registrations += 1;
    observedKeys.add(key);
    onCreate();
    final controller = StreamController<int?>();
    intControllers.add(controller);
    return ObservationHandle<int>(
      seed: null,
      events: controller.stream,
      cancel: () => cancellations += 1,
    );
  }

  @override
  ObservationHandle<String> observeString(String key) {
    registrations += 1;
    observedKeys.add(key);
    onCreate();
    final controller = StreamController<String?>();
    controllers.add(controller);
    return ObservationHandle<String>(
      seed: key,  // so the rendered text says which observation is on screen,
      events: controller.stream,
      cancel: () => cancellations += 1,
    );
  }

  @override
  ObservationHandle<double> observeNumber(String key) {
    registrations += 1;
    observedKeys.add(key);
    onCreate();
    final controller = StreamController<double?>();
    numberControllers.add(controller);
    return ObservationHandle<double>(
      seed: null,
      events: controller.stream,
      cancel: () {},
    );
  }

  @override
  ObservationHandle<String> observeJson(String key) {
    registrations += 1;
    observedKeys.add(key);
    onCreate();
    final controller = StreamController<String?>();
    controllers.add(controller);
    return ObservationHandle<String>(
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

Widget _host(CoproductClient client, Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: CoproductScope(client: client, child: child),
    );

Widget _column(List<Widget> children) => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: children),
    );
