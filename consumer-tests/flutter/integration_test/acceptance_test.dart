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
}

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
    {required String because}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('timed out waiting: $because');
}
