import 'dart:convert';
import 'dart:io';

import 'package:coproduct_acceptance/snapshot.dart';

// A deterministic host fixture for the acceptance gate. Binds loopback on an
// OS-assigned port, prints one readiness record to stdout, and serves the
// snapshot for an authorized GET /v1/snapshot. All logs go to stderr
Future<void> main(List<String> args) async {
  final opts = _parse(args);
  final platform = opts['platform'];
  if (platform != 'ios' && platform != 'android') {
    stderr.writeln('fixture: --platform must be ios or android');
    exit(2);
  }
  final key = opts['key'];
  if (key == null || key.isEmpty) {
    stderr.writeln('fixture: --key is required');
    exit(2);
  }
  final body = jsonEncode(buildSnapshotEnvelope(
    expectedPlatform: platform!,
    appVersion: opts['version']!,
    appBuild: opts['build']!,
    generatedAt: '2026-08-01T00:00:00Z',
  ));

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  ProcessSignal.sigint.watch().listen((_) => _shutdown(server));
  ProcessSignal.sigterm.watch().listen((_) => _shutdown(server));
  stdout.writeln('COPRODUCT_FIXTURE_READY port=${server.port}');
  // Flush so the runner observes readiness immediately rather than waiting on
  // stdout buffering to release the line
  await stdout.flush();

  await for (final req in server) {
    final res = req.response;
    if (req.uri.path != '/v1/snapshot') {
      stderr.writeln('fixture: 404 ${req.method} ${req.uri.path}');
      res.statusCode = HttpStatus.notFound;
    } else if (req.method != 'GET') {
      stderr.writeln('fixture: 405 ${req.method} ${req.uri.path}');
      res.statusCode = HttpStatus.methodNotAllowed;
    } else if (req.headers.value('authorization') != 'Bearer $key') {
      stderr.writeln('fixture: 401 missing or wrong bearer');
      res.statusCode = HttpStatus.unauthorized;
    } else {
      res.statusCode = HttpStatus.ok;
      res.headers.contentType = ContentType.json;
      res.write(body);
    }
    await res.close();
  }
}

Future<void> _shutdown(HttpServer server) async {
  await server.close(force: true);
  exit(0);
}

Map<String, String> _parse(List<String> args) {
  final map = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    if (args[i].startsWith('--')) map[args[i].substring(2)] = args[i + 1];
  }
  return map;
}
