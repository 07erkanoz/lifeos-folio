/// Evrak çevirici ve düzenleyici için evrensel ara doküman modeli.
/// UDF, DOCX, PDF ve RTF formatları bu ortak model üzerinden birbirine dönüştürülür.
library;

class DocModel {
  final DocPageProperties pageProperties;
  final List<DocStyleDef> styles;
  final List<DocBlock> blocks;
  final Map<String, dynamic> metadata;
  final Map<String, List<DocBlock>> pageRegions;

  DocModel({
    this.pageProperties = const DocPageProperties(),
    this.styles = const [],
    required this.blocks,
    this.metadata = const {},
    this.pageRegions = const {},
  });

  /// Modeldeki tüm düz metni satır satır birleştirip döndürür.
  String toPlainText() {
    final sb = StringBuffer();
    for (final b in blocks) {
      if (b.type == DocBlockType.table && b.table != null) {
        for (final row in b.table!.rows) {
          final cellTexts = <String>[];
          for (final cell in row.cells) {
            cellTexts.add(_cellText(cell.blocks).trim());
          }
          sb.writeln(cellTexts.join(' | '));
        }
      } else if (b.type != DocBlockType.image) {
        sb.writeln(b.plainText);
      }
    }
    return sb.toString().trim();
  }

  /// A cell's words, a table within it too: its text was left out of the
  /// search, its plainText being empty.
  static String _cellText(List<DocBlock> blocks) => [
    for (final cb in blocks)
      if (cb.type == DocBlockType.table && cb.table != null)
        for (final row in cb.table!.rows)
          for (final cell in row.cells) _cellText(cell.blocks)
      else
        cb.plainText,
  ].join(' ');
}

class DocPageProperties {
  final double marginTop;
  final double marginBottom;
  final double marginLeft;
  final double marginRight;
  final bool landscape;
  final double headerOffset;
  final double footerOffset;

  /// The sheet standing upright, in points: A4 unless the document says
  /// otherwise (a Word file may be Letter, Legal or any size); [landscape]
  /// turns it. UDF knows A4 only.
  final double paperWidth;
  final double paperHeight;

  /// A4, 210 × 297 mm, in points.
  static const a4Width = 595.2755905511812, a4Height = 841.8897637795277;

  const DocPageProperties({
    this.marginTop = 42.525,
    this.marginBottom = 42.525,
    this.marginLeft = 42.525,
    this.marginRight = 42.525,
    this.landscape = false,
    this.headerOffset = 20.0,
    this.footerOffset = 20.0,
    this.paperWidth = a4Width,
    this.paperHeight = a4Height,
  });

  /// Whether the sheet is A4, to the hundredth of a millimetre.
  bool get isA4 =>
      (paperWidth - a4Width).abs() < .03 &&
      (paperHeight - a4Height).abs() < .03;

  /// The sheet as it lies on the page: turned for [landscape].
  ({double width, double height}) get sheet => landscape
      ? (width: paperHeight, height: paperWidth)
      : (width: paperWidth, height: paperHeight);

  DocPageProperties copyWith({
    double? marginTop,
    double? marginBottom,
    double? marginLeft,
    double? marginRight,
    bool? landscape,
    double? headerOffset,
    double? footerOffset,
    double? paperWidth,
    double? paperHeight,
  }) => DocPageProperties(
    marginTop: marginTop ?? this.marginTop,
    marginBottom: marginBottom ?? this.marginBottom,
    marginLeft: marginLeft ?? this.marginLeft,
    marginRight: marginRight ?? this.marginRight,
    landscape: landscape ?? this.landscape,
    headerOffset: headerOffset ?? this.headerOffset,
    footerOffset: footerOffset ?? this.footerOffset,
    paperWidth: paperWidth ?? this.paperWidth,
    paperHeight: paperHeight ?? this.paperHeight,
  );
}

class DocStyleDef {
  final String name;
  final String family;
  final double size;
  final String? description;
  final bool bold;
  final bool italic;

  const DocStyleDef({
    required this.name,
    required this.family,
    required this.size,
    this.description,
    this.bold = false,
    this.italic = false,
  });
}

enum DocBlockType { paragraph, listItem, blockQuote, table, image }

enum DocAlignment { left, center, right, justify }

enum DocListType { none, ordered, unordered }

class DocBlock {
  final DocBlockType type;
  final DocAlignment alignment;
  final String plainText;
  final List<DocSpan> spans;
  final DocListType listType;
  final int listLevel;
  final int listId;
  final double leftIndent;
  final double rightIndent;
  final double firstLineIndent;

  /// Room added to the left of every row but the first. UYAP's own attribute,
  /// `Hanging`: court decisions set their heading values with it so that a
  /// value that wraps continues under itself rather than under its label.
  final double hanging;
  final double spacingBefore;
  final double spacingAfter;
  final String? styleName;
  final String? tabSet;
  final double? lineSpacing;
  final DocTable? table;
  final String? imageBase64;
  final String? imageMime;
  final double? imageWidth;
  final double? imageHeight;
  final String? bulletType;
  final String? numberType;

  /// The size and font of the paragraph's end, the line break that closes
  /// it. UYAP counts it in the last row, so it sets the height of that row,
  /// and all of an empty paragraph's: a blank line written at 14 points is
  /// 17 high, not the 14 of the body around it.
  final double? endFontSize;
  final String? endFontFamily;

  /// Whether the paragraph starts a new page: Word's page break, its
  /// "page break before" and a section that begins on a new page.
  final bool pageBreakBefore;

  DocBlock({
    this.type = DocBlockType.paragraph,
    this.alignment = DocAlignment.left,
    required this.plainText,
    this.spans = const [],
    this.listType = DocListType.none,
    this.listLevel = 0,
    this.listId = 0,
    this.leftIndent = 0.0,
    this.rightIndent = 0.0,
    this.firstLineIndent = 0.0,
    this.hanging = 0.0,
    this.spacingBefore = 0.0,
    this.spacingAfter = 0.0,
    this.styleName,
    this.tabSet,
    this.lineSpacing,
    this.table,
    this.imageBase64,
    this.imageMime,
    this.imageWidth,
    this.imageHeight,
    this.bulletType,
    this.numberType,
    this.endFontSize,
    this.endFontFamily,
    this.pageBreakBefore = false,
  });
}

class DocTable {
  final List<DocTableRow> rows;
  final List<double>? columnWidths;

  /// Whether the table prints its lines. Most tables in a UYAP document do
  /// not: an invisible grid is how it lays out the block naming the parties to
  /// a case. Drawing those would put a box around half the document.
  final bool bordered;

  DocTable({required this.rows, this.columnWidths, this.bordered = true});
}

class DocTableRow {
  final List<DocTableCell> cells;
  final bool isHeader;
  DocTableRow({required this.cells, this.isHeader = false});
}

class DocTableCell {
  final List<DocBlock> blocks;
  final int colspan;
  final int rowspan;
  final String? backgroundColor;
  final double? width;

  DocTableCell({
    required this.blocks,
    this.colspan = 1,
    this.rowspan = 1,
    this.backgroundColor,
    this.width,
  });
}

class DocSpan {
  final int startOffset;
  final int length;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final String? fontFamily;
  final double? fontSize;
  final String? color;
  final String? background;
  final bool superscript;
  final bool subscript;

  /// Where the text leads when it is a link (a web address, an e-mail).
  final String? link;

  const DocSpan({
    required this.startOffset,
    required this.length,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.fontFamily,
    this.fontSize,
    this.color,
    this.background,
    this.superscript = false,
    this.subscript = false,
    this.link,
  });

  int get endOffset => startOffset + length;
}
