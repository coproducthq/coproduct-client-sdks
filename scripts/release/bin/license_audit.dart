import 'dart:io';

import 'package:coproduct_release/cargo_metadata.dart';
import 'package:coproduct_release/license_audit.dart';
import 'package:coproduct_release/shipped_graph.dart';

// dart run bin/license_audit.dart [--write]
//
// Audits the redistribution license of every third-party crate that
// statically links into the five prebuilt binaries the Flutter package
// ships, and generates NOTICE-THIRD-PARTY.md plus third_party_licenses/ from
// the result. Without --write, verifies the committed output still matches a
// fresh audit byte for byte and fails naming any drift. Run from
// scripts/release.
Future<void> main(List<String> args) async {
  final write = args.contains('--write');

  final scriptDir = File.fromUri(Platform.script).parent;
  final releaseDir = scriptDir.parent; // bin -> scripts/release
  final repoRoot = releaseDir.parent.parent.path; // scripts/release -> scripts -> repo root
  final pkgDir = '$repoRoot/sdks/flutter/coproduct';
  final manifestPath = '$repoRoot/ffi/coproduct-ffi-frb/Cargo.toml';

  _requireCargoAvailable();

  try {
    final graph = computeShippedGraph(manifestPath: manifestPath);
    final metadata = loadCargoMetadata(manifestPath: manifestPath);
    final policy =
        LicensePolicy.fromJson(File('${releaseDir.path}/license-policy.json').readAsStringSync());
    final canonicalTemplates = CanonicalLicenseTemplates.fromFiles(
      mitTemplate:
          File('${releaseDir.path}/assets/canonical-LICENSE-MIT.txt').readAsStringSync(),
      apache2Text:
          File('${releaseDir.path}/assets/canonical-LICENSE-APACHE.txt').readAsStringSync(),
    );

    final inputs = <PackageLicenseInput>[];
    for (final key in graph.thirdParty) {
      final info = metadata[key];
      if (info == null) {
        throw LicenseAuditError(
            'package ${packageKeyLabel(key)} is in the shipped graph but cargo metadata has no '
            'entry for it');
      }
      inputs.add(PackageLicenseInput(
        key: key,
        spdxLicense: info.license,
        availableFiles: _readLicenseLikeFiles(info.sourceDir),
      ));
    }

    final generated = buildNotices(
      packages: inputs,
      policy: policy,
      canonicalTemplates: canonicalTemplates,
      vendoredTexts: _readVendoredTexts(releaseDir),
    );

    if (write) {
      _writeGenerated(pkgDir: pkgDir, generated: generated);
      stdout.writeln(
          'wrote NOTICE-THIRD-PARTY.md and ${generated.licenseFiles.length} license texts '
          'for ${inputs.length} third-party packages');
      return;
    }

    final existingNoticePath = '$pkgDir/NOTICE-THIRD-PARTY.md';
    final existingNotice =
        File(existingNoticePath).existsSync() ? File(existingNoticePath).readAsStringSync() : null;
    final licenseDir = Directory('$pkgDir/third_party_licenses');
    final existingLicenseFiles = <String, String>{
      if (licenseDir.existsSync())
        for (final entry in licenseDir.listSync())
          if (entry is File) entry.uri.pathSegments.last: entry.readAsStringSync(),
    };

    final mismatches = verifyGeneratedNotices(
      generated: generated,
      existingNoticeMarkdown: existingNotice,
      existingLicenseFiles: existingLicenseFiles,
    );
    if (mismatches.isNotEmpty) {
      stderr.writeln('license audit found ${mismatches.length} mismatch(es):');
      for (final m in mismatches) {
        stderr.writeln('  - $m');
      }
      stderr.writeln('COPRODUCT_LICENSE_STATUS pass=false');
      exit(1);
    }

    stdout.writeln(
        'license audit clean: ${inputs.length} third-party packages, no copyleft, notices match');
    stdout.writeln('COPRODUCT_LICENSE_STATUS pass=true');
  } on ShippedGraphError catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('COPRODUCT_LICENSE_STATUS pass=false');
    exit(1);
  } on CargoMetadataError catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('COPRODUCT_LICENSE_STATUS pass=false');
    exit(1);
  } on LicenseAuditError catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('COPRODUCT_LICENSE_STATUS pass=false');
    exit(1);
  }
}

/// Confirms `cargo` actually resolves before trusting anything it prints, so
/// a missing toolchain fails with a clear message instead of surfacing as an
/// empty or malformed graph deeper in the audit.
void _requireCargoAvailable() {
  final ProcessResult result;
  try {
    result = Process.runSync('cargo', ['--version']);
  } on ProcessException catch (e) {
    stderr.writeln('cargo is not on PATH: $e');
    stderr.writeln('COPRODUCT_LICENSE_STATUS pass=false');
    exit(1);
  }
  if (result.exitCode != 0) {
    stderr.writeln('cargo --version failed (exit ${result.exitCode}): ${result.stderr}');
    stderr.writeln('COPRODUCT_LICENSE_STATUS pass=false');
    exit(1);
  }
}

/// Lists the license-like files directly inside a crate's packaged source
/// directory (LICENSE, LICENCE, or COPYING, in any casing or with any
/// extension) and reads their contents, so the selector can choose among
/// them deterministically rather than trusting filesystem iteration order.
Map<String, String> _readLicenseLikeFiles(String sourceDir) {
  final dir = Directory(sourceDir);
  if (!dir.existsSync()) return const {};
  final result = <String, String>{};
  for (final entry in dir.listSync()) {
    if (entry is! File) continue;
    final name = entry.uri.pathSegments.last;
    final upper = name.toUpperCase();
    if (upper.startsWith('LICENSE') || upper.startsWith('LICENCE') || upper.startsWith('COPYING')) {
      result[name] = entry.readAsStringSync();
    }
  }
  return result;
}

void _writeGenerated({required String pkgDir, required GeneratedNotices generated}) {
  File('$pkgDir/NOTICE-THIRD-PARTY.md').writeAsStringSync(generated.noticeMarkdown);
  final licenseDir = Directory('$pkgDir/third_party_licenses');
  licenseDir.createSync(recursive: true);
  final keep = generated.licenseFiles.keys.toSet();
  for (final entry in licenseDir.listSync()) {
    if (entry is File && !keep.contains(entry.uri.pathSegments.last)) {
      entry.deleteSync();
    }
  }
  generated.licenseFiles.forEach((name, content) {
    File('${licenseDir.path}/$name').writeAsStringSync(content);
  });
}

/// Upstream notices for crates that declare a license but package no license
/// file. They are tracked rather than synthesized so the real copyright line is
/// reproduced, which is what the licenses require
Map<String, String> _readVendoredTexts(Directory releaseDir) {
  // Resolved from the script's own location like every other input, so the
  // audit behaves the same regardless of the working directory it runs from
  final dir = Directory('${releaseDir.path}/assets/vendored');
  if (!dir.existsSync()) return const {};
  return {
    for (final f in dir.listSync().whereType<File>())
      f.uri.pathSegments.last: f.readAsStringSync(),
  };
}
