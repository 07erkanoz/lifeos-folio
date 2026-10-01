import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/fonts/font_line_metrics.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';

/// Where each run of text is drawn on the page, in order.
///
/// Each paragraph is placed with its own `cm` inside `q`/`Q`, and `Td` moves
/// the pen from there, so a position is the sum of the open translations and
/// the move.
List<({double x, double y})> penMoves(List<int> pdf) {
  final text = String.fromCharCodes(pdf);
  final out = <({double x, double y})>[];
  final token = RegExp(
    r'(?:([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+) cm)'
    r'|(?:([-\d.]+) ([-\d.]+) Td)|(?:\bq\b)|(?:\bQ\b)',
  );
  for (final match in RegExp(r'stream\r?\n').allMatches(text)) {
    final end = text.indexOf('endstream', match.end);
    if (end < 0) continue;
    String content;
    try {
      content = String.fromCharCodes(
        ZLibDecoder().convert(pdf.sublist(match.end, end)),
      );
    } on FormatException {
      continue;
    }
    var x = 0.0, y = 0.0;
    final saved = <(double, double)>[];
    for (final t in token.allMatches(content)) {
      if (t.group(0) == 'q') {
        saved.add((x, y));
      } else if (t.group(0) == 'Q') {
        if (saved.isNotEmpty) (x, y) = saved.removeLast();
      } else if (t.group(1) != null) {
        x += double.parse(t.group(5)!);
        y += double.parse(t.group(6)!);
      } else {
        out.add((
          x: x + double.parse(t.group(7)!),
          y: y + double.parse(t.group(8)!),
        ));
      }
    }
  }
  return out;
}

/// The baselines of the rows, top of the page first.
Future<List<double>> baselines(WidgetTester tester, DocModel model) async {
  final bytes = await tester.runAsync(() => PdfService.modelToPdfBytes(model));
  final rows = <double>[];
  for (final move in penMoves(bytes!)) {
    if (rows.isEmpty || (move.y - rows.last).abs() > 0.01) rows.add(move.y);
  }
  return rows;
}

void main() {
  final long = List.filled(60, 'kelime').join(' ');

  for (final spacing in [null, 1.15, 1.5]) {
    testWidgets('rows sit where Swing puts them at ${(spacing ?? 1) - 1}', (
      tester,
    ) async {
      final rows = await baselines(
        tester,
        DocModel(
          blocks: [DocBlock(plainText: long, lineSpacing: spacing)],
        ),
      );
      expect(rows.length, greaterThan(2), reason: '$rows');
      // Twelve point Times New Roman, the file's default, in whole points as
      // UYAP lays it out: 14, 16 and 20 (test/fixtures/pages).
      final pitch = FontLineMetrics.common.uyapRow(12, spacing);
      expect((rows[1] - rows[2]).abs(), closeTo(pitch, 0.01));
    });
  }

  testWidgets('a row takes its whole spacing, the last one too', (
    tester,
  ) async {
    // Two one-row paragraphs: the step between them is one whole row, the
    // spacing included, not the bare line box.
    final rows = await baselines(
      tester,
      DocModel(
        blocks: [
          DocBlock(plainText: 'Birinci', lineSpacing: 1.15),
          DocBlock(plainText: 'İkinci', lineSpacing: 1.15),
        ],
      ),
    );
    final pitch = FontLineMetrics.common.uyapRow(12, 1.15);
    expect((rows[0] - rows[1]).abs(), closeTo(pitch, 0.01));
  });

  testWidgets('half the spacing is above the text, as in UYAP\'s rows', (
    tester,
  ) async {
    // At 1.5 lines a 12 point row is 14 + 3 + 3: the text starts 3 points
    // lower than at single spacing.
    final single = await baselines(
      tester,
      DocModel(blocks: [DocBlock(plainText: 'Birinci')]),
    );
    final wide = await baselines(
      tester,
      DocModel(blocks: [DocBlock(plainText: 'Birinci', lineSpacing: 1.5)]),
    );
    expect(single.first - wide.first, closeTo(3, 0.01));
  });

  testWidgets('the first row starts at its indent, the rest at the margin', (
    tester,
  ) async {
    final bytes = await tester.runAsync(
      () => PdfService.modelToPdfBytes(
        DocModel(blocks: [DocBlock(plainText: long, firstLineIndent: 36)]),
      ),
    );
    final moves = penMoves(bytes!);
    final firstRow = moves.first;
    final secondRow = moves.firstWhere((m) => m.y < firstRow.y - 1);
    expect(firstRow.x - secondRow.x, closeTo(36, 0.01));
  });

  testWidgets('a tab on the indented first row reaches the stop past it', (
    tester,
  ) async {
    // Two rows that must put "Soyad" on the same 72 pt stop: one tabbed from
    // the left indent, and one that starts 36 pt in, writes "Ad" and tabs.
    // Compared with each other rather than with a margin worked out from
    // the pen, which moves with the first letter's side bearing and so with
    // whichever font the machine has.
    final bytes = await tester.runAsync(
      () => PdfService.modelToPdfBytes(
        DocModel(
          blocks: [
            DocBlock(plainText: '\tSoyad'),
            DocBlock(plainText: 'Ad\tSoyad', firstLineIndent: 36),
          ],
        ),
      ),
    );
    final moves = penMoves(bytes!);
    expect(moves.length, 3, reason: '$moves');
    // Counted from where the indented row's text starts instead, "Soyad"
    // would land at 36 + 72.
    expect(moves[2].x, closeTo(moves[0].x, 0.01));
  });
}
