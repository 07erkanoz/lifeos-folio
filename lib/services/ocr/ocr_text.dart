import '../../models/document_model.dart';

/// Text read by OCR, as a document to edit.
///
/// Tesseract ends a line where the page did, and leaves a blank line between
/// the blocks it finds. A paragraph set justified comes out as lines of
/// nearly one length, each cut wherever the margin fell; the parties of a
/// filing, a list or an address come out as short lines that each stand
/// alone. So a line runs on into the next when that one opens in lower case,
/// or when it is about as long as the longest in its block and ends neither
/// a sentence nor a label — unless the next opens an item of its own, "2- …"
/// or "TEMSİLCİ : …". Any other line ends its paragraph, and a block is set
/// apart by an empty paragraph, as the page set it apart, unless it opens in
/// lower case: then Tesseract broke a paragraph at a gap in the page.
///
/// What printing put on every page and the writer never wrote is left out:
/// UYAP's editor heads each printed page with the file's name and foots it
/// with "Sayfa 1/2". So is one misreading of a bold colon, ":!".
DocModel ocrDocModel(String text) {
  final paragraphs = <String>[];
  final parts = _clean(text).split(RegExp(r'\n[ \t]*\n'));
  for (final part in parts) {
    final lines = [
      for (final line in part.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (lines.isEmpty) continue;
    var paragraph = '';
    if (paragraphs.isNotEmpty) {
      if (_opensLower(lines.first) && !_ends(paragraphs.last)) {
        paragraph = paragraphs.removeLast();
      } else {
        paragraphs.add('');
      }
    }
    final longest = lines.fold(0, (a, b) => a > b.length ? a : b.length);
    for (var i = 0; i < lines.length; i++) {
      paragraph = paragraph.isEmpty ? lines[i] : _join(paragraph, lines[i]);
      if (i == lines.length - 1 || !_runsOn(lines[i], lines[i + 1], longest)) {
        paragraphs.add(paragraph);
        paragraph = '';
      }
    }
  }
  return DocModel(
    blocks: [
      for (final paragraph in paragraphs.isEmpty ? [''] : paragraphs)
        DocBlock(plainText: paragraph),
    ],
  );
}

/// A line that is the name of a file, or a page's number.
final _furniture = RegExp(
  r'^(?:[^\n]{1,120}\.(?:udf|docx?|rtf|odt|pdf)|Sayfa\s*\d+\s*/\s*\d+)$',
  caseSensitive: false,
);

/// A label in capitals, where the colon after it was read as "!".
final _bangLabel = RegExp(r'^([A-ZÇĞİÖŞÜ][A-ZÇĞİÖŞÜ .]{2,}?)\s+!\s+');

String _clean(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('\f', '\n\n')
    .split('\n')
    .map(
      (line) => _furniture.hasMatch(line.trim())
          ? ''
          : line
                .replaceAll(':!', ':')
                .replaceFirstMapped(_bangLabel, (m) => '${m[1]} : '),
    )
    .join('\n');

/// Whether [line] was cut by the margin rather than ended by its writer.
bool _runsOn(String line, String next, int longest) {
  if (_opensItem(next)) return false;
  if (_opensLower(next)) return true;
  return line.length >= 40 && line.length >= longest * .8 && !_ends(line);
}

bool _opensLower(String line) => RegExp(r'^[a-zçğıöşü]').hasMatch(line);

/// "2- TURHAN …", "3) …", "TEMSİLCİ : …": a line of its own.
bool _opensItem(String line) =>
    RegExp(r'^\d{1,2}\s*[-.)]\s').hasMatch(line) ||
    RegExp(r'^\d{1,2}\s*-').hasMatch(line) ||
    RegExp(r'^[A-ZÇĞİÖŞÜ][A-ZÇĞİÖŞÜ .]{2,}\s*:').hasMatch(line);

/// A line that ends a sentence or a label. "2021/309 K." and "T.C." end in
/// a dot and do not: one capital letter before it is an abbreviation.
bool _ends(String line) =>
    RegExp(r'[.:;!?]$').hasMatch(line) &&
    !RegExp(r'(?:^|[\s.])[A-ZÇĞİÖŞÜ]\.$').hasMatch(line);

/// Two lines of one paragraph. A word the margin hyphenated is put back
/// together: "tespi-" and "tini" are "tespitini".
String _join(String before, String after) {
  final hyphenated =
      RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]-$').hasMatch(before) &&
      RegExp(r'^[a-zçğıöşü]').hasMatch(after);
  return hyphenated
      ? '${before.substring(0, before.length - 1)}$after'
      : '$before $after';
}
