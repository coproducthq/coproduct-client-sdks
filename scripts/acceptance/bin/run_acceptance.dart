import 'dart:convert';
import 'dart:io';

import 'package:coproduct_acceptance/device_query.dart';
import 'package:coproduct_acceptance/flag_table.dart';
import 'package:coproduct_acceptance/runner.dart';
import 'package:coproduct_acceptance/sdk_key.dart';
import 'package:coproduct_acceptance/version_pin.dart';

// Public gate: dart run bin/run_acceptance.dart <ios|android> <device-id>
// Run from scripts/acceptance. Emits COPRODUCT_FLUTTER_ACCEPTANCE_<P>_STATUS
// pass=true and exits 0 only when the on-device test passes
Future<void> main(List<String> args) async {
  if (args.length != 2 || (args[0] != 'ios' && args[0] != 'android')) {
    stderr.writeln('usage: run_acceptance.dart <ios|android> <device-id>');
    exit(2);
  }
  final platform = args[0];
  final deviceId = args[1];

  final consumerDir = Directory('../../consumer-tests/flutter').absolute.path;
  final pubspec = File('$consumerDir/pubspec.yaml').readAsStringSync();
  final pin = parsePinnedVersion(pubspec);

  final devicesRaw = await Process.run('flutter', ['devices', '--machine']);
  if (devicesRaw.exitCode != 0) {
    stderr.writeln('flutter devices failed: ${devicesRaw.stderr}');
    exit(2);
  }
  try {
    requireAcceptanceDevice(
        jsonDecode(devicesRaw.stdout as String) as List, platform, deviceId);
  } on AcceptanceDeviceError catch (e) {
    stderr.writeln(e.message);
    exit(2);
  }

  final key = generateSdkKey();
  final expected = jsonEncode(expectedTable());

  final code = await runAcceptance(
    fixtureCommand: [
      Platform.resolvedExecutable, 'run', 'bin/fixture.dart',
      '--platform', platform, '--version', pin.version, '--build', pin.build,
      '--key', key,
    ],
    endpointForPort: (port) => endpointFor(platform, port),
    testCommandForEndpoint: (endpoint) => [
      'flutter', 'test', 'integration_test/acceptance_test.dart',
      '-d', deviceId,
      '--dart-define=COPRODUCT_ENDPOINT=$endpoint',
      '--dart-define=COPRODUCT_SDK_KEY=$key',
      '--dart-define=COPRODUCT_EXPECTED=$expected',
    ],
    testWorkingDirectory: consumerDir,
    readinessTimeout: const Duration(seconds: 15),
    overallTimeout: const Duration(minutes: 8),
    log: stderr.writeln,
  );

  if (code == 0) {
    stdout.writeln(
        'COPRODUCT_FLUTTER_ACCEPTANCE_${platform.toUpperCase()}_STATUS pass=true');
  }
  exit(code);
}
