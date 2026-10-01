import '../../models/document_model.dart';

/// A document model as JSON: what Folio puts on the clipboard for itself.
///
/// HTML and RTF are for other programs, and each loses something on the way
/// — tab stops, a hanging indent, the rules a Word document's tabs follow.
/// Between two Folio editors the model itself travels, so a paragraph copied
/// from one petition into another arrives exactly as it was.
///
/// Reading is defensive: the clipboard belongs to every program on the
/// machine, so a value of the wrong type falls back to the model's default
/// instead of reaching the editor.
abstract final class DocModelJson {
  static const version = 1;

  static Map<String, Object?> encode(DocModel model) => {
    'version': version,
    'blocks': [for (final block in model.blocks) _block(block)],
    'metadata': {
      for (final key in _metadataKeys)
        if (model.metadata[key] case final value?
            when value is String || value is num || value is bool)
          key: value,
    },
  };

  /// The document-wide settings a block is read against: whose tab rules
  /// apply, and whether a line break inside a paragraph is UYAP's or Word's.
  static const _metadataKeys = [
    'formatId',
    'tabRules',
    'defaultTabStop',
    'openEnd',
    'resolver',
  ];

  static DocModel? decode(Object? json) {
    if (json is! Map || json['version'] != version) return null;
    final blocks = json['blocks'];
    if (blocks is! List) return null;
    final metadata = json['metadata'];
    return DocModel(
      blocks: [for (final block in blocks) ?_readBlock(block)],
      metadata: {
        if (metadata is Map)
          for (final key in _metadataKeys)
            if (metadata[key] case final value?
                when value is String || value is num || value is bool)
              key: value,
      },
    );
  }

  static Map<String, Object?> _block(DocBlock b) => {
    'type': b.type.name,
    'text': b.plainText,
    if (b.alignment != DocAlignment.left) 'align': b.alignment.name,
    if (b.spans.isNotEmpty) 'spans': [for (final s in b.spans) _span(s)],
    if (b.listType != DocListType.none) 'list': b.listType.name,
    if (b.listLevel != 0) 'level': b.listLevel,
    if (b.listId != 0) 'listId': b.listId,
    if (b.leftIndent != 0) 'left': b.leftIndent,
    if (b.rightIndent != 0) 'right': b.rightIndent,
    if (b.firstLineIndent != 0) 'first': b.firstLineIndent,
    if (b.hanging != 0) 'hanging': b.hanging,
    if (b.spacingBefore != 0) 'before': b.spacingBefore,
    if (b.spacingAfter != 0) 'after': b.spacingAfter,
    'style': ?b.styleName,
    'tabs': ?b.tabSet,
    'line': ?b.lineSpacing,
    'endSize': ?b.endFontSize,
    'endFamily': ?b.endFontFamily,
    if (b.table != null) 'table': _table(b.table!),
    'image': ?b.imageBase64,
    'mime': ?b.imageMime,
    'width': ?b.imageWidth,
    'height': ?b.imageHeight,
    'bullet': ?b.bulletType,
    'number': ?b.numberType,
  };

  static Map<String, Object?> _span(DocSpan s) => {
    'at': s.startOffset,
    'length': s.length,
    if (s.bold) 'bold': true,
    if (s.italic) 'italic': true,
    if (s.underline) 'underline': true,
    if (s.strikethrough) 'strike': true,
    if (s.superscript) 'super': true,
    if (s.subscript) 'sub': true,
    'font': ?s.fontFamily,
    'size': ?s.fontSize,
    'color': ?s.color,
    'background': ?s.background,
  };

  static Map<String, Object?> _table(DocTable t) => {
    if (t.columnWidths != null) 'widths': t.columnWidths,
    if (!t.bordered) 'bordered': false,
    'rows': [
      for (final row in t.rows)
        {
          if (row.isHeader) 'header': true,
          'cells': [
            for (final cell in row.cells)
              {
                'blocks': [for (final b in cell.blocks) _block(b)],
                if (cell.colspan != 1) 'colspan': cell.colspan,
                if (cell.rowspan != 1) 'rowspan': cell.rowspan,
                'background': ?cell.backgroundColor,
                'width': ?cell.width,
              },
          ],
        },
    ],
  };

  static DocBlock? _readBlock(Object? json, [int depth = 0]) {
    // Tables nest; a clipboard that nests them without end is not a table.
    if (json is! Map || depth > 16) return null;
    final text = _string(json['text']) ?? '';
    final type = _enum(
      DocBlockType.values,
      json['type'],
      DocBlockType.paragraph,
    );
    final table = json['table'] is Map
        ? _readTable(json['table'] as Map, depth)
        : null;
    if (type == DocBlockType.table && table == null) return null;
    return DocBlock(
      type: type,
      plainText: text,
      alignment: _enum(DocAlignment.values, json['align'], DocAlignment.left),
      spans: [
        if (json['spans'] case final List spans)
          for (final span in spans) ?_readSpan(span, text.length),
      ],
      listType: _enum(DocListType.values, json['list'], DocListType.none),
      listLevel: _int(json['level']) ?? 0,
      listId: _int(json['listId']) ?? 0,
      leftIndent: _number(json['left']) ?? 0,
      rightIndent: _number(json['right']) ?? 0,
      firstLineIndent: _number(json['first']) ?? 0,
      hanging: _number(json['hanging']) ?? 0,
      spacingBefore: _number(json['before']) ?? 0,
      spacingAfter: _number(json['after']) ?? 0,
      styleName: _string(json['style']),
      tabSet: _string(json['tabs']),
      lineSpacing: _number(json['line']),
      endFontSize: _number(json['endSize']),
      endFontFamily: json['endFamily'] as String?,
      table: table,
      imageBase64: _string(json['image']),
      imageMime: _string(json['mime']),
      imageWidth: _number(json['width']),
      imageHeight: _number(json['height']),
      bulletType: _string(json['bullet']),
      numberType: _string(json['number']),
    );
  }

  static DocSpan? _readSpan(Object? json, int textLength) {
    if (json is! Map) return null;
    final at = _int(json['at']);
    final length = _int(json['length']);
    if (at == null || length == null || at < 0 || length <= 0) return null;
    if (at >= textLength) return null;
    return DocSpan(
      startOffset: at,
      length: length.clamp(1, textLength - at),
      bold: json['bold'] == true,
      italic: json['italic'] == true,
      underline: json['underline'] == true,
      strikethrough: json['strike'] == true,
      superscript: json['super'] == true,
      subscript: json['sub'] == true,
      fontFamily: _string(json['font']),
      fontSize: _number(json['size']),
      color: _color(json['color']),
      background: _color(json['background']),
    );
  }

  static DocTable? _readTable(Map json, int depth) {
    final rows = json['rows'];
    if (rows is! List) return null;
    final widths = json['widths'];
    final table = DocTable(
      columnWidths: widths is List
          ? [for (final w in widths) _number(w) ?? 0]
          : null,
      bordered: json['bordered'] != false,
      rows: [
        for (final row in rows)
          if (row is Map && row['cells'] is List)
            DocTableRow(
              isHeader: row['header'] == true,
              cells: [
                for (final cell in row['cells'] as List)
                  if (cell is Map)
                    DocTableCell(
                      blocks: [
                        if (cell['blocks'] case final List blocks)
                          for (final block in blocks)
                            ?_readBlock(block, depth + 1),
                      ],
                      colspan: (_int(cell['colspan']) ?? 1).clamp(1, 1000),
                      rowspan: (_int(cell['rowspan']) ?? 1).clamp(1, 1000),
                      backgroundColor: _color(cell['background']),
                      width: _number(cell['width']),
                    ),
              ],
            ),
      ],
    );
    return table.rows.isEmpty ? null : table;
  }

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  static String? _string(Object? value) => value is String ? value : null;

  static int? _int(Object? value) => value is int ? value : null;

  static double? _number(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;

  /// Only the one form the editor draws; anything else is left unset.
  static String? _color(Object? value) =>
      value is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)
      ? value.toLowerCase()
      : null;
}
