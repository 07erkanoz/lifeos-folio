import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'editor_units.dart';

/// The sheets of paper behind the editor: as many as its text takes, each
/// [pageHeight] tall, [gutter] apart. The editor ends where its last page's
/// text area does, so the height it is given always holds whole sheets.
class EditorSheetsPainter extends CustomPainter {
  const EditorSheetsPainter({required this.pageHeight, required this.gutter});

  final double pageHeight;
  final double gutter;

  /// Room between two sheets: 24 pixels on the screen, laid out in points.
  static const room = 24 / EditorUnits.screenScale;

  static int pageCount(double height, double pageHeight, double gutter) =>
      math.max(1, ((height + gutter) / (pageHeight + gutter)).round());

  @override
  void paint(Canvas canvas, Size size) {
    final pages = pageCount(size.height, pageHeight, gutter);
    final shadow = Paint()
      ..color = const Color(0x14000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final paper = Paint()..color = Colors.white;
    final edge = Paint()
      ..color = const Color(0xFFD6DAE1)
      ..style = PaintingStyle.stroke;
    for (var page = 0; page < pages; page++) {
      final sheet = Rect.fromLTWH(
        0,
        page * (pageHeight + gutter),
        size.width,
        pageHeight,
      );
      canvas
        ..drawRect(sheet.shift(const Offset(0, 2)), shadow)
        ..drawRect(sheet, paper)
        ..drawRect(sheet.deflate(.5), edge);
    }
  }

  @override
  bool shouldRepaint(EditorSheetsPainter old) =>
      old.pageHeight != pageHeight || old.gutter != gutter;
}
