import 'dart:io';

import 'package:coproduct_acceptance/runner.dart';

// Drives runAcceptance with stub fixture and test commands that record their
// pids, so a signal test can send this process a signal and verify the runner
// tears the whole tree down before exiting. Args: <fixturePidFile> <testPidFile>
Future<void> main(List<String> args) async {
  final code = await runAcceptance(
    fixtureCommand: [
      Platform.resolvedExecutable,
      'run',
      'test/helpers/pid_sleeper.dart',
      args[0],
      'ready',
    ],
    testCommandForEndpoint: (_) => [
      Platform.resolvedExecutable,
      'run',
      'test/helpers/pid_sleeper.dart',
      args[1],
    ],
    endpointForPort: (p) => Uri.parse('http://127.0.0.1:$p'),
    testWorkingDirectory: Directory.current.path,
    readinessTimeout: const Duration(seconds: 15),
    overallTimeout: const Duration(minutes: 5),
    log: (_) {},
  );
  exit(code);
}
