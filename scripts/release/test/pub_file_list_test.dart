import 'dart:io';

import 'package:test/test.dart';

import '../lib/pub_file_list.dart';

void main() {
  group('parsePubFileList', () {
    test('reconstructs full paths from indent depth', () {
      const tree = '''
├── CHANGELOG.md (2 KB)
├── android
│   ├── build.gradle (1 KB)
│   └── src
│       └── main
│           └── jniLibs
│               └── arm64-v8a
│                   └── libcoproduct_ffi_frb.so (1 MB)
└── pubspec.yaml (1 KB)''';
      expect(parsePubFileList(tree), equals([
        'CHANGELOG.md',
        'android/build.gradle',
        'android/src/main/jniLibs/arm64-v8a/libcoproduct_ffi_frb.so',
        'pubspec.yaml',
      ]));
    });

    test('keeps names containing spaces', () {
      const tree = '''
├── doc
│   └── state management recipes.md (9 KB)''';
      expect(parsePubFileList(tree),
          equals(['doc/state management recipes.md']));
    });

    test('keeps dotted names and the sub-kilobyte size form', () {
      expect(parsePubFileList('├── .pubignore (<1 KB)'), equals(['.pubignore']));
    });

    test('throws on a line it cannot parse rather than skipping it', () {
      expect(() => parsePubFileList('├── ok.md (1 KB)\n~~~ unexpected ~~~'),
          throwsA(isA<FormatException>()));
    });
  });

  group('extractTreeSection', () {
    test('skips the resolution preamble and the validation suffix', () {
      const transcript = '''
Resolving dependencies...
Downloading packages...
  analyzer 10.0.1 (14.1.0 available)
Publishing coproduct 1.0.0 to https://pub.dev:
├── pubspec.yaml (1 KB)
└── lib
    └── coproduct.dart (2 KB)

Total compressed archive size: 21 MB.
Package has 1 warning.''';
      expect(parsePubTranscript(transcript),
          equals(['pubspec.yaml', 'lib/coproduct.dart']));
    });

    test('throws when the header is absent', () {
      expect(() => parsePubTranscript('Resolving dependencies...'),
          throwsA(isA<FormatException>()));
    });

    test('throws when the terminator is absent', () {
      expect(
          () => parsePubTranscript(
              'Publishing x 1.0.0 to https://pub.dev:\n├── a.md (1 KB)'),
          throwsA(isA<FormatException>()));
    });
  });

  group('against the captured real transcript', () {
    // A real `pub publish --dry-run` transcript from a staged release package.
    // Predicting this shape rather than capturing it is what broke an earlier
    // parser, so the fixture is tracked beside the test.
    late String transcript;

    setUpAll(() {
      transcript =
          File('test/fixtures/pub-dry-run.txt').readAsStringSync();
    });

    test('parses every line with nothing left over', () {
      final files = parsePubTranscript(transcript);
      expect(files, isNotEmpty);
      expect(files, contains('pubspec.yaml'));
      expect(files, contains('lib/coproduct.dart'));
      expect(files, contains('ios/coproduct.podspec'));
    });

    test('finds the bundled native artifacts at full depth', () {
      final files = parsePubTranscript(transcript);
      expect(
          files,
          contains(
              'ios/CoproductFFI.xcframework/ios-arm64/libcoproduct_ffi_frb.a'));
      expect(
          files,
          contains(
              'android/src/main/jniLibs/arm64-v8a/libcoproduct_ffi_frb.so'));
    });

    test('reads the compressed size', () {
      expect(parseCompressedMb(transcript), greaterThan(0));
    });
  });
}
