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
            final cellContent = cell.blocks.map((cb) => cb.plainText).join(' ');
            cellTexts.add(cellContent.trim());
          }
          sb.writeln(cellTexts.join(' | '));
        }
      } else if (b.type != DocBlockType.image) {
        sb.writeln(b.plainText);
      }
    }
    return sb.toString().trim();
  }
}

class DocPageProperties {
  final double marginTop;
  final double marginBottom;
  final double marginLeft;
  final double marginRight;
  final bool landscape;
  final double headerOffset;
  final double footerOffset;

  const DocPageProperties({
    this.marginTop = 42.525,
    this.marginBottom = 42.525,
    this.marginLeft = 42.525,
    this.marginRight = 42.525,
    this.landscape = false,
    this.headerOffset = 20.0,
    this.footerOffset = 20.0,
  });
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
  });

  int get endOffset => startOffset + length;
}
