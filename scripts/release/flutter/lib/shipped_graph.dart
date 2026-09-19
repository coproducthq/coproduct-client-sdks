import 'dart:io';

/// A package identity in the shipped dependency graph. Keyed by name and
/// version together, so two published versions of the same crate name are
/// tracked as distinct entries rather than collapsing into one.
typedef PackageKey = (String name, String version);

/// Thrown when `cargo tree` cannot be run, exits nonzero, or prints a line
/// this reader does not recognize.
class ShippedGraphError implements Exception {
  ShippedGraphError(this.message);
  final String message;
  @override
  String toString() => 'ShippedGraphError: $message';
}

/// The six architectures the Flutter package ships a prebuilt binary for
///
/// `i686-linux-android` stays out of this list: it backs the native Android
/// SDK, not the Flutter package, which ships no 32-bit x86 ABI
const shippedTargets = <String>[
  'aarch64-apple-ios',
  'aarch64-apple-ios-sim',
  'x86_64-apple-ios',
  'armv7-linux-androideabi',
  'aarch64-linux-android',
  'x86_64-linux-android',
];

/// The union of the shipped dependency graph across every target, split into
/// the third-party packages that need a license audit and the workspace-local
/// crates (this repository's own code) that do not.
class ShippedGraph {
  const ShippedGraph({required this.thirdParty, required this.workspaceLocal});
  final Set<PackageKey> thirdParty;
  final Set<PackageKey> workspaceLocal;
}

/// One parsed entry from a `cargo tree --prefix none --format "{p}"` line.
class ParsedTreeEntry {
  const ParsedTreeEntry(this.key, {required this.isWorkspaceLocal});
  final PackageKey key;
  final bool isWorkspaceLocal;
}

/// Parses one line of `cargo tree --prefix none --format "{p}"` output.
///
/// A registry package prints as `name vVERSION`, optionally suffixed with
/// `(*)` when cargo has already expanded that subtree elsewhere in the same
/// tree and collapses the repeat. A workspace-local path dependency instead
/// suffixes an absolute filesystem path, which is what distinguishes this
/// repository's own crates from every published dependency. Returns null when
/// the line does not match either shape.
ParsedTreeEntry? parseCargoTreeEntry(String line) {
  final match = RegExp(r'^(\S+) v(\S+)(?: \((.*)\))?$').firstMatch(line.trim());
  if (match == null) return null;
  final name = match.group(1)!;
  final version = match.group(2)!;
  final suffix = match.group(3);
  // Only an absolute filesystem path marks a workspace-local crate. Treating
  // every other suffix as local would drop a git or proc-macro dependency from
  // the audit entirely while still reporting success, so anything unrecognized
  // fails loudly instead.
  var isWorkspaceLocal = false;
  if (suffix != null && suffix != '*') {
    if (suffix.startsWith('/')) {
      isWorkspaceLocal = true;
    } else {
      throw ShippedGraphError(
          'unrecognized cargo tree suffix "($suffix)" for $name v$version, so it '
          'cannot be classified as shipped or workspace-local');
    }
  }
  return ParsedTreeEntry((name, version), isWorkspaceLocal: isWorkspaceLocal);
}

/// Runs `cargo tree` for [target] against [manifestPath] and returns its
/// stdout lines, throwing [ShippedGraphError] on a nonzero exit so a broken
/// toolchain fails loudly rather than silently returning an empty graph.
List<String> runCargoTree({
  required String manifestPath,
  required String target,
  required String cargoBin,
  required ProcessResult Function(String executable, List<String> args) runProcess,
}) {
  final result = runProcess(cargoBin, [
    'tree',
    '--edges',
    'normal,no-proc-macro',
    '--target',
    target,
    '--manifest-path',
    manifestPath,
    '--prefix',
    'none',
    '--format',
    '{p}',
  ]);
  if (result.exitCode != 0) {
    throw ShippedGraphError(
        'cargo tree failed for target $target (exit ${result.exitCode}): ${result.stderr}');
  }
  final stdout = result.stdout;
  if (stdout is! String || stdout.trim().isEmpty) {
    throw ShippedGraphError('cargo tree produced no output for target $target');
  }
  return stdout.split('\n');
}

/// Computes the union shipped dependency graph across [targets] (defaulting
/// to [shippedTargets]) from the crate at [manifestPath]. [runProcess]
/// defaults to a real synchronous `cargo tree` invocation and is injectable
/// so tests can replay committed fixture output instead of depending on a
/// live toolchain.
ShippedGraph computeShippedGraph({
  required String manifestPath,
  List<String> targets = shippedTargets,
  String cargoBin = 'cargo',
  ProcessResult Function(String executable, List<String> args)? runProcess,
}) {
  final run = runProcess ??
      (executable, args) => Process.runSync(executable, args);
  final thirdParty = <PackageKey>{};
  final workspaceLocal = <PackageKey>{};
  for (final target in targets) {
    final lines = runCargoTree(
      manifestPath: manifestPath,
      target: target,
      cargoBin: cargoBin,
      runProcess: run,
    );
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final entry = parseCargoTreeEntry(line);
      if (entry == null) {
        throw ShippedGraphError('unparsed cargo tree line for target $target: "$line"');
      }
      if (entry.isWorkspaceLocal) {
        workspaceLocal.add(entry.key);
      } else {
        thirdParty.add(entry.key);
      }
    }
  }
  return ShippedGraph(thirdParty: thirdParty, workspaceLocal: workspaceLocal);
}
