import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/overlay_card.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';

import 'support/fake_path_provider.dart';

/// Lets both clocks move.
///
/// Loading the document is file I/O on the real clock, which only `runAsync`
/// advances; the scan then waits on a `Timer`, which only a `pump` given a
/// duration advances. A loop that does one and not the other waits for ever.
Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Does a citation drawn in the editor actually answer a press?
///
/// The rest of this feature is tested away from the editor, but the one
/// thing no unit can show is whether Quill lets a span of its own text carry
/// a recognizer — the editor also wants that press, to put the caret down.
/// It does: this is what proves it.
void main() {
  testWidgets('pressing a cited law in the editor opens the article', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    useFakePathProvider();
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio_cite_'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );

    final file = File('${dir.path}/dilekce.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(
            blocks: [
              DocBlock(
                plainText: 'Boşanma talebi TMK m. 166 uyarınca sunulmuştur.',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: EditorWidget(
            initialFilePath: file.path,
            initialFormat: EvrakFormat.udf,
          ),
        ),
      ),
    );

    await waitFor(tester, () => find.byType(QuillEditor).evaluate().isNotEmpty);
    expect(find.byType(QuillEditor), findsOneWidget);
    // The scan waits for the typing to settle, and the table has to load.
    await waitFor(tester, () {
      for (final element
          in find
              .descendant(
                of: find.byType(QuillEditor),
                matching: find.byType(RichText),
              )
              .evaluate()) {
        var marked = false;
        ((element.widget as RichText).text as TextSpan).visitChildren((span) {
          if (span is TextSpan && span.recognizer != null) marked = true;
          return !marked;
        });
        if (marked) return true;
      }
      return false;
    });

    // Find the span the citation was drawn into, and press it where it sits.
    final paragraph = find
        .descendant(
          of: find.byType(QuillEditor),
          matching: find.byType(RichText),
        )
        .evaluate()
        .map((e) => e.widget as RichText)
        .firstWhere(
          // The drawn text carries the marks that make it break where the
          // page does (word joiners, zero-width spaces); read past them.
          (r) => _visible(r.text.toPlainText()).contains('TMK m. 166'),
          orElse: () => throw StateError('atıf taşıyan satır bulunamadı'),
        );

    final plain = paragraph.text.toPlainText();
    final at = plain.indexOf('TMK') + 4;
    var pressed = false;
    paragraph.text.visitChildren((span) {
      if (span is! TextSpan || span.recognizer == null) return true;
      final text = span.toPlainText();
      if (!text.contains('TMK')) return true;
      pressed = true;
      return false;
    });
    expect(
      pressed,
      isTrue,
      reason: 'atıf, kendi dokunma tanıyıcısını taşıyan bir parça olmalı',
      skip: false,
    );
    expect(at, greaterThan(0));

    // Now the press itself, through the real gesture path.
    final box = tester.renderObject<RenderBox>(find.byType(QuillEditor));
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: TextDirection.ltr,
      textAlign: paragraph.textAlign,
    )..layout(maxWidth: box.size.width);
    final spot = painter.getOffsetForCaret(TextPosition(offset: at), Rect.zero);
    painter.dispose();

    // Through the paragraph's own transform: the page is drawn larger than
    // it is laid out (see EditorUnits).
    final line = tester.renderObject<RenderBox>(
      find.byWidget(paragraph, skipOffstage: false),
    );
    await tester.tapAt(line.localToGlobal(spot + const Offset(0, 5)));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey('article-panel')),
      findsOneWidget,
      reason: 'atıfa basınca madde kartı açılmalı',
    );
    expect(find.textContaining('Türk Medeni Kanunu m. 166'), findsOneWidget);

    // And Esc puts it away, the way main.dart asks it to.
    expect(OverlayCard.dismissActive(), isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('article-panel')), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

String _visible(String text) =>
    text.replaceAll('\u2060', '').replaceAll('\u200b', '');
