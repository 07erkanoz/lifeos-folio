import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/services/editor/editor_settings.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/uyap_case_panel.dart';

/// The UYAP case beside the page, from the editor's own toolbar.
void main() {
  testWidgets('the toolbar opens the UYAP panel beside the page and closes '
      'it again', (tester) async {
    final dir = Directory.systemTemp.createTempSync('folio-editor-uyap-');
    addTearDown(() => dir.deleteSync(recursive: true));
    EditorSettings.instance = EditorSettings(directory: dir);
    addTearDown(() => EditorSettings.instance = EditorSettings());
    // Wide enough for the whole toolbar in the test's broad Ahem letters.
    tester.view.physicalSize = const Size(2300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: EditorWidget(draft: EditorDrafts().draft('new', 'Yeni evrak')),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(UyapCasePanel), findsNothing);
    // Named, on a screen this wide.
    await tester.tap(find.text('UYAP dosyası'));
    await tester.pump();
    expect(find.byType(UyapCasePanel), findsOneWidget);
    // A new document, tied to nothing yet.
    expect(find.byKey(const ValueKey('uyap-panel-link')), findsOneWidget);
    await tester.tap(find.byTooltip('Paneli kapat'));
    await tester.pump();
    expect(find.byType(UyapCasePanel), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }, skip: !(Platform.isLinux || Platform.isWindows));
}
