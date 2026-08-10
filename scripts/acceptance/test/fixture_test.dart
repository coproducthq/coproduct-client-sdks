import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<(Process, int)> _startFixture(String key) async {
  final p = await Process.start(Platform.resolvedExecutable, [
    'run',
    'bin/fixture.dart',
    '--platform', 'ios',
    '--version', '1.0.0',
    '--build', '1',
    '--key', key,
  ]);
  final line = await p.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .firstWhere((l) => l.startsWith('COPRODUCT_FIXTURE_READY'));
  final port = int.parse(RegExp(r'port=(\d+)').firstMatch(line)!.group(1)!);
  return (p, port);
}

void main() {
  test('serves the snapshot for an authorized GET /v1/snapshot', () async {
    const key = 'cpk_mob_abcdefghjkmnpqrstvwxyz0123456789';
    final (proc, port) = await _startFixture(key);
    addTearDown(() => proc.kill());
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/v1/snapshot'));
    req.headers.set('Authorization', 'Bearer $key');
    final resp = await req.close();
    expect(resp.statusCode, 200);
    expect(resp.headers.contentType?.mimeType, 'application/json');
    final body = jsonDecode(await resp.transform(utf8.decoder).join())
        as Map<String, Object?>;
    expect(body.containsKey('snapshot'), isTrue);
    expect(body.containsKey('sdkContext'), isFalse);
    client.close();
  });

  test('rejects a wrong path, method, and missing bearer', () async {
    const key = 'cpk_mob_abcdefghjkmnpqrstvwxyz0123456789';
    final (proc, port) = await _startFixture(key);
    addTearDown(() => proc.kill());
    final client = HttpClient();

    final wrongPath = await (await client
            .getUrl(Uri.parse('http://127.0.0.1:$port/nope')))
        .close();
    expect(wrongPath.statusCode, 404);

    final wrongMethod = await (await client
            .postUrl(Uri.parse('http://127.0.0.1:$port/v1/snapshot')))
        .close();
    expect(wrongMethod.statusCode, 405);

    final noAuth = await (await client
            .getUrl(Uri.parse('http://127.0.0.1:$port/v1/snapshot')))
        .close();
    expect(noAuth.statusCode, 401);
    client.close();
  });

  test('requires the literal Bearer scheme on the snapshot route', () async {
    const key = 'cpk_mob_abcdefghjkmnpqrstvwxyz0123456789';
    final (proc, port) = await _startFixture(key);
    addTearDown(() => proc.kill());
    final client = HttpClient();

    Future<int> statusFor(String? authorization) async {
      final req =
          await client.getUrl(Uri.parse('http://127.0.0.1:$port/v1/snapshot'));
      if (authorization != null) {
        req.headers.set('Authorization', authorization);
      }
      final resp = await req.close();
      await resp.drain<void>();
      return resp.statusCode;
    }

    // Positive control: a well-formed bearer still succeeds, so this test
    // cannot pass by rejecting everything
    expect(await statusFor('Bearer $key'), 200);

    // The bare key with no scheme must not authorize
    expect(await statusFor(key), 401,
        reason: 'a raw key with no Bearer prefix must not authorize');

    // A lowercase scheme must not authorize
    expect(await statusFor('bearer $key'), 401,
        reason: 'the scheme comparison is case-sensitive');

    // A bearer with an empty token must not authorize
    expect(await statusFor('Bearer '), 401,
        reason: 'an empty token must not authorize');

    client.close();
  });

  test('the control routes drive a delayed poll end to end', () async {
    final f = await _startControlledFixture();
    try {
      // Arm, then start a snapshot request that must not complete yet
      expect((await _control(f.port, 'POST', '/control/block-next-poll')).statusCode, 200);

      var snapshotDone = false;
      final snapshot = _snapshot(f.port, f.key).then((r) {
        snapshotDone = true;
        return r;
      });

      // The fixture acknowledges the held request through its state
      await _waitForState(f.port, 'blocked');
      expect(snapshotDone, isFalse, reason: 'the poll is being held');

      // Change what will be served while the poll is held
      final set = await _control(f.port, 'POST', '/control/snapshot',
          body: '{"omitFlags":["fetch-control"]}');
      expect(set.statusCode, 200);

      expect((await _control(f.port, 'POST', '/control/release')).statusCode, 200);
      final served = await snapshot.timeout(const Duration(seconds: 5));
      expect(served.statusCode, 200);
      final flags = ((jsonDecode(served.body) as Map)['snapshot']
          as Map)['flags'] as List;
      expect(flags.map((f) => (f as Map)['key']),
          isNot(contains('fetch-control')),
          reason: 'the held poll serves the snapshot chosen while it waited');

      final state = jsonDecode(
          (await _control(f.port, 'GET', '/control/state')).body) as Map;
      expect(state['state'], 'idle');
      expect(state['servedPolls'], 1);
      expect(state['snapshotVersion'], 2);
    } finally {
      f.process.kill();
    }
  });

  test('an illegal control command is rejected rather than ignored', () async {
    final f = await _startControlledFixture();
    try {
      final early = await _control(f.port, 'POST', '/control/release');
      expect(early.statusCode, 409,
          reason: 'releasing with nothing held is a harness bug');
    } finally {
      f.process.kill();
    }
  });

  test('control paths reject the wrong method and unknown paths', () async {
    final f = await _startControlledFixture();
    try {
      expect((await _control(f.port, 'GET', '/control/release')).statusCode, 405);
      expect((await _control(f.port, 'POST', '/control/nope')).statusCode, 404);
    } finally {
      f.process.kill();
    }
  });

  test('reset releases a held poll and restores the full snapshot', () async {
    final f = await _startControlledFixture();
    try {
      expect((await _control(f.port, 'POST', '/control/snapshot',
              body: '{"omitFlags":["fetch-control"]}'))
          .statusCode, 200);
      expect((await _control(f.port, 'POST', '/control/block-next-poll')).statusCode, 200);
      final held = _snapshot(f.port, f.key);
      await _waitForState(f.port, 'blocked');

      expect((await _control(f.port, 'POST', '/control/reset')).statusCode, 200,
          reason: 'reset is always legal, whatever state a failure left behind');

      // The held response must actually complete, and with the whole table back
      final served = await held.timeout(const Duration(seconds: 5),
          onTimeout: () => fail('reset left a client hanging'));
      expect(served.statusCode, 200);
      final flags = ((jsonDecode(served.body) as Map)['snapshot']
          as Map)['flags'] as List;
      expect(flags.map((f) => (f as Map)['key']), contains('fetch-control'),
          reason: 'reset restored the omitted flag');

      final state = jsonDecode(
          (await _control(f.port, 'GET', '/control/state')).body) as Map;
      expect(state['state'], 'idle');
      expect(state['omittedFlags'], isEmpty);
    } finally {
      f.process.kill();
    }
  });

  test('teardown completes a held response', () async {
    final f = await _startControlledFixture();
    await _control(f.port, 'POST', '/control/block-next-poll');
    final snapshot = _snapshot(f.port, f.key);
    await _waitForState(f.port, 'blocked');

    // SIGTERM is what the runner sends when it tears the tree down
    f.process.kill(ProcessSignal.sigterm);
    // The spec requires teardown to COMPLETE outstanding responses, so a
    // connection error is a failure here, not an acceptable outcome. Demand a
    // real 200 with a decodable snapshot
    final served = await snapshot.timeout(const Duration(seconds: 10),
        onTimeout: () => fail('teardown left a client hanging'));
    expect(served.statusCode, 200,
        reason: 'teardown completes the held response rather than dropping it');
    expect(
        ((jsonDecode(served.body) as Map)['snapshot'] as Map)['flags'],
        isA<List>(),
        reason: 'the completed response carries a real snapshot body');
  });
}

Future<({Process process, int port, String key})>
    _startControlledFixture() async {
  const key = 'cpk_mob_abcdefghjkmnpqrstvwxyz0123456789';
  final (proc, port) = await _startFixture(key);
  addTearDown(() => proc.kill(ProcessSignal.sigkill));
  return (process: proc, port: port, key: key);
}

// Each helper closes its own client in a finally. A polling loop that created
// a client per attempt and left it to garbage collection would build real
// socket pressure and turn a diagnostic timeout into a flaky one
Future<({int statusCode, String body})> _control(int port, String method, String path,
    {String? body}) async {
  final client = HttpClient();
  try {
    final req = await client.open(method, '127.0.0.1', port, path);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(body);
    }
    final res = await req.close();
    return (statusCode: res.statusCode, body: await utf8.decodeStream(res));
  } finally {
    client.close(force: true);
  }
}

Future<({int statusCode, String body})> _snapshot(int port, String key) async {
  final client = HttpClient();
  try {
    final req = await client.open('GET', '127.0.0.1', port, '/v1/snapshot');
    req.headers.set('authorization', 'Bearer $key');
    final res = await req.close();
    return (statusCode: res.statusCode, body: await utf8.decodeStream(res));
  } finally {
    client.close(force: true);
  }
}

Future<void> _waitForState(int port, String want) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final state =
        jsonDecode((await _control(port, 'GET', '/control/state')).body) as Map;
    if (state['state'] == want) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('fixture never reached state $want');
}
