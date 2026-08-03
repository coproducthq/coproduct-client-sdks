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
}
