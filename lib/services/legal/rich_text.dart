import 'package:flutter/foundation.dart';

import '../../models/document_model.dart';
import 'citation.dart' show upperTr;

/// A stretch of a paragraph and the emphasis it was written with.
@immutable
class RichRun {
  const RichRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });

  final String text;
  final bool bold, italic, underline;

  bool looksLike(RichRun other) =>
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline;

  RichRun withText(String value) =>
      RichRun(value, bold: bold, italic: italic, underline: underline);

  RichRun get emboldened =>
      RichRun(text, bold: true, italic: italic, underline: underline);

  @override
  bool operator ==(Object other) =>
      other is RichRun && other.text == text && looksLike(other);

  @override
  int get hashCode => Object.hash(text, bold, italic, underline);

  @override
  String toString() =>
      '${bold ? '**' : ''}${italic ? '_' : ''}$text${italic ? '_' : ''}${bold ? '**' : ''}';
}

/// A paragraph of an official text, reduced to what a lawyer reads it by.
///
/// The case bank, the Constitutional Court and the legislation site all
/// serve pages that came out of Word, with its fonts, colours and sizes.
/// Those belong to somebody else's page and would fight the app's own theme,
/// and the PDF and UDF written from a preview, so they are let go. What is
/// kept is what carries meaning: the paragraph breaks, the bold that marks a
/// heading and a holding, italics, underlining and where a line is set.
@immutable
class RichParagraph {
  const RichParagraph(this.runs, {this.alignment = DocAlignment.left});

  final List<RichRun> runs;
  final DocAlignment alignment;

  String get text => runs.map((run) => run.text).join();

  /// A paragraph set entirely in bold: a heading, a label, a holding.
  bool get isBold => runs.isNotEmpty && runs.every((run) => run.bold);

  @override
  bool operator ==(Object other) =>
      other is RichParagraph &&
      other.alignment == alignment &&
      listEquals(other.runs, runs);

  @override
  int get hashCode => Object.hash(alignment, Object.hashAll(runs));

  @override
  String toString() => 'RichParagraph(${alignment.name}: ${runs.join()})';
}

// -- reading a page ---------------------------------------------------------

const _blocks = {
  'p',
  'div',
  'li',
  'tr',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'blockquote',
  'center',
  'table',
  'ul',
  'ol',
  'dd',
  'dt',
  'section',
  'article',
  'header',
  'footer',
  'pre',
  'body',
};
const _skipped = {
  'script',
  'style',
  'head',
  'title',
  'xml',
  'noscript',
  'template',
};
const _boldTags = {'b', 'strong', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'th'};
const _italicTags = {'i', 'em', 'cite'};
const _underlineTags = {'u', 'ins'};

/// Tags that never close: emphasis given to them by a style would never end.
const _void = {
  'img',
  'meta',
  'hr',
  'input',
  'link',
  'col',
  'area',
  'base',
  'wbr',
  'source',
  'br',
};

final _token = RegExp(
  r'''<!--[\s\S]*?-->|<[!?][^>]*>|<(/?)([a-zA-Z][a-zA-Z0-9:-]*)((?:[^>"']|"[^"]*"|'[^']*')*)>|([^<]+)|<''',
);

const _entities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'shy': '',
  'ccedil': 'ç',
  'Ccedil': 'Ç',
  'ouml': 'ö',
  'Ouml': 'Ö',
  'uuml': 'ü',
  'Uuml': 'Ü',
  'acirc': 'â',
  'Acirc': 'Â',
  'icirc': 'î',
  'Icirc': 'Î',
  'ucirc': 'û',
  'Ucirc': 'Û',
  'laquo': '«',
  'raquo': '»',
  'ldquo': '“',
  'rdquo': '”',
  'lsquo': '‘',
  'rsquo': '’',
  'ndash': '–',
  'mdash': '—',
  'hellip': '…',
  'sect': '§',
  'middot': '·',
  'bull': '•',
  'deg': '°',
};

/// Every HTML entity a page may use, named or numbered.
String decodeEntities(String value) => value.replaceAllMapped(
  RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'),
  (m) {
    final name = m.group(1)!;
    if (name.startsWith('#')) {
      final hex = name.length > 1 && (name[1] == 'x' || name[1] == 'X');
      final code = int.tryParse(
        hex ? name.substring(2) : name.substring(1),
        radix: hex ? 16 : 10,
      );
      return code != null && code > 0 && code <= 0x10FFFF
          ? String.fromCharCode(code)
          : m.group(0)!;
    }
    return _entities[name] ?? _entities[name.toLowerCase()] ?? m.group(0)!;
  },
);

String _attribute(String raw, String name) {
  final m = RegExp(
    '(?:^|\\s)$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  ).firstMatch(raw);
  return m == null ? '' : (m.group(1) ?? m.group(2) ?? m.group(3) ?? '');
}

DocAlignment? _alignmentOf(String raw) {
  final style = _attribute(raw, 'style').toLowerCase();
  final set =
      RegExp(r'text-align\s*:\s*(\w+)').firstMatch(style)?.group(1) ??
      _attribute(raw, 'align').toLowerCase();
  return switch (set) {
    'center' => DocAlignment.center,
    'right' => DocAlignment.right,
    'justify' => DocAlignment.justify,
    _ => null,
  };
}

({bool bold, bool italic, bool underline}) _emphasisOf(String raw) {
  final style = _attribute(raw, 'style').toLowerCase();
  return (
    bold: RegExp(r'font-weight\s*:\s*(?:bold|bolder|[6-9]00)').hasMatch(style),
    italic: RegExp(r'font-style\s*:\s*italic').hasMatch(style),
    underline: RegExp(r'text-decoration[^;]*underline').hasMatch(style),
  );
}

/// A short line in capitals — "I. YARGILAMA SÜRECİ", "K A R A R" — or a
/// short line ending in its only colon — "Davacı İstemi:" — is a heading.
///
/// Measured on a decision of the Court of Cassation's General Assembly: the
/// bank sends it as one paragraph broken by eighty-eight line breaks, bold
/// only in the title, its section headings in plain type. Making those
/// headings bold again is what makes the decision readable.
bool _looksLikeHeading(String value) {
  final text = value.trim();
  if (text.isEmpty || text.length > 90) return false;
  if (!RegExp('[A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(text)) return false;
  if (text == upperTr(text) &&
      RegExp('[A-ZÇĞİÖŞÜ]{2}').hasMatch(text.replaceAll(RegExp(r'\s+'), ''))) {
    return true;
  }
  return text.length <= 60 &&
      text.endsWith(':') &&
      text.indexOf(':') == text.length - 1;
}

/// "MAHKEMESİ : Asliye Hukuk" — the label in capitals is set bold, the
/// value plain.
final _label = RegExp(r'^([A-ZÇĞİÖŞÜ][A-ZÇĞİÖŞÜ .()/-]{1,40}?\s*:)');

RichParagraph? _finish(
  List<RichRun> runs,
  DocAlignment alignment, {
  required bool headings,
}) {
  // Runs set alike are joined; the space the paragraph began and ended
  // with is let go.
  final joined = <RichRun>[];
  for (final run in runs) {
    if (joined.isNotEmpty && joined.last.looksLike(run)) {
      joined.last = joined.last.withText(joined.last.text + run.text);
    } else {
      joined.add(run);
    }
  }
  if (joined.isEmpty) return null;
  joined.first = joined.first.withText(joined.first.text.trimLeft());
  joined.last = joined.last.withText(joined.last.text.trimRight());
  joined.removeWhere((run) => run.text.isEmpty);
  final text = joined.map((run) => run.text).join();
  if (text.trim().isEmpty) return null;

  if (headings && joined.every((run) => !run.bold)) {
    // "TARİHİ : 23/06/2011" is a label and its value, not a heading in
    // capitals: only the label is set bold.
    final label = _label.firstMatch(text);
    final head = label?.group(1);
    if (head != null &&
        head.length < text.trimRight().length &&
        joined.first.text.length >= head.length) {
      final first = joined.first;
      return RichParagraph([
        first.withText(head).emboldened,
        if (first.text.length > head.length)
          first.withText(first.text.substring(head.length)),
        ...joined.skip(1),
      ], alignment: alignment);
    }
    if (_looksLikeHeading(text)) {
      return RichParagraph([
        for (final run in joined) run.emboldened,
      ], alignment: alignment);
    }
  }
  return RichParagraph(joined, alignment: alignment);
}

/// Any page of HTML as paragraphs.
///
/// With [headings] a short line in capitals is taken for a heading and set
/// bold; off, the page's own bold is all there is.
List<RichParagraph> richParagraphsOf(String html, {bool headings = true}) {
  final out = <RichParagraph>[];
  var runs = <RichRun>[];
  DocAlignment? paragraphAlignment;
  var started = false;
  final blocks = <(String, DocAlignment?)>[];
  final styled = <(String, ({bool bold, bool italic, bool underline}))>[];
  var bold = 0, italic = 0, underline = 0;
  var skipping = 0;

  DocAlignment? currentAlignment() {
    for (final block in blocks.reversed) {
      if (block.$2 != null) return block.$2;
    }
    return null;
  }

  void close() {
    if (started) {
      final done = _finish(
        runs,
        paragraphAlignment ?? DocAlignment.left,
        headings: headings,
      );
      if (done != null) out.add(done);
    }
    runs = <RichRun>[];
    started = false;
  }

  void write(String text) {
    if (text.isEmpty) return;
    if (!started) {
      started = true;
      paragraphAlignment = currentAlignment();
    }
    runs.add(
      RichRun(
        text,
        bold: bold > 0 || styled.any((s) => s.$2.bold),
        italic: italic > 0 || styled.any((s) => s.$2.italic),
        underline: underline > 0 || styled.any((s) => s.$2.underline),
      ),
    );
  }

  for (final m in _token.allMatches(html)) {
    final text = m.group(4);
    final name = m.group(2);
    if (text != null || (name == null && m.group(0) == '<')) {
      if (skipping > 0) continue;
      write(
        decodeEntities(text ?? '<')
            .replaceAll('\u{00A0}', ' ')
            .replaceAll(RegExp(r'\s+'), ' '),
      );
      continue;
    }
    // A comment, a doctype, a processing instruction.
    if (name == null) continue;
    final tag = name.toLowerCase();
    final closing = m.group(1) == '/';
    final attributes = m.group(3) ?? '';
    if (_skipped.contains(tag)) {
      skipping += closing ? -1 : 1;
      if (skipping < 0) skipping = 0;
      continue;
    }
    if (skipping > 0) continue;
    if (tag == 'br') {
      close();
      continue;
    }
    if ((tag == 'td' || tag == 'th') && closing) write(' ');
    if (_blocks.contains(tag)) {
      close();
      if (closing) {
        final at = blocks.lastIndexWhere((block) => block.$1 == tag);
        if (at >= 0) blocks.removeRange(at, blocks.length);
      } else {
        blocks.add((
          tag,
          tag == 'center' ? DocAlignment.center : _alignmentOf(attributes),
        ));
      }
    }
    if (_boldTags.contains(tag)) {
      bold = closing ? (bold > 0 ? bold - 1 : 0) : bold + 1;
    }
    if (_italicTags.contains(tag)) {
      italic = closing ? (italic > 0 ? italic - 1 : 0) : italic + 1;
    }
    if (_underlineTags.contains(tag)) {
      underline = closing ? (underline > 0 ? underline - 1 : 0) : underline + 1;
    }
    // Emphasis given by a style: the bank bolds a list item that way.
    if (closing) {
      final at = styled.lastIndexWhere((s) => s.$1 == tag);
      if (at >= 0) styled.removeAt(at);
    } else if (!m.group(0)!.endsWith('/>') && !_void.contains(tag)) {
      final emphasis = _emphasisOf(attributes);
      if (emphasis.bold || emphasis.italic || emphasis.underline) {
        styled.add((tag, emphasis));
      }
    }
  }
  close();
  return out;
}

/// Plain text as paragraphs, one a line, headings bold as in a page.
List<RichParagraph> plainParagraphsOf(String text) {
  final out = <RichParagraph>[];
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final done = _finish(
      [RichRun(line.replaceAll(RegExp(r'\s+'), ' '))],
      DocAlignment.left,
      headings: true,
    );
    if (done != null) out.add(done);
  }
  return out;
}

// -- an article ---------------------------------------------------------------

/// "MADDE 166 –", "GEÇİCİ MADDE 3-", "Madde 68/a -": where an article opens.
final _opening = RegExp(
  r'^((?:(?:GEÇİCİ|Geçici|EK|Ek|MÜKERRER|Mükerrer)\s+)?(?:MADDE|Madde)\s*\d{1,4}'
  r'(?:\s*/\s*[A-Za-zÇĞİÖŞÜçğıöşü])?\s*[-‐‑‒–—−])\s*',
);

/// A line that does not end a sentence.
final _openEnded = RegExp(r'[.;:!?…)\]"”’]$');

/// A line that goes on with a sentence: a small letter, and not a bent's own
/// mark, "a)" or "b.".
final _goesOn = RegExp(r'^[a-zçğıöşüâîû][^).\s]');

/// An article's text as paragraphs, from its own shape.
///
/// For the older copy that arrives as plain text. Nothing is invented: a
/// side heading on the first line, the "MADDE 166-" that opens the article
/// and its paragraphs are marked because the text already has them. With
/// [firstLineHeading] off the first line is not guessed at, because the
/// headings were given separately.
List<RichParagraph> articleParagraphsOf(
  String text, {
  bool firstLineHeading = true,
}) {
  final lines = [
    for (final line in text.split(RegExp(r'\r?\n')))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  // "MADDE 97-" alone on its line has its text on the next.
  for (var i = 0; i < lines.length - 1; i++) {
    final open = _opening.firstMatch(lines[i]);
    if (open != null && open.group(0)!.trim() == lines[i]) {
      lines.replaceRange(i, i + 2, ['${open.group(1)} ${lines[i + 1]}']);
    }
  }
  // Older laws break their lines in the middle of a sentence; a paragraph a
  // line made the article look cut short.
  for (var i = 0; i < lines.length - 1; i++) {
    if (!_openEnded.hasMatch(lines[i]) && _goesOn.hasMatch(lines[i + 1])) {
      lines.replaceRange(i, i + 2, ['${lines[i]} ${lines[i + 1]}']);
      i--;
    }
  }
  return [
    for (var i = 0; i < lines.length; i++)
      _articleLine(lines[i], i, firstLineHeading),
  ];
}

RichParagraph _articleLine(String line, int index, bool firstLineHeading) {
  final open = _opening.firstMatch(line);
  if (open != null) {
    final rest = line.substring(open.end);
    return RichParagraph([
      RichRun(open.group(1)!, bold: true),
      if (rest.isNotEmpty) RichRun(' $rest'),
    ], alignment: DocAlignment.justify);
  }
  if (firstLineHeading &&
      index == 0 &&
      line.length <= 90 &&
      !RegExp(r'[.;,]$').hasMatch(line)) {
    return RichParagraph([RichRun(line, bold: true)]);
  }
  return RichParagraph([RichRun(line)], alignment: DocAlignment.justify);
}

/// Whether a paragraph opens an article: "MADDE 97-".
bool opensArticle(RichParagraph paragraph) =>
    _opening.hasMatch(paragraph.text.trim());

// -- leaving the app ----------------------------------------------------------

/// The paragraphs as plain text, a line each.
String plainTextOfParagraphs(Iterable<RichParagraph> paragraphs) =>
    paragraphs.map((p) => p.text).join('\n');

/// A document with [reference] at its head, centred and bold, and the
/// paragraphs under it: what is copied, and what a PDF or a UDF is written
/// from. A decision or an article without its reference cannot be cited.
DocModel documentOfParagraphs(
  String reference,
  List<RichParagraph> paragraphs,
) => DocModel(
  blocks: [
    DocBlock(
      plainText: reference,
      alignment: DocAlignment.center,
      spans: [DocSpan(startOffset: 0, length: reference.length, bold: true)],
      spacingAfter: 12,
    ),
    for (final paragraph in paragraphs) _blockOf(paragraph),
  ],
);

DocBlock _blockOf(RichParagraph paragraph) {
  final spans = <DocSpan>[];
  var at = 0;
  for (final run in paragraph.runs) {
    if (run.bold || run.italic || run.underline) {
      spans.add(
        DocSpan(
          startOffset: at,
          length: run.text.length,
          bold: run.bold,
          italic: run.italic,
          underline: run.underline,
        ),
      );
    }
    at += run.text.length;
  }
  return DocBlock(
    plainText: paragraph.text,
    alignment: paragraph.alignment,
    spans: spans,
    spacingAfter: 6,
  );
}

// -- how a decision is referred to -------------------------------------------

/// The bank names a chamber on its own — "15. Hukuk Dairesi", "4. Daire" —
/// and a reference names the court it belongs to.
String fullCourtName(String court) {
  final name = court.replaceAll(RegExp(r'\s+'), ' ').trim();
  final key = upperTr(name);
  if (name.isEmpty ||
      RegExp('YARGITAY|DANIŞTAY|MAHKEME|BÖLGE|ANAYASA').hasMatch(key)) {
    return name;
  }
  if (RegExp(r'^\d{1,2}\. ?(HUKUK|CEZA) DAİRESİ$').hasMatch(key) ||
      RegExp(r'^(HUKUK|CEZA|BÜYÜK) GENEL KURULU$').hasMatch(key) ||
      key.contains('İÇTİHAD')) {
    return 'Yargıtay $name';
  }
  if (RegExp(r'^\d{1,2}\. ?DAİRE$').hasMatch(key) ||
      key.contains('DAVA DAİRELERİ KURULU')) {
    return 'Danıştay $name';
  }
  return name;
}

/// "Yargıtay 15. Hukuk Dairesi, 2016/1531 E., 2017/3344 K., 21.09.2017 T."
///
/// The very form the citation scanner reads, so a reference pasted back
/// into a document is marked again.
String decisionReference({
  required String court,
  required String esas,
  required String karar,
  String date = '',
}) {
  final named = fullCourtName(court);
  final body = '$esas E., $karar K.${date.isEmpty ? '' : ', $date T.'}';
  return named.isEmpty ? body : '$named, $body';
}

/// A name a file can be saved under: the characters systems refuse turn
/// into dashes, and a trailing full stop goes, so "…2017 T." + ".pdf" does
/// not become "T..pdf".
String fileNameOf(String value) {
  final name = value
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final cut = name.length > 120 ? name.substring(0, 120) : name;
  final done = cut.replaceFirst(RegExp(r'[.\s]+$'), '');
  return done.isEmpty ? 'kaynak' : done;
}
