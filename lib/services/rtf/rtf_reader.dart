import 'dart:convert';
import 'dart:typed_data';

import '../../models/document_model.dart';
import '../text/windows_codepages.dart';

/// Reads Rich Text Format.
///
/// Nothing on pub.dev reads RTF, and a Turkish law office has drawers full of
/// it: templates and old correspondence that Word still writes. The format is
/// plain bytes with `{\control ...}` groups, so it is read here rather than
/// handed to a converter that would have to be installed on every machine.
///
/// Turkish is the whole point of the care taken over encodings. A file written
/// by Word carries `\ansicpg1254` or a font with `\fcharset162`, and reading
/// its bytes as Latin-1 would turn "İhtarname" into "Ýhtarname". Newer files
/// escape the same letters as `\u351?`, which has to win over the replacement
/// character that follows it.
class RtfReader {
  /// Twips to points: RTF measures in twentieths of a point.
  static const _twip = 1 / 20;

  static DocModel? readBytes(List<int> bytes) {
    try {
      return _Parser(bytes).run();
    } catch (_) {
      return null;
    }
  }

  /// [readBytes] for what a program put on the clipboard, which also says
  /// whether the copy stopped inside its last paragraph: Word leaves the
  /// `\par` off a paragraph whose end was not selected.
  static DocModel? readClipboard(List<int> bytes) {
    try {
      return _Parser(bytes).run(clipboard: true);
    } catch (_) {
      return null;
    }
  }

  /// Whether these bytes look like RTF at all.
  static bool looksLikeRtf(List<int> bytes) {
    if (bytes.length < 5) return false;
    return bytes[0] == 0x7b && // {
        bytes[1] == 0x5c && // \
        bytes[2] == 0x72 && // r
        bytes[3] == 0x74 && // t
        bytes[4] == 0x66; // f
  }
}

/// Character formatting as RTF tracks it: one set per group, restored on `}`.
class _Style {
  bool bold = false;
  bool italic = false;
  bool underline = false;
  bool strike = false;
  bool superscript = false;
  bool subscript = false;
  bool hidden = false;
  double? size;
  String? family;
  String? color;
  String? background;

  /// How many characters follow a `\uN` escape as its fallback, and how many
  /// of them are still to be thrown away.
  int unicodeSkip = 1;
  int unicodeSkipPending = 0;
  int codepage;
  int destination;

  _Style({this.codepage = 1252, this.destination = 0});

  _Style copy() => _Style(codepage: codepage, destination: destination)
    ..bold = bold
    ..italic = italic
    ..underline = underline
    ..strike = strike
    ..superscript = superscript
    ..subscript = subscript
    ..hidden = hidden
    ..size = size
    ..family = family
    ..color = color
    ..background = background
    ..unicodeSkip = unicodeSkip
    ..unicodeSkipPending = unicodeSkipPending;

  bool sameAs(_Style other) =>
      bold == other.bold &&
      italic == other.italic &&
      underline == other.underline &&
      strike == other.strike &&
      superscript == other.superscript &&
      subscript == other.subscript &&
      size == other.size &&
      family == other.family &&
      color == other.color &&
      background == other.background;
}

/// Paragraph formatting, reset by `\pard`.
class _Paragraph {
  DocAlignment alignment = DocAlignment.left;
  double left = 0, right = 0, first = 0, before = 0, after = 0;

  /// `\sl` as written, and whether `\slmult1` makes it a multiple of lines.
  int spacing = 0;
  bool multiple = false;
  DocListType list = DocListType.none;
  int level = 0;

  /// Tab stops, `position:alignment:0` in points from the margin, and the
  /// alignment the next `\tx` takes.
  List<String> tabs = [];
  String tabAlign = '0';

  _Paragraph copy() => _Paragraph()
    ..alignment = alignment
    ..left = left
    ..right = right
    ..first = first
    ..before = before
    ..after = after
    ..spacing = spacing
    ..multiple = multiple
    ..list = list
    ..level = level
    ..tabs = List.of(tabs)
    ..tabAlign = tabAlign;
}

/// Destinations whose contents are not body text. Anything starting with `\*`
/// is skipped too, which is how RTF marks everything a reader may not know.
const _skipped = {
  'fonttbl',
  'colortbl',
  'stylesheet',
  'info',
  'listtable',
  'listoverridetable',
  'rsidtbl',
  'generator',
  'themedata',
  'colorschememapping',
  'latentstyles',
  'datastore',
  'xmlnstbl',
  'filetbl',
  'revtbl',
  'upr',
  'footnote',
  'annotation',
  'atnid',
  'atnauthor',
  'xe',
  'tc',
  'bkmkstart',
  'bkmkend',
  'nonshppict',
  'shppict',
  'object',
  'template',
  'ftnsep',
  'ftnsepc',
  'ftncn',
  'aftnsep',
  'aftnsepc',
  'aftncn',
};

class _Parser {
  final List<int> bytes;
  int at = 0;

  final blocks = <DocBlock>[];
  final buffer = StringBuffer();
  final spans = <DocSpan>[];

  final styles = <_Style>[];
  final paragraphs = <_Paragraph>[];
  final fonts = <int, String>{};
  final alternatives = <int, String>{};
  final fontCodepages = <int, int>{};
  final colors = <int, String?>{};

  _Style style = _Style();
  _Paragraph paragraph = _Paragraph();

  /// Where the run being built started, and how it is formatted.
  int runStart = 0;
  _Style runStyle = _Style();

  /// Depth at which the current skipped destination began; -1 while reading
  /// body text.
  int skipDepth = -1;
  int depth = 0;

  /// Set while reading a `{\fonttbl ...}` or `{\colortbl ...}` so the tables
  /// can be built without treating their contents as text.
  String? table;
  int? tableDepth;
  int tableFont = 0;
  int tableCharset = 0;
  final tableName = StringBuffer();

  /// A font entry's `{\*\falt …}`: the font the document asked for, where
  /// the name before it is the one the writing program put in its place.
  StringBuffer? alternative;
  int? alternativeDepth;
  int red = 0, green = 0, blue = 0;
  bool colorSpecified = false;

  /// Tables, which RTF writes as a run of rows rather than as a structure:
  /// each cell ends with `\cell`, each row with `\row`, and the column edges
  /// arrive beforehand as `\cellx` positions. A table ends when a paragraph
  /// turns up that is not in one.
  final tableRows = <DocTableRow>[];
  final rowCells = <DocTableCell>[];
  final cellBlocks = <DocBlock>[];
  final cellEdges = <double>[];
  List<double>? tableEdges;
  bool inTable = false;
  bool inCell = false;

  /// A picture being collected, and the size the document asks for it.
  StringBuffer? picture;
  int? pictureDepth;
  String? pictureMime;
  double? pictureWidth, pictureHeight;

  int documentCodepage = 1252;
  bool declaredCodepage = false;

  /// Where a tab with no stop of its own goes: every half inch unless the
  /// document says otherwise with `\deftab`.
  double defaultTab = 36;

  /// A list item's marker as the document wrote it out, `{\listtext 1.\tab}`
  /// or `{\pntext \'b7\tab}`: what says whether the list counts.
  StringBuffer? marker;
  int? markerDepth;

  /// Whether the table being read draws its lines, and each cell's shade.
  bool tableBordered = false;
  bool borderSide = false;
  final cellShades = <String?>[];
  String? pendingShade;

  _Parser(this.bytes);

  DocModel run({bool clipboard = false}) {
    if (!RtfReader.looksLikeRtf(bytes)) {
      throw const FormatException('RTF başlığı bulunamadı.');
    }
    while (at < bytes.length) {
      final byte = bytes[at];
      if (byte == 0x7b) {
        at++;
        depth++;
        styles.add(style.copy());
        paragraphs.add(paragraph.copy());
        style = style.copy();
      } else if (byte == 0x7d) {
        at++;
        _closeGroup();
      } else if (byte == 0x5c) {
        at++;
        _control();
      } else if (byte == 0x0d || byte == 0x0a || byte == 0) {
        // Line breaks in the source are not text, nor the NUL a clipboard
        // owner leaves at the end.
        at++;
      } else {
        at++;
        _byte(byte);
      }
    }
    if (inCell) _closeCell();
    if (rowCells.isNotEmpty) _closeRow();
    // The last `\par` already closed the last paragraph; closing again would
    // add an empty one at the end of every document. Text after it is a
    // paragraph whose end was not copied.
    final openEnd = buffer.isNotEmpty || spans.isNotEmpty;
    if (openEnd) _closeParagraph();
    _closeTable();
    if (blocks.isEmpty) blocks.add(DocBlock(plainText: ''));
    return DocModel(
      blocks: blocks,
      metadata: {
        // RTF is Word's: its tabs count from the margin and carry on at the
        // default interval, and a `\line` breaks the line, not the paragraph.
        'tabRules': 'word',
        'defaultTabStop': defaultTab,
        if (clipboard) 'openEnd': openEnd,
      },
    );
  }

  /// One byte of content, which belongs to whatever is being collected.
  void _byte(int byte) {
    if (picture != null) {
      picture!.writeCharCode(byte);
      return;
    }
    if (table == 'font') {
      if (alternative != null) {
        alternative!.writeCharCode(byte);
        return;
      }
      // A font entry carries groups of its own — `{\*\panose ...}` — whose
      // digits are not part of the name.
      if (skipDepth >= 0) return;
      if (byte == 0x3b) {
        _finishFont();
      } else {
        tableName.writeCharCode(byte);
      }
      return;
    }
    if (table == 'color') {
      if (byte == 0x3b) _finishColor();
      return;
    }
    // A `\uN` escape is followed by plain characters standing in for it, for
    // readers that cannot do Unicode. Letting them through turns İ into İ?.
    if (style.unicodeSkipPending > 0) {
      style.unicodeSkipPending--;
      return;
    }
    if (skipDepth >= 0 || style.hidden) return;
    _write(_decode(byte));
  }

  void _closeGroup() {
    if (pictureDepth != null && depth <= pictureDepth!) _finishPicture();
    DocListType? counted;
    if (markerDepth != null && depth <= markerDepth!) {
      final text = marker.toString().trim();
      counted = text.isEmpty
          ? null
          : RegExp(r'^[\(\[]?([0-9]+|[a-zA-Z]|[ivxlcdmIVXLCDM]+)[\.\)\]]')
                .hasMatch(text)
          ? DocListType.ordered
          : DocListType.unordered;
      marker = null;
      markerDepth = null;
    }
    if (alternativeDepth != null && depth <= alternativeDepth!) {
      final name = alternative.toString().replaceAll(';', '').trim();
      if (name.isNotEmpty) alternatives[tableFont] = name;
      alternative = null;
      alternativeDepth = null;
    }
    if (tableDepth != null) {
      if (table == 'font' && depth == tableDepth! + 1) _finishFont();
      if (depth <= tableDepth!) {
        if (table == 'font') _inferCodepage();
        table = null;
        tableDepth = null;
      }
    }
    if (skipDepth >= 0 && depth <= skipDepth) skipDepth = -1;
    depth--;
    if (styles.isNotEmpty) {
      _flushRun();
      style = styles.removeLast();
      runStyle = style.copy();
      paragraph = paragraphs.removeLast();
    }
    if (counted != null) paragraph.list = counted;
  }

  /// Reads one control word or control symbol.
  void _control() {
    if (at >= bytes.length) return;
    final first = bytes[at];
    if (!_isLetter(first)) {
      at++;
      _symbol(first);
      return;
    }
    final start = at;
    while (at < bytes.length && _isLetter(bytes[at])) {
      at++;
    }
    final word = String.fromCharCodes(bytes.sublist(start, at));
    int? value;
    var negative = false;
    if (at < bytes.length && bytes[at] == 0x2d) {
      negative = true;
      at++;
    }
    if (at < bytes.length && _isDigit(bytes[at])) {
      var number = 0;
      while (at < bytes.length && _isDigit(bytes[at])) {
        number = number * 10 + (bytes[at] - 0x30);
        at++;
      }
      value = negative ? -number : number;
    }
    // One space after a control word is the delimiter, not text.
    if (at < bytes.length && bytes[at] == 0x20) at++;
    _word(word, value);
  }

  void _symbol(int code) {
    switch (code) {
      case 0x5c: // \\
      case 0x7b: // \{
      case 0x7d: // \}
        if (skipDepth < 0 && !style.hidden) _write(String.fromCharCode(code));
      case 0x27: // \'hh
        final value = _hexByte();
        if (value == null) return;
        if (style.unicodeSkipPending > 0) {
          style.unicodeSkipPending--;
          return;
        }
        if (table == 'font') {
          tableName.write(_decode(value));
        } else if (picture == null && skipDepth < 0 && !style.hidden) {
          _write(_decode(value));
        }
      case 0x7e: // non-breaking space
        if (skipDepth < 0 && !style.hidden) _write(' ');
      case 0x5f: // non-breaking hyphen
        if (skipDepth < 0 && !style.hidden) _write('‑');
      case 0x2a: // \* — a destination this reader is allowed not to know
        _skip();
      case 0x2d: // optional hyphen: nothing to show
        break;
      case 0x0a:
      case 0x0d:
        _paragraphBreak();
    }
  }

  int? _hexByte() {
    if (at + 1 >= bytes.length) return null;
    final value = int.tryParse(
      String.fromCharCodes(bytes.sublist(at, at + 2)),
      radix: 16,
    );
    at += 2;
    return value;
  }

  void _word(String word, int? value) {
    // A `\uN` escape is followed by replacement characters to discard.
    if (word != 'u' && style.unicodeSkipPending > 0 && _isText(word)) {
      style.unicodeSkipPending--;
      return;
    }
    switch (word) {
      // Destinations.
      case 'fonttbl':
        table = 'font';
        tableDepth = depth;
        tableFont = 0;
        tableCharset = 0;
        tableName.clear();
      case 'colortbl':
        table = 'color';
        tableDepth = depth;
        red = green = blue = 0;
        colorSpecified = false;
        colors.clear();
      case 'pict':
        picture = StringBuffer();
        pictureDepth = depth;
        pictureMime = null;
        pictureWidth = pictureHeight = null;
      case 'pngblip':
        pictureMime = 'image/png';
      case 'jpegblip':
        pictureMime = 'image/jpeg';
      case 'picwgoal':
        if (value != null) pictureWidth = value * RtfReader._twip;
      case 'pichgoal':
        if (value != null) pictureHeight = value * RtfReader._twip;

      // Document.
      case 'ansicpg':
        if (value != null) {
          documentCodepage = value;
          declaredCodepage = true;
          style.codepage = value;
        }
      case 'uc':
        if (value != null) style.unicodeSkip = value;
      case 'u':
        if (value == null) break;
        final code = value < 0 ? value + 65536 : value;
        if (table == 'font') {
          tableName.writeCharCode(code);
        } else if (picture == null && skipDepth < 0 && !style.hidden) {
          _write(String.fromCharCode(code));
        }
        style.unicodeSkipPending = style.unicodeSkip;

      // Paragraphs.
      case 'par':
      case 'sect':
        _paragraphBreak();
      case 'pard':
        paragraph = _Paragraph();
      case 'listtext':
      case 'pntext':
        marker = StringBuffer();
        markerDepth = depth;
      case 'deftab':
        if (value != null && value > 0) defaultTab = value * RtfReader._twip;
      case 'tqr':
        paragraph.tabAlign = '1';
      case 'tqc':
        paragraph.tabAlign = '2';
      case 'tqdec':
        paragraph.tabAlign = '4';
      case 'tx':
      case 'tb':
        if (value != null && value > 0) {
          paragraph.tabs.add(
            '${value * RtfReader._twip}:'
            '${word == 'tb' ? '5' : paragraph.tabAlign}:0',
          );
        }
        paragraph.tabAlign = '0';
      case 'plain':
        _flushRun();
        style
          ..bold = false
          ..italic = false
          ..underline = false
          ..strike = false
          ..superscript = false
          ..subscript = false
          ..size = null
          ..color = null
          ..background = null;
        runStyle = style.copy();
      case 'ql':
        paragraph.alignment = DocAlignment.left;
      case 'qc':
        paragraph.alignment = DocAlignment.center;
      case 'qr':
        paragraph.alignment = DocAlignment.right;
      case 'qj':
        paragraph.alignment = DocAlignment.justify;
      case 'li':
        paragraph.left = (value ?? 0) * RtfReader._twip;
      case 'ri':
        paragraph.right = (value ?? 0) * RtfReader._twip;
      case 'fi':
        paragraph.first = (value ?? 0) * RtfReader._twip;
      case 'sb':
        paragraph.before = (value ?? 0) * RtfReader._twip;
      case 'sa':
        paragraph.after = (value ?? 0) * RtfReader._twip;
      case 'sl':
        // With \slmult1 a multiple of 240 twips is a line; without it, a
        // height, exact when negative.
        paragraph.spacing = value ?? 0;
      case 'slmult':
        paragraph.multiple = value == 1;
      case 'intbl':
        inCell = true;
      case 'trowd':
        // A new row definition; the edges that follow describe its columns.
        cellEdges.clear();
        cellShades.clear();
        pendingShade = null;
      case 'cellx':
        if (value != null) cellEdges.add(value * RtfReader._twip);
        cellShades.add(pendingShade);
        pendingShade = null;
      case 'clcbpat':
        pendingShade = colors[value];
      case 'clbrdrt':
      case 'clbrdrb':
      case 'clbrdrl':
      case 'clbrdrr':
      case 'trbrdrt':
      case 'trbrdrb':
      case 'trbrdrl':
      case 'trbrdrr':
      case 'trbrdrh':
      case 'trbrdrv':
        borderSide = true;
      case 'brdrnone':
      case 'brdrnil':
        borderSide = false;
      case 'cell':
      case 'nestcell':
        _closeCell();
      case 'row':
      case 'nestrow':
        _closeRow();
      case 'ls':
        paragraph.list = DocListType.unordered;
      case 'ilvl':
        paragraph.level = value ?? 0;

      // Characters.
      case 'b':
        _setStyle(() => style.bold = value != 0);
      case 'i':
        _setStyle(() => style.italic = value != 0);
      case 'ul':
        _setStyle(() => style.underline = value != 0);
      case 'ulnone':
        _setStyle(() => style.underline = false);
      case 'uld':
      case 'uldb':
      case 'ulw':
      case 'ulth':
      case 'uldash':
      case 'uldashd':
      case 'uldashdd':
      case 'ulwave':
      case 'ulhwave':
      case 'ulldash':
      case 'ulthd':
      case 'ulthdash':
      case 'ulthdashd':
      case 'ulthdashdd':
      case 'ulthldash':
      case 'ululdbwave':
        _setStyle(() => style.underline = value != 0);
      case 'chcbpat':
        _setStyle(() => style.background = colors[value]);
      case 'strike':
        _setStyle(() => style.strike = value != 0);
      case 'super':
        _setStyle(() => style.superscript = value != 0);
      case 'sub':
        _setStyle(() => style.subscript = value != 0);
      case 'nosupersub':
        _setStyle(() {
          style.superscript = false;
          style.subscript = false;
        });
      case 'v':
        style.hidden = value != 0;
      case 'fs':
        if (value != null) _setStyle(() => style.size = value / 2);
      case 'f':
        if (value == null) break;
        if (table == 'font') {
          tableFont = value;
        } else {
          _setStyle(() {
            style.family = fonts[value];
            style.codepage = fontCodepages[value] ?? documentCodepage;
          });
        }
      case 'fcharset':
        if (table == 'font' && value != null) tableCharset = value;
      case 'falt':
        if (table == 'font') {
          alternative = StringBuffer();
          alternativeDepth = depth;
        }
      case 'cf':
        _setStyle(() => style.color = colors[value]);
      case 'highlight':
      case 'cb':
        _setStyle(() => style.background = colors[value]);
      case 'red':
        colorSpecified = true;
        red = value ?? 0;
      case 'green':
        colorSpecified = true;
        green = value ?? 0;
      case 'blue':
        colorSpecified = true;
        blue = value ?? 0;

      // Characters that arrive as control words.
      case 'tab':
        _write('\t');
      case 'line':
      case 'softline':
        _write('\n');
      case 'emdash':
        _write('—');
      case 'endash':
        _write('–');
      case 'lquote':
        _write('‘');
      case 'rquote':
        _write('’');
      case 'ldblquote':
        _write('“');
      case 'rdblquote':
        _write('”');
      case 'bullet':
        _write('•');
      case 'enspace':
      case 'emspace':
      case 'qmspace':
        _write(' ');

      case 'bin':
        // Binary data, counted in bytes and not text under any circumstance.
        final count = value ?? 0;
        at = (at + count).clamp(0, bytes.length);

      default:
        if (_skipped.contains(word)) {
          _skip();
        } else if (borderSide &&
            word.startsWith('brdr') &&
            !const {'brdrw', 'brdrcf', 'brdrsp'}.contains(word)) {
          // A border style on a cell or a row: the table draws lines.
          tableBordered = true;
          borderSide = false;
        }
    }
  }

  /// Whether a control word stands for a character, and so counts against a
  /// `\uN` escape's replacement allowance.
  static bool _isText(String word) => const {
    'tab',
    'line',
    'emdash',
    'endash',
    'lquote',
    'rquote',
    'ldblquote',
    'rdblquote',
    'bullet',
  }.contains(word);

  /// Begins skipping a destination. The outermost one wins: a stylesheet has
  /// ignorable destinations of its own inside it, and letting one of those end
  /// the skip when it closes would spill the rest of the stylesheet — style
  /// names and all — into the document.
  void _skip() {
    if (skipDepth < 0) skipDepth = depth;
  }

  void _setStyle(void Function() change) {
    _flushRun();
    change();
    runStyle = style.copy();
  }

  void _write(String text) {
    if (marker != null) {
      marker!.write(text);
      return;
    }
    if (skipDepth >= 0 || table != null || picture != null || style.hidden) {
      return;
    }
    if (text.isEmpty) return;
    if (!style.sameAs(runStyle)) _flushRun();
    buffer.write(text);
  }

  /// Records the run that just ended, if it carries any formatting worth
  /// keeping.
  void _flushRun() {
    final end = buffer.length;
    if (end <= runStart) {
      runStart = end;
      runStyle = style.copy();
      return;
    }
    final s = runStyle;
    if (s.bold ||
        s.italic ||
        s.underline ||
        s.strike ||
        s.superscript ||
        s.subscript ||
        s.size != null ||
        s.family != null ||
        s.color != null ||
        s.background != null) {
      spans.add(
        DocSpan(
          startOffset: runStart,
          length: end - runStart,
          bold: s.bold,
          italic: s.italic,
          underline: s.underline,
          strikethrough: s.strike,
          superscript: s.superscript,
          subscript: s.subscript,
          fontFamily: s.family,
          fontSize: s.size,
          color: s.color,
          background: s.background,
        ),
      );
    }
    runStart = end;
    runStyle = style.copy();
  }

  void _paragraphBreak() {
    // A paragraph that is not in a table ends whatever table came before it.
    if (!inCell) _closeTable();
    _closeParagraph();
  }

  void _closeCell() {
    inCell = true;
    _closeParagraph();
    final index = rowCells.length;
    rowCells.add(
      DocTableCell(
        blocks: cellBlocks.isEmpty
            ? [DocBlock(plainText: '')]
            : List.of(cellBlocks),
        backgroundColor: index < cellShades.length ? cellShades[index] : null,
      ),
    );
    cellBlocks.clear();
    inCell = false;
  }

  void _closeRow() {
    if (rowCells.isEmpty) return;
    tableRows.add(DocTableRow(cells: List.of(rowCells)));
    rowCells.clear();
    // The widths of the first row are the widths of the table.
    if (tableEdges == null && cellEdges.isNotEmpty) {
      tableEdges = List.of(cellEdges);
    }
    inTable = true;
  }

  /// Hands over the rows collected so far as one table.
  void _closeTable() {
    if (!inTable || tableRows.isEmpty) {
      tableRows.clear();
      inTable = false;
      return;
    }
    final edges = tableEdges;
    List<double>? widths;
    if (edges != null && edges.length > 1) {
      widths = [
        for (var i = 0; i < edges.length; i++)
          i == 0 ? edges[0] : edges[i] - edges[i - 1],
      ];
    }
    blocks.add(
      DocBlock(
        type: DocBlockType.table,
        plainText: '',
        table: DocTable(
          rows: List.of(tableRows),
          columnWidths: widths,
          // RTF says where the lines are per cell; a table that names none
          // is a layout grid, and a viewer that boxed every one of those
          // would be unreadable.
          bordered: tableBordered,
        ),
      ),
    );
    tableRows.clear();
    tableEdges = null;
    inTable = false;
    tableBordered = false;
  }

  void _closeParagraph() {
    _flushRun();
    final text = buffer.toString();
    if (text.isEmpty && spans.isEmpty && blocks.isEmpty && !inCell) {
      // Leading empty paragraphs before any content are noise.
      buffer.clear();
      spans.clear();
      runStart = 0;
      return;
    }
    // A negative first line indent is a hanging one: the rows after the
    // first start at the left indent, the first further out, which is the
    // model's `hanging` measured from where the first row starts.
    final hanging = paragraph.first < 0
        ? (-paragraph.first).clamp(0.0, paragraph.left)
        : 0.0;
    (inCell ? cellBlocks : blocks).add(
      DocBlock(
        plainText: text,
        spans: List.of(spans),
        alignment: paragraph.alignment,
        listType: paragraph.list,
        listLevel: paragraph.level,
        type: paragraph.list == DocListType.none
            ? DocBlockType.paragraph
            : DocBlockType.listItem,
        leftIndent: paragraph.left - hanging,
        rightIndent: paragraph.right,
        firstLineIndent: paragraph.first < 0 ? 0 : paragraph.first,
        hanging: hanging,
        spacingBefore: paragraph.before,
        spacingAfter: paragraph.after,
        lineSpacing: _lineSpacing(),
        tabSet: paragraph.tabs.isEmpty ? null : paragraph.tabs.join(','),
      ),
    );
    buffer.clear();
    spans.clear();
    runStart = 0;
    runStyle = style.copy();
  }

  /// The paragraph's line spacing as a multiple of a single line, or null
  /// for single spacing.
  double? _lineSpacing() {
    final raw = paragraph.spacing;
    if (raw == 0) return null;
    double multiple;
    if (paragraph.multiple) {
      multiple = raw.abs() / 240;
    } else {
      // A height: against a single line of the paragraph's type, about 1.15
      // of its size.
      final size = spans.isNotEmpty ? spans.first.fontSize ?? 12 : 12;
      multiple = raw.abs() * RtfReader._twip / (size * 1.15);
    }
    if (!multiple.isFinite || multiple < 1.04) return null;
    return (multiple.clamp(1, 4) * 100).round() / 100;
  }

  void _finishFont() {
    var name = tableName.toString().split(';').first.trim();
    // LibreOffice writes the font it drew with, Liberation Serif where the
    // document asked for Times New Roman, and the document's own after it.
    final alternative = alternatives[tableFont];
    if (alternative != null && _stand.hasMatch(name)) name = alternative;
    if (name.isNotEmpty) fonts[tableFont] = name;
    final codepage = _charsetCodepage(tableCharset);
    if (codepage != null) fontCodepages[tableFont] = codepage;
    tableName.clear();
    tableCharset = 0;
  }

  /// Word does not always say which codepage it wrote. When it does not, the
  /// font table still does: a document whose fonts are all Turkish was written
  /// in Turkish, and reading it as Western European turns Ş into Þ.
  void _inferCodepage() {
    if (declaredCodepage || fontCodepages.isEmpty) return;
    final counts = <int, int>{};
    for (final codepage in fontCodepages.values) {
      counts[codepage] = (counts[codepage] ?? 0) + 1;
    }
    var best = documentCodepage, seen = 0;
    counts.forEach((codepage, count) {
      if (count > seen) {
        best = codepage;
        seen = count;
      }
    });
    documentCodepage = best;
    style.codepage = best;
    for (final entry in styles) {
      entry.codepage = best;
    }
  }

  void _finishColor() {
    // The first semicolon is index zero (usually automatic), not index one.
    colors[colors.length] = colorSpecified
        ? '#${red.clamp(0, 255).toRadixString(16).padLeft(2, '0')}'
              '${green.clamp(0, 255).toRadixString(16).padLeft(2, '0')}'
              '${blue.clamp(0, 255).toRadixString(16).padLeft(2, '0')}'
        : null;
    red = green = blue = 0;
    colorSpecified = false;
  }

  void _finishPicture() {
    final hex = picture.toString().replaceAll(RegExp(r'\s'), '');
    picture = null;
    pictureDepth = null;
    if (pictureMime == null || hex.length < 32) return;
    final data = Uint8List(hex.length ~/ 2);
    for (var i = 0; i + 1 < hex.length; i += 2) {
      final value = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (value == null) return;
      data[i ~/ 2] = value;
    }
    _closeParagraph();
    blocks.add(
      DocBlock(
        type: DocBlockType.image,
        plainText: '',
        imageBase64: base64Encode(data),
        imageMime: pictureMime,
        imageWidth: pictureWidth,
        imageHeight: pictureHeight,
      ),
    );
  }

  String _decode(int byte) {
    if (byte < 0x80) return String.fromCharCode(byte);
    final exceptions = switch (style.codepage) {
      1254 => cp1254,
      1250 => cp1250,
      _ => cp1252,
    };
    return String.fromCharCode(exceptions[byte] ?? byte);
  }

  /// Families that stand in for a font a document names but the machine
  /// that wrote it lacks: metric twins of Times New Roman, Arial, Calibri…
  static final _stand = RegExp(
    r'^(Liberation |DejaVu |Carlito|Caladea|Noto (Serif|Sans)$)',
  );

  static bool _isLetter(int byte) =>
      (byte >= 0x61 && byte <= 0x7a) || (byte >= 0x41 && byte <= 0x5a);
  static bool _isDigit(int byte) => byte >= 0x30 && byte <= 0x39;

  /// The Windows codepage a font's charset implies, for files that carry no
  /// `\ansicpg`. 162 is Turkish, which is most of them here.
  static int? _charsetCodepage(int charset) => switch (charset) {
    0 || 1 => null,
    162 => 1254,
    238 => 1250,
    204 => 1251,
    161 => 1253,
    186 => 1257,
    _ => null,
  };
}
