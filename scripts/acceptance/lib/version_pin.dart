/// The u64 ceiling: components must fit so the core's numeric canonicalization
/// leaves them unchanged.
final BigInt _u64Max = BigInt.parse('18446744073709551615');

/// Android's versionCode ceiling (Google Play). app_build must fit so native
/// packaging does not normalize it.
final BigInt _versionCodeMax = BigInt.from(2100000000);

/// Parses the pinned `version: <v>+<build>` from the consumer pubspec text and
/// enforces the canonical fixed point: the raw strings must already equal the
/// forms the core and native packaging produce, so the fixture rule values match
/// the attributes the device collects. Throws [FormatException] otherwise.
({String version, String build}) parsePinnedVersion(String pubspecText) {
  final lines = pubspecText.split('\n');
  final matches = lines
      .map((l) => RegExp(r'^version:\s*(\S+)\s*$').firstMatch(l))
      .whereType<RegExpMatch>()
      .toList();
  if (matches.isEmpty) {
    throw const FormatException('no top-level version: found');
  }
  if (matches.length > 1) {
    throw const FormatException('duplicate top-level version:');
  }
  final raw = matches.single.group(1)!;
  final plus = raw.indexOf('+');
  if (plus < 0) {
    throw FormatException('version must be <version>+<build>, got $raw');
  }
  final version = raw.substring(0, plus);
  final build = raw.substring(plus + 1);

  final vMatch =
      RegExp(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')
          .firstMatch(version);
  if (vMatch == null) {
    throw FormatException('non-canonical version $version');
  }
  for (var i = 1; i <= 3; i++) {
    if (BigInt.parse(vMatch.group(i)!) > _u64Max) {
      throw FormatException('version component exceeds u64 in $version');
    }
  }

  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(build)) {
    throw FormatException('non-canonical build $build');
  }
  if (BigInt.parse(build) > _versionCodeMax) {
    throw FormatException('build exceeds the Android versionCode range');
  }
  return (version: version, build: build);
}
