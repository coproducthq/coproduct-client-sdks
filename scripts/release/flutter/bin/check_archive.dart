// Verify the staged package would publish exactly the intended files, carry only
// the one expected warning, and stay within the size thresholds.
//
// Membership is checked in both directions. A one-directional check is what let
// an entire example application ship unnoticed in an earlier measurement, so a
// file that is not on the allowlist fails the release just as a missing required
// file does.
import 'dart:convert';
import 'dart:io';

import '../lib/pub_file_list.dart';

/// The exact number of files pub publishes. See the assertion below for why a
/// count earns its keep next to the membership allowlist.
const _expectedFileCount = 140;

const _maxCompressedMb = 35;
const _maxUncompressedMb = 115;

/// Files that must be present.
const _required = <String>[
  'CHANGELOG.md',
  'LICENSE',
  'NOTICE-THIRD-PARTY.md',
  'PROVENANCE.json',
  'README.md',
  'analysis_options.yaml',
  'pubspec.yaml',
  'doc/state_management_recipes.md',
  'doc/testing.md',
  'lib/coproduct.dart',
  'lib/testing.dart',
  'example/README.md',
  'example/analysis_options.yaml',
  'example/assets/bucketing_vectors.json',
  'example/lib/main.dart',
  'example/pubspec.yaml',
];

/// Native artifacts and the platform files beside them, enumerated exactly. A
/// broad `ios/` or `android/` prefix would silently permit an extra slice, an
/// unexpected ABI, or a stale binary.
const _platformExact = <String>[
  'ios/Classes/dummy_file.c',
  'ios/CoproductFFI.xcframework/Info.plist',
  'ios/CoproductFFI.xcframework/ios-arm64/libcoproduct_ffi_frb.a',
  'ios/CoproductFFI.xcframework/ios-arm64-simulator/libcoproduct_ffi_frb.a',
  'ios/coproduct.podspec',
  'ios/stage_prebuilt.sh',
  'android/build.gradle',
  'android/settings.gradle',
  'android/src/main/AndroidManifest.xml',
  'android/src/main/jniLibs/arm64-v8a/libcoproduct_ffi_frb.so',
  'android/src/main/jniLibs/armeabi-v7a/libcoproduct_ffi_frb.so',
  'android/src/main/jniLibs/x86_64/libcoproduct_ffi_frb.so',
];

/// Roots whose contents are governed entirely by [_platformExact].
const _exactRoots = <String>['ios/', 'android/'];

/// Prefixes whose contents are permitted without enumeration.
const _allowedPrefixes = <String>['lib/', 'doc/', 'example/lib/', 'example/assets/'];

/// Nothing matching these may ship.
const _forbidden = <String>[
  'cargokit/',
  'flutter_rust_bridge.yaml',
  'linux/',
  'macos/',
  'windows/',
  'test/',
  'example/ios/',
  'example/android/',
  'example/integration_test/',
];

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: check_archive.dart <stage-dir>');
    exit(2);
  }
  final stage = args.single;
  // The reference for generated content is the repository package, so resolve
  // the repository root from this script's location rather than the stage.
  final repoRoot = File.fromUri(Platform.script).parent.parent.parent.parent.parent.path;
  final issues = <String>[];

  // The dry run resolves dependencies and writes .dart_tool, so it runs against
  // a throwaway copy: the canonical stage must not change between sealing and
  // publication.
  final probe = Directory.systemTemp.createTempSync('coproduct-archive-probe');
  final probeStage = '${probe.path}/stage';
  final copy = Process.runSync('cp', ['-R', stage, probeStage]);
  if (copy.exitCode != 0) {
    stderr.writeln('could not copy the stage: ${copy.stderr}');
    exit(1);
  }

  final dry = Process.runSync('flutter', ['pub', 'publish', '--dry-run'],
      workingDirectory: probeStage);
  final output = '${dry.stdout}\n${dry.stderr}';
  probe.deleteSync(recursive: true);

  // Match the one expected warning precisely rather than by substring: a
  // different flutter_rust_bridge complaint would slip past a looser test.
  final expectedPin = RegExp(
      r'Your dependency on "flutter_rust_bridge" should allow more than one version');
  final warnings = RegExp(r'^\* (.+)$', multiLine: true)
      .allMatches(output)
      .map((m) => m.group(1)!)
      .toList();
  final pinWarnings = warnings.where(expectedPin.hasMatch).toList();
  if (pinWarnings.length != 1) {
    issues.add(
        'expected exactly one flutter_rust_bridge pin warning, found ${pinWarnings.length}');
  }
  for (final w in warnings.where((w) => !expectedPin.hasMatch(w))) {
    issues.add('unexpected warning: $w');
  }
  if (output.contains('Package validation found the following error')) {
    issues.add('the dry run reported an error');
  }
  // The dry run exits nonzero while any warning stands, so a zero exit means the
  // pin warning is gone and the constraint was widened.
  if (dry.exitCode == 0) {
    issues.add('the dry run exited zero, so the expected pin warning is absent');
  }

  final List<String> files;
  try {
    files = parsePubTranscript(output);
  } on FormatException catch (e) {
    stderr.writeln('could not read the dry-run file list: ${e.message}');
    exit(1);
  }

  for (final r in _required) {
    if (!files.contains(r)) issues.add('missing required entry: $r');
  }
  for (final p in _platformExact) {
    if (!files.contains(p)) issues.add('missing required native entry: $p');
  }

  // The license texts are generated, so the reference is the set the repository
  // package carries, not the stage's own directory. Comparing the stage against
  // itself only proves internal consistency: deleting a text from the stage
  // removes it from both sides and the comparison still agrees.
  final referenceDir =
      Directory('$repoRoot/sdks/flutter/coproduct/third_party_licenses');
  if (!referenceDir.existsSync()) {
    issues.add('the repository package has no third_party_licenses directory');
  } else {
    final expected = referenceDir
        .listSync()
        .whereType<File>()
        .map((f) => 'third_party_licenses/${f.uri.pathSegments.last}')
        .toSet();
    final shipped =
        files.where((f) => f.startsWith('third_party_licenses/')).toSet();
    for (final missing in expected.difference(shipped)) {
      issues.add('generated license text not published: $missing');
    }
    for (final extra in shipped.difference(expected)) {
      issues.add('published license text was not generated: $extra');
    }
    if (expected.isEmpty) {
      issues.add('the repository package generated no license texts');
    }
  }

  for (final f in files) {
    if (_forbidden.any((p) => f == p || f.startsWith(p))) {
      issues.add('forbidden entry shipped: $f');
      continue;
    }
    if (f.startsWith('third_party_licenses/')) continue;
    if (_exactRoots.any(f.startsWith)) {
      if (!_platformExact.contains(f)) {
        issues.add('unexpected entry under a native root: $f');
      }
      continue;
    }
    final permitted = _required.contains(f) || _allowedPrefixes.any(f.startsWith);
    if (!permitted) issues.add('entry not on the allowlist: $f');
  }

  // The last gate re-derives what the first one proved. Membership shows a path
  // exists; it cannot distinguish a real library from a stale one or from a text
  // file of the same name, so the shipped binaries are re-verified here.
  //
  // Staging hashes the build output. This re-hashes the staged copies, closing
  // the window between the copy and the archive, and it is bidirectional: a
  // staged binary the stamp does not describe is as much a defect as a stamped
  // one that changed.
  final stampPath = '${Platform.environment['COPRODUCT_RELEASE_OUT']}/BUILD-STAMP.json';
  final stampFile = File(stampPath);
  if (!stampFile.existsSync()) {
    issues.add('no BUILD-STAMP.json at $stampPath, so the staged binaries '
        'cannot be tied to a build');
  } else {
    final stamp = jsonDecode(stampFile.readAsStringSync()) as Map<String, dynamic>;
    final artifacts = (stamp['artifacts'] as Map<String, dynamic>).cast<String, String>();
    final stagedNativeRels = _platformExact
        .where((p) => p.endsWith('.a') || p.endsWith('.so'))
        .toList();
    final covered = <String>{};
    for (final entry in artifacts.entries) {
      final matches =
          stagedNativeRels.where((rel) => rel.endsWith(entry.key)).toList();
      if (matches.length != 1) {
        issues.add('build stamp names ${entry.key}, which matches '
            '${matches.length} staged files (expected exactly 1)');
        continue;
      }
      covered.add(matches.single);
      final f = File('$stage/${matches.single}');
      if (!f.existsSync()) {
        issues.add('stamped artifact missing from the stage: ${matches.single}');
        continue;
      }
      final h = Process.runSync('shasum', ['-a', '256', f.path]);
      if (h.exitCode != 0) {
        issues.add('could not hash ${matches.single}');
        continue;
      }
      final got = (h.stdout as String).trim().split(RegExp(r'\s+')).first;
      if (got != entry.value) {
        issues.add('content changed since the build: ${matches.single}');
      }
    }
    for (final rel in stagedNativeRels) {
      if (!covered.contains(rel)) {
        issues.add('staged binary is not described by the build stamp: $rel');
      }
    }
  }

  final stagedNatives = <String>[
    for (final p in _platformExact)
      if (p.endsWith('.a') || p.endsWith('.so')) '$stage/$p'
  ];
  final machO = stagedNatives.where((p) => p.endsWith('.a')).toList();
  final elf = stagedNatives.where((p) => p.endsWith('.so')).toList();
  final checker = '$repoRoot/scripts/audit/frb-symbol-check.sh';
  for (final group in [
    (mode: 'macho', files: machO),
    (mode: 'elf', files: elf),
  ]) {
    if (group.files.isEmpty) continue;
    final r = Process.runSync(checker, [group.mode, ...group.files]);
    if (r.exitCode != 0) {
      issues.add('staged ${group.mode} binaries failed symbol verification');
      for (final line in (r.stderr as String).trim().split('\n')) {
        if (line.trim().isNotEmpty) issues.add('  $line');
      }
    }
  }

  final compressedMb = parseCompressedMb(output);
  stdout.writeln(
      'compressed archive: ${compressedMb.toStringAsFixed(1)} MB (max $_maxCompressedMb)');
  if (compressedMb > _maxCompressedMb) {
    issues.add('compressed archive $compressedMb MB exceeds $_maxCompressedMb MB');
  }

  final du = Process.runSync('du', ['-sm', stage]);
  final uncompressedMb =
      int.parse((du.stdout as String).trim().split(RegExp(r'\s+')).first);
  stdout.writeln(
      'uncompressed stage: $uncompressedMb MB (max $_maxUncompressedMb)');
  if (uncompressedMb > _maxUncompressedMb) {
    issues.add('uncompressed stage $uncompressedMb MB exceeds $_maxUncompressedMb MB');
  }

  // Asserted, not just reported. Every downstream gate is built from this same
  // parse of pub's human-readable output, so a file silently dropped by the
  // parser is absent from the extraction, the seal, and the membership check at
  // once while still riding in pub's real tarball. A count is the one check that
  // does not share that derivation. Update it deliberately when the published
  // set changes.
  stdout.writeln('published files: ${files.length} (expected $_expectedFileCount)');
  if (files.length != _expectedFileCount) {
    issues.add('published file count is ${files.length}, expected '
        '$_expectedFileCount. If this change is intended, update '
        '_expectedFileCount; if not, a file was added or silently dropped.');
  }

  if (issues.isNotEmpty) {
    for (final i in issues) {
      stderr.writeln('  $i');
    }
    exit(1);
  }
  stdout.writeln('COPRODUCT_FLUTTER_ARCHIVE_STATUS pass=true');
}
