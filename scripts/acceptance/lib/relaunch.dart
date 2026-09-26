/// The acceptance suite runs twice around a real app termination, so the
/// session attributes are proven across an actual process relaunch rather than
/// by resetting a guard inside one process

/// The consumer app both platforms install. Uninstalled before the first pass so
/// that pass is a genuine first launch
const String kConsumerAppId = 'app.coproduct.consumer.flutter';

/// Slack on each first_seen_at bound for a clock step the step check still
/// accepts and for whole-second rounding. The second pass's bounds and the
/// first pass's floor come from clock readings that bracket the stamp, so for
/// them the slack covers no build or run time. The first pass's ceiling is
/// computed from the timeouts rather than read from a clock, so it counts on
/// those timeouts covering everything before the stamp, and the slack is the
/// only margin for any time they do not bound, such as spawning the fixture
/// and the test process
const int kClockSkewSeconds = 10;

/// The wait between passes. It is what separates an unchanged first_seen_at from
/// one recreated at the second launch, so it must exceed twice the skew
const Duration kRelaunchGap = Duration(seconds: 30);

/// One pass's session expectations and whether the app survives it
class SessionPass {
  const SessionPass({
    required this.sessionCount,
    required this.firstSeenFloor,
    required this.firstSeenCeiling,
    required this.keepInstalled,
  });

  final int sessionCount;
  final int firstSeenFloor;
  final int firstSeenCeiling;
  final bool keepInstalled;
}

/// A fresh install: one session, created during this pass. The ceiling is the
/// longest the pass may run, the fixture readiness wait followed by the test
/// run, so a timestamp in milliseconds fails it
SessionPass firstPass({
  required int startedAt,
  required Duration readinessTimeout,
  required Duration overallTimeout,
}) =>
    SessionPass(
      sessionCount: 1,
      firstSeenFloor: startedAt - kClockSkewSeconds,
      firstSeenCeiling: startedAt +
          readinessTimeout.inSeconds +
          overallTimeout.inSeconds +
          kClockSkewSeconds,
      keepInstalled: true,
    );

/// The relaunch: one more session, and a timestamp that predates the end of the
/// first pass, which a value recreated at this launch cannot
SessionPass secondPass({required int firstStartedAt, required int firstEndedAt}) =>
    SessionPass(
      sessionCount: 2,
      firstSeenFloor: firstStartedAt - kClockSkewSeconds,
      firstSeenCeiling: firstEndedAt + kClockSkewSeconds,
      keepInstalled: false,
    );

/// [adb] is the full path the Android script's own ANDROID_HOME gives, rather
/// than whatever adb PATH happens to find
List<String> uninstallCommand(String platform, String deviceId, {String adb = 'adb'}) =>
    switch (platform) {
      'ios' => ['xcrun', 'simctl', 'uninstall', deviceId, kConsumerAppId],
      'android' => [adb, '-s', deviceId, 'uninstall', kConsumerAppId],
      _ => throw ArgumentError('unknown platform $platform'),
    };

List<String> installedProbeCommand(String platform, String deviceId, {String adb = 'adb'}) =>
    switch (platform) {
      'ios' => ['xcrun', 'simctl', 'get_app_container', deviceId, kConsumerAppId],
      'android' => [adb, '-s', deviceId, 'shell', 'pm', 'path', kConsumerAppId],
      _ => throw ArgumentError('unknown platform $platform'),
    };

/// Read from the probe rather than the uninstall's exit code, because
/// uninstalling an app that is not installed fails on Android and a real
/// failure to uninstall looks the same
bool isInstalled(String platform, int exitCode, String stdout) =>
    switch (platform) {
      'ios' => exitCode == 0,
      'android' => exitCode == 0 && stdout.contains('package:'),
      _ => throw ArgumentError('unknown platform $platform'),
    };

int epochSecondsNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// How far the device clock may move against the host's during a run. The
/// bounds are taken from the device clock, so a constant offset cancels, but a
/// step between the end of the first pass and the second launch would not. A
/// backward step larger than the gap minus the skew would let a recreated
/// timestamp through, so this stays well under that
const int kClockStepSeconds = 5;

/// The exit code when the run could not be set up, such as when a previous
/// install could not be removed
const int kCodeSetupFailed = 2;

/// The exit code when the device clock stepped during the run. It shares the
/// setup failure code because the run proved nothing either way
const int kCodeClockStepped = kCodeSetupFailed;

/// The command that prints the clock the app stamps first_seen_at with, or
/// null when that is the host clock. A simulator runs on the host kernel, so it
/// has no clock of its own
List<String>? deviceClockCommand(String platform, String deviceId,
        {String adb = 'adb'}) =>
    switch (platform) {
      'ios' => null,
      'android' => [adb, '-s', deviceId, 'shell', 'date', '+%s'],
      _ => throw ArgumentError('unknown platform $platform'),
    };

/// Reads `date +%s` output. adb can end a line with a carriage return, and
/// anything but a bare run of digits is refused rather than guessed at
int parseEpochSeconds(String stdout) {
  final text = stdout.trim();
  if (!RegExp(r'^[0-9]{9,11}$').hasMatch(text)) {
    throw FormatException('the device clock printed "$text", not epoch seconds');
  }
  return int.parse(text);
}

/// One clock reading: the device's epoch seconds from its `date +%s` output,
/// and how far that is from the host's reading taken just before it
({int device, int offset}) clockReadingFrom(String stdout, int hostSeconds) {
  final device = parseEpochSeconds(stdout);
  return (device: device, offset: device - hostSeconds);
}

/// Runs the relaunch pair only once the app is verified absent, so the first
/// pass is a genuine first launch. [clearInstall] removes any install a
/// previous run left and reports whether the app is now gone
Future<int> runRelaunchGate({
  required String deviceId,
  required Future<bool> Function() clearInstall,
  required Future<int> Function() runPair,
  required void Function(String) log,
}) async {
  if (!await clearInstall()) {
    log('could not uninstall $kConsumerAppId from $deviceId, so the first pass '
        'would not be a first launch');
    return kCodeSetupFailed;
  }
  return runPair();
}

/// Whether the device clock kept its offset from the host between two readings
bool clockHeldSteady(int offsetBefore, int offsetAfter) =>
    (offsetAfter - offsetBefore).abs() <= kClockStepSeconds;

/// The on-device test command for one pass. Only the first pass keeps the app
/// installed, because `flutter test` uninstalls an integration-test app when it
/// finishes and the relaunch needs the first pass's install and its data
List<String> acceptanceTestCommand({
  required String deviceId,
  required SessionPass pass,
  required Uri endpoint,
  required String key,
  required String controlKey,
  required String reactiveKey,
  required String expected,
}) =>
    [
      'flutter', 'test', 'integration_test/acceptance_test.dart',
      '-d', deviceId,
      if (pass.keepInstalled) '--no-uninstall',
      '--dart-define=COPRODUCT_ENDPOINT=$endpoint',
      '--dart-define=COPRODUCT_SDK_KEY=$key',
      '--dart-define=COPRODUCT_SDK_KEY_CONTROL=$controlKey',
      '--dart-define=COPRODUCT_SDK_KEY_REACTIVE=$reactiveKey',
      '--dart-define=COPRODUCT_EXPECTED=$expected',
    ];

/// Runs the suite twice around a real app termination and returns the exit
/// code. The first_seen_at bounds come from [readClock], which reads the clock
/// the app stamps with and its offset from the host. A pass that fails ends the
/// run with its own code, and a clock that stepped during either pass ends it
/// with [kCodeClockStepped], since its bounds would then prove nothing
Future<int> runRelaunchPair({
  required Future<int> Function(SessionPass pass) runPass,
  required Future<({int device, int offset})> Function() readClock,
  required Future<void> Function(Duration) delay,
  required Duration readinessTimeout,
  required Duration overallTimeout,
  required void Function(String) log,
}) async {
  bool requireSteadyClock(int before, int after) {
    log('clock: device minus host is ${after}s');
    if (clockHeldSteady(before, after)) return true;
    log('the device clock moved ${after - before}s against the host during '
        'the run, so its first_seen_at bounds prove nothing');
    return false;
  }

  final start = await readClock();
  log('clock: device minus host is ${start.offset}s');
  final first = await runPass(firstPass(
      startedAt: start.device,
      readinessTimeout: readinessTimeout,
      overallTimeout: overallTimeout));
  if (first != 0) return first;
  final end = await readClock();
  if (!requireSteadyClock(start.offset, end.offset)) return kCodeClockStepped;

  // The first pass ended by stopping the app, so the second pass launches a new
  // process against the data the first one left
  log('relaunch: waiting ${kRelaunchGap.inSeconds}s before the second pass');
  await delay(kRelaunchGap);
  final code = await runPass(
      secondPass(firstStartedAt: start.device, firstEndedAt: end.device));
  if (code != 0) return code;

  // A step during the second pass could have moved its stamp under the ceiling,
  // so a green second pass counts only if the clock held
  final after = await readClock();
  if (!requireSteadyClock(end.offset, after.offset)) return kCodeClockStepped;
  return 0;
}
