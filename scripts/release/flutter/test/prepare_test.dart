import 'dart:io';

import 'package:coproduct_release/prepare.dart';
import 'package:test/test.dart';

void main() {
  group('validateVersion', () {
    test('accepts a release semver', () => validateVersion('0.1.0'));
    test('rejects a non-semver', () {
      expect(() => validateVersion('nope'), throwsA(isA<ReleasePrepError>()));
    });
    test('rejects a -dev suffix (a release must not be a dev build)', () {
      expect(() => validateVersion('0.1.0-dev'),
          throwsA(isA<ReleasePrepError>()));
    });
    test('rejects noncanonical leading zeros', () {
      for (final v in ['01.0.0', '0.01.0', '0.0.01']) {
        expect(() => validateVersion(v), throwsA(isA<ReleasePrepError>()),
            reason: v);
      }
    });
  });

  group('validateDate', () {
    test('accepts a canonical date', () => validateDate('2026-08-04'));
    test('rejects a non-date', () {
      expect(() => validateDate('tomorrow'), throwsA(isA<ReleasePrepError>()));
    });
    test('rejects an impossible date', () {
      expect(() => validateDate('2026-13-40'), throwsA(isA<ReleasePrepError>()));
    });
  });

  group('bumpPubspecVersion', () {
    test('replaces the dev version', () {
      expect(bumpPubspecVersion('name: coproduct\nversion: 0.1.0-dev\n', '0.1.0'),
          'name: coproduct\nversion: 0.1.0\n');
    });
    test('is idempotent on the already-prepared version', () {
      expect(bumpPubspecVersion('version: 0.1.0\n', '0.1.0'), 'version: 0.1.0\n');
    });
    test('bumps from an already-released version', () {
      // The case every release after the first one hits
      expect(bumpPubspecVersion('version: 1.0.0\n', '1.0.1'),
          'version: 1.0.1\n');
    });

    test('throws when there is no version line to bump', () {
      expect(() => bumpPubspecVersion('name: coproduct\n', '1.0.1'),
          throwsA(isA<ReleasePrepError>()));
    });
  });

  group('bumpSdkVersion', () {
    test('replaces the constant', () {
      expect(
          bumpSdkVersion("const _coproductSdkVersion = '0.1.0-dev';\n", '0.1.0'),
          "const _coproductSdkVersion = '0.1.0';\n");
    });
    test('is idempotent', () {
      expect(bumpSdkVersion("const _coproductSdkVersion = '0.1.0';\n", '0.1.0'),
          "const _coproductSdkVersion = '0.1.0';\n");
    });
    test('bumps from an already-released version', () {
      expect(bumpSdkVersion("const _coproductSdkVersion = '1.0.0';\n", '1.0.1'),
          "const _coproductSdkVersion = '1.0.1';\n");
    });

    test('throws when the constant is absent', () {
      expect(() => bumpSdkVersion('const other = 1;\n', '1.0.1'),
          throwsA(isA<ReleasePrepError>()));
    });
  });

  group('promoteReadmeInstall', () {
    const before = '''
> The SDK is not yet published to pub.dev. Until it is, clone this repository
> and point a path dependency at the `sdks/flutter/coproduct` directory inside
> your checkout:

```yaml
dependencies:
  coproduct:
    path: /absolute/or/relative/path/to/coproduct-client-sdks/sdks/flutter/coproduct
```

After release, this becomes an ordinary version dependency.
''';
    const after = '''
Add it to your `pubspec.yaml`:

```yaml
dependencies:
  coproduct: ^0.1.0
```
''';
    test('rewrites the install block to the published version', () {
      expect(promoteReadmeInstall(before, '0.1.0'), after);
    });
    test('is idempotent once rewritten', () {
      expect(promoteReadmeInstall(after, '0.1.0'), after);
    });
    test('throws when the placeholder block is absent', () {
      expect(() => promoteReadmeInstall('no install block here', '0.1.0'),
          throwsA(isA<ReleasePrepError>()));
    });
  });

  group('promoteChangelog', () {
    test('dates the Unreleased heading', () {
      expect(promoteChangelog('## Unreleased\n\nbody\n', '0.1.0', '2026-08-04'),
          '## 0.1.0 - 2026-08-04\n\nbody\n');
    });
    test('is idempotent on the same version and date', () {
      expect(promoteChangelog('## 0.1.0 - 2026-08-04\n\nbody\n', '0.1.0', '2026-08-04'),
          '## 0.1.0 - 2026-08-04\n\nbody\n');
    });
    test('throws when there is no Unreleased heading', () {
      expect(() => promoteChangelog('## 0.0.1\n', '0.1.0', '2026-08-04'),
          throwsA(isA<ReleasePrepError>()));
    });
    test('rejects a drifted heading prefix rather than transforming it', () {
      expect(
          () => promoteChangelog(
              '## Unreleased notes\n\nbody\n', '0.1.0', '2026-08-04'),
          throwsA(isA<ReleasePrepError>()));
    });
    test('rejects extra text after an already-dated heading', () {
      expect(
          () => promoteChangelog(
              '## 0.1.0 - 2026-08-04 draft\n\nbody\n', '0.1.0', '2026-08-04'),
          throwsA(isA<ReleasePrepError>()));
    });
  });

  group('auditIdentity', () {
    test('passes when every version-bearing file agrees', () {
      expect(
          auditIdentity(
              pubspec: 'version: 0.1.0\n',
              sdkVersion: "const _coproductSdkVersion = '0.1.0';\n",
              readme: 'coproduct: ^0.1.0\n',
              podspec: "  s.version          = '0.1.0'\n",
              version: '0.1.0'),
          isEmpty);
    });
    test('reports each place that disagrees', () {
      expect(
          auditIdentity(
              pubspec: 'version: 0.1.0-dev\n',
              sdkVersion: "const _coproductSdkVersion = '0.1.0';\n",
              readme: 'coproduct: <released-version>\n',
              podspec: "  s.version          = '0.1.0'\n",
              version: '0.1.0'),
          hasLength(2));
    });
  });

  group('promoteReadmeInstall against the real install block', () {
    const realBlock = """## Installation

> The SDK is not yet published to pub.dev. Until it is, clone this repository
> and point a path dependency at the `sdks/flutter/coproduct` directory inside
> your checkout:

```yaml
dependencies:
  coproduct:
    path: /absolute/or/relative/path/to/coproduct-client-sdks/sdks/flutter/coproduct
```

After release, this becomes an ordinary version dependency.

## Quickstart
""";

    test('replaces the whole clone-and-path block with a version dependency', () {
      final out = promoteReadmeInstall(realBlock, '1.0.0');
      expect(out, contains('coproduct: ^1.0.0'));
      expect(out, isNot(contains('not yet published')));
      expect(out, isNot(contains('path: /absolute')));
      expect(out, isNot(contains('becomes an ordinary version dependency')));
      expect(out, contains('## Quickstart'));
    });

    test('is idempotent', () {
      final once = promoteReadmeInstall(realBlock, '1.0.0');
      expect(promoteReadmeInstall(once, '1.0.0'), equals(once));
    });
  });

  group('bumpPodspecVersion', () {
    test('promotes the placeholder version', () {
      const before = "  s.version          = '0.0.1'\n";
      expect(bumpPodspecVersion(before, '1.0.0'),
          equals("  s.version          = '1.0.0'\n"));
    });

    test('is idempotent on an already-prepared podspec', () {
      const done = "  s.version          = '1.0.0'\n";
      expect(bumpPodspecVersion(done, '1.0.0'), equals(done));
    });

    test('bumps from an already-released version, preserving alignment', () {
      // The identity audit matches this line verbatim, so the original spacing
      // must survive the rewrite
      const released = "  s.version          = '1.0.0'\n";
      expect(bumpPodspecVersion(released, '1.0.1'),
          "  s.version          = '1.0.1'\n");
    });

    test('throws when there is no s.version line', () {
      expect(() => bumpPodspecVersion("  s.summary = 'x'\n", '1.0.1'),
          throwsA(isA<ReleasePrepError>()));
    });
  });

  group('prepareRelease (end to end on a fixture tree)', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('rel_fixture');
      Directory('${dir.path}/lib/src').createSync(recursive: true);
      File('${dir.path}/pubspec.yaml')
          .writeAsStringSync('name: coproduct\nversion: 0.1.0-dev\n');
      File('${dir.path}/lib/src/sdk_version.dart')
          .writeAsStringSync("const _coproductSdkVersion = '0.1.0-dev';\n");
      // Mirrors the shipped README's install block, so a drift between the two
      // fails here rather than at release time
      File('${dir.path}/README.md').writeAsStringSync('''
> The SDK is not yet published to pub.dev. Until it is, clone this repository
> and point a path dependency at the `sdks/flutter/coproduct` directory inside
> your checkout:

```yaml
dependencies:
  coproduct:
    path: /absolute/or/relative/path/to/coproduct-client-sdks/sdks/flutter/coproduct
```

After release, this becomes an ordinary version dependency.
''');
      File('${dir.path}/CHANGELOG.md').writeAsStringSync('## Unreleased\n\nbody\n');
      Directory('${dir.path}/ios').createSync(recursive: true);
      File('${dir.path}/ios/coproduct.podspec')
          .writeAsStringSync("  s.version          = '0.0.1'\n");
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('prepares all five files and the audit is clean', () {
      prepareRelease(pkgDir: dir.path, version: '0.1.0', date: '2026-08-04');
      expect(File('${dir.path}/pubspec.yaml').readAsStringSync(),
          contains('version: 0.1.0\n'));
      expect(File('${dir.path}/lib/src/sdk_version.dart').readAsStringSync(),
          contains("'0.1.0'"));
      expect(File('${dir.path}/README.md').readAsStringSync(),
          contains('coproduct: ^0.1.0'));
      expect(File('${dir.path}/CHANGELOG.md').readAsStringSync(),
          startsWith('## 0.1.0 - 2026-08-04'));
      expect(File('${dir.path}/ios/coproduct.podspec').readAsStringSync(),
          contains("s.version          = '0.1.0'"));
    });

    test('is idempotent when run twice with the same arguments', () {
      prepareRelease(pkgDir: dir.path, version: '0.1.0', date: '2026-08-04');
      final snapshot = {
        for (final f in ['pubspec.yaml', 'lib/src/sdk_version.dart', 'README.md', 'CHANGELOG.md'])
          f: File('${dir.path}/$f').readAsStringSync()
      };
      prepareRelease(pkgDir: dir.path, version: '0.1.0', date: '2026-08-04');
      for (final entry in snapshot.entries) {
        expect(File('${dir.path}/${entry.key}').readAsStringSync(), entry.value);
      }
    });

    test('rejects an invalid version without touching the tree', () {
      final before = File('${dir.path}/pubspec.yaml').readAsStringSync();
      expect(() => prepareRelease(pkgDir: dir.path, version: 'nope', date: '2026-08-04'),
          throwsA(isA<ReleasePrepError>()));
      expect(File('${dir.path}/pubspec.yaml').readAsStringSync(), before);
    });

    test('a write failure rolls the whole tree back to originals', () {
      const names = ['pubspec.yaml', 'lib/src/sdk_version.dart', 'README.md',
                     'CHANGELOG.md', 'ios/coproduct.podspec'];
      final before = {
        for (final f in names) f: File('${dir.path}/$f').readAsStringSync()
      };
      var calls = 0;
      expect(
          () => prepareRelease(
                pkgDir: dir.path,
                version: '0.1.0',
                date: '2026-08-04',
                writeFile: (path, content) {
                  calls++;
                  if (calls == 1) {
                    File(path).writeAsStringSync(content); // first write succeeds
                  } else if (calls == 2) {
                    File(path).writeAsStringSync('PARTIAL'); // second partially applies
                    throw const FileSystemException('disk full');
                  } else {
                    File(path).writeAsStringSync(content); // restores succeed
                  }
                },
              ),
          throwsA(isA<ReleasePrepError>()));
      // Every file, including the partially written one, is restored
      for (final entry in before.entries) {
        expect(File('${dir.path}/${entry.key}').readAsStringSync(), entry.value,
            reason: entry.key);
      }
    });

    test('an incomplete rollback is reported, not claimed successful', () {
      // Forward write 2 fails to trigger rollback, and the first restore (call 3)
      // also fails, so the tree cannot be fully restored
      var calls = 0;
      expect(
          () => prepareRelease(
                pkgDir: dir.path,
                version: '0.1.0',
                date: '2026-08-04',
                writeFile: (path, content) {
                  calls++;
                  if (calls == 1) {
                    File(path).writeAsStringSync(content);
                  } else if (calls == 2) {
                    File(path).writeAsStringSync('PARTIAL');
                    throw const FileSystemException('disk full');
                  } else if (calls == 3) {
                    throw const FileSystemException('still read-only');
                  } else {
                    File(path).writeAsStringSync(content);
                  }
                },
              ),
          throwsA(isA<ReleasePrepError>().having((e) => e.message, 'message',
              allOf(contains('rollback was incomplete'),
                  contains('pubspec.yaml')))));
    });
  });
}
