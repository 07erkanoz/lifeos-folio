import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../models/document_model.dart';
import '../../services/editor/doc_delta_map.dart';
import '../../services/fonts/document_fonts.dart';
import '../../services/layout/table_columns.dart';
import 'editor_line_layout.dart';
import 'editor_paged_table.dart';
import 'editor_tab_spans.dart';
import 'editor_clipboard.dart';

/// Draws tables inside the editor, and lets their cells be typed in.
///
/// A third of the UDF files here have a table, and UYAP uses them for more
/// than data: a one-row, four-column table is how it draws a bordered box
/// around a heading. Standing them in as 〔Tablo 1 — kaydetmede korunur〕 meant
/// a document could be opened, edited and saved without ever showing a third
/// of what was on the page.
///
/// Cells that hold plain paragraphs get their own little editor. A cell that
/// holds something else — a nested table, a picture — is drawn but not typed
/// in, and is handed back to the writer exactly as it was read.
class EditorTableEmbed extends EmbedBuilder {
  /// The blocks the mapper keeps aside; the embed carries only the index, the
  /// way the placeholder did.
  final List<DocBlock> Function() blocks;
  final void Function(int index, DocBlock updated) onChanged;

  /// Announces which cell holds the cursor, so the toolbar can act on it.
  final void Function(QuillController?) onFocus;

  /// Takes the table out of the document, given where it sits in it.
  final void Function(int documentOffset) onDelete;

  /// Says that a table's cells are being thrown away.
  final VoidCallback onCellsGone;

  /// Says that a click landed in a table rather than in the body.
  final VoidCallback onPointerInside;

  /// Whether the document is a Word one, whose tables keep their shares
  /// exactly and pad their cells; a UYAP one's do neither.
  final bool Function() word;

  /// Whether its cells are only shown, not typed in.
  final bool Function() readOnly;

  EditorTableEmbed({
    this.word = _never,
    this.readOnly = _never,
    required this.blocks,
    required this.onChanged,
    required this.onFocus,
    required this.onDelete,
    required this.onCellsGone,
    required this.onPointerInside,
  });

  static bool _never() => false;

  @override
  String get key => DocDeltaMap.kTableEmbed;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final index = embedContext.node.value.data;
    final all = blocks();
    final table = index is int && index >= 0 && index < all.length
        ? all[index].table
        : null;
    if (table == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '〔Korunan içerik — kaydetmede korunur〕',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }
    return EditorTableView(
      table: table,
      onChanged: (updated) => onChanged(
        index as int,
        DocBlock(
          type: DocBlockType.table,
          plainText: '',
          alignment: all[index].alignment,
          table: updated,
        ),
      ),
      onFocus: onFocus,
      onDelete: () => onDelete(embedContext.node.documentOffset),
      onCellsGone: onCellsGone,
      onPointerInside: onPointerInside,
      readOnly: readOnly(),
      word: word(),
    );
  }
}

/// A table drawn the way it prints, with each cell editable in place.
class EditorTableView extends StatefulWidget {
  final DocTable table;
  final ValueChanged<DocTable> onChanged;
  final void Function(QuillController?) onFocus;

  /// Says that the cells built so far are being thrown away, so nothing
  /// keeps pointing at one of them.
  final VoidCallback? onCellsGone;

  /// Says that a click landed in the table rather than in the body around it.
  final VoidCallback? onPointerInside;

  /// Takes the whole table out of the document. A table is the one thing on
  /// the page you cannot select by dragging across it, so without this there
  /// is no way to be rid of one.
  final VoidCallback? onDelete;

  /// A table inside another table is shown, not typed in: nothing is lost,
  /// since the outer cell hands its content back untouched.
  final bool readOnly;

  /// See [EditorTableEmbed.word].
  final bool word;

  const EditorTableView({
    super.key,
    required this.table,
    required this.onChanged,
    required this.onFocus,
    this.onDelete,
    this.onCellsGone,
    this.onPointerInside,
    this.readOnly = false,
    this.word = false,
  });

  @override
  State<EditorTableView> createState() => _EditorTableViewState();
}

/// One cell's editing state: either an editor, or content kept as it was.
class _Cell {
  final QuillController? controller;
  final FocusNode? focus;

  /// What the cell was read as, and what it is handed back as. Everything
  /// but the text lives here, including the colour it is filled with.
  DocTableCell original;
  _Cell(this.original, {this.controller, this.focus});

  bool get editable => controller != null;

  void dispose() {
    controller?.dispose();
    focus?.dispose();
  }
}

class _EditorTableViewState extends State<EditorTableView> {
  late DocTable _table;
  late List<List<_Cell>> _cells;

  /// The table this view itself last handed up. An update carrying it back is
  /// our own keystroke coming round again, and rebuilding the cells for it
  /// would take the cursor out of the one being typed in.
  DocTable? _reported;
  int? _focusedRow, _focusedColumn;

  /// The cell last typed in, kept after the cursor has left it.
  ///
  /// Opening the fill menu takes the focus, so by the time a colour is picked
  /// no cell is focused any more; without this the pick would land nowhere.
  _Cell? _lastCell;

  /// Whether the fill menu is open, so the controls under it stay put.
  bool _menuOpen = false;

  /// Whether the table is picked as a whole, so a format goes to every cell.
  bool _wholeTable = false;

  /// What a printed table line looks like.
  static const _border = Color(0xFF9AA2B1);

  /// What a table that prints no lines looks like while it is being edited:
  /// Word shows the same guides, and they are the only way to tell where one
  /// cell ends and the next begins.
  static const _guide = Color(0xFFDDE1E8);

  /// What a table picked as a whole looks like: the same wash the editor
  /// puts over selected text.
  static const _picked = Color(0x332F6FEB);

  @override
  void initState() {
    super.initState();
    _table = widget.table;
    _build();
    // Shown once and left so: what it draws is nothing unless a cell has
    // the cursor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _portal.show();
    });
  }

  @override
  void didUpdateWidget(covariant EditorTableView old) {
    super.didUpdateWidget(old);
    if (identical(widget.table, _reported) || identical(widget.table, _table)) {
      return;
    }
    _disposeCells();
    _table = widget.table;
    _build();
  }

  /// Whether a cell is plain enough to be typed in.
  static bool _plain(DocTableCell cell) => cell.blocks.every(
    (b) => b.type == DocBlockType.paragraph || b.type == DocBlockType.listItem,
  );

  void _build() {
    _wholeTable = false;
    _lastCell = null;
    _cells = [
      for (final row in _table.rows)
        [
          for (final cell in row.cells)
            if (widget.readOnly || !_plain(cell))
              _Cell(cell)
            else
              _Cell(
                cell,
                controller: _CellController(
                  document: Document.fromDelta(
                    DocDeltaMap.modeldenDelta(
                      DocModel(
                        blocks: cell.blocks.isEmpty
                            ? [DocBlock(plainText: '')]
                            : cell.blocks,
                        metadata: widget.word
                            ? const {'tabRules': 'word'}
                            : const {},
                      ),
                    ).delta,
                  ),
                  selection: const TextSelection.collapsed(offset: 0),
                ),
                focus: FocusNode(debugLabel: 'table-cell'),
              ),
        ],
    ];
    for (var r = 0; r < _cells.length; r++) {
      for (var c = 0; c < _cells[r].length; c++) {
        final cell = _cells[r][c];
        cell.controller?.document.changes.listen((_) => _report());
        final row = r, column = c;
        cell.focus?.addListener(() {
          if (!mounted) return;
          final has = cell.focus!.hasFocus;
          if (has) _lastCell = cell;
          widget.onFocus(has ? cell.controller : null);
          setState(() {
            _focusedRow = has ? row : null;
            _focusedColumn = has ? column : null;
          });
        });
      }
    }
  }

  /// [defer] holds the old cells until the frame is over. The toolbar acts on
  /// whichever cell has the cursor, and disposing that cell's controller while
  /// the toolbar is still pointing at it would be a use after free.
  void _disposeCells({bool defer = false}) {
    // The toolbar holds on to whichever cell was last typed in, so it has to
    // be told when that cell stops existing.
    widget.onCellsGone?.call();
    final old = _cells;
    void release() {
      for (final row in old) {
        for (final cell in row) {
          cell.dispose();
        }
      }
    }

    if (defer) {
      WidgetsBinding.instance.addPostFrameCallback((_) => release());
    } else {
      release();
    }
  }

  /// Every cell that can be typed in, in the order they are read.
  Iterable<_Cell> get _editable =>
      _cells.expand((row) => row).where((cell) => cell.editable);

  /// Picks the whole table, so the next font, size or colour lands on all of
  /// it. The toolbar and its dialogs only ever act on the one controller they
  /// were handed, so the carrying is done by the controller itself — see
  /// [_CellController].
  void _selectWholeTable() {
    final cells = _editable.toList();
    if (cells.isEmpty) return;
    final group = _CellGroup([for (final cell in cells) cell.controller!]);
    for (final cell in cells) {
      final controller = cell.controller!;
      controller.updateSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: controller.document.length - 1,
        ),
        ChangeSource.local,
      );
      (controller as _CellController).group = group;
    }
    // The toolbar acts on whichever cell the cursor is in, so one of them has
    // to hold it for the table to be reachable at all.
    cells.first.focus?.requestFocus();
    setState(() => _wholeTable = true);
  }

  void _releaseWholeTable() {
    if (!_wholeTable) return;
    for (final cell in _editable) {
      (cell.controller! as _CellController).group = null;
    }
    setState(() => _wholeTable = false);
  }

  void _deleteTable() {
    // Let the toolbar and the document editor go of the cell before the
    // table it lives in is taken away.
    widget.onFocus(null);
    _focusedRow = null;
    _focusedColumn = null;
    widget.onDelete!();
  }

  @override
  void dispose() {
    if (_focusedRow != null) {
      // Not during dispose: whoever is told about it will want to rebuild,
      // and this frame is already past the point where that is allowed.
      final tell = widget.onFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) => tell(null));
    }
    _disposeCells();
    super.dispose();
  }

  DocTable _current() => DocTable(
    columnWidths: _table.columnWidths,
    bordered: _table.bordered,
    rows: [
      for (var r = 0; r < _table.rows.length; r++)
        DocTableRow(
          isHeader: _table.rows[r].isHeader,
          cells: [
            for (var c = 0; c < _table.rows[r].cells.length; c++)
              _cellOf(_cells[r][c]),
          ],
        ),
    ],
  );

  /// Hands the whole table back after a cell changed.
  void _report() {
    final next = _current();
    _reported = next;
    widget.onChanged(next);
  }

  /// Rows and columns change the shape, so the cells are rebuilt around them.
  /// The cursor goes back to where it was: adding a row and being thrown out
  /// of the table would mean clicking back in for every single one.
  void _reshape(DocTable next) {
    final row = _focusedRow, column = _focusedColumn;
    // Let the toolbar go of the cell before its controller is taken away.
    widget.onFocus(null);
    _disposeCells(defer: true);
    _table = next;
    _reported = next;
    _build();
    setState(() {});
    widget.onChanged(next);
    if (row == null || column == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final r = row.clamp(0, _cells.length - 1);
      if (_cells[r].isEmpty) return;
      _cells[r][column.clamp(0, _cells[r].length - 1)].focus?.requestFocus();
    });
  }

  void _toggleBorder() {
    final next = _current();
    _reshape(
      DocTable(
        rows: next.rows,
        columnWidths: next.columnWidths,
        bordered: !_table.bordered,
      ),
    );
  }

  DocTableCell _cellOf(_Cell cell) {
    if (!cell.editable) return cell.original;
    return DocTableCell(
      colspan: cell.original.colspan,
      rowspan: cell.original.rowspan,
      backgroundColor: cell.original.backgroundColor,
      width: cell.original.width,
      blocks: DocDeltaMap.deltadanModel(cell.controller!.document.toDelta())
          .blocks,
    );
  }

  /// The colour a cell is filled with, if the document gave it one.
  static Color? _shadeOf(_Cell cell) {
    final value = cell.original.backgroundColor;
    final rgb = int.tryParse((value ?? '').replaceFirst('#', ''), radix: 16);
    return rgb == null ? null : Color(rgb | 0xff000000);
  }

  /// Fills the cells being worked on, or clears them when [shade] is null:
  /// the whole table when it is picked, otherwise the one with the cursor.
  void _shade(String? shade) {
    final last = _lastCell;
    final touched = _wholeTable
        ? _editable.toList()
        : [
            for (final cell in _editable)
              if (identical(cell, last)) cell,
          ];
    if (touched.isEmpty) return;
    for (final cell in touched) {
      cell.original = DocTableCell(
        blocks: cell.original.blocks,
        colspan: cell.original.colspan,
        rowspan: cell.original.rowspan,
        backgroundColor: shade,
        width: cell.original.width,
      );
    }
    _report();
    setState(() {});
  }

  static DocTableCell _emptyCell() =>
      DocTableCell(blocks: [DocBlock(plainText: '')]);

  int get _columnCount =>
      _table.rows.fold(0, (n, r) => r.cells.length > n ? r.cells.length : n);

  void _addRow() {
    final rows = List.of(_current().rows);
    final at = (_focusedRow ?? rows.length - 1) + 1;
    rows.insert(
      at.clamp(0, rows.length),
      DocTableRow(cells: [for (var i = 0; i < _columnCount; i++) _emptyCell()]),
    );
    _reshape(
      DocTable(
        columnWidths: _table.columnWidths,
        rows: rows,
        bordered: _table.bordered,
      ),
    );
  }

  void _removeRow() {
    if (_table.rows.length <= 1) return;
    final rows = List.of(_current().rows)
      ..removeAt(
        (_focusedRow ?? _table.rows.length - 1).clamp(
          0,
          _table.rows.length - 1,
        ),
      );
    _reshape(
      DocTable(
        columnWidths: _table.columnWidths,
        rows: rows,
        bordered: _table.bordered,
      ),
    );
  }

  void _addColumn() {
    final at = ((_focusedColumn ?? _columnCount - 1) + 1).clamp(
      0,
      _columnCount,
    );
    final rows = [
      for (final row in _current().rows)
        DocTableRow(
          isHeader: row.isHeader,
          cells: List.of(row.cells)
            ..insert(at.clamp(0, row.cells.length), _emptyCell()),
        ),
    ];
    _reshape(
      DocTable(
        rows: rows,
        columnWidths: _widthsWith(at, insert: true),
        bordered: _table.bordered,
      ),
    );
  }

  void _removeColumn() {
    if (_columnCount <= 1) return;
    final at = (_focusedColumn ?? _columnCount - 1).clamp(0, _columnCount - 1);
    final rows = [
      for (final row in _current().rows)
        DocTableRow(
          isHeader: row.isHeader,
          cells: row.cells.length > at
              ? (List.of(row.cells)..removeAt(at))
              : row.cells,
        ),
    ];
    _reshape(
      DocTable(
        rows: rows,
        columnWidths: _widthsWith(at, insert: false),
        bordered: _table.bordered,
      ),
    );
  }

  /// Column widths follow the columns, so the rest keep the proportions the
  /// document was written with.
  List<double>? _widthsWith(int at, {required bool insert}) {
    final widths = _table.columnWidths;
    if (widths == null) return null;
    final next = List.of(widths);
    if (insert) {
      next.insert(
        at.clamp(0, next.length),
        widths.isEmpty ? 100 : widths.first,
      );
    } else if (at < next.length) {
      next.removeAt(at);
    }
    return next;
  }

  /// Where the controls float: above the table, so they come and go
  /// without moving it, or anything after it, down the page.
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    final columns = _columnCount;
    if (columns == 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) => _drawn(
        columns,
        _widths(columns, constraints.maxWidth),
        constraints.maxWidth,
      ),
    );
  }

  /// The widths a column edge is being dragged to, until it is let go of.
  ///
  /// Written straight into [_table] would make the widget the parent still
  /// holds stop matching this one, and every cell would be rebuilt mid-drag.
  List<double>? _dragging;

  /// What each column is drawn at, in points: as the printed page draws it
  /// (see [TableColumns]).
  List<double> _widths(int columns, double available) => TableColumns.widths(
    available,
    columns,
    shares: _dragging ?? _table.columnWidths,
    whole: !widget.word,
  );

  /// Moves an edge, taking from one side and giving to the other so the table
  /// stays the width of the page. UYAP writes its spans as shares of the
  /// whole rather than as measurements, and so does this.
  void _dragEdge(int edge, double dx, int columns, double available) {
    final widths = TableColumns.widths(
      available,
      columns,
      shares: _dragging ?? _table.columnWidths,
      whole: false,
    );
    const smallest = 24.0;
    final give = dx.clamp(smallest - widths[edge], widths[edge + 1] - smallest);
    if (give == 0) return;
    widths[edge] += give;
    widths[edge + 1] -= give;
    setState(() => _dragging = widths);
  }

  void _dropEdge() {
    final widths = _dragging;
    if (widths == null) return;
    _dragging = null;
    _table = DocTable(
      rows: _table.rows,
      columnWidths: widths,
      bordered: _table.bordered,
    );
    _report();
    setState(() {});
  }

  /// A Word cell keeps its text off its lines, as the preview draws it; a
  /// UYAP one draws it against them.
  EdgeInsets get _padding =>
      widget.word ? const EdgeInsets.all(4) : EdgeInsets.zero;

  Widget _drawn(int columns, List<double> widths, double available) {
    final focused = _focusedRow != null || _menuOpen;
    final cells = <EditorPagedCell>[];
    final children = <Widget>[];
    for (var r = 0; r < _cells.length; r++) {
      var column = 0;
      var x = 0.0;
      for (var c = 0; c < _cells[r].length && column < columns; c++) {
        final cell = _cells[r][c];
        final span = cell.original.colspan < 1 ? 1 : cell.original.colspan;
        var width = 0.0;
        for (var k = column; k < column + span && k < columns; k++) {
          width += widths[k];
        }
        cells.add(
          EditorPagedCell(
            row: r,
            x: x,
            width: width,
            fill: _wholeTable
                ? _picked
                : _shadeOf(cell) ??
                      (_table.rows[r].isHeader
                          ? const Color(0xFFF1F3F7)
                          : null),
          ),
        );
        children.add(
          KeyedSubtree(
            key: ObjectKey(cell),
            child: Padding(
              padding: _padding,
              child: _cellWidget(cell, width - _padding.horizontal),
            ),
          ),
        );
        x += width;
        column += span;
      }
    }
    return Listener(
      // Around the controls as well as the table: pressing one of those is
      // not a click into the body, and taking the cursor out of the cell
      // would close the very row of buttons being used.
      onPointerDown: (_) => widget.onPointerInside?.call(),
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => focused && !widget.readOnly
            ? Align(
                alignment: Alignment.topLeft,
                child: CompositedTransformFollower(
                  link: _link,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.topLeft,
                  followerAnchor: Alignment.bottomLeft,
                  child: Listener(
                    onPointerDown: (_) => widget.onPointerInside?.call(),
                    child: Material(
                      color: Colors.white,
                      elevation: 2,
                      borderRadius: BorderRadius.circular(4),
                      child: _controls(),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
        child: CompositedTransformTarget(
          link: _link,
          child: Stack(
            key: const ValueKey('table'),
            children: [
              Listener(
                // A click anywhere in the table is a cursor going somewhere,
                // so the table stops being picked as a whole. The controls
                // sit above this, and pressing one of those does not let the
                // pick go.
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _releaseWholeTable(),
                child: EditorPagedTable(
                  cells: cells,
                  line: _table.bordered ? _border : _guide,
                  lineWidth: _table.bordered ? .7 : .5,
                  children: children,
                ),
              ),
              if (focused && !widget.readOnly)
                ..._edges(columns, widths, available),
            ],
          ),
        ),
      ),
    );
  }

  /// A grip on every line between two columns, so a column can be given the
  /// width its text needs. A table is drawn to the width of the page and its
  /// columns share that width out, so widening one narrows its neighbour and
  /// the table never spills past the margin.
  List<Widget> _edges(int columns, List<double> widths, double available) {
    final edges = <Widget>[];
    var x = 0.0;
    for (var i = 0; i < columns - 1; i++) {
      x += widths[i];
      final edge = i;
      edges.add(
        Positioned(
          left: x - 4,
          top: 0,
          bottom: 0,
          width: 9,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (d) =>
                  _dragEdge(edge, d.delta.dx, columns, available),
              onHorizontalDragEnd: (_) => _dropEdge(),
              onHorizontalDragCancel: _dropEdge,
            ),
          ),
        ),
      );
    }
    return edges;
  }

  /// Only while a cell holds the cursor: a row of buttons floating over every
  /// table in the document would be noise, and one stray click from deleting
  /// a row.
  Widget _controls() => Padding(
    padding: const EdgeInsets.all(3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _control(Icons.add, 'Satır ekle', _addRow),
        _control(
          Icons.remove,
          'Satırı sil',
          _table.rows.length > 1 ? _removeRow : null,
        ),
        const SizedBox(width: 6),
        _control(Icons.add, 'Sütun ekle', _addColumn, vertical: true),
        _control(
          Icons.remove,
          'Sütunu sil',
          _columnCount > 1 ? _removeColumn : null,
          vertical: true,
        ),
        const SizedBox(width: 8),
        _control(
          _wholeTable ? Icons.select_all : Icons.border_outer,
          _wholeTable ? 'Tablo seçili — bırak' : 'Tüm tabloyu seç',
          _wholeTable ? _releaseWholeTable : _selectWholeTable,
        ),
        const SizedBox(width: 8),
        _shadeButton(),
        const SizedBox(width: 8),
        if (widget.onDelete != null)
          _control(Icons.delete_outline, 'Tabloyu sil', _deleteTable),
        const SizedBox(width: 8),
        _control(
          _table.bordered ? Icons.border_all : Icons.border_clear,
          _table.bordered ? 'Çerçeveyi kaldır' : 'Çerçeve çiz',
          _toggleBorder,
        ),
        if (!_table.bordered)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Text(
              'kılavuz çizgiler yazdırılmaz',
              style: TextStyle(fontSize: 10, color: Color(0xFF7A8396)),
            ),
          ),
      ],
    ),
  );

  /// The fills a table is given in practice: a grey or a pale tint behind a
  /// heading row, and nothing at all.
  static const _shades = <(String, String?)>[
    ('Dolgu yok', null),
    ('Açık gri', '#f1f3f7'),
    ('Gri', '#d9dde5'),
    ('Sarı', '#fff3c4'),
    ('Yeşil', '#ddf3e0'),
    ('Mavi', '#dce9fa'),
    ('Kırmızı', '#fadcdc'),
  ];

  Widget _shadeButton() => PopupMenuButton<int>(
    tooltip: _wholeTable ? 'Tabloyu boya' : 'Hücreyi boya',
    padding: EdgeInsets.zero,
    iconSize: 13,
    icon: const Icon(
      Icons.format_color_fill,
      size: 13,
      color: Color(0xFF5E6675),
    ),
    onOpened: () => setState(() => _menuOpen = true),
    onCanceled: () => setState(() => _menuOpen = false),
    onSelected: (i) {
      _menuOpen = false;
      _shade(_shades[i].$2);
    },
    itemBuilder: (_) => [
      for (var i = 0; i < _shades.length; i++)
        PopupMenuItem(
          value: i,
          height: 32,
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _shades[i].$2 == null
                      ? Colors.white
                      : Color(
                          int.parse(_shades[i].$2!.substring(1), radix: 16) |
                              0xff000000,
                        ),
                  border: Border.all(color: _border, width: .7),
                ),
              ),
              const SizedBox(width: 8),
              Text(_shades[i].$1, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
    ],
  );

  Widget _control(
    IconData icon,
    String tip,
    VoidCallback? action, {
    bool vertical = false,
  }) => Tooltip(
    message: tip,
    child: InkWell(
      onTap: action,
      child: Opacity(
        opacity: action == null ? .35 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: const Color(0xFF5E6675)),
              Icon(
                vertical
                    ? Icons.table_chart_outlined
                    : Icons.table_rows_outlined,
                size: 13,
                color: const Color(0xFF5E6675),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  /// A cell [width] points wide, its lines broken where the printed page
  /// breaks them in a cell that wide.
  Widget _cellWidget(_Cell cell, double width) {
    if (!cell.editable) {
      final nested = cell.original.blocks
          .where((b) => b.type == DocBlockType.table && b.table != null)
          .toList();
      if (nested.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final b in nested)
              EditorTableView(
                table: b.table!,
                onChanged: (_) {},
                onFocus: (_) {},
                readOnly: true,
                word: widget.word,
              ),
          ],
        );
      }
      return Text(
        cell.original.blocks.map((b) => b.plainText).join('\n'),
        style: TextStyle(
          fontSize: 12,
          height: 1.15,
          color: Colors.black,
          fontFamily: DocumentFonts.family('Times New Roman'),
        ),
      );
    }
    return Actions(
      // Between the cell's editor and the document's, so the cell's own key
      // handling is the one that runs. See [_OwnAction].
      actions: _cellActions,
      child: QuillEditor.basic(
        controller: cell.controller!,
        focusNode: cell.focus,
        config: QuillEditorConfig(
          lineLayoutBuilder: EditorLineLayout.builder(pageWidth: width),
          textSpanBuilder: EditorTabSpans.builder(pageWidth: width),
          customStyles: DefaultStyles(
            paragraph: DefaultTextBlockStyle(
              TextStyle(
                color: Colors.black,
                fontFamily: DocumentFonts.family('Times New Roman'),
                fontSize: 12,
                height: 1.15,
              ),
              const HorizontalSpacing(0, 0),
              const VerticalSpacing(0, 0),
              const VerticalSpacing(0, 0),
              null,
            ),
            lists: DefaultListBlockStyle(
              TextStyle(
                color: Colors.black,
                fontFamily: DocumentFonts.family('Times New Roman'),
                fontSize: 12,
                height: 1.15,
              ),
              const HorizontalSpacing(0, 0),
              const VerticalSpacing(0, 0),
              const VerticalSpacing(0, 0),
              null,
              null,
            ),
            // Nor between the lines of an indented block, which Quill spaces
            // 6 apart by default: the page does not.
            indent: DefaultTextBlockStyle(
              TextStyle(
                color: Colors.black,
                fontFamily: DocumentFonts.family('Times New Roman'),
                fontSize: 12,
                height: 1.15,
              ),
              const HorizontalSpacing(0, 0),
              const VerticalSpacing(0, 0),
              const VerticalSpacing(0, 0),
              null,
            ),
          ),
          customStyleBuilder: (attribute) => attribute.key == 'font'
              ? TextStyle(
                  fontFamily: DocumentFonts.family(attribute.value as String?),
                )
              : const TextStyle(),
          scrollable: false,
          expands: false,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  /// One shared set is enough: only one cell holds the cursor at a time, and
  /// an intent is carried out before the next one arrives.
  late final Map<Type, Action<Intent>> _cellActions = <Type, Action<Intent>>{
    DeleteCharacterIntent: _OwnAction<DeleteCharacterIntent>(),
    DeleteToNextWordBoundaryIntent:
        _OwnAction<DeleteToNextWordBoundaryIntent>(),
    DeleteToLineBreakIntent: _OwnAction<DeleteToLineBreakIntent>(),
    ExtendSelectionByCharacterIntent:
        _OwnAction<ExtendSelectionByCharacterIntent>(),
    ExtendSelectionToNextWordBoundaryIntent:
        _OwnAction<ExtendSelectionToNextWordBoundaryIntent>(),
    ExtendSelectionToLineBreakIntent:
        _OwnAction<ExtendSelectionToLineBreakIntent>(),
    ExtendSelectionVerticallyToAdjacentLineIntent:
        _OwnAction<ExtendSelectionVerticallyToAdjacentLineIntent>(),
    ExtendSelectionToDocumentBoundaryIntent:
        _OwnAction<ExtendSelectionToDocumentBoundaryIntent>(),
    ExtendSelectionToNextWordBoundaryOrCaretLocationIntent:
        _OwnAction<ExtendSelectionToNextWordBoundaryOrCaretLocationIntent>(),
    ExpandSelectionToDocumentBoundaryIntent:
        _OwnAction<ExpandSelectionToDocumentBoundaryIntent>(),
    ExpandSelectionToLineBreakIntent:
        _OwnAction<ExpandSelectionToLineBreakIntent>(),
    SelectAllTextIntent: _OwnAction<SelectAllTextIntent>(),
    CopySelectionTextIntent: _OwnAction<CopySelectionTextIntent>(),
    PasteTextIntent: _OwnAction<PasteTextIntent>(),
    UndoTextIntent: _OwnAction<UndoTextIntent>(),
    RedoTextIntent: _OwnAction<RedoTextIntent>(),
  };
}

/// A cell's controller, which can be asked to carry the whole table.
///
/// The toolbar acts on one controller: the cell the cursor is in. Picking a
/// font, a size or a colour opens a dialog that hands the choice to that one
/// controller and to nothing else, so there was no way to restyle a table
/// without going cell by cell.
///
/// Rather than teach every tool about tables, the cell carries the others
/// with it. While the table is picked as a whole, [group] holds every cell in
/// it and a format applied here is applied to all of them — which covers the
/// tools that exist now and the ones added later, since each of them can only
/// reach the cell the same way.
class _CellController extends QuillController with EditorClipboard {
  _CellController({required super.document, required super.selection}) {
    // A cell holds text only; a table or a picture pasted into it is set as
    // text (see [EditorClipboard]).
    pasteTarget = PasteTarget.cell;
  }

  /// Null unless the table is picked as a whole.
  _CellGroup? group;

  // The flag is marked experimental upstream, but it is part of the method
  // being overridden and has to be passed along as it was given.
  @override
  // ignore: experimental_member_use
  void formatSelection(
    Attribute<dynamic>? attribute, {
    bool shouldNotifyListeners = true,
  }) {
    super.formatSelection(
      attribute,
      // ignore: experimental_member_use
      shouldNotifyListeners: shouldNotifyListeners,
    );
    // Each cell carries the same group, so without the latch the first one
    // would hand the format to the second, which would hand it back.
    final group = this.group;
    if (group == null || group.spreading) return;
    group.spreading = true;
    try {
      for (final other in group.cells) {
        if (identical(other, this)) continue;
        other.formatSelection(attribute);
      }
    } finally {
      group.spreading = false;
    }
  }
}

/// The cells of one table, while it is picked as a whole.
class _CellGroup {
  _CellGroup(this.cells);

  final List<QuillController> cells;

  /// Set while a format is going round the group.
  bool spreading = false;
}

/// Hands a key back to the editor that asked, instead of letting the editor
/// around it answer.
///
/// Quill registers its delete, selection, copy, paste and undo handling with
/// [Action.overridable], which looks for an override in the widgets above it
/// and prefers that to its own. A cell's editor is drawn inside the
/// document's, so every one of those found the document's handler and ran it:
/// Delete in a cell measured what to remove against the *document* and then
/// wrote the result into the *cell*, which is how one keypress poured the
/// whole document into a cell. The arrow keys, select all, copy, paste and
/// undo were reaching past the cell in the same way.
///
/// An override that simply calls [Action.callingAction] puts the cell's own
/// handler back in charge, on the cell's own text, and stops the document's
/// from ever being consulted.
class _OwnAction<T extends Intent> extends ContextAction<T> {
  @override
  bool isEnabled(T intent, [BuildContext? context]) =>
      callingAction?.isEnabled(intent) ?? false;

  @override
  bool consumesKey(T intent) => callingAction?.consumesKey(intent) ?? false;

  @override
  Object? invoke(T intent, [BuildContext? context]) {
    final own = callingAction;
    if (own == null) return null;
    return own is ContextAction<T>
        ? own.invoke(intent, context)
        : own.invoke(intent);
  }
}
