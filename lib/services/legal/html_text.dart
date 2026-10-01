/// Marks where one block of a page ended, before the spaces are flattened.
const _blockEnd = '@@FOLIO-BLOCK@@';

/// The words of an HTML page, with the markup taken out.
///
/// Both official sources — the legislation site and the case bank — serve
/// pages that came out of Word, and Word wraps its source in the middle of
/// sentences, so the line breaks in the file mean nothing. The ends of
/// blocks are marked first and every other run of space is then flattened;
/// otherwise an article or a decision would be cut wherever Word happened
/// to wrap.
String plainTextOf(String html) {
  var s = html.replaceAll(
    RegExp(
      r'<(script|style)[^>]*>.*?</\1>',
      dotAll: true,
      caseSensitive: false,
    ),
    '',
  );
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), _blockEnd);
  s = s.replaceAll(
    RegExp(r'</(p|div|tr|td|h[1-6]|li)>', caseSensitive: false),
    _blockEnd,
  );
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = unescapeEntities(s).replaceAll(' ', ' ');
  final lines = <String>[];
  for (final part in s.split(_blockEnd)) {
    final flat = part.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isNotEmpty) lines.add(flat);
  }
  return lines.join('\n');
}

/// The handful of HTML entities these pages use.
String unescapeEntities(String value) => value
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAllMapped(
      RegExp(r'&#(\d{2,6});'),
      (m) => String.fromCharCode(int.parse(m.group(1)!)),
    )
    // Last, so that an escaped ampersand cannot make a second entity.
    .replaceAll('&amp;', '&');
