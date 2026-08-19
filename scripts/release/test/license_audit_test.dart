import 'dart:io';

import 'package:coproduct_release/license_audit.dart';
import 'package:test/test.dart';

const _mitTemplate = 'MIT License\n\nCopyright (c) the {crate} contributors\n\n[boilerplate]\n';
const _apacheText = 'Apache License 2.0\n\n[boilerplate]\n';

CanonicalLicenseTemplates _templates() =>
    CanonicalLicenseTemplates.fromFiles(mitTemplate: _mitTemplate, apache2Text: _apacheText);

LicensePolicy _policy({
  List<String> allowed = const ['MIT', 'Apache-2.0', 'Unlicense', 'Zlib', '0BSD'],
  Map<String, PolicyClarification> clarifications = const {},
}) =>
    LicensePolicy(allowedLicenses: allowed, clarifications: clarifications);

void main() {
  group('splitLicenseExpression', () {
    test('splits the modern OR form', () {
      expect(splitLicenseExpression('MIT OR Apache-2.0'), ['MIT', 'Apache-2.0']);
    });
    test('splits the deprecated slash form', () {
      expect(splitLicenseExpression('Apache-2.0/MIT'), ['Apache-2.0', 'MIT']);
    });
    test('returns a single term unchanged', () {
      expect(splitLicenseExpression('MIT'), ['MIT']);
    });
    test('splits a three-way OR expression', () {
      expect(splitLicenseExpression('0BSD OR MIT OR Apache-2.0'), ['0BSD', 'MIT', 'Apache-2.0']);
    });
  });

  group('electLicense', () {
    test('elects the allow-list-preferred term regardless of expression order', () {
      expect(electLicense('Apache-2.0 OR MIT', ['MIT', 'Apache-2.0'], package: 'p@1'), 'MIT');
      expect(electLicense('MIT OR Apache-2.0', ['MIT', 'Apache-2.0'], package: 'p@1'), 'MIT');
    });
    test('falls through to a lower-preference term when the top choice is absent', () {
      expect(electLicense('Unlicense OR MIT', ['Apache-2.0', 'MIT'], package: 'p@1'), 'MIT');
    });
    test('throws naming the package and the expression when nothing is allowed', () {
      expect(
        () => electLicense('GPL-3.0', ['MIT', 'Apache-2.0'], package: 'gpl-pkg@1.0.0'),
        throwsA(isA<LicenseAuditError>().having(
            (e) => e.message, 'message', allOf(contains('gpl-pkg@1.0.0'), contains('GPL-3.0')))),
      );
    });
  });

  group('selectLicenseFiles', () {
    test('picks the single keyword-matching file among several', () {
      expect(selectLicenseFiles('MIT', ['LICENSE-APACHE', 'LICENSE-MIT']), ['LICENSE-MIT']);
    });
    test('matches case-insensitively', () {
      expect(selectLicenseFiles('Apache-2.0', ['LICENSE-Apache', 'LICENSE-MIT']), ['LICENSE-Apache']);
    });
    test('uses the sole file when no name matches, for a single-term license', () {
      expect(selectLicenseFiles('MIT', ['LICENSE']), ['LICENSE']);
    });
    test('uses the sole file when no name matches, for a dual expression', () {
      expect(selectLicenseFiles('Apache-2.0', ['LICENSE']), ['LICENSE']);
    });
    test('redistributes every file when the match is ambiguous', () {
      expect(selectLicenseFiles('MIT', ['LICENSE-A', 'LICENSE-B']), ['LICENSE-A', 'LICENSE-B']);
    });
    test('returns nothing when the crate ships no license-like file', () {
      expect(selectLicenseFiles('MIT', []), isEmpty);
    });
  });

  group('buildNotices', () {
    test('generates a notice row and a license file for a simple SPDX package', () {
      final generated = buildNotices(
        packages: [
          PackageLicenseInput(
            key: ('demo', '1.0.0'),
            spdxLicense: 'MIT OR Apache-2.0',
            availableFiles: {'LICENSE-MIT': 'mit text', 'LICENSE-APACHE': 'apache text'},
          ),
        ],
        policy: _policy(),
        canonicalTemplates: _templates(),
      );
      expect(generated.noticeMarkdown, contains('demo'));
      expect(generated.noticeMarkdown, contains('MIT'));
      expect(generated.licenseFiles, {'demo-1.0.0-LICENSE-MIT': 'mit text'});
    });

    test('a clarified package with no SPDX field elects the clarified license', () {
      final generated = buildNotices(
        packages: [
          PackageLicenseInput(
            key: ('allo-isolate', '0.1.27'),
            spdxLicense: null,
            availableFiles: {'LICENSE': 'apache text via license_file'},
          ),
        ],
        policy: _policy(clarifications: {
          'allo-isolate@0.1.27': const PolicyClarification(
              license: 'Apache-2.0', reason: 'r', textSource: 'auto'),
        }),
        canonicalTemplates: _templates(),
      );
      expect(generated.noticeMarkdown, contains('Apache-2.0'));
      expect(generated.licenseFiles, {'allo-isolate-0.1.27-LICENSE': 'apache text via license_file'});
    });

    test('a clarified package with no license file falls back to embedded canonical text', () {
      final generated = buildNotices(
        packages: [
          PackageLicenseInput(key: ('dart-sys', '4.1.5'), spdxLicense: 'MIT OR Apache-2.0', availableFiles: {}),
        ],
        policy: _policy(clarifications: {
          'dart-sys@4.1.5': const PolicyClarification(
              license: 'MIT', reason: 'r', textSource: 'embeddedCanonical'),
        }),
        canonicalTemplates: _templates(),
      );
      expect(generated.licenseFiles.keys, ['dart-sys-4.1.5-MIT.txt']);
      expect(generated.licenseFiles['dart-sys-4.1.5-MIT.txt'], contains('the dart-sys contributors'));
    });

    test('throws when a package has no SPDX field and no clarification', () {
      expect(
        () => buildNotices(
          packages: [
            PackageLicenseInput(key: ('mystery', '1.0.0'), spdxLicense: null, availableFiles: {}),
          ],
          policy: _policy(),
          canonicalTemplates: _templates(),
        ),
        throwsA(isA<LicenseAuditError>().having((e) => e.message, 'message', contains('mystery@1.0.0'))),
      );
    });

    test('throws naming the package when no license text can be found', () {
      expect(
        () => buildNotices(
          packages: [
            PackageLicenseInput(key: ('bare', '1.0.0'), spdxLicense: 'MIT', availableFiles: {}),
          ],
          policy: _policy(),
          canonicalTemplates: _templates(),
        ),
        throwsA(isA<LicenseAuditError>().having((e) => e.message, 'message', contains('bare@1.0.0'))),
      );
    });

    test('throws when a clarification disagrees with automatic election', () {
      expect(
        () => buildNotices(
          packages: [
            PackageLicenseInput(
              key: ('demo', '1.0.0'),
              spdxLicense: 'MIT OR Apache-2.0',
              availableFiles: {'LICENSE-MIT': 'x', 'LICENSE-APACHE': 'y'},
            ),
          ],
          policy: _policy(clarifications: {
            'demo@1.0.0':
                const PolicyClarification(license: 'Apache-2.0', reason: 'r', textSource: 'auto'),
          }),
          canonicalTemplates: _templates(),
        ),
        throwsA(isA<LicenseAuditError>().having((e) => e.message, 'message', contains('demo@1.0.0'))),
      );
    });

    test('throws when a clarification names a license outside the allow list', () {
      expect(
        () => buildNotices(
          packages: [
            PackageLicenseInput(key: ('x', '1.0.0'), spdxLicense: null, availableFiles: {'LICENSE': 'x'}),
          ],
          policy: _policy(
            allowed: ['MIT'],
            clarifications: {
              'x@1.0.0':
                  const PolicyClarification(license: 'Apache-2.0', reason: 'r', textSource: 'auto'),
            },
          ),
          canonicalTemplates: _templates(),
        ),
        throwsA(isA<LicenseAuditError>()),
      );
    });

    test('throws when a policy clarification names a package not in the shipped graph', () {
      expect(
        () => buildNotices(
          packages: [
            PackageLicenseInput(key: ('demo', '1.0.0'), spdxLicense: 'MIT', availableFiles: {'LICENSE': 'x'}),
          ],
          policy: _policy(clarifications: {
            'ghost@9.9.9':
                const PolicyClarification(license: 'MIT', reason: 'r', textSource: 'auto'),
          }),
          canonicalTemplates: _templates(),
        ),
        throwsA(isA<LicenseAuditError>().having((e) => e.message, 'message', contains('ghost@9.9.9'))),
      );
    });

    test('removing MIT from the allow list fails every MIT-only package, naming it', () {
      expect(
        () => buildNotices(
          packages: [
            PackageLicenseInput(key: ('bytes', '1.11.1'), spdxLicense: 'MIT', availableFiles: {'LICENSE': 'x'}),
          ],
          policy: _policy(allowed: ['Apache-2.0', 'Unlicense', 'Zlib', '0BSD']),
          canonicalTemplates: _templates(),
        ),
        throwsA(isA<LicenseAuditError>().having(
            (e) => e.message, 'message', allOf(contains('bytes@1.11.1'), contains('MIT')))),
      );
    });
  });

  group('verifyGeneratedNotices', () {
    test('reports no mismatches when disk matches a fresh audit', () {
      final generated = GeneratedNotices(noticeMarkdown: 'NOTICE', licenseFiles: {'a-1.0.0-LICENSE': 'text'});
      expect(
        verifyGeneratedNotices(
            generated: generated,
            existingNoticeMarkdown: 'NOTICE',
            existingLicenseFiles: {'a-1.0.0-LICENSE': 'text'}),
        isEmpty,
      );
    });

    test('names a missing license file', () {
      final generated = GeneratedNotices(noticeMarkdown: 'NOTICE', licenseFiles: {'a-1.0.0-LICENSE': 'text'});
      final mismatches = verifyGeneratedNotices(
          generated: generated, existingNoticeMarkdown: 'NOTICE', existingLicenseFiles: {});
      expect(mismatches, hasLength(1));
      expect(mismatches.single.toString(), contains('a-1.0.0-LICENSE'));
    });

    test('names a license file whose bytes changed', () {
      final generated = GeneratedNotices(noticeMarkdown: 'NOTICE', licenseFiles: {'a-1.0.0-LICENSE': 'text'});
      final mismatches = verifyGeneratedNotices(
          generated: generated,
          existingNoticeMarkdown: 'NOTICE',
          existingLicenseFiles: {'a-1.0.0-LICENSE': 'textX'});
      expect(mismatches, hasLength(1));
      expect(mismatches.single.toString(), contains('a-1.0.0-LICENSE'));
    });

    test('names a stale extra file the current audit no longer produces', () {
      final generated = GeneratedNotices(noticeMarkdown: 'NOTICE', licenseFiles: {});
      final mismatches = verifyGeneratedNotices(
          generated: generated,
          existingNoticeMarkdown: 'NOTICE',
          existingLicenseFiles: {'stale-1.0.0-LICENSE': 'x'});
      expect(mismatches, hasLength(1));
      expect(mismatches.single.toString(), contains('stale-1.0.0-LICENSE'));
    });

    test('reports a missing notice file', () {
      final generated = GeneratedNotices(noticeMarkdown: 'NOTICE', licenseFiles: {});
      final mismatches =
          verifyGeneratedNotices(generated: generated, existingNoticeMarkdown: null, existingLicenseFiles: {});
      expect(mismatches, hasLength(1));
      expect(mismatches.single.toString(), contains('NOTICE-THIRD-PARTY.md'));
    });
  });

  group('the real repository policy against the real shipped graph', () {
    test('the committed policy JSON parses and its allow list has no copyleft term', () {
      final policy = LicensePolicy.fromJson(File('license-policy.json').readAsStringSync());
      for (final license in policy.allowedLicenses) {
        expect(license, isNot(anyOf(contains('GPL'), contains('MPL'), contains('LGPL'))));
      }
      expect(policy.clarifications.keys, {
        'allo-isolate@0.1.27',
        'dart-sys@4.1.5',
        'flutter_rust_bridge@2.12.0',
      });
    });
  });
}
