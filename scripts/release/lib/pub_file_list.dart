/// Parses the file tree that `pub publish --dry-run` prints.
///
/// The tree is drawn with box-drawing characters and prints directory names
/// without a trailing slash, so a text search for a directory such as `example/`
/// matches nothing even when the whole directory ships. Reconstructing full
/// paths from the indent depth is what makes membership checkable.
///
/// Indentation is four characters per level. Measuring in bytes reports six for
/// a `|   ` prefix because the box-drawing character is three bytes in UTF-8;
/// Dart strings count UTF-16 code units, so dividing the length by four is
/// correct as written.
library;

final _entry = RegExp(
    r'^(?<indent>[\s│]*)(?:├──|└──)\s(?<name>.+?)(?:\s\((?:<?\d+(?:\.\d+)?)\s?[KMG]?B\))?$');
final _sizeSuffix = RegExp(r'\((?:<?\d+(?:\.\d+)?)\s?[KMG]?B\)$');
final _header = RegExp(r'^Publishing .+ to .+:$');
final _terminator = RegExp(r'^Total compressed archive size:');

/// Extracts the tree section from a complete dry-run transcript.
///
/// The transcript opens with dependency resolution and closes with validation
/// messages, so the tree is located rather than assumed: handing the whole
/// transcript to the entry parser throws on the first line.
String extractTreeSection(String transcript) {
  final lines = transcript.split('\n');
  final start = lines.indexWhere(_header.hasMatch);
  if (start < 0) {
    throw const FormatException(
        'dry-run output has no "Publishing ... to ...:" header');
  }
  final end = lines.indexWhere(_terminator.hasMatch, start);
  if (end < 0) {
    throw const FormatException(
        'dry-run output has no "Total compressed archive size:" line');
  }
  final tree =
      lines.sublist(start + 1, end).where((l) => l.trim().isNotEmpty).toList();
  if (tree.isEmpty) {
    throw const FormatException(
        'dry-run output has a header and a terminator but no tree between them');
  }
  return tree.join('\n');
}

/// Parses a complete dry-run transcript into relative file paths.
List<String> parsePubTranscript(String transcript) =>
    parsePubFileList(extractTreeSection(transcript));

/// Parses an already-extracted tree section into relative file paths.
///
/// Throws on any line it does not recognize, so an unparsed line can never be
/// mistaken for an absent file.
List<String> parsePubFileList(String treeOutput) {
  final paths = <String>[];
  final stack = <String>[];
  for (final raw in treeOutput.split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty) continue;
    final m = _entry.firstMatch(line);
    if (m == null) {
      throw FormatException('unrecognized dry-run line: $line');
    }
    final depth = m.namedGroup('indent')!.length ~/ 4;
    final name = m.namedGroup('name')!;
    while (stack.length > depth) {
      stack.removeLast();
    }
    if (_sizeSuffix.hasMatch(line)) {
      paths.add([...stack, name].join('/'));
    } else {
      stack.add(name);
    }
  }
  return paths;
}

/// The compressed archive size in megabytes, as the dry run reports it.
double parseCompressedMb(String transcript) {
  // pub scales the unit, so a small package reports KB and an MB-only pattern
  // would throw on output that is perfectly valid
  final m = RegExp(r'Total compressed archive size: <?([\d.]+) ?([KMG])B')
      .firstMatch(transcript);
  if (m == null) {
    throw const FormatException(
        'dry-run output has no recognizable compressed archive size line');
  }
  final value = double.parse(m.group(1)!);
  switch (m.group(2)!) {
    case 'K':
      return value / 1024;
    case 'M':
      return value;
    default:
      return value * 1024;
  }
}
