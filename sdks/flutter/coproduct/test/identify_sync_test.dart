import 'dart:async';
import 'dart:convert';

import 'package:coproduct/src/coproduct_client.dart';
import 'package:coproduct/src/errors.dart';
import 'package:coproduct/src/identify_sync.dart';
import 'package:coproduct/src/paywall/http_paywall_client.dart';
import 'package:coproduct/src/paywall/paywall_client.dart';
import 'package:coproduct/src/testing/in_memory_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records each send, and fails or stalls it on demand
class _Sends {
  final List<(String, String)> pairs = [];
  Object? failWith;
  Future<void>? gate;

  Future<void> call({
    required String appUserId,
    required String targetingKey,
  }) async {
    pairs.add((appUserId, targetingKey));
    if (gate != null) await gate;
    final failure = failWith;
    if (failure != null) throw failure;
  }
}

/// A client over the in-memory backend whose sign-ins go to [sends]. Each
/// call gets its own sent set, so tests do not share the process-wide one
CoproductClient _client(
  _Sends sends, {
  String? Function()? anonymousId,
  List<Object>? errors,
  Set<(String, String, String)>? sentPairs,
}) {
  final backend = InMemoryBackend(anonymousId: 'anon-1');
  return createClientForBackend(
    backend,
    anonymousId: anonymousId ?? () => backend.anonymousId,
    identifySync: IdentifySync(
      scope: 'test',
      send: sends.call,
      onError: (error, stack) => errors?.add(error),
      sentPairs: sentPairs ?? {},
    ),
  );
}

void main() {
  test('anonymousId is null on a client given no reader', () {
    final client = createClientForBackend(InMemoryBackend());
    expect(client.anonymousId, isNull);
  });

  test('identify sends the anonymous id and the user id', () async {
    final sends = _Sends();
    final client = _client(sends);

    await client.identify(userId: 'user-1');
    await pumpEventQueue();

    expect(sends.pairs, [('anon-1', 'user-1')]);
  });

  test('the same pair is sent once, and a new user is sent again', () async {
    final sends = _Sends();
    final client = _client(sends);

    await client.identify(userId: 'user-1');
    await client.identify(userId: 'user-1');
    await pumpEventQueue();
    expect(sends.pairs, [('anon-1', 'user-1')]);

    await client.identify(userId: 'user-2');
    await pumpEventQueue();
    expect(sends.pairs, [('anon-1', 'user-1'), ('anon-1', 'user-2')]);
  });

  test(
    'a pair already sent in this process is not sent by a new client',
    () async {
      // A shutdown and a new initialize build a new client and a new sync over
      // the same sent set
      final sends = _Sends();
      final sent = <(String, String, String)>{};

      await _client(sends, sentPairs: sent).identify(userId: 'user-1');
      await _client(sends, sentPairs: sent).identify(userId: 'user-1');
      await pumpEventQueue();

      expect(sends.pairs, [('anon-1', 'user-1')]);
    },
  );

  test('nothing is sent when the user id equals the anonymous id', () async {
    final sends = _Sends();
    final client = _client(sends);

    await client.identify(userId: 'anon-1');
    await pumpEventQueue();

    expect(sends.pairs, isEmpty);
  });

  test('nothing is sent while the anonymous id is unknown', () async {
    final sends = _Sends();
    final client = _client(sends, anonymousId: () => null);

    await client.identify(userId: 'user-1');
    await pumpEventQueue();

    expect(sends.pairs, isEmpty);
  });

  test('nothing is sent with linkAnonymous: false', () async {
    final sends = _Sends();
    final client = _client(sends);

    await client.identify(userId: 'user-1', linkAnonymous: false);
    await pumpEventQueue();

    expect(sends.pairs, isEmpty);
    expect(client.previousAnonymousId, isNull);
  });

  test('nothing is sent when the local identify fails', () async {
    final sends = _Sends();
    final client = _client(sends);

    await expectLater(
      client.identify(userId: ''),
      throwsA(isA<InvalidTargetingKey>()),
    );
    await pumpEventQueue();

    expect(sends.pairs, isEmpty);
  });

  test('a failing send does not fail identify, and is reported', () async {
    final sends = _Sends()
      ..failWith = const PaywallServerError(statusCode: 500, message: 'boom');
    final errors = <Object>[];
    final client = _client(sends, errors: errors);

    await client.identify(userId: 'user-1');
    await pumpEventQueue();

    expect(client.previousAnonymousId, 'anon-1');
    expect(errors, [isA<PaywallServerError>()]);

    // A failed pair is forgotten, so the next identify tries again
    sends.failWith = null;
    await client.identify(userId: 'user-1');
    await pumpEventQueue();
    expect(sends.pairs, [('anon-1', 'user-1'), ('anon-1', 'user-1')]);
  });

  test('a throwing error reporter does not escape', () async {
    final sends = _Sends()..failWith = StateError('boom');
    final backend = InMemoryBackend(anonymousId: 'anon-1');
    final client = createClientForBackend(
      backend,
      anonymousId: () => backend.anonymousId,
      identifySync: IdentifySync(
        scope: 'test',
        send: sends.call,
        onError: (error, stack) => throw StateError('reporter boom'),
        sentPairs: {},
      ),
    );

    await client.identify(userId: 'user-1');
    await pumpEventQueue();

    expect(sends.pairs, hasLength(1));
  });

  test('identify does not wait for the send', () async {
    // The gate never completes, so identify can only finish if it does not
    // await the request
    final sends = _Sends()..gate = Completer<void>().future;
    final client = _client(sends);

    await client.identify(userId: 'user-1');

    expect(sends.pairs, [('anon-1', 'user-1')]);
    expect(client.previousAnonymousId, 'anon-1');
  });

  test('the send posts the pair to /v1/identify on the API', () async {
    final requests = <http.Request>[];
    final api = HttpPaywallClient(
      sdkKey: 'cpk_mob_test',
      apiBaseUrl: Uri.parse('https://api.example'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      }),
    );
    final backend = InMemoryBackend(anonymousId: 'anon-1');
    final client = createClientForBackend(
      backend,
      anonymousId: () => backend.anonymousId,
      identifySync: IdentifySync(
        scope: 'test',
        send: api.identify,
        onError: (error, stack) => fail('unexpected error: $error'),
        sentPairs: {},
      ),
    );

    await client.identify(userId: 'user-1');
    await pumpEventQueue();

    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://api.example/v1/identify');
    expect(request.headers['Authorization'], 'Bearer cpk_mob_test');
    expect(jsonDecode(request.body), {
      'anonymous_id': 'anon-1',
      'targeting_key': 'user-1',
    });
  });
}
