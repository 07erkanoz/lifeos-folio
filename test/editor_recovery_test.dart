import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/plain_text_editor.dart';
import 'package:evrak_convert/ui/widgets/document_ruler.dart';
import 'package:evrak_convert/ui/widgets/document_history_dialog.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';

/// The body editor, told apart from the cell editors a table brings with it.
QuillController body(WidgetTester tester) => tester
    .widgetList<QuillEditor>(find.byType(QuillEditor))
    .firstWhere((e) => e.focusNode.debugLabel == 'document-editor')
    .controller;

/// Where the first table sits in the body text.
int tableAt(QuillController controller) {
  var offset = 0;
  for (final op in controller.document.toDelta().toList()) {
    final data = op.data;
    if (data is Map && data.containsKey(DocDeltaMap.kTableEmbed)) return offset;
    offset += op.length ?? 0;
  }
  return -1;
}

Widget app(Widget child, {bool dark = false}) => MaterialApp(
  theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    FlutterQuillLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);
Future<void> ready(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 150 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(condition(), true);
}

Future<T> io<T>(WidgetTester tester, Future<T> Function() action) async {
  var done = false;
  T? value;
  Object? error;
  action().then(
    (result) {
      value = result;
      done = true;
    },
    onError: (Object e) {
      error = e;
      done = true;
    },
  );
  await ready(tester, () => done);
  if (error != null) throw error!;
  return value as T;
}

Future<DocumentRevision> autosave(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 11));
  List<DocumentRevision>? entries;
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    // The editor is still open, and an open editor's draft is not offered
    // for recovery; the test looks at it all the same.
    entries = await io(
      tester,
      () => DocumentHistory.instance.recoveries(includeOpen: true),
    );
    if (entries!.isNotEmpty) break;
  }
  expect(entries, hasLength(1));
  return entries!.single;
}

void main() {
  testWidgets(
    'crash recovery preserves exact rich delta, margins and noncontiguous table references; history restores as an unsaved edit',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-rich-recovery-'),
      ))!;
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      final source = File('${dir.path}/belge.udf');
      DocBlock table(String value) => DocBlock(
        type: DocBlockType.table,
        plainText: '',
        table: DocTable(
          columnWidths: [120],
          rows: [
            DocTableRow(
              cells: [
                DocTableCell(blocks: [DocBlock(plainText: value)]),
              ],
            ),
          ],
        ),
      );
      final original = UdfWriter.writeBytes(
        DocModel(
          blocks: [
            DocBlock(plainText: 'Özgün'),
            table('Birinci tablo'),
            table('İkinci tablo'),
          ],
        ),
      );
      await tester.runAsync(() => source.writeAsBytes(original));
      var draft = EditorDraft('belge.udf');
      await tester.pumpWidget(
        app(
          EditorWidget(
            initialFilePath: source.path,
            initialFormat: EvrakFormat.udf,
            draft: draft,
          ),
        ),
      );
      await ready(tester, () => find.byType(QuillEditor).evaluate().isNotEmpty);
      var controller = body(tester);
      final index = tableAt(controller);
      expect(index, greaterThanOrEqualTo(0));
      // The embed and the newline that ends its line.
      controller.replaceText(
        index,
        2,
        '',
        TextSelection.collapsed(offset: index),
      );
      controller.replaceText(
        0,
        0,
        'Yeni ',
        const TextSelection.collapsed(offset: 5),
      );
      final ruler = tester
          .widgetList<DocumentRuler>(find.byType(DocumentRuler))
          .first;
      ruler.onChanged(ruler.leading + 12, ruler.trailing);
      final expected = jsonEncode(controller.document.toDelta().toJson());
      final recovery = await autosave(tester);
      expect(await tester.runAsync(source.readAsBytes), original);
      await tester.pumpWidget(
        const SizedBox.shrink(),
      ); // Abrupt disposal: no Save/Discard.
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      draft = EditorDraft('belge.udf');
      await tester.pumpWidget(
        app(
          EditorWidget(
            initialFilePath: source.path,
            initialFormat: EvrakFormat.udf,
            recovery: recovery,
            draft: draft,
          ),
        ),
      );
      await ready(
        tester,
        () =>
            draft.hasChanges && find.byType(QuillEditor).evaluate().isNotEmpty,
      );
      controller = body(tester);
      expect(jsonEncode(controller.document.toDelta().toJson()), expected);
      expect(await io(tester, () => draft.save!()), true);
      await tester.pump();
      final saved = await tester.runAsync(
        () async => UdfReader.readFile(source.path)!,
      );
      expect(saved!.toPlainText(), contains('İkinci tablo'));
      expect(saved.toPlainText(), isNot(contains('Birinci tablo')));
      expect(saved.pageProperties.marginLeft, closeTo(ruler.leading + 12, .01));
      expect(
        await io(
          tester,
          () => DocumentHistory.instance.recoveries(includeOpen: true),
        ),
        isEmpty,
      );
      await tester.tap(find.byTooltip('Belge geçmişi'));
      await tester.pump();
      const before = 'Üzerine yazılmadan önceki hali';
      await ready(
        tester,
        () => find.textContaining(before).evaluate().isNotEmpty,
      );
      await tester.tap(find.textContaining(before).first);
      await tester.pump();
      // The window opens on the comparison with what the editor holds.
      await ready(
        tester,
        () => find.textContaining('kelime eklenmiş').evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('restore-version')));
      await tester.pump();
      await ready(
        tester,
        () =>
            draft.hasChanges && find.byType(QuillEditor).evaluate().isNotEmpty,
      );
      expect(controller.document.toPlainText(), startsWith('Özgün'));
      expect(
        (await tester.runAsync(() async => UdfReader.readFile(source.path)!))!
            .toPlainText(),
        startsWith('Yeni'),
      );
      await io(tester, () => draft.discard!());
      await tester.pump();
      expect(controller.document.toPlainText(), startsWith('Yeni'));
      expect(draft.hasChanges, false);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
  testWidgets(
    'a never-saved document is recoverable and explicit discard removes the draft',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-new-recovery-'),
      ))!;
      DocumentHistory.instance = DocumentHistory(directory: dir);
      var draft = EditorDraft('Yeni evrak');
      await tester.pumpWidget(app(EditorWidget(draft: draft)));
      final controller = tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller;
      controller.replaceText(
        0,
        0,
        'Kaydedilmemiş çalışma',
        const TextSelection.collapsed(offset: 10),
      );
      final entry = await autosave(tester);
      expect(entry.sourcePath, null);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      draft = EditorDraft('Yeni evrak');
      await tester.pumpWidget(app(EditorWidget(recovery: entry, draft: draft)));
      await ready(tester, () => draft.hasChanges);
      expect(
        tester
            .widget<QuillEditor>(find.byType(QuillEditor))
            .controller
            .document
            .toPlainText(),
        'Kaydedilmemiş çalışma\n',
      );
      await io(tester, () => draft.discard!());
      expect(
        await io(
          tester,
          () => DocumentHistory.instance.recoveries(includeOpen: true),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
  testWidgets(
    'source text recovery works after the source disappears; recovery list fits phone light and black themes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-text-recovery-'),
      ))!;
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      final source = File('${dir.path}/ornek.json');
      await tester.runAsync(() => source.writeAsString('{"eski":true}'));
      await tester.pumpWidget(app(PlainTextEditor(path: source.path)));
      await ready(tester, () => find.byType(TextField).evaluate().isNotEmpty);
      await tester.enterText(find.byType(TextField), '{"yeni":true}');
      final entry = await autosave(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(source.delete);
      final draft = EditorDraft('ornek.json');
      await tester.pumpWidget(
        app(PlainTextEditor(path: source.path, recovery: entry, draft: draft)),
      );
      await ready(tester, () => draft.hasChanges);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '{"yeni":true}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showRecoverableDrafts(context),
                child: const Text('Kurtarma'),
              ),
            ),
            dark: dark,
          ),
        );
        await tester.tap(find.text('Kurtarma'));
        await tester.pump();
        await ready(
          tester,
          () => find.text('ornek.json').evaluate().isNotEmpty,
        );
        expect(tester.takeException(), null);
        await tester.tap(find.text('Kapat'));
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
  testWidgets(
    'reopening a file after a crash keeps its draft and offers it quietly',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-left-draft-'),
      ))!;
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      final source = File('${dir.path}/dilekce.udf');
      await tester.runAsync(
        () => source.writeAsBytes(
          UdfWriter.writeBytes(
            DocModel(blocks: [DocBlock(plainText: 'Kayıtlı metin')]),
          ),
        ),
      );
      Widget editor() => app(
        EditorWidget(
          initialFilePath: source.path,
          initialFormat: EvrakFormat.udf,
        ),
      );
      await tester.pumpWidget(editor());
      await ready(tester, () => find.byType(QuillEditor).evaluate().isNotEmpty);
      body(tester).replaceText(
        0,
        0,
        'Çökmeden önce ',
        const TextSelection.collapsed(offset: 14),
      );
      final crashed = await autosave(tester);
      // The crash: the editor goes without a word about its changes.
      await tester.pumpWidget(const SizedBox.shrink());

      await tester.pumpWidget(editor());
      final button = find.byKey(const ValueKey('left-draft'));
      await ready(tester, () => button.evaluate().isNotEmpty);
      expect(find.byType(SnackBar), findsNothing);
      // Minimising the window writes out the new session's draft. The two
      // sessions used to share one slot, and this deleted the crash's draft
      // before anyone had looked at it.
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        (await io(tester, DocumentHistory.instance.recoveries)).map(
          (e) => e.id,
        ),
        [crashed.id],
      );

      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Taslağı aç'));
      await tester.pump();
      await ready(
        tester,
        () =>
            // The editor gives way to a spinner while the draft is read.
            find.byType(QuillEditor).evaluate().isNotEmpty &&
            body(tester).document.toPlainText().startsWith('Çökmeden önce') &&
            button.evaluate().isEmpty,
      );
      // Taken over: the crash's slot is gone once this editor's own is
      // written, and an open editor's draft is not offered for recovery...
      expect(await io(tester, DocumentHistory.instance.recoveries), isEmpty);
      // ...until this editor, too, goes without a word.
      await tester.pumpWidget(const SizedBox.shrink());
      final left = await io(tester, DocumentHistory.instance.recoveries);
      expect(left, hasLength(1));
      expect(left.single.id, isNot(crashed.id));
      expect(left.single.sourcePath, source.path);
      await tester.pumpAndSettle();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
