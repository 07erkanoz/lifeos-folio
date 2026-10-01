import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/new_document_dialog.dart';

class _Picker extends FilePickerPlatform {
  String? target, suggested;
  List<String>? extensions;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    suggested = fileName;
    extensions = allowedExtensions;
    return target;
  }
}

Future<void> ready(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), true);
}

Future<void> click(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'home creates UDF, DOCX and TXT with matching first-save bytes; cancel preserves draft',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-new-'),
      ))!;
      final history = DocumentHistory.instance;
      final oldPicker = FilePickerPlatform.instance;
      final picker = _Picker();
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      FilePickerPlatform.instance = picker;
      addTearDown(() {
        DocumentHistory.instance = history;
        FilePickerPlatform.instance = oldPicker;
      });
      await tester.pumpWidget(const EvrakConvertApp());
      await tester.pumpAndSettle();
      await click(tester, 'Yeni belge oluştur');
      await click(tester, 'Vazgeç');
      expect(find.byType(EditorWidget), findsNothing);
      for (final option in [
        (EvrakFormat.udf, 'UDF belgesi'),
        (EvrakFormat.docx, 'Word belgesi'),
        (EvrakFormat.text, 'Metin belgesi'),
      ]) {
        await click(tester, 'Yeni belge oluştur');
        await click(tester, option.$2);
        await click(tester, 'Oluştur');
        await ready(
          tester,
          () => find.byType(QuillEditor).evaluate().isNotEmpty,
        );
        final editor = tester.widget<EditorWidget>(find.byType(EditorWidget));
        expect(editor.initialFormat, option.$1);
        expect(
          find.byTooltip('UDF e-imzala'),
          option.$1 == EvrakFormat.udf ? findsOneWidget : findsNothing,
        );
        if (option.$1 == EvrakFormat.udf) {
          // Canceling the required first save must never open card/PIN UI.
          await tester.tap(find.byTooltip('UDF e-imzala'));
          await tester.pump();
          await ready(
            tester,
            () =>
                tester
                    .widget<IconButton>(
                      find.byWidgetPredicate(
                        (w) => w is IconButton && w.tooltip == 'UDF e-imzala',
                      ),
                    )
                    .onPressed !=
                null,
          );
          expect(picker.suggested, endsWith('.udf'));
          expect(find.text('UDF belgesini imzala'), findsNothing);
        }
        final controller = tester
            .widget<QuillEditor>(find.byType(QuillEditor))
            .controller;
        controller.replaceText(
          0,
          0,
          'Yeni belge Türkçe içerik',
          const TextSelection.collapsed(offset: 23),
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.byType(NewDocumentDialog), findsOneWidget);
        await click(tester, 'Vazgeç');
        expect(controller.document.toPlainText(), contains('Türkçe içerik'));
        picker.target = '${dir.path}/created.${option.$1.defaultExtension}';
        await tester.tap(find.byTooltip('Kaydet · Ctrl+S'));
        await tester.pump();
        await ready(
          tester,
          () =>
              tester
                  .widget<IconButton>(
                    find.byWidgetPredicate(
                      (w) => w is IconButton && w.tooltip == 'Kaydet · Ctrl+S',
                    ),
                  )
                  .onPressed !=
              null,
        );
        expect(picker.suggested, endsWith('.${option.$1.defaultExtension}'));
        expect(picker.extensions, [option.$1.defaultExtension]);
        final bytes = (await tester.runAsync(
          () => File(picker.target!).readAsBytes(),
        ))!;
        if (option.$1 == EvrakFormat.text) {
          expect(utf8.decode(bytes), contains('Türkçe içerik'));
        } else {
          final archive = ZipDecoder().decodeBytes(bytes);
          final xml = archive.findFile(
            option.$1 == EvrakFormat.udf ? 'content.xml' : 'word/document.xml',
          );
          expect(xml, isNotNull);
          expect(
            utf8.decode(xml!.content as List<int>),
            contains('Türkçe içerik'),
          );
        }
        await tester.tap(find.byTooltip('Arşive dön'));
        await tester.pumpAndSettle();
        expect(find.text('Değişiklikler kaydedilsin mi?'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('format chooser fits narrow phones in white and black themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      EvrakFormat? chosen;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  chosen = await showDialog<EvrakFormat>(
                    context: context,
                    builder: (_) => const NewDocumentDialog(),
                  );
                },
                child: const Text('Yeni belge'),
              ),
            ),
          ),
        ),
      );
      await click(tester, 'Yeni belge');
      await click(tester, 'Word belgesi');
      await click(tester, 'Oluştur');
      expect(chosen, EvrakFormat.docx);
      expect(tester.takeException(), isNull);
    }
  });
}
