import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../models/document_model.dart';
import '../../services/fonts/document_fonts.dart';
import '../../services/layout/list_markers.dart';

/// A list item's number or bullet in the editor, drawn where UYAP and the
/// preview draw it (see [ListMarkers]): in the indent beside the first row,
/// taking no room. Its origin is the line's left edge at the top of its
/// first row.
class EditorListMarker extends StatelessWidget {
  const EditorListMarker({
    super.key,
    required this.label,
    required this.shape,
    required this.textStart,
    required this.row,
    required this.fontFamily,
    required this.size,
  });

  /// The number, or null for a bullet of [shape].
  final String? label;
  final BulletShape shape;

  /// Where the first row's text begins, from the line's left edge.
  final double textStart;

  /// The first row's height.
  final double row;
  final String? fontFamily;
  final double size;

  /// The marker for [line], a list item, numbered among the document's lists
  /// as UYAP numbers them; null for a line that is not one.
  static EditorListMarker? of(
    Line line, {
    required double textStart,
    required double row,
  }) {
    final list = line.style.attributes[Attribute.list.key]?.value;
    if (list != 'ordered' && list != 'bullet') return null;
    final layout = line.style.attributes['doc-layout']?.value;
    final kind = layout is Map ? layout : const {};
    final first = line.children.isEmpty ? null : line.children.first;
    final font = first?.style.attributes[Attribute.font.key]?.value;
    final kept = first?.style.attributes['size']?.value;
    final pixels = kept is num ? kept.toDouble() : double.tryParse('$kept');
    return EditorListMarker(
      label: list == 'ordered'
          ? ListMarkers.label(kind['number'] as String?, _numberOf(line))
          : null,
      shape: ListMarkers.shape(kind['bullet'] as String?),
      textStart: textStart,
      row: row,
      fontFamily: DocumentFonts.family(font is String ? font : null),
      // A run's size is kept in 96 dpi pixels; the page is laid out in
      // points.
      size: pixels == null ? 12 : pixels * 72 / 96,
    );
  }

  /// [line]'s number among the document's list items.
  static int _numberOf(Line line) {
    Node node = line;
    while (node.parent != null) {
      node = node.parent!;
    }
    final lines = <Line>[];
    void collect(Node n) {
      if (n is Line) {
        lines.add(n);
      } else if (n is Root) {
        n.children.forEach(collect);
      } else if (n is Block) {
        n.children.forEach(collect);
      }
    }

    collect(node);
    final blocks = [
      for (final l in lines)
        () {
          final attrs = l.style.attributes;
          final list = attrs[Attribute.list.key]?.value;
          final layout = attrs['doc-layout']?.value;
          final indent = attrs[Attribute.indent.key]?.value;
          return DocBlock(
            plainText: '',
            listType: list == 'ordered'
                ? DocListType.ordered
                : list == 'bullet'
                ? DocListType.unordered
                : DocListType.none,
            listId: layout is Map ? (layout['listId'] as int? ?? 0) : 0,
            listLevel: indent is int ? indent : 0,
          );
        }(),
    ];
    return ListMarkers.numbers(blocks)[lines.indexOf(line)] ?? 1;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(size: Size.zero, painter: _MarkerPainter(this)),
  );
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.marker);

  final EditorListMarker marker;

  @override
  void paint(Canvas canvas, Size size) {
    final label = marker.label;
    if (label != null) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.black,
            fontFamily: marker.fontFamily,
            fontSize: marker.size,
            fontFeatures: const [FontFeature.disable('kern')],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final at = ListMarkers.numberAt(
        textStart: marker.textStart,
        advance: painter.width,
        row: marker.row,
        size: marker.size,
      );
      painter
        ..paint(
          canvas,
          Offset(
            at.x,
            at.baseline -
                painter.computeDistanceToActualBaseline(
                  TextBaseline.alphabetic,
                ),
          ),
        )
        ..dispose();
      return;
    }
    final at = ListMarkers.bulletAt(
      textStart: marker.textStart,
      row: marker.row,
      size: marker.size,
    );
    final s = at.side;
    final fill = Paint()..color = Colors.black;
    final box = Rect.fromLTWH(at.x, at.y, s, s);
    switch (marker.shape) {
      case BulletShape.circle:
        canvas.drawOval(box, fill);
      case BulletShape.square:
        canvas.drawRect(box, fill);
      case BulletShape.squareOutline:
        canvas.drawRect(
          box,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .6,
        );
      case BulletShape.arrow:
        canvas.drawPath(
          Path()
            ..moveTo(box.left, box.top)
            ..lineTo(box.right, box.center.dy)
            ..lineTo(box.left, box.bottom)
            ..lineTo(box.left + s * .3, box.center.dy)
            ..close(),
          fill,
        );
      case BulletShape.diamond:
        canvas.drawPath(
          Path()
            ..moveTo(box.center.dx, box.top)
            ..lineTo(box.right, box.center.dy)
            ..lineTo(box.center.dx, box.bottom)
            ..lineTo(box.left, box.center.dy)
            ..close(),
          fill,
        );
      case BulletShape.triangle:
        canvas.drawPath(
          Path()
            ..moveTo(box.left, box.bottom)
            ..lineTo(box.right, box.bottom)
            ..lineTo(box.center.dx, box.top)
            ..close(),
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(_MarkerPainter old) =>
      old.marker.label != marker.label ||
      old.marker.shape != marker.shape ||
      old.marker.textStart != marker.textStart ||
      old.marker.row != marker.row ||
      old.marker.size != marker.size ||
      old.marker.fontFamily != marker.fontFamily;
}
