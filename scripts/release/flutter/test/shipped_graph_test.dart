import 'dart:io';

import 'package:coproduct_release/shipped_graph.dart';
import 'package:test/test.dart';

/// Replays a committed real `cargo tree --prefix none --format "{p}"`
/// transcript for [target] instead of running a live process, per the
/// fixtures captured from the actual toolchain in test/fixtures.
ProcessResult _fixtureRunner(String executable, List<String> args) {
  final targetIndex = args.indexOf('--target');
  final target = args[targetIndex + 1];
  final content =
      File('test/fixtures/cargo-tree-$target.txt').readAsStringSync();
  return ProcessResult(0, 0, content, '');
}

void main() {
  group('parseCargoTreeEntry classification', () {
    test('an absolute path marks a workspace-local crate', () {
      final e = parseCargoTreeEntry('coproduct-core v0.0.1 (/repo/core/coproduct-core)');
      expect(e!.isWorkspaceLocal, isTrue);
    });

    test('a bare registry entry is a shipped dependency', () {
      expect(parseCargoTreeEntry('anyhow v1.0.102')!.isWorkspaceLocal, isFalse);
    });

    test('the dedupe marker is a shipped dependency', () {
      expect(parseCargoTreeEntry('anyhow v1.0.102 (*)')!.isWorkspaceLocal, isFalse);
    });

    test('a git suffix throws rather than vanishing from the audit', () {
      expect(
          () => parseCargoTreeEntry(
              'foo v1.0.0 (https://github.com/a/b?tag=v1#abc123)'),
          throwsA(isA<ShippedGraphError>()));
    });

    test('a proc-macro suffix throws rather than vanishing from the audit', () {
      expect(() => parseCargoTreeEntry('foo v1.0.0 (proc-macro)'),
          throwsA(isA<ShippedGraphError>()));
    });
  });

  group('parseCargoTreeEntry', () {
    test('parses a plain registry package line', () {
      final entry = parseCargoTreeEntry('anyhow v1.0.102');
      expect(entry, isNotNull);
      expect(entry!.key, ('anyhow', '1.0.102'));
      expect(entry.isWorkspaceLocal, isFalse);
    });

    test('parses a collapsed-repeat marker as a registry package, not local', () {
      final entry = parseCargoTreeEntry('parking_lot v0.12.5 (*)');
      expect(entry, isNotNull);
      expect(entry!.key, ('parking_lot', '0.12.5'));
      expect(entry.isWorkspaceLocal, isFalse);
    });

    test('parses a workspace path dependency as local', () {
      final entry = parseCargoTreeEntry(
          'coproduct-core v0.0.1 (/Users/nathan/coproduct/coproduct-client-sdks/core/coproduct-core)');
      expect(entry, isNotNull);
      expect(entry!.key, ('coproduct-core', '0.0.1'));
      expect(entry.isWorkspaceLocal, isTrue);
    });

    test('returns null for an unrecognized line', () {
      expect(parseCargoTreeEntry('not a tree line'), isNull);
    });

    test('every line of every committed fixture parses', () {
      for (final target in shippedTargets) {
        final lines =
            File('test/fixtures/cargo-tree-$target.txt').readAsStringSync().split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          expect(parseCargoTreeEntry(line), isNotNull, reason: 'target $target line "$line"');
        }
      }
    });
  });

  group('computeShippedGraph (against committed fixtures)', () {
    test('unions all five targets into the known 79-package shipped graph', () {
      final graph = computeShippedGraph(
        manifestPath: 'unused-in-fixture-mode',
        runProcess: _fixtureRunner,
      );
      expect(graph.thirdParty.length + graph.workspaceLocal.length, 79);
      expect(graph.workspaceLocal, {('coproduct-core', '0.0.1'), ('coproduct_ffi_frb', '0.0.1')});
      expect(graph.thirdParty, contains(('allo-isolate', '0.1.27')));
      expect(graph.thirdParty, contains(('dart-sys', '4.1.5')));
      expect(graph.thirdParty, contains(('flutter_rust_bridge', '2.12.0')));
    });

    test('throws naming the target on a nonzero cargo tree exit', () {
      expect(
        () => computeShippedGraph(
          manifestPath: 'unused',
          targets: const ['aarch64-apple-ios'],
          runProcess: (exe, args) => ProcessResult(0, 1, '', 'target not found'),
        ),
        throwsA(isA<ShippedGraphError>().having(
            (e) => e.message, 'message', allOf(contains('aarch64-apple-ios'), contains('target not found')))),
      );
    });

    test('throws on an unparseable line rather than silently skipping it', () {
      expect(
        () => computeShippedGraph(
          manifestPath: 'unused',
          targets: const ['aarch64-apple-ios'],
          runProcess: (exe, args) => ProcessResult(0, 0, 'this is not a cargo tree line', ''),
        ),
        throwsA(isA<ShippedGraphError>()),
      );
    });
  });

  group('real toolchain integration', () {
    test('computeShippedGraph against the live repo matches the committed fixture union', () {
      // Tests run from scripts/release/flutter, so the repo root is three up
      final repoRoot = Directory.current.parent.parent.parent.path;
      final manifestPath = '$repoRoot/ffi/coproduct-ffi-frb/Cargo.toml';
      if (Process.runSync('cargo', ['--version']).exitCode != 0) {
        markTestSkipped('cargo not available');
        return;
      }
      final graph = computeShippedGraph(manifestPath: manifestPath);
      expect(graph.thirdParty.length + graph.workspaceLocal.length, 79);
      expect(graph.workspaceLocal, {('coproduct-core', '0.0.1'), ('coproduct_ffi_frb', '0.0.1')});
    });
  });
}
