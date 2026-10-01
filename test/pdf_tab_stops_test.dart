import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';

/// Where the exported PDF places text, read back out of the file.
///
/// The preview is this PDF, so measuring the bytes is measuring what the
/// reader sees. Content streams are deflated; `x y Td` is the operator that
/// moves the pen before a run is drawn.
List<double> penPositions(List<int> pdf) {
  final text = String.fromCharCodes(pdf);
  final out = <double>[];
  for (final match in RegExp(r'stream\r?\n').allMatches(text)) {
    final end = text.indexOf('endstream', match.end);
    if (end < 0) continue;
    List<int> inflated;
    try {
      inflated = ZLibDecoder().convert(pdf.sublist(match.end, end));
    } on FormatException {
      continue;
    }
    for (final move in RegExp(
      r'([-\d.]+) ([-\d.]+) Td',
    ).allMatches(String.fromCharCodes(inflated))) {
      out.add(double.parse(move.group(1)!));
    }
  }
  return out;
}

Future<List<double>> exportPositions(
  WidgetTester tester,
  DocModel model,
) async {
  final bytes = await tester.runAsync(() => PdfService.modelToPdfBytes(model));
  return penPositions(bytes!);
}

void main() {
  testWidgets('labels of different lengths reach one column in the export', (
    tester,
  ) async {
    // The preview renders through this path, so the columns a filing is built
    // from have to survive it. They did not: the text engine draws a tab
    // exactly as wide as a space, 3.00 pt against 3.00 pt when measured, so
    // every value sat one space after a label of its own length.
    final positions = await exportPositions(
      tester,
      DocModel(
        blocks: [
          DocBlock(plainText: 'Arabuluculuk Sicil Numarası\t: 12173'),
          DocBlock(plainText: 'Adı ve Soyadı\t\t: Çiğdem Öz'),
        ],
      ),
    );
    // Each line starts again at zero; the run after the tabs is what has to
    // match, and it does at the second stop — the long label spends one tab,
    // the short one spends two.
    final lines = <List<double>>[];
    for (final x in positions) {
      if (x == 0 || lines.isEmpty) lines.add([]);
      lines.last.add(x);
    }
    expect(lines.length, 2, reason: 'iki satır bekleniyordu');
    final first = lines[0].firstWhere(
      (x) => x >= 144 && x < 145,
      orElse: () => -1,
    );
    final second = lines[1].firstWhere(
      (x) => x >= 144 && x < 145,
      orElse: () => -1,
    );
    expect(first, isNot(-1), reason: 'uzun etiket durağa varmadı');
    expect(
      second,
      closeTo(first, 0.1),
      reason: 'kısa etiket aynı sütuna varmadı',
    );
  });

  testWidgets('a justified line positioned with spaces is not squeezed', (
    tester,
  ) async {
    // These documents centre a heading by typing spaces in front of it. The
    // text engine reads each run of them as a word it may stretch, and on a
    // line it measures as too wide it stretches by a negative amount: every
    // run is pulled back over the one before it and the heading is drawn on
    // top of itself. A run of spaces is emitted as a box of the same width
    // instead, so the position survives and there is nothing left to squeeze.
    final positions = await exportPositions(
      tester,
      DocModel(
        blocks: [
          DocBlock(
            plainText:
                '${' ' * 37}ARABULUCUYA BAŞVURMA ,BİLGİLENDİRME ve 2.ve  '
                'ANLAŞMA SON OTURUM TUTANAĞIDIR.',
            alignment: DocAlignment.justify,
          ),
        ],
      ),
    );
    for (var i = 1; i < positions.length; i++) {
      // A new line restarts at the margin; within one, the pen only advances.
      if (positions[i] < 1) continue;
      expect(
        positions[i],
        greaterThanOrEqualTo(positions[i - 1] - 0.5),
        reason: 'kelime geriye çekildi: $positions',
      );
    }
  });

  testWidgets('nothing is inserted where there was no tab', (tester) async {
    // The engine moves the pen once per word either way, so what says a gap
    // was not invented is that no run was pushed out to a stop: a short line
    // stays within its own width instead of jumping to the first inch.
    final positions = await exportPositions(
      tester,
      DocModel(blocks: [DocBlock(plainText: 'Kısa')]),
    );
    expect(positions.every((x) => x < 72), isTrue, reason: '$positions');
  });
}
