import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/layout/page_numbers.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pdf_readback.dart';

/// Where UYAP's own editor starts each page, held against Folio's PDF.
///
/// The documents in fixtures/pages/udf are synthetic, each built to show one
/// of UYAP's page rules; pages.json is what UYAP did with them, measured by
/// fixtures/pages/capture_pages.sh. What they showed:
///
/// * A row stays on a page while its bottom is within the text area, and
///   otherwise starts the next page; every row on its own, so a paragraph
///   splits anywhere and one row may be left alone — even inside a table
///   cell.
/// * Space above a paragraph goes with its first row, to the top of a page
///   too; space below one does not count towards whether it fits, and is
///   not carried over.
/// * The header and footer are drawn at their offsets from the edge and take
///   nothing from the text area, unless one is taller than its margin: then
///   the text starts below it (or ends above it) on every page.
/// * A table row taller than what is left of a page goes on on the next
///   one a cell row at a time, each cell on its own (10-tablo-uzun-hucre).
void main() {
  final expected =
      (jsonDecode(File('test/fixtures/pages/pages.json').readAsStringSync())
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as List).cast<String>()));

  String squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  for (final MapEntry(key: name, value: starts) in expected.entries) {
    testWidgets('pages start where UYAP starts them: $name', (tester) async {
      final model = UdfReader.readBytes(
        File('test/fixtures/pages/udf/$name').readAsBytesSync(),
      )!;
      final bytes = await tester.runAsync(
        () => PdfService.modelToPdfBytes(model),
      );
      final pdf = (await tester.runAsync(() => PdfReadback.of(bytes!)))!;
      expect(pdf.pageCount, starts.length, reason: 'sayfa sayısı');
      // The header and footer are on every page; the body is what says
      // where a page starts.
      final regions = [
        for (final blocks in model.pageRegions.values)
          for (final b in blocks)
            if (b.plainText.trim().isNotEmpty) squash(b.plainText),
      ];
      // So are the page numbers, as UYAP draws them.
      final numberings = [
        for (final attrs
            in ((model.metadata['pageRegionAttrs'] as Map?) ?? const {}).values)
          ?PageNumbering.parse(attrs as Map),
      ];
      String body(int page) {
        var text = squash(pdf.pageText(page));
        for (final region in regions) {
          text = squash(text.replaceFirst(region, ''));
        }
        for (final numbering in numberings) {
          final label = squash(numbering.label(page + 1, pdf.pageCount));
          if (label.isNotEmpty) text = squash(text.replaceFirst(label, ''));
        }
        return text;
      }

      for (var i = 0; i < starts.length; i++) {
        final want = squash(starts[i]);
        // An empty paragraph starting a page draws no text to read back.
        if (want.isEmpty) continue;
        final got = body(i);
        expect(
          got.startsWith(want),
          isTrue,
          reason:
              'sayfa ${i + 1} "$want" ile başlamalı, '
              '"${got.substring(0, 40)}" ile başlıyor',
        );
      }
    });
  }
}
