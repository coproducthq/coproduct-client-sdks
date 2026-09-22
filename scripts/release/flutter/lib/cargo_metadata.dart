import 'dart:convert';
import 'dart:io';

import 'shipped_graph.dart';

/// Thrown when `cargo metadata` cannot be run, exits nonzero, or its JSON
/// does not carry the fields this reader depends on.
class CargoMetadataError implements Exception {
  CargoMetadataError(this.message);
  final String message;
  @override
  String toString() => 'CargoMetadataError: $message';
}

/// The subset of a `cargo metadata` package record the license audit needs:
/// its declared SPDX expression (or null when the crate publishes none), the
/// `license-file` field it names (or null), and the directory its packaged
/// source was extracted into, which is where the actual license text lives.
class CargoPackageInfo {
  const CargoPackageInfo({
    required this.name,
    required this.version,
    required this.license,
    required this.licenseFile,
    required this.sourceDir,
  });

  final String name;
  final String version;
  final String? license;
  final String? licenseFile;
  final String sourceDir;

  PackageKey get key => (name, version);
}

/// Parses a `cargo metadata --format-version 1` JSON payload into a lookup by
/// package key. Pure and fixture-testable: no process is run here.
Map<PackageKey, CargoPackageInfo> parseCargoMetadata(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (e) {
    throw CargoMetadataError('cargo metadata output is not valid JSON: $e');
  }
  if (decoded is! Map<String, dynamic>) {
    throw CargoMetadataError('cargo metadata output is not a JSON object');
  }
  final packages = decoded['packages'];
  if (packages is! List) {
    throw CargoMetadataError('cargo metadata output has no "packages" array');
  }
  final result = <PackageKey, CargoPackageInfo>{};
  for (final entry in packages) {
    if (entry is! Map<String, dynamic>) {
      throw CargoMetadataError('cargo metadata package entry is not an object');
    }
    final name = entry['name'];
    final version = entry['version'];
    final manifestPath = entry['manifest_path'];
    if (name is! String || version is! String || manifestPath is! String) {
      throw CargoMetadataError(
          'cargo metadata package entry is missing name, version, or manifest_path');
    }
    final license = entry['license'];
    final licenseFile = entry['license_file'];
    result[(name, version)] = CargoPackageInfo(
      name: name,
      version: version,
      license: license is String ? license : null,
      licenseFile: licenseFile is String ? licenseFile : null,
      sourceDir: File(manifestPath).parent.path,
    );
  }
  return result;
}

/// Runs `cargo metadata` against [manifestPath] and parses its output. Scoped
/// to a single workspace member's manifest still resolves the whole
/// workspace graph, which is why the shipped-package set is computed
/// separately from `cargo tree` and looked up here rather than the reverse.
Map<PackageKey, CargoPackageInfo> loadCargoMetadata({
  required String manifestPath,
  String cargoBin = 'cargo',
  ProcessResult Function(String executable, List<String> args)? runProcess,
}) {
  final run = runProcess ?? (executable, args) => Process.runSync(executable, args);
  final result = run(cargoBin, [
    'metadata',
    '--format-version',
    '1',
    '--manifest-path',
    manifestPath,
  ]);
  if (result.exitCode != 0) {
    throw CargoMetadataError('cargo metadata failed (exit ${result.exitCode}): ${result.stderr}');
  }
  final stdout = result.stdout;
  if (stdout is! String || stdout.trim().isEmpty) {
    throw CargoMetadataError('cargo metadata produced no output');
  }
  return parseCargoMetadata(stdout);
}
