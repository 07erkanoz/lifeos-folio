import 'dart:io';

import 'package:evrak_convert/services/editor/document_history.dart';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/temp_directory.dart';

import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/ui/home_page.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/document_ruler.dart';
import 'package:evrak_convert/ui/widgets/document_preview_widget.dart';
import 'package:evrak_convert/ui/widgets/drop_zone.dart';
import 'package:evrak_convert/services/desktop/desktop_companion.dart';

// Navigation tests exercise the real source document but not native PDF textures.
class _NoPdfRenderer extends Fake implements PdfrxEntryFunctions {
  @override
  Future<void> init() async {}
  @override
  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    bool allowDataOwnershipTransfer = false,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async =>
      throw UnsupportedError('Native rendering is covered by Linux UI checks');
}

class _Picker extends FilePickerPlatform {
  String? target;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => target;
}

Future<void> ready(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 150 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

Future<void> click(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
    PdfrxEntryFunctions.instance = _NoPdfRenderer();
  });
  testWidgets(
    'preview, external document and back navigation honor save/discard/cancel',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-draft-ui-'),
      ))!;
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      final original = File('${dir.path}/original.udf');
      final other = File('${dir.path}/other.udf');
      await tester.runAsync(() async {
        for (final file in [original, other]) {
          await file.writeAsBytes(
            UdfWriter.writeBytes(
              DocModel(blocks: [DocBlock(plainText: 'Özgün belge')]),
            ),
          );
        }
      });
      final library = LibraryController(
        databasePath: '${dir.path}/index.sqlite',
        watchFolders: false,
      );
      await tester.pumpWidget(
        EvrakConvertApp(initialPaths: [original.path], library: library),
      );
      await ready(tester, () => find.text('Düzenle').evaluate().isNotEmpty);

      // Closing to the tray while reading and coming back must land on the
      // homepage. `_showLibrary` alone only restores the side panel: the
      // document area keeps drawing whatever is selected, so the file being
      // read used to reappear beside the archive every time. The opposite case
      // — an editor holding changes, which has to stay mounted or lose the
      // draft — is asserted further down, where hasChanges survives this call.
      tester.state<HomePageState>(find.byType(HomePage)).showHomeFromTray();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byType(DocumentPreviewWidget, skipOffstage: false),
        findsNothing,
        reason: 'tepsiden dönünce okunan belge ekranda kalmamalı',
      );
      tester
          .widget<DropZoneOverlay>(find.byType(DropZoneOverlay))
          .onFilesDropped([original.path]);
      await ready(tester, () => find.text('Düzenle').evaluate().isNotEmpty);

      await click(tester, 'Düzenle');
      await ready(tester, () => find.byType(QuillEditor).evaluate().isNotEmpty);
      final controller = tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller;
      final draft = tester
          .widget<EditorWidget>(find.byType(EditorWidget))
          .draft!;
      expect(draft.hasChanges, false);
      controller.updateSelection(
        const TextSelection.collapsed(offset: 3),
        ChangeSource.local,
      );
      expect(draft.hasChanges, false);
      await click(tester, 'Önizlemeye Dön');
      expect(find.byType(AlertDialog), findsNothing);
      await click(tester, 'Düzenle');
      controller.replaceText(
        0,
        0,
        'Yeni ',
        const TextSelection.collapsed(offset: 5),
      );
      expect(draft.hasChanges, true);
      tester.state<HomePageState>(find.byType(HomePage)).showHomeFromTray();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Evraklarınız. Tek bir yerde.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(draft.hasChanges, true);
      expect(controller.document.toPlainText(), startsWith('Yeni '));
      tester
          .widget<DropZoneOverlay>(find.byType(DropZoneOverlay))
          .onFilesDropped([original.path]);
      await ready(tester, () => find.text('Düzenle').evaluate().isNotEmpty);
      await click(tester, 'Düzenle');
      expect(
        identical(
          tester.widget<QuillEditor>(find.byType(QuillEditor)).controller,
          controller,
        ),
        isTrue,
      );
      expect(draft.hasChanges, true);
      await click(tester, 'Önizlemeye Dön');
      expect(find.text('Değişiklikler kaydedilsin mi?'), findsOneWidget);
      await click(tester, 'Vazgeç');
      expect(find.byType(EditorWidget), findsOneWidget);
      expect(controller.document.toPlainText(), startsWith('Yeni '));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Kaydetmeden çık'), findsOneWidget);
      await click(tester, 'Vazgeç');
      await click(tester, 'Önizlemeye Dön');
      await click(tester, 'Kaydet');
      await ready(tester, () => find.text('Düzenle').evaluate().isNotEmpty);
      expect(draft.hasChanges, false);
      expect(
        (await tester.runAsync(() async => UdfReader.readFile(original.path)))!
            .toPlainText(),
        'Yeni Özgün belge',
      );
      expect(find.byType(DocumentPreviewWidget), findsOneWidget);
      await click(tester, 'Düzenle');
      controller.replaceText(
        0,
        0,
        'SİL ',
        const TextSelection.collapsed(offset: 4),
      );
      tester
          .widget<DropZoneOverlay>(find.byType(DropZoneOverlay))
          .onFilesDropped([other.path]);
      await tester.pumpAndSettle();
      await click(tester, 'Vazgeç');
      expect(find.byType(EditorWidget), findsOneWidget);
      tester
          .widget<DropZoneOverlay>(find.byType(DropZoneOverlay))
          .onFilesDropped([other.path]);
      await tester.pumpAndSettle();
      await click(tester, 'Kaydetmeden çık');
      await ready(
        tester,
        () => find.byType(DocumentPreviewWidget).evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<DocumentPreviewWidget>(find.byType(DocumentPreviewWidget))
            .file
            .path,
        other.path,
      );
      expect(controller.document.toPlainText(), 'Yeni Özgün belge\n');
      expect(draft.hasChanges, false);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async => library.dispose());
      await removeTemporaryDirectory(tester, dir);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('a document saved under a new name is shown by its new name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final picker = _Picker();
    final old = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = old);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-save-as-'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final original = File('${dir.path}/eski.udf');
    await tester.runAsync(
      () => original.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'Özgün belge')]),
        ),
      ),
    );
    final library = LibraryController(
      databasePath: '${dir.path}/index.sqlite',
      watchFolders: false,
    );
    await tester.pumpWidget(
      EvrakConvertApp(initialPaths: [original.path], library: library),
    );
    await ready(tester, () => find.text('Düzenle').evaluate().isNotEmpty);
    await click(tester, 'Düzenle');
    await ready(tester, () => find.byType(QuillEditor).evaluate().isNotEmpty);
    String title() => tester
        .widget<Text>(find.byKey(const ValueKey('workspace-title')))
        .data!;
    expect(title(), 'eski.udf');
    tester
        .widget<QuillEditor>(find.byType(QuillEditor).first)
        .controller
        .replaceText(0, 0, 'Yeni ', const TextSelection.collapsed(offset: 5));
    picker.target = '${dir.path}/yeni.udf';
    await click(tester, 'Dosya');
    await click(tester, 'Farklı kaydet…');
    await ready(
      tester,
      () => find
          .textContaining('Başarıyla kaydedildi: yeni.udf')
          .evaluate()
          .isNotEmpty,
    );
    expect(title(), 'yeni.udf');
    await tester.pumpWidget(const SizedBox.shrink());
    await removeTemporaryDirectory(tester, dir);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'canceled or failed saves keep new document dirty; undo and ruler discard restore clean state',
    (tester) async {
      final drafts = EditorDrafts();
      final draft = drafts.draft('new', 'Yeni evrak');
      final picker = _Picker();
      final old = FilePickerPlatform.instance;
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = old);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          home: Scaffold(body: EditorWidget(draft: draft)),
        ),
      );
      await tester.pump();
      final controller = tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller;
      controller.replaceText(
        0,
        0,
        'Taslak',
        const TextSelection.collapsed(offset: 6),
      );
      controller.undo();
      expect(draft.hasChanges, false);
      controller.redo();
      expect(draft.hasChanges, true);
      // The title bar's unsaved dot follows once typing pauses.
      await tester.pump(const Duration(milliseconds: 350));
      expect(draft.edited.value, isTrue);
      final context = tester.element(find.byType(EditorWidget));
      final canceled = drafts.confirm(context);
      await tester.pumpAndSettle();
      await click(tester, 'Kaydet');
      expect(await canceled, false);
      expect(draft.hasChanges, true);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-save-fail-'),
      ))!;
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      picker.target = '${dir.path}/missing/document.udf';
      final failed = drafts.confirm(context);
      await tester.pumpAndSettle();
      await click(tester, 'Kaydet');
      await ready(
        tester,
        () => find.textContaining('Kaydetme hatası:').evaluate().isNotEmpty,
      );
      expect(await failed, false);
      expect(draft.hasChanges, true);
      final discarded = drafts.confirm(context);
      await tester.pumpAndSettle();
      await click(tester, 'Kaydetmeden çık');
      var didDiscard = false;
      discarded.then((_) => didDiscard = true);
      await ready(tester, () => didDiscard);
      expect(await discarded, true);
      expect(controller.document.toPlainText(), '\n');
      expect(draft.hasChanges, false);
      await tester.pump(const Duration(milliseconds: 350));
      expect(draft.edited.value, isFalse);
      final ruler = tester
          .widgetList<DocumentRuler>(find.byType(DocumentRuler))
          .firstWhere((r) => r.axis == Axis.horizontal);
      ruler.onChanged(ruler.leading + 36, ruler.trailing);
      await tester.pump();
      expect(draft.hasChanges, true);
      await tester.pump(const Duration(milliseconds: 350));
      expect(draft.edited.value, isTrue);
      var clean = false;
      draft.discard!().then((_) => clean = true);
      await ready(tester, () => clean);
      await tester.pump();
      expect(draft.hasChanges, false);
      await tester.pumpWidget(const SizedBox.shrink());
      await removeTemporaryDirectory(tester, dir);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'window close and tray quit cannot bypass canceled draft decisions',
    (tester) async {
      final calls = <String>[];
      var approved = false;
      var checks = 0;
      for (final name in [
        'window_manager',
        'tray_manager',
        'com.erkanoz.folio/quick_search',
      ]) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel(name),
          (call) async {
            calls.add('$name:${call.method}');
            return null;
          },
        );
      }
      final companion = DesktopCompanion(
        beforeClose: () async {
          checks++;
          return approved;
        },
      );
      companion.onWindowClose();
      await tester.pumpAndSettle();
      await companion.quit();
      expect(checks, 2);
      expect(calls.where((value) => value.endsWith(':destroy')), isEmpty);
      approved = true;
      await companion.quit();
      expect(calls, contains('window_manager:destroy'));
      companion.dispose();
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
