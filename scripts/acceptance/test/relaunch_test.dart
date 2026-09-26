import 'package:coproduct_acceptance/relaunch.dart';
import 'package:test/test.dart';

void main() {
  test('the gap between passes outlasts the skew on both sides', () {
    // A timestamp recreated in pass two lands at least the gap minus the skew
    // after pass one ended, and pass two's ceiling is the skew after it. Unless
    // the gap exceeds twice the skew, a recreated value can pass
    expect(kRelaunchGap.inSeconds, greaterThan(2 * kClockSkewSeconds));
  });

  test('the first pass expects a fresh install and keeps it', () {
    final pass = firstPass(
        startedAt: 1767225600,
        readinessTimeout: const Duration(seconds: 15),
        overallTimeout: const Duration(minutes: 8));
    expect(pass.sessionCount, 1);
    expect(pass.firstSeenFloor, 1767225600 - kClockSkewSeconds);
    expect(pass.firstSeenCeiling, 1767225600 + 15 + 480 + kClockSkewSeconds);
    expect(pass.keepInstalled, isTrue);
  });

  test('the first pass ceiling includes the fixture readiness wait', () {
    // The readiness wait elapses before the overall timeout starts, so a stamp
    // taken late in a pass whose fixture was slow to start is still in range
    SessionPass withReadiness(int seconds) => firstPass(
        startedAt: 1767225600,
        readinessTimeout: Duration(seconds: seconds),
        overallTimeout: const Duration(minutes: 8));
    expect(withReadiness(45).firstSeenCeiling - withReadiness(0).firstSeenCeiling,
        45);
    expect(withReadiness(0).firstSeenCeiling,
        1767225600 + 480 + kClockSkewSeconds);
  });

  test('the first pass ceiling rejects milliseconds', () {
    final pass = firstPass(
        startedAt: 1767225600,
        readinessTimeout: const Duration(seconds: 15),
        overallTimeout: const Duration(minutes: 8));
    expect(1767225600 * 1000, greaterThanOrEqualTo(pass.firstSeenCeiling));
  });

  test('the second pass expects the relaunch and an unchanged timestamp', () {
    final pass = secondPass(firstStartedAt: 1767225600, firstEndedAt: 1767225900);
    expect(pass.sessionCount, 2);
    expect(pass.firstSeenFloor, 1767225600 - kClockSkewSeconds);
    expect(pass.firstSeenCeiling, 1767225900 + kClockSkewSeconds);
    expect(pass.keepInstalled, isFalse);
  });

  test('uninstall and probe commands name the consumer app on each platform', () {
    expect(uninstallCommand('ios', 'SIM'),
        ['xcrun', 'simctl', 'uninstall', 'SIM', kConsumerAppId]);
    expect(uninstallCommand('android', 'emu-1'),
        ['adb', '-s', 'emu-1', 'uninstall', kConsumerAppId]);
    expect(installedProbeCommand('ios', 'SIM'),
        ['xcrun', 'simctl', 'get_app_container', 'SIM', kConsumerAppId]);
    expect(installedProbeCommand('android', 'emu-1'),
        ['adb', '-s', 'emu-1', 'shell', 'pm', 'path', kConsumerAppId]);
    expect(uninstallCommand('android', 'emu-1', adb: '/sdk/platform-tools/adb').first,
        '/sdk/platform-tools/adb');
  });

  test('installation is read from the probe, not from the uninstall result', () {
    expect(isInstalled('ios', 0, '/path/to/container'), isTrue);
    expect(isInstalled('ios', 1, ''), isFalse);
    expect(isInstalled('android', 0, 'package:/data/app/base.apk'), isTrue);
    // pm path exits zero with no output on some releases when nothing matches
    expect(isInstalled('android', 0, ''), isFalse);
    expect(isInstalled('android', 1, ''), isFalse);
    // A failed probe is not an install, whatever it printed
    expect(isInstalled('android', 1, 'package:/x'), isFalse);
  });

  test('the bounds keep their exact widths', () {
    expect(kClockSkewSeconds, 10);
    expect(kRelaunchGap, const Duration(seconds: 30));
  });

  test('a clock step the check allows cannot hide a recreated timestamp', () {
    // A recreated value lands at least the gap after the first pass ended, less
    // any backward step, and must still reach the second pass ceiling
    expect(kRelaunchGap.inSeconds - kClockStepSeconds,
        greaterThanOrEqualTo(kClockSkewSeconds));
  });

  test('the device clock is read from adb on Android and the host on iOS', () {
    expect(deviceClockCommand('android', 'emu-1', adb: '/sdk/platform-tools/adb'),
        ['/sdk/platform-tools/adb', '-s', 'emu-1', 'shell', 'date', '+%s']);
    expect(deviceClockCommand('ios', 'SIM'), isNull);
  });

  test('epoch seconds parse from device output and nothing else does', () {
    expect(parseEpochSeconds('1790191438\n'), 1790191438);
    expect(parseEpochSeconds('1790191438\r\n'), 1790191438);
    for (final bad in [
      '',
      'date: bad format',
      '1790191438123',
      '-1790191438',
      '1790191438 1790191439',
      '0x6AB3',
    ]) {
      expect(() => parseEpochSeconds(bad), throwsFormatException, reason: bad);
    }
  });

  test('a clock that keeps its offset is steady and one that steps is not', () {
    expect(clockHeldSteady(-93, -93), isTrue);
    expect(clockHeldSteady(-93, -93 + kClockStepSeconds), isTrue);
    expect(clockHeldSteady(-93, -93 - kClockStepSeconds), isTrue);
    expect(clockHeldSteady(-93, -93 + kClockStepSeconds + 1), isFalse);
    expect(clockHeldSteady(-93, -93 - kClockStepSeconds - 1), isFalse);
  });

  test('each pass builds its test command, and only the first keeps the app', () {
    List<String> commandFor(SessionPass pass) => acceptanceTestCommand(
          deviceId: 'emu-1',
          pass: pass,
          endpoint: Uri.parse('http://10.0.2.2:5000'),
          key: 'k1',
          controlKey: 'k2',
          reactiveKey: 'k3',
          expected: '[]',
        );
    final first = commandFor(firstPass(
        startedAt: 1000,
        readinessTimeout: const Duration(seconds: 15),
        overallTimeout: const Duration(minutes: 8)));
    final second = commandFor(secondPass(firstStartedAt: 1000, firstEndedAt: 1300));
    expect(first, [
      'flutter', 'test', 'integration_test/acceptance_test.dart',
      '-d', 'emu-1',
      '--no-uninstall',
      '--dart-define=COPRODUCT_ENDPOINT=http://10.0.2.2:5000',
      '--dart-define=COPRODUCT_SDK_KEY=k1',
      '--dart-define=COPRODUCT_SDK_KEY_CONTROL=k2',
      '--dart-define=COPRODUCT_SDK_KEY_REACTIVE=k3',
      '--dart-define=COPRODUCT_EXPECTED=[]',
    ]);
    expect(second, isNot(contains('--no-uninstall')));
    expect(second, [...first]..remove('--no-uninstall'));
  });

  group('the relaunch pair', () {
    late List<String> events;
    late List<SessionPass> passes;
    late List<String> logs;

    setUp(() {
      events = [];
      passes = [];
      logs = [];
    });

    // Clock readings are served in order, one per read. Each device reading
    // is paired with its offset from the host
    Future<int> run({
      required List<({int device, int offset})> clock,
      List<int> codes = const [0, 0],
    }) {
      var reads = 0;
      var runs = 0;
      return runRelaunchPair(
        runPass: (pass) async {
          passes.add(pass);
          events.add('pass${passes.length}');
          return codes[runs++];
        },
        readClock: () async {
          events.add('clock');
          return clock[reads++];
        },
        delay: (d) async => events.add('delay ${d.inSeconds}'),
        readinessTimeout: const Duration(seconds: 15),
        overallTimeout: const Duration(minutes: 8),
        log: logs.add,
      );
    }

    const steady = [
      (device: 1000, offset: -90),
      (device: 1300, offset: -90),
      (device: 1500, offset: -91),
    ];

    test('a green pair runs both passes in order and returns zero', () async {
      expect(await run(clock: steady), 0);
      expect(events, [
        'clock',
        'pass1',
        'clock',
        'delay ${kRelaunchGap.inSeconds}',
        'pass2',
        'clock',
      ]);
    });

    test('the first pass keeps the install and the second does not', () async {
      await run(clock: steady);
      expect(passes.map((p) => p.keepInstalled), [true, false]);
      expect(passes.map((p) => p.sessionCount), [1, 2]);
    });

    test('the bounds come from the device clock readings around pass one',
        () async {
      await run(clock: steady);
      expect(passes[0].firstSeenFloor, 1000 - kClockSkewSeconds);
      expect(passes[0].firstSeenCeiling, 1000 + 15 + 480 + kClockSkewSeconds);
      expect(passes[1].firstSeenFloor, 1000 - kClockSkewSeconds);
      expect(passes[1].firstSeenCeiling, 1300 + kClockSkewSeconds);
    });

    test('the offset from the host is logged', () async {
      await run(clock: steady);
      expect(logs, contains('clock: device minus host is -90s'));
    });

    test('a failed first pass returns its code and never relaunches', () async {
      expect(await run(clock: steady, codes: const [12, 0]), 12);
      expect(events, ['clock', 'pass1']);
    });

    test('a failed second pass returns its code', () async {
      expect(await run(clock: steady, codes: const [0, 1]), 1);
      expect(events.last, 'pass2');
    });

    test('a clock step during the first pass fails the run before pass two',
        () async {
      final code = await run(clock: const [
        (device: 1000, offset: -90),
        (device: 1294, offset: -96),
        (device: 1500, offset: -96),
      ]);
      expect(code, kCodeClockStepped);
      expect(events, ['clock', 'pass1', 'clock']);
    });

    test('a clock step across the second pass fails a green run', () async {
      final code = await run(clock: const [
        (device: 1000, offset: -90),
        (device: 1300, offset: -90),
        (device: 1494, offset: -96),
      ]);
      expect(code, kCodeClockStepped);
      expect(events.last, 'clock');
    });

    test('a step exactly at the tolerance still passes', () async {
      final code = await run(clock: [
        (device: 1000, offset: -90),
        (device: 1300, offset: -90 - kClockStepSeconds),
        (device: 1500, offset: -90),
      ]);
      expect(code, 0);
    });

    test('a clock step fails with the setup exit code', () {
      expect(kCodeSetupFailed, 2);
      expect(kCodeClockStepped, kCodeSetupFailed);
    });
  });

  test('a clock reading keeps the device time and its offset from the host', () {
    // The fix itself: the bounds come from the device, never the host, so an
    // emulator running behind cannot admit a recreated timestamp
    expect(clockReadingFrom('1790191438\r\n', 1790191529),
        (device: 1790191438, offset: -91));
    expect(clockReadingFrom('1790191600\n', 1790191529),
        (device: 1790191600, offset: 71));
    expect(() => clockReadingFrom('date: bad format', 1790191529),
        throwsFormatException);
  });

  test('the pair runs only once the app is verified absent', () async {
    final logged = <String>[];
    var pairs = 0;
    Future<int> pair() async {
      pairs++;
      return 7;
    }

    expect(
        await runRelaunchGate(
          deviceId: 'emu-1',
          clearInstall: () async => false,
          runPair: pair,
          log: logged.add,
        ),
        kCodeSetupFailed);
    expect(pairs, 0, reason: 'a leftover install means no first launch');
    expect(logged.single, contains('could not uninstall'));

    expect(
        await runRelaunchGate(
          deviceId: 'emu-1',
          clearInstall: () async => true,
          runPair: pair,
          log: logged.add,
        ),
        7,
        reason: 'the pair decides the result once the app is gone');
    expect(pairs, 1);
  });
}
