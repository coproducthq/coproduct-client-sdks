import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coproduct_acceptance/fixture_control.dart';
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
  // A second key lets one fixture serve two tests whose snapshot caches must
  // not share a scope. Optional, so a single-test run is unchanged
  final keys = {
    key,
    if (opts['second-key']?.isNotEmpty ?? false) opts['second-key']!,
  };

  final control = FixtureControl(
    buildBody: (version, omitted) => jsonEncode(buildSnapshotEnvelope(
      expectedPlatform: platform!,
      appVersion: opts['version']!,
      appBuild: opts['build']!,
      generatedAt: '2026-08-01T00:00:00Z',
      version: version,
      omitFlags: omitted,
    )),
  );

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

  // Teardown must COMPLETE a held response, not race it. So every handler is
  // tracked while it runs, and shutdown releases the gate, waits for the
  // handlers to finish writing, and only then closes the socket
  final inFlight = <Future<void>>{};
  var shuttingDown = false;
  Future<void>? shutdownFuture;
  Future<void> shutdown() => shutdownFuture ??= () async {
        shuttingDown = true;
        control.completeOutstanding();
        // Bounded, so one wedged handler cannot hang teardown forever. Kept
        // under the runner's own teardown grace period so a fixture that runs
        // this drain to its limit still exits before the runner escalates to
        // a kill signal
        await Future.wait(inFlight.toList())
            .timeout(const Duration(seconds: 2), onTimeout: () {
          stderr.writeln('fixture: a handler did not finish before teardown');
          return const <void>[];
        });
        await server.close(force: true);
        exit(0);
      }();

  ProcessSignal.sigint.watch().listen((_) => unawaited(shutdown()));
  ProcessSignal.sigterm.watch().listen((_) => unawaited(shutdown()));
  stdout.writeln('COPRODUCT_FIXTURE_READY port=${server.port}');
  // Flush so the runner observes readiness immediately rather than waiting on
  // stdout buffering to release the line
  await stdout.flush();

  await for (final req in server) {
    if (shuttingDown) {
      req.response.statusCode = HttpStatus.serviceUnavailable;
      await req.response.close();
      continue;
    }
    // Each request is handled without awaiting the previous one, so a held
    // snapshot request cannot stop a control command from being served. That
    // is the whole point of the control channel. A handler error is logged
    // rather than left to surface as an unhandled asynchronous error
    final handled = _handle(req, control, keys).catchError((Object error) {
      stderr.writeln('fixture: handler failed: $error');
    });
    inFlight.add(handled);
    unawaited(handled.whenComplete(() => inFlight.remove(handled)));
  }
}

bool _authorized(String? header, Set<String> keys) =>
    header != null &&
    header.startsWith('Bearer ') &&
    keys.contains(header.substring(7));

Future<void> _handle(
    HttpRequest req, FixtureControl control, Set<String> keys) async {
  final res = req.response;
  final path = req.uri.path;
  try {
    if (path == '/v1/snapshot') {
      if (req.method != 'GET') {
        stderr.writeln('fixture: 405 ${req.method} $path');
        res.statusCode = HttpStatus.methodNotAllowed;
      } else if (!_authorized(req.headers.value('authorization'), keys)) {
        stderr.writeln('fixture: 401 missing or wrong bearer');
        res.statusCode = HttpStatus.unauthorized;
      } else {
        // Park here while the fixture is armed. The body is read after the
        // gate opens, so a snapshot chosen while this poll waited is the one
        // it serves
        await control.awaitTurn();
        res.statusCode = HttpStatus.ok;
        res.headers.contentType = ContentType.json;
        res.write(control.body);
      }
    } else if (path.startsWith('/control/')) {
      await _handleControl(req, res, control);
    } else {
      stderr.writeln('fixture: 404 ${req.method} $path');
      res.statusCode = HttpStatus.notFound;
    }
  } catch (error) {
    stderr.writeln('fixture: 500 ${req.method} $path: $error');
    res.statusCode = HttpStatus.internalServerError;
  }
  await res.close();
}

Future<void> _handleControl(
    HttpRequest req, HttpResponse res, FixtureControl control) async {
  final path = req.uri.path;
  // Only these routes exist, each with exactly one legal method
  const legalMethods = {
    '/control/block-next-poll': 'POST',
    '/control/release': 'POST',
    '/control/snapshot': 'POST',
    '/control/reset': 'POST',
    '/control/state': 'GET',
  };
  final legal = legalMethods[path];
  if (legal == null) {
    stderr.writeln('fixture: 404 ${req.method} $path');
    res.statusCode = HttpStatus.notFound;
    return;
  }
  if (req.method != legal) {
    stderr.writeln('fixture: 405 ${req.method} $path');
    res.statusCode = HttpStatus.methodNotAllowed;
    return;
  }

  try {
    switch (path) {
      case '/control/block-next-poll':
        await req.drain<void>();
        control.armBlockNextPoll();
      case '/control/release':
        await req.drain<void>();
        control.release();
      case '/control/snapshot':
        final raw = await utf8.decodeStream(req);
        final decoded = jsonDecode(raw) as Map<String, Object?>;
        final omit = (decoded['omitFlags'] as List? ?? const [])
            .cast<String>()
            .toSet();
        control.setActiveSnapshot(omit);
      case '/control/reset':
        // Always legal: a test calls this in teardown without knowing what
        // state a failure left behind
        await req.drain<void>();
        control.reset();
      case '/control/state':
        await req.drain<void>();
    }
  } on FixtureControlError catch (error) {
    // An illegal command is a harness bug, so it is reported rather than
    // silently ignored
    stderr.writeln('fixture: 409 ${req.method} $path: ${error.message}');
    res.statusCode = HttpStatus.conflict;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode({'error': error.message}));
    return;
  }

  res.statusCode = HttpStatus.ok;
  res.headers.contentType = ContentType.json;
  res.write(jsonEncode({
    'state': control.state.name,
    'servedPolls': control.servedPolls,
    'snapshotVersion': control.snapshotVersion,
    'omittedFlags': control.omittedFlags.toList()..sort(),
  }));
}

Map<String, String> _parse(List<String> args) {
  final map = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    if (args[i].startsWith('--')) map[args[i].substring(2)] = args[i + 1];
  }
  return map;
}
