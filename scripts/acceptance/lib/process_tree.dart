import 'dart:io';

/// A surviving process after a teardown, identified by pid and its start time so
/// a report names the exact process rather than a bare pid.
class ProcessTreeSurvivor {
  const ProcessTreeSurvivor(this.pid, this.start);
  final int pid;
  final String start;

  @override
  String toString() => 'pid $pid (started $start)';
}

/// Thrown when a previously observed member of the tree is still alive after the
/// escalation deadline, whether it is still in the tree or escaped by
/// reparenting, so teardown never reports success while a process it owned may
/// still be running.
class ProcessTreeTerminationError implements Exception {
  ProcessTreeTerminationError(this.rootPid, this.survivors);
  final int rootPid;
  final List<ProcessTreeSurvivor> survivors;

  @override
  String toString() =>
      'process tree rooted at $rootPid still has live members: '
      '${survivors.join(', ')}';
}

/// Thrown when `ps` cannot be inspected, so a failed listing is surfaced rather
/// than mistaken for an empty process table.
class ProcessInspectionError implements Exception {
  ProcessInspectionError(this.exitCode, this.stderr);
  final int exitCode;
  final String stderr;

  @override
  String toString() => 'ps exited $exitCode: ${stderr.trim()}';
}

/// One process's parent, start time, and whether it is a zombie. The start time
/// is an opaque identity token, only ever compared for equality, never parsed.
typedef _Proc = ({int ppid, String start, bool zombie});

/// One row of an injected process table, used only by tests to drive the reuse
/// and reparenting cases that cannot be reproduced with real processes.
typedef ProcessSample = ({int pid, int ppid, String start, bool zombie});

Map<int, _Proc> _tableFromSamples(List<ProcessSample> samples) {
  final table = <int, _Proc>{};
  for (final s in samples) {
    table[s.pid] = (ppid: s.ppid, start: s.start, zombie: s.zombie);
  }
  return table;
}

/// Snapshots pid -> (ppid, start, zombie) from `ps` (portable across macOS and
/// Linux). pid, ppid, and the state code are the first three whitespace tokens
/// and lstart is the remainder, which contains internal spaces and is taken
/// verbatim. A state code beginning with Z marks a zombie awaiting reap.
Map<int, _Proc> _procTable() {
  final result = Process.runSync('ps', ['-eo', 'pid=,ppid=,stat=,lstart=']);
  if (result.exitCode != 0) {
    // A failed listing must not read as an empty table, which would strand a
    // child unsignaled and report teardown as complete
    throw ProcessInspectionError(result.exitCode, result.stderr as String);
  }
  final table = <int, _Proc>{};
  for (final line in (result.stdout as String).split('\n')) {
    final m = RegExp(r'^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.+?)\s*$').firstMatch(line);
    if (m == null) continue;
    table[int.parse(m.group(1)!)] = (
      ppid: int.parse(m.group(2)!),
      start: m.group(4)!,
      zombie: m.group(3)!.startsWith('Z'),
    );
  }
  return table;
}

/// Collects the members of [root]'s tree, deepest first, from a process-table
/// snapshot. A pid appears only when its ancestry still chains up to [root] in
/// this snapshot, so a process that has reparented out of the tree, or an
/// unrelated process that reused a pid, is excluded rather than pursued.
List<int> _descendantsLeafFirst(int root, Map<int, _Proc> table) {
  final children = <int, List<int>>{};
  table.forEach(
      (pid, proc) => children.putIfAbsent(proc.ppid, () => []).add(pid));
  final ordered = <int>[];
  void visit(int pid) {
    for (final c in children[pid] ?? const []) {
      visit(c);
    }
    if (table.containsKey(pid)) ordered.add(pid);
  }

  visit(root);
  return ordered;
}

bool _signal(int pid, ProcessSignal sig) {
  try {
    return Process.killPid(pid, sig);
  } catch (_) {
    return false;
  }
}

/// Terminates [rootPid] and every descendant. Dart can signal only one pid and a
/// child outlives its parent, so this walks the tree from a fresh `ps` snapshot
/// each pass, signals leaf-first so a parent cannot re-observe a reaped child,
/// re-scans for survivors, and escalates to SIGKILL after [graceWindow].
///
/// A pid is only ever signaled while its ancestry currently traces back to
/// [rootPid], and only while its start time still matches the value recorded
/// when it was first seen. An unrelated process that reused a dead member's pid
/// therefore chains to a different parent, or carries a different start time, and
/// is never signaled. The deliberate cost is that a member which reparents out of
/// the tree (its intermediate ancestor exits during teardown) is never pursued,
/// because at one-second start-time resolution a reparented pid cannot be told
/// apart from a reused one, and leaking a stray child is safer than killing an
/// unrelated process.
///
/// It never signals the runner itself and treats a zombie awaiting reap as
/// terminated. The original root identity is captured from the first snapshot
/// and fences every later traversal, so once that root exits no new process is
/// discovered or signaled: an unrelated tree that reused the root's pid is never
/// walked, and its children never become targets. Success is not reported while
/// any process ever observed in the tree is still alive by identity, whether
/// still in the tree or escaped by reparenting: after the SIGKILL it polls until
/// every observed identity is gone, and if one remains past the escalation
/// deadline it throws [ProcessTreeTerminationError] rather than returning as if
/// teardown succeeded. A pid reused with a different start time is never walked
/// or signaled. A same-second reuse that also carries the same start time cannot
/// be distinguished at one-second resolution and is the residual this ps-based
/// approach accepts, in exchange for needing neither elevated privileges nor a
/// process-group supervisor.
///
/// [sampleProcesses] and [sendSignal] are injected only by tests, to drive the
/// reuse and reparenting cases that cannot be reproduced with real processes.
Future<void> killProcessTree(
  int rootPid, {
  Duration graceWindow = const Duration(seconds: 5),
  List<ProcessSample> Function()? sampleProcesses,
  bool Function(int pid, ProcessSignal sig)? sendSignal,
}) async {
  if (rootPid == pid) return;
  final snapshot = sampleProcesses == null
      ? _procTable
      : () => _tableFromSamples(sampleProcesses());
  final signal = sendSignal ?? _signal;

  // Fence on the root identity: capture the start time of the process that owns
  // rootPid now, and refuse to traverse once that exact process is gone. This is
  // what stops an unrelated tree that later reuses rootPid from being walked
  final firstTable = snapshot();
  final root = firstTable[rootPid];
  if (root == null || root.zombie) return;
  final rootStart = root.start;

  // The start time each pid carried when first seen as a member of the tree, so
  // it can be recognized later even after it reparents out, and a pid whose start
  // time changed (it exited and its number was reused) is treated as gone
  final observed = <int, String>{rootPid: rootStart};

  // Current, live, non-zombie descendants to signal, deepest first, excluding the
  // runner and any pid whose identity no longer matches. Returns nothing once the
  // verified root is gone, so no member of a reused-pid tree is ever discovered
  List<ProcessTreeSurvivor> signalTargets(Map<int, _Proc> table) {
    final currentRoot = table[rootPid];
    if (currentRoot == null ||
        currentRoot.zombie ||
        currentRoot.start != rootStart) {
      return const [];
    }
    final targets = <ProcessTreeSurvivor>[];
    for (final p in _descendantsLeafFirst(rootPid, table)) {
      if (p == pid) continue;
      final proc = table[p]!;
      final start = observed.putIfAbsent(p, () => proc.start);
      if (proc.start != start) continue; // pid reused since first seen
      if (proc.zombie) continue; // awaiting reap, effectively terminated
      targets.add(ProcessTreeSurvivor(p, proc.start));
    }
    return targets;
  }

  // Every previously observed member still alive by identity, anywhere in the
  // table, whether still in the tree or escaped by reparenting. A non-empty
  // result means teardown is not yet complete
  List<ProcessTreeSurvivor> observedSurvivors(Map<int, _Proc> table) {
    final survivors = <ProcessTreeSurvivor>[];
    observed.forEach((p, start) {
      final proc = table[p];
      if (proc == null || proc.start != start || proc.zombie) return;
      survivors.add(ProcessTreeSurvivor(p, start));
    });
    return survivors;
  }

  for (final m in signalTargets(firstTable)) {
    signal(m.pid, ProcessSignal.sigterm);
  }
  final deadline = DateTime.now().add(graceWindow);
  while (DateTime.now().isBefore(deadline)) {
    final table = snapshot();
    signalTargets(table); // keep observed current as new descendants appear
    if (observedSurvivors(table).isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  // Escalate to SIGKILL for whatever is still a current descendant. An escaped
  // member is deliberately not signaled, only reported below
  for (final m in signalTargets(snapshot())) {
    signal(m.pid, ProcessSignal.sigkill);
  }
  // Prove termination: poll until every observed identity is gone, bounded so an
  // unkillable state cannot hang teardown, then surface any survivor
  final killDeadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(killDeadline)) {
    final table = snapshot();
    signalTargets(table);
    if (observedSurvivors(table).isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  final survivors = observedSurvivors(snapshot());
  if (survivors.isNotEmpty) {
    throw ProcessTreeTerminationError(rootPid, survivors);
  }
}
