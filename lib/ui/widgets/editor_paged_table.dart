import 'dart:math' as math;

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
    this.fill,
  });

  final int row;

  /// From the table's left edge.
  final double x;
  final double width;
  final Color? fill;
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
    var child = firstChild;
    var index = 0;
    var y = 0.0;
    var width = 0.0;
    while (child != null) {
      final row = _cells[index].row;
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
        bottom = math.max(bottom, top + child.size.height);
        width = math.max(width, cell.x + cell.width);
        child = data.nextSibling;
        index++;
      }
      while (rows.length < row) {
        rows.add((top: top, bottom: top));
      }
      rows.add((top: top, bottom: bottom));
      y = bottom;
    }
    _rows = rows;
    size = constraints.constrain(Size(width, y));
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
    // Fills first, a whole row tall and a page at a time.
    for (final cell in _cells) {
      final fill = cell.fill;
      if (fill != null && cell.row < _rows.length) {
        final row = _rows[cell.row];
        for (final part in _onPages(row.top, row.bottom)) {
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
    for (var r = 0; r < _rows.length; r++) {
      final row = _rows[r];
      if (row.bottom <= row.top) continue;
      final parts = _onPages(row.top, row.bottom);
      final edges = <double>{};
      var left = double.infinity, right = 0.0;
      for (final cell in _cells) {
        if (cell.row != r) continue;
        edges
          ..add(cell.x)
          ..add(cell.x + cell.width);
        left = math.min(left, cell.x);
        right = math.max(right, cell.x + cell.width);
      }
      for (final part in parts) {
        for (final x in edges) {
          lines.drawLine(
            offset + Offset(x, part.top),
            offset + Offset(x, part.bottom),
            paint,
          );
        }
      }
      lines
        ..drawLine(
          offset + Offset(left, row.top),
          offset + Offset(right, row.top),
          paint,
        )
        ..drawLine(
          offset + Offset(left, row.bottom),
          offset + Offset(right, row.bottom),
          paint,
        );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
