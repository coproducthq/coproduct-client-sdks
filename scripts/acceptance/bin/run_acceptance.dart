import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coproduct_acceptance/device_query.dart';
import 'package:coproduct_acceptance/flag_table.dart';
import 'package:coproduct_acceptance/relaunch.dart';
import 'package:coproduct_acceptance/runner.dart';
import 'package:coproduct_acceptance/sdk_key.dart';
import 'package:coproduct_acceptance/version_pin.dart';

/// How long the fixture has to report readiness before a pass starts its test.
/// The first pass's first_seen_at ceiling includes it, since it elapses before
/// the overall timeout begins
const Duration kFixtureReadinessTimeout = Duration(seconds: 15);

/// The bound on each one-shot device command, so a hung adb or simctl cannot
/// hold a run the overall timeout does not cover. A timed-out command is left
/// running rather than killed: the run ends straight after with a setup
/// failure, so an orphaned adb or simctl costs nothing but its own process
const Duration kDeviceCommandTimeout = Duration(seconds: 10);

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

  // Release gates point this at a disposable consumer that resolves the SDK
  // from the extracted archive; the default keeps the in-repo consumer
  final consumerDir = Platform.environment['COPRODUCT_CONSUMER_DIR'] ??
      Directory('../../consumer-tests/flutter').absolute.path;
  final pubspec = File('$consumerDir/pubspec.yaml').readAsStringSync();
  final pin = parsePinnedVersion(pubspec);

  final devicesRaw = await Process.run('flutter', ['devices', '--machine']);
  if (devicesRaw.exitCode != 0) {
    stderr.writeln('flutter devices failed: ${devicesRaw.stderr}');
    exit(2);
  }
  try {
    requireAcceptanceDevice(
        decodeDeviceList(devicesRaw.stdout as String), platform, deviceId);
  } on AcceptanceDeviceError catch (e) {
    stderr.writeln(e.message);
    exit(2);
  }

  // Spans the build as well as the run, because `flutter test` does both
  // under one clock. The no-Rust gate uses a fresh HOME, so its Gradle cache
  // is empty every run and its build is always cold.
  //
  // The default stays at 8 deliberately. Every long build measured so far
  // (968s, 1070s, 2065s) came from a machine with 24.5 of 25.6 GB of swap
  // consumed, where the same build took 12s healthy. Those numbers say
  // nothing about a cold build on a healthy machine, and setting a gate's
  // tolerance from them would retire the timeout as a signal. Override it,
  // measure a healthy cold run, then change this from evidence
  final overallTimeout = Duration(
      minutes: int.parse(
          Platform.environment['COPRODUCT_ACCEPTANCE_TIMEOUT_MINUTES'] ?? '8'));

  // The first pass has to be a genuine first launch, so any install a previous
  // run left behind goes first. Absence is verified rather than inferred from
  // the uninstall, which fails on Android when there is nothing to remove
  final androidHome = Platform.environment['ANDROID_HOME'];
  final adb = (androidHome == null || androidHome.isEmpty)
      ? 'adb'
      : '$androidHome/platform-tools/adb';
  // Bounded like the clock reading, because the overall timeout covers only
  // the passes. A hung or missing tool reports false, and the gate then stops
  // the run with its setup code
  Future<bool> clearInstall() async {
    final uninstall = uninstallCommand(platform, deviceId, adb: adb);
    final probe = installedProbeCommand(platform, deviceId, adb: adb);
    try {
      await Process.run(uninstall.first, uninstall.skip(1).toList())
          .timeout(kDeviceCommandTimeout);
      final probed = await Process.run(probe.first, probe.skip(1).toList())
          .timeout(kDeviceCommandTimeout);
      return !isInstalled(platform, probed.exitCode, probed.stdout as String);
    } on TimeoutException {
      stderr.writeln('removing $kConsumerAppId from $deviceId did not finish '
          'within ${kDeviceCommandTimeout.inSeconds}s');
      return false;
    } on ProcessException catch (e) {
      stderr.writeln('could not run ${e.executable} to remove $kConsumerAppId '
          'from $deviceId: ${e.message}');
      return false;
    }
  }

  Future<int> runPass(SessionPass pass) {
    final key = generateSdkKey();
    // A distinct key per test that must start from a cold snapshot cache
    final controlKey = generateSdkKey();
    final reactiveKey = generateSdkKey();
    final expected = jsonEncode(expectedTable());
    return runAcceptance(
      fixtureCommand: [
        Platform.resolvedExecutable, 'run', 'bin/fixture.dart',
        '--platform', platform, '--version', pin.version, '--build', pin.build,
        '--session-count', '${pass.sessionCount}',
        '--first-seen-floor', '${pass.firstSeenFloor}',
        '--first-seen-ceiling', '${pass.firstSeenCeiling}',
        '--key', key,
        '--key', controlKey,
        '--key', reactiveKey,
      ],
      endpointForPort: (port) => endpointFor(platform, port),
      testCommandForEndpoint: (endpoint) => acceptanceTestCommand(
        deviceId: deviceId,
        pass: pass,
        endpoint: endpoint,
        key: key,
        controlKey: controlKey,
        reactiveKey: reactiveKey,
        expected: expected,
      ),
      testWorkingDirectory: consumerDir,
      readinessTimeout: kFixtureReadinessTimeout,
      overallTimeout: overallTimeout,
      log: stderr.writeln,
    );
  }

  // The app stamps first_seen_at from the device clock, so the bounds are read
  // from it too. An emulator can run minutes behind the host, and bounds from
  // the host clock would then admit a timestamp recreated at the relaunch
  final clockCommand = deviceClockCommand(platform, deviceId, adb: adb);
  Future<({int device, int offset})> readClock() async {
    if (clockCommand == null) return (device: epochSecondsNow(), offset: 0);
    final host = epochSecondsNow();
    // Bounded, because the overall timeout covers only the passes and a hung
    // adb would otherwise hold the run forever
    final ProcessResult r;
    try {
      r = await Process.run(clockCommand.first, clockCommand.skip(1).toList())
          .timeout(kDeviceCommandTimeout);
    } on TimeoutException {
      stderr.writeln('reading the clock on $deviceId did not finish');
      exit(2);
    } on ProcessException catch (e) {
      stderr.writeln('could not run ${e.executable} to read the clock on '
          '$deviceId: ${e.message}');
      exit(2);
    }
    if (r.exitCode != 0) {
      stderr.writeln('could not read the clock on $deviceId: ${r.stderr}');
      exit(2);
    }
    try {
      return clockReadingFrom(r.stdout as String, host);
    } on FormatException catch (e) {
      stderr.writeln(e.message);
      exit(2);
    }
  }

  final code = await runRelaunchGate(
    deviceId: deviceId,
    clearInstall: clearInstall,
    runPair: () => runRelaunchPair(
      runPass: runPass,
      readClock: readClock,
      delay: (gap) => Future<void>.delayed(gap),
      readinessTimeout: kFixtureReadinessTimeout,
      overallTimeout: overallTimeout,
      log: stderr.writeln,
    ),
    log: stderr.writeln,
  );

  if (code == 0) {
    stdout.writeln(
        'COPRODUCT_FLUTTER_ACCEPTANCE_${platform.toUpperCase()}_STATUS pass=true');
  }
  exit(code);
}

/// Decodes `flutter devices --machine` output.
///
/// The tool prints notices before the JSON in some environments, most reliably
/// on a fresh HOME where the analytics notice appears, so the array is located
/// rather than assumed to start at the first character.
List<dynamic> decodeDeviceList(String stdout) {
  // The tool prints its analytics notice after the array in a minimal
  // environment, so the array is bounded at both ends rather than assumed to run
  // to the end of the output. Both brackets sit at column zero on their own line.
  final lines = stdout.split('\n');
  final start = lines.indexWhere((l) => l.startsWith('['));
  if (start < 0) {
    throw const FormatException(
        'flutter devices --machine printed no JSON array');
  }
  final end = lines.indexWhere((l) => l.startsWith(']'), start);
  if (end < 0) {
    throw const FormatException(
        'flutter devices --machine printed an unterminated JSON array');
  }
  return jsonDecode(lines.sublist(start, end + 1).join('\n')) as List<dynamic>;
}
