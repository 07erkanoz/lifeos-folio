import 'dart:io';

import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/services/editor/editor_settings.dart';
import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/editor/snippets.dart';
import 'package:evrak_convert/services/editor/suggestions/phrase_memory.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

/// Yazarken öneri, gerçek editörde: liste yazma durunca açılır, Tab ya da
/// Enter alır, Esc o kelime boyunca kapatır; liste kapalıyken Enter satır
/// açar.
void main() {
  late PhraseMemory memory;
  late Directory settingsDir;

  setUp(() {
    SnippetStore.useShared(SnippetStore.memory());
    LawyerProfile.use(const LawyerProfile());
    memory = PhraseMemory.memory();
    PhraseMemory.useShared(memory);
    settingsDir = Directory.systemTemp.createTempSync('folio-editor-set-');
    EditorSettings.instance = EditorSettings(directory: settingsDir);
  });
  tearDown(() {
    LawyerProfile.use(null);
    PhraseMemory.useShared(null);
    memory.dispose();
    EditorSettings.instance = EditorSettings();
    settingsDir.deleteSync(recursive: true);
  });

  Future<QuillController> openEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
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
    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    return tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
  }

  /// Types [text] a letter at a time at the end, then waits for the pause
  /// the list opens after.
  Future<void> type(
    WidgetTester tester,
    QuillController controller,
    String text,
  ) async {
    for (final letter in text.split('')) {
      final end = controller.document.length - 1;
      controller.replaceText(
        end,
        0,
        letter,
        TextSelection.collapsed(offset: end + 1),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 250));
  }

  String body(QuillController controller) =>
      controller.document.toPlainText().trimRight();

  final list = find.byKey(const ValueKey('suggestion-list'));

  testWidgets('the list opens as typing pauses, and Tab takes the marked '
      'line in one step to undo', (tester) async {
    final controller = await openEditor(tester);
    await type(tester, controller, 'Borçlu hakkında icra');
    expect(list, findsOneWidget);
    expect(
      find.byKey(const ValueKey('suggestion-İcra ve İflas Kanunu')),
      findsOneWidget,
    );
    // "İcra Hukuk Mahkemesine" and the others come first; walk to the code.
    final keys = [
      for (final item
          in find
              .descendant(of: list, matching: find.byType(InkWell))
              .evaluate())
        ((item.widget as InkWell).key as ValueKey).value,
    ];
    for (var i = 0; i < keys.indexOf('suggestion-İcra ve İflas Kanunu'); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(body(controller), 'Borçlu hakkında İcra ve İflas Kanunu');
    expect(list, findsNothing);
    // One undo brings back what was typed.
    controller.undo();
    await tester.pump();
    expect(body(controller), 'Borçlu hakkında icra');
  });

  testWidgets('Enter takes the marked suggestion, as Tab does', (tester) async {
    final controller = await openEditor(tester);
    await type(tester, controller, 'Gereğini say');
    expect(list, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(list, findsNothing);
    expect(body(controller), contains('saygılarımla'));
    expect(body(controller), isNot(contains('\n')));
  });

  testWidgets('with the list closed, Enter opens a line', (tester) async {
    final controller = await openEditor(tester);
    await type(tester, controller, 'Gereğini say');
    expect(list, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.document.toPlainText(), startsWith('Gereğini say\n'));
    expect(body(controller), isNot(contains('saygılarımla')));
  });

  testWidgets('Esc closes the list until the next word', (tester) async {
    final controller = await openEditor(tester);
    await type(tester, controller, 'Yukarıda aç');
    expect(list, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(list, findsNothing);
    await type(tester, controller, 'ık');
    expect(list, findsNothing);
    await type(tester, controller, 'lanan nedenlerle. Davanın kab');
    expect(list, findsOneWidget);
  });

  testWidgets('a phrase from two saved documents is offered, with how many', (
    tester,
  ) async {
    const phrase = 'Müvekkilin kiracı olduğu taşınmazda tespit yapılmasını';
    memory.learnSaved('/a.udf', phrase);
    memory.learnSaved('/b.udf', phrase);
    final controller = await openEditor(tester);
    await type(tester, controller, 'Müvekkilin kir');
    expect(find.text('2 belgede'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(body(controller), phrase);
    expect(memory.phrases.single.accepted, 1);
  });

  testWidgets('turned off in the settings, nothing is suggested', (
    tester,
  ) async {
    // Set directly: saving it writes a file, which a widget test cannot wait on.
    EditorSettings.instance.suggestions = false;
    final controller = await openEditor(tester);
    await type(tester, controller, 'Borçlu hakkında icra');
    expect(list, findsNothing);
    // Tab is a tab again.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      controller.document.toPlainText(),
      startsWith('Borçlu hakkında icra\t'),
    );
  });
}
