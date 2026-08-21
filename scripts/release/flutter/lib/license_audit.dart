import 'dart:convert';

import 'shipped_graph.dart';

/// Thrown by every stage of the license audit: a disallowed license, a
/// missing policy clarification, a missing license text, or a verification
/// mismatch. Always names the offending package or file so a failure is
/// actionable from the message alone.
class LicenseAuditError implements Exception {
  LicenseAuditError(this.message);
  final String message;
  @override
  String toString() => 'LicenseAuditError: $message';
}

/// A reviewed decision recorded for one package that the automatic election
/// or file-selection path cannot resolve on its own: a crate that publishes
/// no SPDX license field, or one whose packaged source ships no license file
/// at all for its declared license. [textSource] is `"auto"` to still select
/// from the crate's own packaged files (used when only the election itself
/// needs a documented decision) or `"embeddedCanonical"` to fall back to this
/// tool's bundled standard license text when the crate provides no file to
/// redistribute.
class PolicyClarification {
  const PolicyClarification({
    required this.license,
    required this.reason,
    required this.textSource,
  });

  factory PolicyClarification.fromJson(Map<String, dynamic> json) {
    final license = json['license'];
    final reason = json['reason'];
    final textSource = json['textSource'];
    if (license is! String || reason is! String || textSource is! String) {
      throw LicenseAuditError(
          'policy clarification is missing license, reason, or textSource');
    }
    if (textSource != 'auto' &&
        textSource != 'embeddedCanonical' &&
        textSource != 'vendored') {
      throw LicenseAuditError('policy clarification has unknown textSource "$textSource"');
    }
    return PolicyClarification(license: license, reason: reason, textSource: textSource);
  }

  final String license;
  final String reason;
  final String textSource;
}

/// The reviewed license policy: an ordered allow list that doubles as the
/// preference order for electing among a dual license expression, plus the
/// clarifications for packages the automatic path cannot resolve.
class LicensePolicy {
  const LicensePolicy({required this.allowedLicenses, required this.clarifications});

  factory LicensePolicy.fromJson(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw LicenseAuditError('license policy is not valid JSON: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw LicenseAuditError('license policy is not a JSON object');
    }
    final allowed = decoded['allowedLicenses'];
    if (allowed is! List || allowed.any((e) => e is! String)) {
      throw LicenseAuditError('license policy "allowedLicenses" must be a list of strings');
    }
    final clarificationsJson = decoded['clarifications'];
    if (clarificationsJson is! Map<String, dynamic>) {
      throw LicenseAuditError('license policy "clarifications" must be an object');
    }
    final clarifications = <String, PolicyClarification>{
      for (final entry in clarificationsJson.entries)
        entry.key: PolicyClarification.fromJson(entry.value as Map<String, dynamic>),
    };
    return LicensePolicy(
      allowedLicenses: allowed.cast<String>(),
      clarifications: clarifications,
    );
  }

  final List<String> allowedLicenses;
  final Map<String, PolicyClarification> clarifications;
}

/// Renders a package key the same way everywhere: policy clarifications,
/// generated file names, and error messages all key off this string so a
/// human reading any of them can find the same package in the others.
String packageKeyLabel(PackageKey key) => '${key.$1}@${key.$2}';

/// Splits an SPDX license expression into its individual permitted terms,
/// handling both the `OR` operator and the deprecated `/` separator. A plain
/// single-term expression (no separator at all) returns that one term.
List<String> splitLicenseExpression(String expr) {
  final parts = expr.contains(' OR ') ? expr.split(' OR ') : expr.split('/');
  return parts.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

/// Elects the term of [expr] that ranks first in [allowedLicenses], not the
/// term that appears first in the expression itself, so the same package
/// always elects the same license regardless of how its author ordered the
/// dual expression. Throws, naming [package], when no term in the expression
/// appears in the allow list at all.
String electLicense(String expr, List<String> allowedLicenses, {required String package}) {
  final terms = splitLicenseExpression(expr).toSet();
  for (final candidate in allowedLicenses) {
    if (terms.contains(candidate)) return candidate;
  }
  throw LicenseAuditError(
      'package $package has no allowed license among "$expr" (allowed: ${allowedLicenses.join(', ')})');
}

/// The case-insensitive filename keyword that identifies a license-like file
/// as text for a given elected term.
const _licenseKeywords = <String, String>{
  'MIT': 'mit',
  'Apache-2.0': 'apache',
  'Unlicense': 'unlicense',
  'Zlib': 'zlib',
  '0BSD': '0bsd',
};

/// Chooses which of a crate's packaged license-like files correspond to
/// [electedTerm], deterministically rather than by filesystem order.
///
/// - No files at all: nothing to select; caller decides whether that is an
///   error or a signal to fall back to a policy clarification.
/// - Exactly one file's name keyword-matches the elected term (for example
///   `LICENSE-MIT` for `MIT`): that file alone stands for the license.
/// - No file keyword-matches, but the crate ships exactly one license-like
///   file in total (a bare `LICENSE` covering a single-term license, or a
///   single file covering a dual expression): that file stands for the
///   elected term, since it is the only text the crate provides.
/// - Otherwise the match is ambiguous (a keyword match found more than one
///   candidate, or several unmatched files with no way to prefer one): every
///   license-like file present is redistributed, because no single file can
///   be attributed to the elected term alone.
List<String> selectLicenseFiles(String electedTerm, List<String> availableFileNames) {
  if (availableFileNames.isEmpty) return const [];
  final keyword = _licenseKeywords[electedTerm];
  final matches = keyword == null
      ? const <String>[]
      : (availableFileNames.where((f) => f.toLowerCase().contains(keyword)).toList()
        ..sort());
  if (matches.length == 1) return matches;
  if (availableFileNames.length == 1) return [availableFileNames.single];
  if (matches.isNotEmpty) return matches;
  return List<String>.from(availableFileNames)..sort();
}

/// The standard SPDX license body text this tool can fall back to when a
/// package's packaged source ships no license file for its declared term.
/// [crateName] fills the copyright attribution line, since the packaged
/// crate itself does not supply a copyright holder to quote.
class CanonicalLicenseTemplates {
  const CanonicalLicenseTemplates(this._templates);

  factory CanonicalLicenseTemplates.fromFiles({
    required String mitTemplate,
    required String apache2Text,
  }) =>
      CanonicalLicenseTemplates({'MIT': mitTemplate, 'Apache-2.0': apache2Text});

  final Map<String, String> _templates;

  String render(String license, String crateName) {
    final template = _templates[license];
    if (template == null) {
      throw LicenseAuditError('no canonical license text embedded for "$license"');
    }
    return template.replaceAll('{crate}', crateName);
  }
}

/// One package's packaged source as input to the audit: its declared SPDX
/// expression (or null when it publishes none) and the license-like files
/// available in its extracted crate directory, by filename, with content.
class PackageLicenseInput {
  const PackageLicenseInput({
    required this.key,
    required this.spdxLicense,
    required this.availableFiles,
  });

  final PackageKey key;
  final String? spdxLicense;
  final Map<String, String> availableFiles;
}

/// One row of the generated notice, and the destination filenames (relative
/// to `third_party_licenses/`) that carry its redistributed license text.
class ThirdPartyNoticeEntry {
  const ThirdPartyNoticeEntry({
    required this.key,
    required this.electedLicense,
    required this.licenseFileNames,
  });

  final PackageKey key;
  final String electedLicense;
  final List<String> licenseFileNames;
}

/// The full generated output: the notice document and every redistributed
/// license text file, keyed by the name it is written under.
class GeneratedNotices {
  const GeneratedNotices({required this.noticeMarkdown, required this.licenseFiles});
  final String noticeMarkdown;
  final Map<String, String> licenseFiles;
}

/// Builds the stable destination filename for one package's redistributed
/// license text, so a filename never collides between two different packages
/// (or two versions of the same package) and never depends on filesystem
/// iteration order.
String licenseFileDestName(PackageKey key, String sourceFileName) =>
    '${key.$1}-${key.$2}-$sourceFileName';

/// Elects a license and selects its text for every package in [packages],
/// then renders `NOTICE-THIRD-PARTY.md` and the redistributed license texts.
/// Throws [LicenseAuditError], naming the package, when a license cannot be
/// elected or no text can be found for it. Throws when [policy] carries a
/// clarification for a package that is not in [packages] (a stale entry that
/// would otherwise go silently unused).
GeneratedNotices buildNotices({
  required List<PackageLicenseInput> packages,
  required LicensePolicy policy,
  required CanonicalLicenseTemplates canonicalTemplates,
  Map<String, String> vendoredTexts = const {},
}) {
  final sorted = List<PackageLicenseInput>.from(packages)
    ..sort((a, b) {
      final byName = a.key.$1.compareTo(b.key.$1);
      return byName != 0 ? byName : a.key.$2.compareTo(b.key.$2);
    });

  final entries = <ThirdPartyNoticeEntry>[];
  final licenseFiles = <String, String>{};
  final usedClarifications = <String>{};

  for (final pkg in sorted) {
    final label = packageKeyLabel(pkg.key);
    final clarification = policy.clarifications[label];
    if (clarification != null) usedClarifications.add(label);

    final String elected;
    if (clarification != null) {
      elected = clarification.license;
      if (!policy.allowedLicenses.contains(elected)) {
        throw LicenseAuditError(
            'package $label\'s clarified license "$elected" is not in the allow list');
      }
      if (pkg.spdxLicense != null) {
        final autoElected =
            electLicense(pkg.spdxLicense!, policy.allowedLicenses, package: label);
        if (autoElected != elected) {
          throw LicenseAuditError(
              'package $label\'s clarification elects "$elected" but its SPDX expression '
              '"${pkg.spdxLicense}" would elect "$autoElected"; update the clarification or '
              'remove it');
        }
      }
    } else {
      if (pkg.spdxLicense == null) {
        throw LicenseAuditError(
            'package $label publishes no SPDX license field and has no policy clarification');
      }
      elected = electLicense(pkg.spdxLicense!, policy.allowedLicenses, package: label);
    }

    final List<String> destNames;
    if (clarification?.textSource == 'vendored') {
      // The crate declares a license but packages no notice, so the real
      // upstream text is tracked here rather than synthesized. Reproducing the
      // actual copyright line is what the license asks for
      final destName = '${pkg.key.$1}-${pkg.key.$2}-$elected.txt';
      final vendored = vendoredTexts[destName];
      if (vendored == null) {
        throw LicenseAuditError(
            'package $label is marked vendored but no tracked notice named '
            '$destName was supplied');
      }
      licenseFiles[destName] = vendored;
      destNames = [destName];
    } else if (clarification?.textSource == 'embeddedCanonical') {
      final destName = '${pkg.key.$1}-${pkg.key.$2}-$elected.txt';
      licenseFiles[destName] = canonicalTemplates.render(elected, pkg.key.$1);
      destNames = [destName];
    } else {
      final selected = selectLicenseFiles(elected, pkg.availableFiles.keys.toList());
      if (selected.isEmpty) {
        throw LicenseAuditError(
            'package $label elected "$elected" but no license text was found and no policy '
            'clarification supplies one');
      }
      destNames = [
        for (final sourceName in selected) licenseFileDestName(pkg.key, sourceName)
      ];
      for (var i = 0; i < selected.length; i++) {
        licenseFiles[destNames[i]] = pkg.availableFiles[selected[i]]!;
      }
    }

    entries.add(ThirdPartyNoticeEntry(
      key: pkg.key,
      electedLicense: elected,
      licenseFileNames: destNames,
    ));
  }

  final staleClarifications =
      policy.clarifications.keys.toSet().difference(usedClarifications);
  if (staleClarifications.isNotEmpty) {
    throw LicenseAuditError(
        'policy clarifications name packages not in the shipped graph: '
        '${(staleClarifications.toList()..sort()).join(', ')}');
  }

  return GeneratedNotices(
    noticeMarkdown: renderNoticeMarkdown(entries),
    licenseFiles: licenseFiles,
  );
}

/// Renders the third-party notice document listing every audited package,
/// its elected license, and the file(s) that carry its redistributed text.
String renderNoticeMarkdown(List<ThirdPartyNoticeEntry> entries) {
  final buffer = StringBuffer()
    ..writeln('# Third-party notices')
    ..writeln()
    ..writeln('This package bundles prebuilt native binaries statically linked against '
        'the following third-party libraries. Their license texts are redistributed '
        'under `third_party_licenses/`.')
    ..writeln()
    ..writeln('| Package | Version | License | License text |')
    ..writeln('|---|---|---|---|');
  for (final entry in entries) {
    final files = entry.licenseFileNames
        .map((f) => '[`$f`](third_party_licenses/$f)')
        .join(', ');
    buffer.writeln(
        '| ${entry.key.$1} | ${entry.key.$2} | ${entry.electedLicense} | $files |');
  }
  return buffer.toString();
}

/// One difference found while verifying generated notices against what is
/// already on disk.
class NoticeMismatch {
  const NoticeMismatch(this.description);
  final String description;
  @override
  String toString() => description;
}

/// Compares [generated] against the files actually present on disk
/// ([existingNoticeMarkdown] and [existingLicenseFiles]), reporting every
/// difference: a missing file, a changed body, or a stale extra file that the
/// current audit would no longer produce. An empty result means the two
/// trees match byte for byte.
List<NoticeMismatch> verifyGeneratedNotices({
  required GeneratedNotices generated,
  required String? existingNoticeMarkdown,
  required Map<String, String> existingLicenseFiles,
}) {
  final mismatches = <NoticeMismatch>[];
  if (existingNoticeMarkdown == null) {
    mismatches.add(const NoticeMismatch('NOTICE-THIRD-PARTY.md is missing'));
  } else if (existingNoticeMarkdown != generated.noticeMarkdown) {
    mismatches.add(const NoticeMismatch('NOTICE-THIRD-PARTY.md content does not match a fresh audit'));
  }

  final expectedNames = generated.licenseFiles.keys.toSet();
  final actualNames = existingLicenseFiles.keys.toSet();

  for (final missing in expectedNames.difference(actualNames).toList()..sort()) {
    mismatches.add(NoticeMismatch('missing required license text: $missing'));
  }
  for (final stale in actualNames.difference(expectedNames).toList()..sort()) {
    mismatches.add(NoticeMismatch('stale license text no longer produced by the audit: $stale'));
  }
  for (final name in expectedNames.intersection(actualNames).toList()..sort()) {
    if (existingLicenseFiles[name] != generated.licenseFiles[name]) {
      mismatches.add(NoticeMismatch('license text changed: $name'));
    }
  }
  return mismatches;
}
