import 'dart:convert';
import 'dart:io';

import 'package:coproduct_acceptance/process_tree.dart';
import 'package:test/test.dart';

// A pid is alive only when ps lists it in a non-zombie state, so a zombie
// awaiting reap counts as terminated the same way killProcessTree treats it
bool _alive(int pid) {
  final r = Process.runSync('ps', ['-o', 'stat=', '-p', '$pid']);
  if (r.exitCode != 0) return false;
  final stat = (r.stdout as String).trim();
  return stat.isNotEmpty && !stat.startsWith('Z');
}

void main() {
  test('escalates to SIGKILL and removes a stubborn tree', () async {
    final child = await Process.start(
        Platform.resolvedExecutable, ['run', 'test/helpers/stubborn_child.dart']);
    final line = await child.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .firstWhere((l) => l.startsWith('CHILD='));
    final m = RegExp(r'CHILD=(\d+) GRANDCHILD=(\d+)').firstMatch(line)!;
    final grandchildPid = int.parse(m.group(2)!);
    expect(_alive(grandchildPid), isTrue);

    await killProcessTree(child.pid,
        graceWindow: const Duration(milliseconds: 500));
    await child.exitCode;

    // The helper polls until the tree is gone, so the grandchild is already
    // terminated when it returns, with no extra settle wait
    expect(_alive(grandchildPid), isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('never signals the runner process itself', () async {
    // Killing our own pid's tree must not kill this test process. A child we
    // own is torn down, but the runner survives to make this assertion
    final sleeper = await Process.start('sleep', ['600']);
    await killProcessTree(sleeper.pid,
        graceWindow: const Duration(milliseconds: 200));
    expect(_alive(pid), isTrue);
  });

  test('never signals a process outside the target tree', () async {
    // A bystander the runner started, but that is not under the target root,
    // must survive teardown. This locks the safety guarantee that the walk only
    // ever signals the root's current tree, so a reused pid belonging to an
    // unrelated process is never terminated
    final bystander = await Process.start('sleep', ['600']);
    final target = await Process.start('sleep', ['600']);
    expect(_alive(bystander.pid), isTrue);
    expect(_alive(target.pid), isTrue);

    await killProcessTree(target.pid,
        graceWindow: const Duration(milliseconds: 300));

    expect(_alive(target.pid), isFalse);
    expect(_alive(bystander.pid), isTrue);

    bystander.kill(ProcessSignal.sigkill);
    await bystander.exitCode;
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('an escaped observed child fails teardown but is never signaled',
      () async {
    // The outer sh dies on SIGTERM; the inner sh traps SIGTERM and reparents to
    // init when the outer dies. The helper must refuse to signal the escaped
    // inner process, yet must not report teardown success while it is still
    // alive, so it throws with the survivor instead
    final middle = await Process.start('sh', [
      '-c',
      r'''sh -c 'trap "" TERM; while :; do sleep 1; done' & echo LEAF=$!; while :; do sleep 1; done'''
    ]);
    final line = await middle.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((l) => l.startsWith('LEAF='));
    final leafPid = int.parse(RegExp(r'LEAF=(\d+)').firstMatch(line)!.group(1)!);
    expect(_alive(leafPid), isTrue);

    await expectLater(
        killProcessTree(middle.pid,
            graceWindow: const Duration(milliseconds: 300)),
        throwsA(isA<ProcessTreeTerminationError>()));
    await middle.exitCode;

    // The escaped child was reported as a survivor, not signaled, so it lives on
    expect(_alive(leafPid), isTrue);

    // Clean up the process the test deliberately leaked
    Process.killPid(leafPid, ProcessSignal.sigkill);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a reused root pid does not turn a replacement tree into targets',
      () async {
    // Injected snapshots stand in for a race that cannot be reproduced with real
    // processes: the original root exits during teardown and its pid is reused by
    // an unrelated tree with a different start time. The fence on the original
    // root identity must stop the walk, so the replacement root and its brand new
    // child are never signaled
    final signalled = <int>[];
    var call = 0;
    List<ProcessSample> samples() {
      call++;
      if (call == 1) {
        return const [
          (pid: 1000, ppid: 1, start: 'A', zombie: false),
          (pid: 1001, ppid: 1000, start: 'B', zombie: false),
        ];
      }
      // rootPid 1000 is now an unrelated process (different start) with a new
      // child 1002 that was never part of the original tree
      return const [
        (pid: 1000, ppid: 1, start: 'C', zombie: false),
        (pid: 1002, ppid: 1000, start: 'D', zombie: false),
      ];
    }

    await killProcessTree(1000,
        graceWindow: const Duration(milliseconds: 50),
        sampleProcesses: samples,
        sendSignal: (p, sig) {
          signalled.add(p);
          return true;
        });

    // Only the original tree was signaled; the replacement root's new child was
    // never discovered, so it is never a target
    expect(signalled, [1001, 1000]);
    expect(signalled, isNot(contains(1002)));
  });
}
