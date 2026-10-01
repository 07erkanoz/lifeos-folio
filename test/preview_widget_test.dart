import 'dart:io';
import 'dart:typed_data';

import 'package:evrak_convert/services/editor/document_history.dart';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/drop_zone.dart';
import 'package:evrak_convert/ui/widgets/document_preview_widget.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/image_viewer_widget.dart';
import 'package:evrak_convert/ui/widgets/signature_banner.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/udf/signature_parser.dart';

class _SignedSavePicker extends FilePickerPlatform {
  String target;
  int calls = 0;
  _SignedSavePicker(this.target);
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
    calls++;
    return target;
  }
}

void main() {
  testWidgets(
    'external file launch opens full-width preview with panels opt-in',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-external-'),
      ))!;
      final file = File('${dir.path}/document.png');
      await tester.runAsync(
        () =>
            file.writeAsBytes(img.encodePng(img.Image(width: 30, height: 60))),
      );
      await tester.pumpWidget(EvrakConvertApp(initialPaths: [file.path]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(EditorWidget), findsNothing);
      expect(tester.getSize(find.byType(ImageViewerWidget)).width, 1400);
      expect(find.byTooltip('Sonuçları göster'), findsOneWidget);
      await tester.tap(find.byTooltip('Sonuçları göster'));
      await tester.pump();
      expect(
        tester.getSize(find.byType(ImageViewerWidget)).width,
        lessThan(1200),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );

  testWidgets(
    'signed editor warns only on first confirmed save and preserves source',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('signed-editor-'),
      ))!;
      final history = DocumentHistory.instance;
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      addTearDown(() => DocumentHistory.instance = history);
      final archive = ZipDecoder().decodeBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'İmzalı belge')]),
        ),
      );
      archive.addFile(ArchiveFile('sign.sgn', 3, [1, 2, 3]));
      final original = ZipEncoder().encode(archive);
      final file = File('${dir.path}/signed.udf');
      await tester.runAsync(() => file.writeAsBytes(original));
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
      for (
        var i = 0;
        i < 100 &&
            find.byKey(const ValueKey('editor-file-menu')).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('imza kaybolur'), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('editor-toolbar'))).height,
        88,
      );
      expect(tester.getSize(find.byType(SignatureBanner)).height, 32);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('editor-toolbar'))).height,
        44,
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(1400, 1000);
      await tester.pump();
      final output = File('${dir.path}/unsigned.udf');
      final picker = _SignedSavePicker(output.path);
      FilePickerPlatform.instance = picker;
      Future<void> save() async {
        await tester.tap(find.byKey(const ValueKey('editor-file-menu')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('UYAP UDF Olarak Kaydet'));
        // Save now has a busy indicator until the confirmation or I/O completes.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Saving disables the save button until the write and the history
      // snapshot are done.
      bool saveEnabled() =>
          tester
              .widget<IconButton>(
                find.ancestor(
                  of: find.byTooltip('Kaydet · Ctrl+S'),
                  matching: find.byType(IconButton),
                ),
              )
              .onPressed !=
          null;

      Future<void> waitForFile(File file) async {
        for (var i = 0; i < 300; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
          if (saveEnabled() && await tester.runAsync(file.exists) == true) {
            break;
          }
        }
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          saveEnabled(),
          true,
          reason: 'Save and history snapshots must complete',
        );
        expect(await tester.runAsync(file.exists), true);
      }

      await save();
      expect(find.text(SignatureBanner.saveNotice), findsOneWidget);
      expect(picker.calls, 0);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(picker.calls, 0);
      expect(await tester.runAsync(output.exists), isFalse);
      await save();
      expect(find.text('İmzasız kopya kaydedilecek'), findsOneWidget);
      await tester.tap(find.text('Anladım, kaydet'));
      await waitForFile(output);
      expect(picker.calls, 1);
      final savedBytes = (await tester.runAsync(output.readAsBytes))!;
      expect(ZipDecoder().decodeBytes(savedBytes).findFile('sign.sgn'), isNull);
      final second = File('${dir.path}/second.udf');
      picker.target = second.path;
      await save();
      expect(find.byType(AlertDialog), findsNothing);
      await waitForFile(second);
      expect(picker.calls, 2);
      // Picking the signed original itself asks first, and a no leaves it.
      picker.target = file.path;
      await save();
      for (
        var i = 0;
        i < 100 &&
            find
                .text('İmzalı dosyanın üzerine yazılsın mı?')
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('İmzalı dosyanın üzerine yazılsın mı?'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(await tester.runAsync(file.readAsBytes), original);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );

  testWidgets('signature details show signer and certificate information', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignatureBanner(
            model: DocModel(
              blocks: [],
              metadata: {
                'hasSignature': true,
                'signatureInfos': [
                  UdfSignatureInfo(
                    signerName: 'Test İmzacı Şule',
                    issuerName: 'Test Sağlayıcı',
                    organization: 'Test Kurum',
                    certificateSerial: 'AB12',
                    signedAt: DateTime.utc(2026, 9, 10, 10),
                  ),
                ],
              },
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Test İmzacı Şule'), findsOneWidget);
    await tester.tap(find.text('Ayrıntılar'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Sertifika sağlayıcısı: Test Sağlayıcı'),
      findsOneWidget,
    );
    expect(find.textContaining('Sertifika seri no: AB12'), findsOneWidget);
    expect(
      find.text('Belgede kayıtlı elektronik imza ve sertifika bilgileri.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'UDF defaults to preview; only the separate edit button opens editor',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('evrak-ui-'),
      ))!;
      final file = File('${dir.path}/belge.udf');
      await tester.runAsync(
        () => file.writeAsBytes(
          UdfWriter.writeBytes(
            DocModel(blocks: [DocBlock(plainText: 'Türkçe belge')]),
          ),
        ),
      );
      await tester.pumpWidget(const EvrakConvertApp());
      tester
          .widget<DropZoneOverlay>(find.byType(DropZoneOverlay))
          .onFilesDropped([file.path]);
      await tester.pump();
      expect(find.byType(DocumentPreviewWidget), findsOneWidget);
      expect(find.byType(EditorWidget), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      final previewRect = tester.getRect(find.byType(DocumentPreviewWidget));
      expect(previewRect.left, greaterThan(300));
      expect(previewRect.top, lessThan(60));
      expect(previewRect.height, greaterThan(900));
      final previewState = tester.state(find.byType(DocumentPreviewWidget));
      await tester.tap(find.byTooltip('Önizlemeyi genişlet'));
      await tester.pump();
      expect(tester.getRect(find.byType(DocumentPreviewWidget)).width, 1400);
      expect(
        tester.state(find.byType(DocumentPreviewWidget)),
        same(previewState),
      );
      await tester.tap(find.byTooltip('Sonuçları göster'));
      await tester.pump();
      expect(
        tester.state(find.byType(DocumentPreviewWidget)),
        same(previewState),
      );
      await tester.tap(find.text('Düzenle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(EditorWidget), findsOneWidget);
      expect(find.byType(DocumentPreviewWidget), findsNothing);
      for (
        var i = 0;
        i < 150 && find.byType(QuillEditor).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.byType(QuillEditor), findsOneWidget);
      final editorState = tester.state(find.byType(EditorWidget));
      expect(tester.getRect(find.byType(EditorWidget)).width, 1400);
      await tester.tap(find.byTooltip('Sol paneli göster'));
      await tester.pump();
      expect(tester.getRect(find.byType(EditorWidget)).width, lessThan(1100));
      expect(tester.state(find.byType(EditorWidget)), same(editorState));
      await tester.tap(find.byTooltip('Sol paneli gizle'));
      await tester.pump();
      expect(tester.getRect(find.byType(EditorWidget)).width, 1400);
      await tester.tap(find.byTooltip('Sol paneli göster'));
      await tester.pump();
      await tester.tap(find.text('Önizlemeye Dön'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(DocumentPreviewWidget), findsOneWidget);
      expect(find.byType(EditorWidget), findsNothing);
      await tester.tap(find.text('Düzenle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.state(find.byType(EditorWidget)), same(editorState));
      expect(tester.getRect(find.byType(EditorWidget)).width, 1400);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );

  testWidgets(
    'image preview rotates both ways without replacing its image provider',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('evrak-image-ui-'),
      ))!;
      final file = File('${dir.path}/image.png');
      await tester.runAsync(
        () =>
            file.writeAsBytes(img.encodePng(img.Image(width: 30, height: 60))),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ImageViewerWidget(filePath: file.path)),
        ),
      );
      final provider = tester.widget<Image>(find.byType(Image)).image;
      await tester.tap(find.byIcon(Icons.rotate_right_rounded));
      await tester.pump();
      expect(
        tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns,
        1,
      );
      expect(tester.widget<Image>(find.byType(Image)).image, provider);
      await tester.tap(find.byTooltip('Sola 90° döndür'));
      await tester.pump();
      expect(
        tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns,
        0,
      );
      await tester.tap(find.byTooltip('Sola 90° döndür'));
      await tester.pump();
      expect(
        tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns,
        3,
      );
      await tester.tap(find.byIcon(Icons.fit_screen_rounded));
      await tester.pump();
      expect(
        tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns,
        0,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );

  testWidgets('signature banner presents metadata without a validity verdict', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignatureBanner(
            model: DocModel(
              blocks: [],
              metadata: {
                'hasSignature': true,
                'signatureBytes': [1, 2, 3],
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('E-İMZALI'), findsOneWidget);
    expect(find.textContaining('İmza ayrıntıları okunamadı'), findsOneWidget);
    expect(find.textContaining('doğrulan'), findsNothing);
    expect(find.textContaining('geçerli'), findsNothing);
    await tester.tap(find.text('Ayrıntılar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Boyut: 3 bayt'), findsOneWidget);
  });

  testWidgets('a signed document says who signed, when, and how many', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignatureBanner(
            model: DocModel(
              blocks: [],
              metadata: {
                'hasSignature': true,
                'signatureInfos': [
                  UdfSignatureInfo(
                    signerName: 'DENEME AVUKAT',
                    signedAt: DateTime(2026, 9, 25, 10, 5),
                  ),
                  UdfSignatureInfo(
                    signerName: 'İKİNCİ İMZACI',
                    signedAt: DateTime(2026, 9, 26, 14, 30),
                  ),
                ],
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('E-İMZALI'), findsOneWidget);
    final line = find.textContaining('DENEME AVUKAT, İKİNCİ İMZACI');
    expect(line, findsOneWidget);
    // The last signature's declared time, and the count.
    final text = tester.widget<Text>(line).textSpan!.toPlainText();
    expect(text, contains('26.09.2026 14:30'));
    expect(text, contains('2 imza'));
    expect(tester.getSize(find.byType(SignatureBanner)).height, 40);
  });
}
