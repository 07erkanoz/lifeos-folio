import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// One cell of an [EditorPagedTable]: where it goes, and what it is filled
/// with.
class EditorPagedCell {
  const EditorPagedCell({
    required this.row,
    required this.x,
    required this.width,
    this.rows = 1,
    this.fill,
  });

  final int row;

  /// The rows it takes from [row] down: more than one for a cell merged
  /// down (rowspan).
  final int rows;

  /// From the table's left edge.
  final double x;
  final double width;
  final Color? fill;

  @override
  bool operator ==(Object other) =>
      other is EditorPagedCell &&
      other.row == row &&
      other.rows == rows &&
      other.x == x &&
      other.width == width &&
      other.fill == fill;

  @override
  int get hashCode => Object.hash(row, rows, x, width, fill);
}

/// A table laid out the way UYAP lays one out on its pages: row under row,
/// each row as tall as its tallest cell, and a cell that reaches the end of
/// a page going on at the top of the next, a line at a time, while the
/// cells beside it go on on their own (test/fixtures/pages,
/// 10-tablo-uzun-hucre).
///
/// The cells are editors, and each one breaks its own lines across the
/// pages: this tells each where on the pages it sits ([QuillPagedHost]).
/// The lines between cells take no room, and are drawn a page at a time.
class EditorPagedTable extends MultiChildRenderObjectWidget {
  const EditorPagedTable({
    super.key,
    required this.cells,
    required this.line,
    required this.lineWidth,
    required super.children,
  }) : assert(cells.length == children.length);

  final List<EditorPagedCell> cells;
  final Color line;
  final double lineWidth;

  @override
  RenderEditorPagedTable createRenderObject(BuildContext context) =>
      RenderEditorPagedTable(cells: cells, line: line, lineWidth: lineWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderEditorPagedTable renderObject,
  ) {
    renderObject
      ..cells = cells
      ..line = line
      ..lineWidth = lineWidth;
  }
}

class _CellParentData extends ContainerBoxParentData<RenderBox> {}

class RenderEditorPagedTable extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CellParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CellParentData>,
        QuillPagedHost {
  RenderEditorPagedTable({
    required this._cells,
    required this._line,
    required this._lineWidth,
  });

  List<EditorPagedCell> _cells;
  set cells(List<EditorPagedCell> value) {
    // The same cells built again (each key in the body builds the table's
    // row again) lay nothing out again; the cells' own changes reach the
    // layout through them.
    if (listEquals(_cells, value)) return;
    _cells = value;
    markNeedsLayout();
  }

  Color _line;
  set line(Color value) {
    if (_line == value) return;
    _line = value;
    markNeedsPaint();
  }

  double _lineWidth;
  set lineWidth(double value) {
    if (_lineWidth == value) return;
    _lineWidth = value;
    markNeedsPaint();
  }

  /// The pages as the table sees them, from its own top.
  QuillPageGeometry? _pages;

  /// Where each row starts and ends, from the table's top.
  List<({double top, double bottom})> _rows = const [];

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CellParentData) {
      child.parentData = _CellParentData();
    }
  }

  @override
  QuillPageGeometry? pagesFor(RenderObject child) {
    final pages = _pages;
    if (pages == null || child is! RenderBox) return pages;
    return pages.shifted((child.parentData as _CellParentData).offset.dy);
  }

  @override
  void performLayout() {
    final pages = pagesFromHost(this);
    final moved = pages != _pages;
    _pages = pages;
    final rows = <({double top, double bottom})>[];
    // Where a cell merged down needs the row it ends in to end, at least:
    // a cell taller than the rows it takes makes its last one taller.
    final ends = <int, double>{};
    var child = firstChild;
    var index = 0;
    var y = 0.0;
    var width = 0.0;
    void close(int row, double top, double bottom) {
      final end = math.max(bottom, ends.remove(row) ?? bottom);
      rows.add((top: top, bottom: end));
      y = end;
    }

    while (child != null) {
      final row = _cells[index].row;
      // Rows no cell begins in: taken by the cells above them.
      while (rows.length < row) {
        close(rows.length, y, y);
      }
      final top = y;
      var bottom = top;
      // Every cell of the row, laid out from the row's top.
      while (child != null && _cells[index].row == row) {
        final cell = _cells[index];
        final data = child.parentData as _CellParentData;
        final at = Offset(cell.x, top);
        if (moved || data.offset != at) {
          data.offset = at;
          relayoutPagedDependents(under: child);
        }
        child.layout(
          BoxConstraints.tightFor(width: cell.width),
          parentUsesSize: true,
        );
        final reach = top + child.size.height;
        if (cell.rows > 1) {
          final last = row + cell.rows - 1;
          ends[last] = math.max(ends[last] ?? reach, reach);
        } else {
          bottom = math.max(bottom, reach);
        }
        width = math.max(width, cell.x + cell.width);
        child = data.nextSibling;
        index++;
      }
      close(row, top, bottom);
    }
    // A cell merged down past the last row: the last row holds it.
    if (ends.isNotEmpty && rows.isNotEmpty) {
      final last = rows.removeLast();
      final end = ends.values.fold(last.bottom, math.max);
      rows.add((top: last.top, bottom: end));
      y = end;
    }
    _rows = rows;
    size = constraints.constrain(Size(width, y));
  }

  /// Where [cell] starts and ends, from the table's top: its first row's top
  /// to its last row's bottom.
  ({double top, double bottom})? _spanOf(EditorPagedCell cell) {
    if (cell.row >= _rows.length) return null;
    final last = math.min(cell.row + cell.rows - 1, _rows.length - 1);
    return (top: _rows[cell.row].top, bottom: _rows[last].bottom);
  }

  /// The parts of [top]..[bottom] that fall on a page's text area: all of it
  /// off pages.
  List<({double top, double bottom})> _onPages(double top, double bottom) {
    final pages = _pages;
    if (pages == null) return [(top: top, bottom: bottom)];
    final out = <({double top, double bottom})>[];
    for (
      var page = pages.pageOf(top);
      page <= pages.pageOf(math.max(top, bottom - .01));
      page++
    ) {
      final from = math.max(top, pages.topOf(page));
      final to = math.min(bottom, pages.bottomOf(page));
      if (to > from) out.add((top: from, bottom: to));
    }
    return out.isEmpty ? [(top: top, bottom: bottom)] : out;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    // Fills first, as tall as the rows the cell takes, a page at a time.
    for (final cell in _cells) {
      final fill = cell.fill;
      final span = _spanOf(cell);
      if (fill != null && span != null) {
        for (final part in _onPages(span.top, span.bottom)) {
          canvas.drawRect(
            Rect.fromLTRB(
              cell.x,
              part.top,
              cell.x + cell.width,
              part.bottom,
            ).shift(offset),
            Paint()..color = fill,
          );
        }
      }
    }
    defaultPaint(context, offset);
    // A cell may have painted into a layer of its own, which leaves the
    // canvas taken before it finished.
    final lines = context.canvas;
    final paint = Paint()
      ..color = _line
      ..strokeWidth = _lineWidth
      ..style = PaintingStyle.stroke;
    // Each cell's own box, as tall as the rows it takes: no line runs
    // through a cell merged down. Its sides a page at a time.
    // An edge two cells share is drawn once: twice, its line came out
    // darker than the rest.
    final drawn = <(double, double, double, double)>{};
    void line(double x1, double y1, double x2, double y2) {
      if (!drawn.add((x1, y1, x2, y2))) return;
      lines.drawLine(offset + Offset(x1, y1), offset + Offset(x2, y2), paint);
    }

    for (final cell in _cells) {
      final span = _spanOf(cell);
      if (span == null || span.bottom <= span.top) continue;
      final left = cell.x, right = cell.x + cell.width;
      for (final part in _onPages(span.top, span.bottom)) {
        line(left, part.top, left, part.bottom);
        line(right, part.top, right, part.bottom);
      }
      line(left, span.top, right, span.top);
      line(left, span.bottom, right, span.bottom);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
