import 'dart:io';

/// Thrown when an input is malformed or a coordinated release file is not in its
/// expected pre-state, so the command fails without mutating the tree rather than
/// producing a split version identity.
class ReleasePrepError implements Exception {
  ReleasePrepError(this.message);
  final String message;
  @override
  String toString() => 'ReleasePrepError: $message';
}

/// A release version is a plain semver with no pre-release/build suffix, so a dev
/// value like 0.1.0-dev cannot be published by mistake.
void validateVersion(String version) {
  if (!RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$').hasMatch(version)) {
    throw ReleasePrepError('version "$version" is not a canonical release semver (X.Y.Z)');
  }
}

/// A canonical YYYY-MM-DD that is also a real calendar date.
void validateDate(String date) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
    throw ReleasePrepError('date "$date" is not YYYY-MM-DD');
  }
  final parsed = DateTime.tryParse('${date}T00:00:00');
  if (parsed == null ||
      '${parsed.year.toString().padLeft(4, '0')}-'
              '${parsed.month.toString().padLeft(2, '0')}-'
              '${parsed.day.toString().padLeft(2, '0')}' !=
          date) {
    throw ReleasePrepError('date "$date" is not a valid calendar date');
  }
}

// Each bump replaces whatever version the file currently names, rather than
// only a fixed placeholder. The placeholders were right for the first release
// and wrong for every one after it: once 1.0.0 shipped, a tree at 1.0.0 matched
// no placeholder and the whole preparation threw. Publishing a dev value stays
// impossible because validateVersion rejects any target that is not a plain
// X.Y.Z, and an unparseable file still throws rather than being rewritten.

String bumpPubspecVersion(String content, String version) {
  final current = RegExp(r'^version: (\S+)$', multiLine: true);
  final match = current.firstMatch(content);
  if (match == null) {
    throw ReleasePrepError('pubspec has no version line');
  }
  if (match.group(1) == version) return content; // idempotent
  return content.replaceFirst(current, 'version: $version');
}

String bumpSdkVersion(String content, String version) {
  final current = RegExp(r"const _coproductSdkVersion = '([^']+)';");
  final match = current.firstMatch(content);
  if (match == null) {
    throw ReleasePrepError('no _coproductSdkVersion constant found');
  }
  if (match.group(1) == version) return content; // idempotent
  return content.replaceFirst(
      current, "const _coproductSdkVersion = '$version';");
}

String bumpPodspecVersion(String content, String version) {
  final current = RegExp(r"s\.version( +)= '([^']+)'");
  final match = current.firstMatch(content);
  if (match == null) {
    throw ReleasePrepError('podspec has no s.version line');
  }
  if (match.group(2) == version) return content; // idempotent
  // The original spacing is preserved: the identity audit matches the podspec
  // line verbatim, so re-aligning it here would fail that audit
  return content.replaceFirst(
      current, "s.version${match.group(1)}= '$version'");
}

String promoteReadmeInstall(String content, String version) {
  // Spans the unpublished notice, the path-dependency block, and the trailing
  // sentence that only makes sense before release
  final placeholder = RegExp(
      r'> The SDK is not yet published to pub\.dev\..*?```\n\nAfter release, this becomes an ordinary version dependency\.\n',
      dotAll: true);
  final replacement =
      'Add it to your `pubspec.yaml`:\n\n```yaml\ndependencies:\n  coproduct: ^$version\n```\n';
  if (placeholder.hasMatch(content)) {
    return content.replaceFirst(placeholder, replacement);
  }
  if (content.contains('coproduct: ^$version')) return content; // idempotent
  // After the first release the placeholder block is long gone and the README
  // carries an ordinary version dependency, so bump that instead
  final published = RegExp(r'coproduct: \^(\S+)');
  if (published.hasMatch(content)) {
    return content.replaceFirst(published, 'coproduct: ^$version');
  }
  throw ReleasePrepError('readme names no coproduct install version');
}

String promoteChangelog(String content, String version, String date) {
  const unreleased = '## Unreleased';
  final dated = '## $version - $date';
  // Match the whole first line, not a prefix, so a drifted heading such as
  // "## Unreleased notes" is rejected rather than silently transformed
  final firstLine = content.split('\n').first;
  if (firstLine == unreleased) {
    return content.replaceFirst(unreleased, dated);
  }
  if (firstLine == dated) return content; // idempotent
  throw ReleasePrepError('changelog first line is not exactly "$unreleased"');
}

/// Returns a list of human-readable identity mismatches, empty when the pubspec
/// version, the SDK version constant, and the README install all name [version].
List<String> auditIdentity({
  required String pubspec,
  required String sdkVersion,
  required String readme,
  required String podspec,
  required String version,
}) {
  final issues = <String>[];
  if (!RegExp('^version: ${RegExp.escape(version)}\$', multiLine: true)
      .hasMatch(pubspec)) {
    issues.add('pubspec version is not $version');
  }
  if (!sdkVersion.contains("const _coproductSdkVersion = '$version';")) {
    issues.add('sdk version constant is not $version');
  }
  if (!readme.contains('coproduct: ^$version')) {
    issues.add('readme install does not reference ^$version');
  }
  // The podspec version is externally visible in a consumer's Podfile.lock
  if (!podspec.contains("s.version          = '$version'")) {
    issues.add('podspec version is not $version');
  }
  return issues;
}

/// Transforms the five coordinated release files under [pkgDir] from the dev
/// state to [version]/[date], validating inputs and every file's pre-state before
/// writing anything, rolling back on a write failure, and running the identity
/// audit afterward. Idempotent on an already-prepared tree. Throws
/// [ReleasePrepError] on any bad input, drift, or audit failure.
void prepareRelease({
  required String pkgDir,
  required String version,
  required String date,
  void Function(String path, String content)? writeFile,
}) {
  validateVersion(version);
  validateDate(date);
  final write = writeFile ?? (String p, String c) => File(p).writeAsStringSync(c);

  final pubspecPath = '$pkgDir/pubspec.yaml';
  final sdkPath = '$pkgDir/lib/src/sdk_version.dart';
  final readmePath = '$pkgDir/README.md';
  final changelogPath = '$pkgDir/CHANGELOG.md';
  final podspecPath = '$pkgDir/ios/coproduct.podspec';

  final transforms = <String, String>{
    pubspecPath: bumpPubspecVersion(File(pubspecPath).readAsStringSync(), version),
    sdkPath: bumpSdkVersion(File(sdkPath).readAsStringSync(), version),
    readmePath: promoteReadmeInstall(File(readmePath).readAsStringSync(), version),
    changelogPath:
        promoteChangelog(File(changelogPath).readAsStringSync(), version, date),
    podspecPath: bumpPodspecVersion(File(podspecPath).readAsStringSync(), version),
  };
  // The map builder above reads every file and runs every transform, so a drift
  // or bad input throws here before any write

  final originals = {
    for (final path in transforms.keys) path: File(path).readAsStringSync()
  };
  try {
    transforms.forEach(write);
  } catch (e) {
    // Restore every file from its original, including one whose write may have
    // partially applied before throwing. Each restore is guarded so a restore
    // failure cannot obscure the primary write error, and any file that could not
    // be restored is named so the caller never reads a clean-rollback claim while
    // the tree is actually partial
    final unrestored = <String>[];
    for (final entry in originals.entries) {
      try {
        write(entry.key, entry.value);
      } catch (_) {
        unrestored.add(entry.key);
      }
    }
    if (unrestored.isEmpty) {
      throw ReleasePrepError('write failed, rolled back from originals: $e');
    }
    throw ReleasePrepError(
        'write failed and rollback was incomplete, these files may be partially '
        'updated and must be restored manually (for example with git checkout): '
        '${unrestored.join(', ')}. Original error: $e');
  }

  final issues = auditIdentity(
    pubspec: File(pubspecPath).readAsStringSync(),
    sdkVersion: File(sdkPath).readAsStringSync(),
    readme: File(readmePath).readAsStringSync(),
    podspec: File(podspecPath).readAsStringSync(),
    version: version,
  );
  if (issues.isNotEmpty) {
    throw ReleasePrepError('identity audit failed:\n  ${issues.join('\n  ')}');
  }
}
