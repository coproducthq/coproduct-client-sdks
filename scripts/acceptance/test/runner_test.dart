import 'package:coproduct_acceptance/runner.dart';
import 'package:test/test.dart';
import 'dart:io';

List<String> _stub(List<String> tail) =>
    [Platform.resolvedExecutable, 'run', 'test/helpers/stub_proc.dart', ...tail];

bool _alive(int pid) => Process.runSync('ps', ['-p', '$pid']).exitCode == 0;

Future<int> _run({
  required List<String> fixtureTail,
  required List<String> testTail,
  Duration readiness = const Duration(seconds: 10),
  Duration overall = const Duration(seconds: 20),
}) =>
    runAcceptance(
      fixtureCommand: _stub(fixtureTail),
      testCommandForEndpoint: (_) => _stub(testTail),
      endpointForPort: (p) => Uri.parse('http://127.0.0.1:$p'),
      testWorkingDirectory: Directory.current.path,
      readinessTimeout: readiness,
      overallTimeout: overall,
      log: (_) {},
    );

void main() {
  test('endpointFor selects the per-platform host', () {
    expect(endpointFor('ios', 9).toString(), 'http://127.0.0.1:9');
    expect(endpointFor('android', 9).toString(), 'http://10.0.2.2:9');
  });

  test('parses the readiness record', () {
    expect(parseFixturePort('COPRODUCT_FIXTURE_READY port=8080'), 8080);
    expect(parseFixturePort('garbage'), isNull);
  });

  test('returns the test exit code on the happy path', () async {
    expect(await _run(fixtureTail: ['fixture-ready'], testTail: ['exit', '0']), 0);
    expect(await _run(fixtureTail: ['fixture-ready'], testTail: ['exit', '3']), 3);
  });

  test('reports a fixture that crashes before readiness', () async {
    expect(await _run(fixtureTail: ['fixture-crash'], testTail: ['exit', '0']),
        kCodeFixtureCrashed);
  });

  test('reports a readiness timeout', () async {
    expect(
        await _run(
            fixtureTail: ['hang'],
            testTail: ['exit', '0'],
            readiness: const Duration(milliseconds: 300)),
        kCodeStartupTimeout);
  });

  test('reports an overall timeout when the test hangs', () async {
    expect(
        await _run(
            fixtureTail: ['fixture-ready'],
            testTail: ['hang'],
            overall: const Duration(milliseconds: 500)),
        kCodeOverallTimeout);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('reports a fixture that exits during the test', () async {
    // The fixture reports readiness, the test hangs, then the fixture exits
    // mid-test, which the runner must surface as a fixture crash
    expect(
        await _run(
            fixtureTail: ['ready-then-exit', '300'],
            testTail: ['hang'],
            overall: const Duration(seconds: 10)),
        kCodeFixtureCrashed);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('treats malformed readiness stdout as no readiness', () async {
    // The fixture writes a line that is not the readiness record and hangs, so
    // no port is ever parsed and the runner falls back to the readiness timeout
    expect(
        await _run(
            fixtureTail: ['bad-ready'],
            testTail: ['exit', '0'],
            readiness: const Duration(milliseconds: 300)),
        kCodeStartupTimeout);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a run that leaks an escaped child does not report success', () async {
    // The fixture spawns a child that ignores SIGTERM and so reparents out of
    // the tree during teardown. The test passes, but the leaked child means
    // teardown is incomplete, so the run must return a nonzero teardown code
    // rather than the test's zero
    final dir = await Directory.systemTemp.createTemp('acc_esc');
    final pidFile = File('${dir.path}/escaped.pid');
    final code = await runAcceptance(
      fixtureCommand: _stub(['escaping-fixture', pidFile.path]),
      testCommandForEndpoint: (_) => _stub(['exit', '0']),
      endpointForPort: (p) => Uri.parse('http://127.0.0.1:$p'),
      testWorkingDirectory: Directory.current.path,
      readinessTimeout: const Duration(seconds: 10),
      overallTimeout: const Duration(seconds: 20),
      teardownGrace: const Duration(milliseconds: 200),
      log: (_) {},
    );
    expect(code, kCodeTeardownIncomplete);

    // Clean up the process the fixture deliberately leaked
    final escapedPid = int.parse(pidFile.readAsStringSync().trim());
    Process.killPid(escapedPid, ProcessSignal.sigkill);
    await dir.delete(recursive: true);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a signal tears the whole tree down before the runner exits', () async {
    final dir = await Directory.systemTemp.createTemp('acc_sig');
    final fixturePidFile = File('${dir.path}/fixture.pid');
    final testPidFile = File('${dir.path}/test.pid');
    final harness = await Process.start(Platform.resolvedExecutable, [
      'run',
      'test/helpers/run_stub_harness.dart',
      fixturePidFile.path,
      testPidFile.path,
    ]);

    // Wait until both stub children have recorded their pids and are alive
    var fpid = 0, tpid = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      if (fixturePidFile.existsSync() && testPidFile.existsSync()) {
        fpid = int.tryParse(fixturePidFile.readAsStringSync().trim()) ?? 0;
        tpid = int.tryParse(testPidFile.readAsStringSync().trim()) ?? 0;
        if (fpid > 0 && tpid > 0 && _alive(fpid) && _alive(tpid)) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(fpid, greaterThan(0), reason: 'fixture child never started');
    expect(tpid, greaterThan(0), reason: 'test child never started');

    // Signal the runner; its handler must tear the tree down before exit
    harness.kill(ProcessSignal.sigterm);
    expect(await harness.exitCode, 143);

    // Both stub children must be gone once the runner has exited
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(_alive(fpid), isFalse, reason: 'fixture child leaked past teardown');
    expect(_alive(tpid), isFalse, reason: 'test child leaked past teardown');
    await dir.delete(recursive: true);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
