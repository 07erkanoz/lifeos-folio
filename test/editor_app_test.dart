import 'dart:io';

import 'package:evrak_convert/editor_app.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_shortcuts_test.dart' show waitFor;
import 'support/fake_path_provider.dart';
import 'support/temp_directory.dart';

class _Picker extends FilePickerPlatform {
  String? answer;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async {
    final path = answer;
    if (path == null) return null;
    return FilePickerResult([
      PlatformFile(
        path: path,
        name: path.split(RegExp(r'[\\/]')).last,
        size: 0,
      ),
    ]);
  }
}

void main() {
  test('the editor opens what its text editor edits, and nothing else', () {
    for (final format in [
      EvrakFormat.udf,
      EvrakFormat.docx,
      EvrakFormat.rtf,
      EvrakFormat.text,
      EvrakFormat.pdf,
    ]) {
      expect(opensInEditor(format), isTrue, reason: '$format');
    }
    expect(opensInEditor(EvrakFormat.spreadsheet), isFalse);
    expect(opensInEditor(EvrakFormat.image), isFalse);
    expect(editorTitle(null), 'LifeOS Editör');
    expect(editorTitle('/a/dilekce.udf'), 'dilekce.udf — LifeOS Editör');
  });

  testWidgets('LifeOS Editör starts on a blank UDF, opens a document with '
      'Ctrl+O, and asks about unsaved work before Ctrl+N', (tester) async {
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    useFakePathProvider();
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-editor-app-'),
    ))!;
    final previous = DocumentHistory.instance;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    addTearDown(() => DocumentHistory.instance = previous);
    final picker = _Picker();
    final kept = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = kept);
    final file = File('${dir.path}/dilekce.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'AÇILAN DİLEKÇE')]),
        ),
      ),
    );

    await tester.pumpWidget(const EditorApp());
    await waitFor(tester, () => find.byType(QuillEditor).evaluate().isNotEmpty);
    expect(find.byKey(const ValueKey('standalone-editor-0')), findsOneWidget);
    QuillController controller() =>
        tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
    // While a document loads the editor shows a spinner instead.
    String text() => find.byType(QuillEditor).evaluate().isEmpty
        ? ''
        : controller().document.toPlainText();
    expect(controller().document.toPlainText().trim(), isEmpty);

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    picker.answer = file.path;
    await press(LogicalKeyboardKey.keyO);
    await waitFor(
      tester,
      () =>
          find
              .byKey(const ValueKey('standalone-editor-1'))
              .evaluate()
              .isNotEmpty &&
          text().contains('AÇILAN DİLEKÇE'),
    );

    controller().replaceText(
      0,
      0,
      'Ek: ',
      const TextSelection.collapsed(offset: 4),
    );
    await tester.pump();
    await press(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(find.text('Değişiklikler kaydedilsin mi?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(controller().document.toPlainText(), startsWith('Ek: AÇILAN'));

    await press(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydetmeden çık'));
    await waitFor(
      tester,
      () => find
          .byKey(const ValueKey('standalone-editor-2'))
          .evaluate()
          .isNotEmpty,
    );
    expect(controller().document.toPlainText().trim(), isEmpty);

    await tester.pumpWidget(const SizedBox());
    // The draft writer's timer, left from the edit made above.
    await tester.pump(const Duration(seconds: 15));
    await removeTemporaryDirectory(tester, dir);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
