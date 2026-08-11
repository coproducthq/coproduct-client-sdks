import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coproduct/coproduct.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await Coproduct.shutdown();
  });

  testWidgets('serves targeted values proving identity and auto attributes',
      (tester) async {
    const endpoint = String.fromEnvironment('COPRODUCT_ENDPOINT');
    const key = String.fromEnvironment('COPRODUCT_SDK_KEY');
    const expectedRaw = String.fromEnvironment('COPRODUCT_EXPECTED');
    expect(endpoint, isNotEmpty, reason: 'runner must pass COPRODUCT_ENDPOINT');
    expect(key, isNotEmpty, reason: 'runner must pass COPRODUCT_SDK_KEY');
    final expected =
        (jsonDecode(expectedRaw) as List).cast<Map<String, dynamic>>();
    // Fail red if the expected table is degenerate or short, so an empty or
    // truncated table cannot pass green having proven nothing about the flags
    // Twelve is the flag count locked by the host flag_table_test
    expect(expected, hasLength(12),
        reason: 'the runner must pass all twelve flag expectations');

    final client = await Coproduct.initialize(
      sdkKey: key,
      config: CoproductConfig(
        endpoint: Uri.parse(endpoint),
        startupTimeout: const Duration(seconds: 10),
      ),
    );
    // A unique key means a cold cache, so Ready proves a real first poll against
    // the fixture rather than a stale snapshot
    expect(client.state, ProviderState.ready);

    Object? read(Map<String, dynamic> row) {
      final flagKey = row['key'] as String;
      final def = row['callerDefault'];
      return switch (row['getter'] as String) {
        'boolean' => client.getBool(flagKey, def as bool),
        'string' => client.getString(flagKey, def as String),
        'integer' => client.getInt(flagKey, def as int),
        'number' => client.getNumber(flagKey, (def as num).toDouble()),
        'json' => client.getJson(flagKey, def),
        _ => throw StateError('unknown getter ${row['getter']}'),
      };
    }

    // Before identify: the fetch control and every auto flag resolve to their
    // target, and every identity flag falls through to its miss
    for (final row in expected) {
      final want = row['kind'] == 'identity' ? row['miss'] : row['target'];
      expect(read(row), want, reason: 'pre-identify ${row['key']}');
    }

    await client.identify(
      userId: 'acceptance-user',
      attributes: {'plan': const AttributeValue.string('pro')},
    );

    // After identify: every flag resolves to its target, proving both identity
    // targeting and that the automatic layer survived identity replacement
    for (final row in expected) {
      expect(read(row), row['target'], reason: 'post-identify ${row['key']}');
    }
  });

  testWidgets('a delayed poll, its release, and a flag removal are observable',
      (tester) async {
    const endpoint = String.fromEnvironment('COPRODUCT_ENDPOINT');
    // A key of its own, so this test's snapshot cache starts cold and the
    // held first poll really is this app's first sight of a snapshot
    const key = String.fromEnvironment('COPRODUCT_SDK_KEY_CONTROL');
    expect(endpoint, isNotEmpty, reason: 'runner must pass COPRODUCT_ENDPOINT');
    expect(key, isNotEmpty,
        reason: 'runner must pass COPRODUCT_SDK_KEY_CONTROL');

    _http = HttpClient();
    addTearDown(() => _http.close(force: true));
    // Leave the fixture clean for whatever runs next in this file, whether or
    // not this test reaches its own release
    addTearDown(() async {
      // Assert rather than fire and forget, so a route typo cannot leave the
      // cleanup silently ineffective for whatever runs next
      expect(await _post('$endpoint/control/reset'), 200,
          reason: 'the fixture must be reset for the next test');
    });

    // Hold the first poll before the app starts, so initialize races a fixture
    // that will not answer until told to
    expect(await _arm(endpoint), 200);

    final client = await Coproduct.initialize(
      sdkKey: key,
      config: CoproductConfig(
        endpoint: Uri.parse(endpoint),
        // Deliberately short: initialize must return on the budget rather than
        // waiting out the held response
        startupTimeout: const Duration(seconds: 2),
      ),
    );

    // The held poll means no snapshot has landed, so the provider is not ready
    // and every read serves the caller's default
    expect(client.state, isNot(ProviderState.ready),
        reason: 'initialize returned on its budget with the poll still held');
    expect(
        client.getString('fetch-control', 'default-before'), 'default-before',
        reason: 'with no snapshot the getter serves the caller default');

    // The fixture acknowledges that the request arrived and is being held
    await _waitForFixtureState(endpoint, 'blocked');

    // Release it and the snapshot lands, which is the poll-driven update
    expect(await _release(endpoint), 200);
    await _waitUntil(
        () async =>
            client.getString('fetch-control', 'default-before') == 'fetched',
        because: 'the released poll delivers the snapshot');
    expect(client.state, ProviderState.ready);

    // The scheduler drops a foreground request while a poll is still in flight,
    // so the release above must have fully settled before the resume. Reaching
    // Ready is that proof
    //
    // Now remove the flag from the served snapshot and drive another poll. The
    // getter must fall back to the caller's default rather than to an empty
    // string, which is what proves a removed flag reads as unavailable
    expect(await _setSnapshot(endpoint, omitFlags: ['fetch-control']), 200);
    final before = await _servedPolls(endpoint);
    await driveSecondPoll(tester);
    await _waitUntil(() async => await _servedPolls(endpoint) > before,
        because: 'the seam drives a second poll');
    await _waitUntil(
        () async =>
            client.getString('fetch-control', 'default-after') ==
            'default-after',
        because: 'a flag that left the snapshot serves the caller default');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('observations react to a poll, an identity change, and removal',
      (tester) async {
    const endpoint = String.fromEnvironment('COPRODUCT_ENDPOINT');
    // Its own key, so no cached snapshot exists and the observations below
    // really do start from the caller defaults
    const key = String.fromEnvironment('COPRODUCT_SDK_KEY_REACTIVE');
    expect(endpoint, isNotEmpty, reason: 'runner must pass COPRODUCT_ENDPOINT');
    expect(key, isNotEmpty,
        reason: 'runner must pass COPRODUCT_SDK_KEY_REACTIVE');

    _http = HttpClient();
    addTearDown(() => _http.close(force: true));
    addTearDown(() async {
      expect(await _post('$endpoint/control/reset'), 200,
          reason: 'the fixture must be reset for the next test');
    });

    expect(await _arm(endpoint), 200);

    final client = await Coproduct.initialize(
      sdkKey: key,
      config: CoproductConfig(
        endpoint: Uri.parse(endpoint),
        startupTimeout: const Duration(seconds: 2),
      ),
    );

    // Defaults chosen to differ from both the miss and the target value, so
    // every transition below is a real change rather than a coincidence
    const stringDefault = 'reactive-default';
    const jsonDefault = {'reactive': 'default'};
    final boolFlag = client.observeBool('identity-bool', true);
    final stringFlag = client.observeString('identity-string', stringDefault);
    final intFlag = client.observeInt('identity-int', -7);
    final numberFlag = client.observeNumber('identity-number', -2.5);
    final jsonFlag = client.observeJson('identity-json', jsonDefault);
    final observations = [boolFlag, stringFlag, intFlag, numberFlag, jsonFlag];
    addTearDown(() {
      for (final observation in observations) {
        observation.dispose();
      }
    });

    // Registered while the first poll is still held, so every observation is
    // seeded from the caller default exactly as the matching getter would be
    expect(boolFlag.value, isTrue);
    expect(stringFlag.value, stringDefault);
    expect(intFlag.value, -7);
    expect(numberFlag.value, -2.5);
    expect(jsonFlag.value, jsonDefault);

    // A real client, a real scope, and a builder that omits client entirely
    // This is the composition a developer actually writes, and every other test
    // of these two widgets uses an interface fake, so this is the only place
    // the whole path runs against the native SDK
    await tester.pumpWidget(CoproductScope(
      client: client,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: CoproductFlagBuilder.stringFlag(
          flagKey: 'identity-string',
          defaultValue: stringDefault,
          builder: _renderFlag,
        ),
      ),
    ));
    expect(find.text(stringDefault), findsOneWidget,
        reason: 'the builder seeds from the scoped client while the poll is '
            'still held');

    await _waitForFixtureState(endpoint, 'blocked');
    expect(await _release(endpoint), 200);

    // The released poll lands the snapshot. No identity is set yet, so every
    // identity flag resolves to its miss value
    //
    // These are five independent streams. Delivery is ordered within one
    // subscription, but nothing orders one subscription against another, so
    // the wait covers all five rather than waiting on one and asserting the
    // rest. The expects afterward exist to name which value was wrong
    await _waitUntil(
        () async =>
            boolFlag.value == false &&
            stringFlag.value == 'identity-string-missed' &&
            intFlag.value == 0 &&
            numberFlag.value == 0.0 &&
            _sameJson(jsonFlag.value, {'variant': 'missed'}),
        because: 'the released poll delivers the snapshot to every observation',
        observed: () => _renderAll(
            boolFlag, stringFlag, intFlag, numberFlag, jsonFlag));
    expect(boolFlag.value, isFalse);
    expect(stringFlag.value, 'identity-string-missed');
    expect(intFlag.value, 0);
    expect(numberFlag.value, 0.0);
    expect(jsonFlag.value, {'variant': 'missed'});

    await _pumpUntilText(tester, 'identity-string-missed',
        because: 'the released poll reaches the widget, not only the client');

    // An identity change re-evaluates every observation without a poll
    await client.identify(
        userId: 'reactive-user',
        attributes: {'plan': const AttributeValue.string('pro')});

    const jsonTarget = {
      'theme': 'acceptance',
      'items': [1, 2, 3],
    };
    await _waitUntil(
        () async =>
            boolFlag.value == true &&
            stringFlag.value == 'identity-string-matched' &&
            intFlag.value == 42 &&
            numberFlag.value == 3.5 &&
            _sameJson(jsonFlag.value, jsonTarget),
        because: 'an identity change re-evaluates every observation',
        observed: () => _renderAll(
            boolFlag, stringFlag, intFlag, numberFlag, jsonFlag));
    expect(boolFlag.value, isTrue);
    expect(stringFlag.value, 'identity-string-matched');
    expect(intFlag.value, 42, reason: 'a fractional number truncates for int');
    expect(numberFlag.value, 3.5);
    expect(jsonFlag.value, jsonTarget);

    await _pumpUntilText(tester, 'identity-string-matched',
        because: 'an identity change rebuilds the widget');

    // A disposed observation stops receiving while a live one on the same key
    // keeps receiving. On its own this does not prove the native session was
    // cancelled, because a Dart-only cancel would look identical from here
    // It is one leg of a composite proof: the host tests prove dispose invokes
    // the native cancel, the core's own tests prove that cancel removes the
    // subscription, and this proves the two are wired together on a device
    // while fanout is demonstrably still running
    final live = client.observeString('identity-string', stringDefault);
    final disposed = client.observeString('identity-string', stringDefault);
    addTearDown(live.dispose);
    expect(live.value, 'identity-string-matched');
    expect(disposed.value, 'identity-string-matched');
    disposed.dispose();

    expect(await _setSnapshot(endpoint, omitFlags: ['identity-string']), 200);
    final before = await _servedPolls(endpoint);
    await driveSecondPoll(tester);
    await _waitUntil(() async => await _servedPolls(endpoint) > before,
        because: 'the foreground path drives a second poll');

    // The flag left the snapshot, so every live observation of it reverts to
    // the caller default while the disposed one keeps the value it last saw
    // Both live observations are waited on, for the same independent-stream
    // reason as above
    await _waitUntil(
        () async =>
            live.value == stringDefault && stringFlag.value == stringDefault,
        because: 'a flag that left the snapshot serves the caller default');
    expect(disposed.value, 'identity-string-matched',
        reason: 'a disposed observation receives nothing further');

    await _pumpUntilText(tester, stringDefault,
        because: 'a flag that left the snapshot returns the widget to the '
            'caller default');

    // Finally, re-enter the SDK from inside a listener, synchronously and
    // asynchronously. Both are ordinary things to write in a listener, and
    // this proves neither one wedges: the synchronous read returns, and the
    // identify completes and is itself delivered
    //
    // Neither one proves the delivery lane is free while a listener runs. A
    // getter resolves snapshot and context state and never takes the
    // per-subscription lane, and the identify is not awaited inside the
    // notification. Delivery reaches Dart through an isolate port enqueue, so
    // no Dart code can run inside the sink write that hands a value over
    final errors = <Object>[];
    String? readFromInsideNotification;
    final reentrant = client.observeBool('identity-bool', true);
    addTearDown(reentrant.dispose);
    expect(reentrant.value, isTrue, reason: 'the pro plan is still identified');

    final seen = <bool>[];
    void onChange() {
      seen.add(reentrant.value);
      if (seen.length != 1) return;
      // A synchronous re-entry first, which a developer might well write
      readFromInsideNotification =
          client.getString('identity-string', stringDefault);
      // Then an asynchronous one, which must complete and deliver in turn
      unawaited(client.identify(
        userId: 'reentrant-user',
        attributes: {'plan': const AttributeValue.string('pro')},
      ).catchError((Object error, StackTrace stack) {
        // A handler for a Future<void> must not return a value, so this records
        // and returns nothing rather than handing back the list's add result
        errors.add(error);
      }));
    }

    reentrant.addListener(onChange);
    addTearDown(() => reentrant.removeListener(onChange));

    // Drop out of the matching plan, which flips the flag and fires the listener
    await client.identify(
        userId: 'reentrant-user',
        attributes: {'plan': const AttributeValue.string('free')});

    // Stop waiting as soon as the identify fails, so a failure is reported as
    // itself rather than as a timeout that says nothing about why
    await _waitUntil(() async => seen.length >= 2 || errors.isNotEmpty,
        because: 'an identify issued from a listener must complete and deliver');
    expect(errors, isEmpty,
        reason: 'a reentrant identify must not fail');
    expect(seen, [false, true],
        reason: 'the reentrant identify was observed after the one that '
            'triggered it');
    expect(readFromInsideNotification, isNotNull,
        reason: 'a synchronous SDK call from inside a notification returns');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

// Top level rather than a closure, so the widget tree above reads as the shape
// a developer would write rather than as test scaffolding
Widget _renderFlag(BuildContext context, String value, Widget? child) =>
    Text(value);

/// Drives a second poll through the production foreground path: the SDK binds
/// an AppLifecycleListener and the scheduler refreshes on resume without waiting
/// out the poll interval. The states are walked one legal step at a time because
/// the framework asserts on transitions that skip a step, and an assert inside
/// the observer aborts the dispatch before the SDK's listener is notified
Future<void> driveSecondPoll(WidgetTester tester) async {
  for (final step in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(step);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

// The control channel shares the fixture's port, so the endpoint the runner
// already passes reaches it

Future<int> _arm(String endpoint) => _post('$endpoint/control/block-next-poll');

Future<int> _release(String endpoint) => _post('$endpoint/control/release');

Future<int> _setSnapshot(String endpoint, {required List<String> omitFlags}) =>
    _post('$endpoint/control/snapshot',
        body: jsonEncode({'omitFlags': omitFlags}));

// One client for the whole test, closed in teardown. The wait loops below can
// issue hundreds of requests, and a client per request left to garbage
// collection builds real socket pressure, turning a diagnostic timeout into a
// flaky device failure
late HttpClient _http;

Future<int> _post(String url, {String? body}) async {
  final req = await _http.postUrl(Uri.parse(url));
  if (body != null) {
    req.headers.contentType = ContentType.json;
    req.write(body);
  }
  final res = await req.close();
  await res.drain<void>();
  return res.statusCode;
}

Future<Map<String, Object?>> _fixtureState(String endpoint) async {
  final req = await _http.getUrl(Uri.parse('$endpoint/control/state'));
  final res = await req.close();
  return jsonDecode(await utf8.decodeStream(res)) as Map<String, Object?>;
}

Future<int> _servedPolls(String endpoint) async =>
    (await _fixtureState(endpoint))['servedPolls']! as int;

Future<void> _waitForFixtureState(String endpoint, String want) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if ((await _fixtureState(endpoint))['state'] == want) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('fixture never reached state $want');
}

// Waits on a real timer rather than tester.pump. The lifecycle sequence that
// drives a second poll takes the app through paused, which disables frames, so
// a pump can never return. These assertions read the client rather than the
// widget tree, so no frame is needed to observe them
Future<void> _waitUntil(Future<bool> Function() done,
    {required String because, String Function()? observed}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  // A wait that covers several values has to say which ones were wrong, or a
  // timeout reports only that something did not happen
  final detail = observed == null ? '' : '\nobserved: ${observed()}';
  fail('timed out waiting: $because$detail');
}

String _renderAll(
        FlagObservation<bool> boolFlag,
        FlagObservation<String> stringFlag,
        FlagObservation<int> intFlag,
        FlagObservation<double> numberFlag,
        FlagObservation<Object?> jsonFlag) =>
    'bool=${boolFlag.value} string=${stringFlag.value} '
    'int=${intFlag.value} number=${numberFlag.value} '
    'json=${jsonEncode(jsonFlag.value)}';

// Waits for the widget under test rather than for a value on some other
// subscription. The builder owns its own observation, and independent
// subscriptions are not ordered against each other, so a wait satisfied by a
// direct observation says nothing about whether the builder's event has landed
Future<void> _pumpUntilText(WidgetTester tester, String expected,
    {required String because}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    if (find.text(expected).evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('the widget never rendered "$expected": $because');
}

// Structural comparison for a JSON observation inside a wait predicate, where a
// mismatch must simply retry rather than fail. Keys are sorted before encoding
// because object key order is not preserved end to end: the core re-serializes
// a JSON variation, so a flag declared as {theme, items} arrives as
// {items, theme}. The expect that follows each wait is the authoritative
// check, and the matcher's map equality is order-insensitive too
bool _sameJson(Object? actual, Object? expected) =>
    jsonEncode(_canonicalJson(actual)) == jsonEncode(_canonicalJson(expected));

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key as String).toList()..sort();
    return {for (final key in keys) key: _canonicalJson(value[key])};
  }
  if (value is List) {
    return [for (final element in value) _canonicalJson(element)];
  }
  return value;
}
