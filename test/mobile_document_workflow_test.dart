import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/platform/document_launch.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/home_page.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:evrak_convert/ui/widgets/document_preview_widget.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/signature_banner.dart';
import 'package:evrak_convert/ui/widgets/document_ruler.dart';

import 'editor_drafts_test.dart' as helpers;
import 'support/pdfium.dart';

class _NoRenderer extends Fake implements PdfrxEntryFunctions {
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
  }) async => throw UnsupportedError('Native rendering is tested separately');
}

void main() {
  final nativeRenderer = PdfrxEntryFunctions.instance;
  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
    PdfrxEntryFunctions.instance = _NoRenderer();
  });
  test('shell launch preserves edit intent and literal filenames through forwarding', () {
    final launch = DocumentLaunch.parse([
      '--edit',
      '--',
      '-belge.udf',
      'Özel belge.docx',
    ]);
    expect(launch.edit, true);
    expect(DocumentLaunch.parse(launch.arguments).paths, launch.paths);
    expect(DocumentLaunch.parse(launch.arguments).edit, true);
    expect(DocumentLaunch.parse(['--preview', '--', 'a.pdf']).edit, false);
  });
  testWidgets(
    'phone opens signed UDF, hides signing, shares and edits; signature notice is deferred to saving',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-mobile-flow-'),
      ))!;
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      final file = File('${dir.path}/imzali.udf');
      final bytes = UdfWriter.writeBytes(
        DocModel(blocks: [DocBlock(plainText: 'İmzalı örnek belge')]),
      );
      final archive = ZipDecoder().decodeBytes(bytes)
        ..addFile(ArchiveFile('sign.sgn', 3, [1, 2, 3]));
      final signed = ZipEncoder().encode(archive);
      await tester.runAsync(() => file.writeAsBytes(signed));
      final library = LibraryController(
        databasePath: ':memory:',
        watchFolders: false,
      );
      final appearance = ThemeController(
        settingsPath: '${dir.path}/theme.json',
      );
      await tester.pumpWidget(
        EvrakConvertApp(
          library: library,
          appearance: appearance,
          initialPaths: [file.path],
        ),
      );
      await helpers.ready(
        tester,
        () => find.byType(SignatureBanner).evaluate().isNotEmpty,
      );
      expect(find.byType(EditorWidget), findsNothing);
      expect(find.byTooltip('Paylaş'), findsOneWidget);
      await tester.tap(find.byTooltip('Belge işlemleri'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('UDF e-imzala'), findsNothing);
      await tester.tapAt(const Offset(10, 400));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('Düzenle'));
      await helpers.ready(
        tester,
        () =>
            find.byKey(const ValueKey('editor-flowing')).evaluate().isNotEmpty,
      );
      expect(find.byType(DocumentRuler), findsNothing);
      // A phone shows the text flowing at its width, not an A4 sheet; the
      // page is one tap away and back.
      expect(find.byKey(const ValueKey('editor-flowing')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-paper')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('editor-view-switch')));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const ValueKey('editor-flowing')), findsNothing);
      expect(find.byKey(const ValueKey('editor-paper')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('editor-view-switch')));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const ValueKey('editor-flowing')), findsOneWidget);
      expect(find.text('İmzasız kopya kaydedilecek'), findsNothing);
      expect(tester.takeException(), null);
      final editor = tester.widget<EditorWidget>(find.byType(EditorWidget));
      final controller = tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller;
      controller.replaceText(
        0,
        0,
        'Yeni ',
        const TextSelection.collapsed(offset: 5),
      );
      final saving = editor.draft!.save!();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('İmzasız kopya kaydedilecek'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(await saving, false);
      expect(await tester.runAsync(file.readAsBytes), signed);
      await tester.tap(find.text('Önizleme'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('Kaydetmeden çık'));
      await helpers.ready(
        tester,
        () => find.text('Düzenle').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Arşive dön'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Belge aç'), findsOneWidget);
      expect(find.text('Yeni belge'), findsOneWidget);
      await tester.tap(find.byTooltip('Ayarlar'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('E-imza ayarları'), findsNothing);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 350));
      await tester.runAsync(() async {
        library.dispose();
        appearance.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await dir.delete(recursive: true);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'warm shell edit launch opens editor and preview launch returns to preview',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-shell-launch-'),
      ))!;
      DocumentHistory.instance = DocumentHistory(
        directory: Directory('${dir.path}/history'),
      );
      final file = File('${dir.path}/ornek.udf');
      await tester.runAsync(
        () => file.writeAsBytes(
          UdfWriter.writeBytes(
            DocModel(blocks: [DocBlock(plainText: 'Örnek belge')]),
          ),
        ),
      );
      final library = LibraryController(
        databasePath: ':memory:',
        watchFolders: false,
      );
      final appearance = ThemeController(
        settingsPath: '${dir.path}/theme.json',
      );
      final launches = StreamController<List<String>>();
      await tester.pumpWidget(
        EvrakConvertApp(library: library, appearance: appearance),
      );
      // Keep app localization/theme; replace only HomePage with its launch stream.
      final app = tester.widget<EvrakConvertApp>(find.byType(EvrakConvertApp));
      expect(app.initialEdit, false);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [FlutterQuillLocalizations.delegate],
          home: HomePage(
            appearance: appearance,
            library: library,
            desktopLaunches: launches.stream,
          ),
        ),
      );
      launches.add(['--edit', '--', file.path]);
      await helpers.ready(
        tester,
        () => find.byType(QuillEditor).evaluate().isNotEmpty,
      );
      expect(find.text('Önizlemeye Dön'), findsOneWidget);
      launches.add(['--preview', '--', file.path]);
      await helpers.ready(
        tester,
        () => find.text('Düzenle').evaluate().isNotEmpty,
      );
      expect(find.byType(DocumentPreviewWidget), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 350));
      await tester.runAsync(() async {
        await launches.close();
        library.dispose();
        appearance.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await dir.delete(recursive: true);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
  testWidgets(
    'PDF edit imports its text only after the fidelity warning is accepted',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-pdf-edit-'),
      ))!;
      final file = File('${dir.path}/ornek.pdf');
      await tester.runAsync(
        () async => file.writeAsBytes(
          await File('test/fixtures/unembedded_turkish.pdf').readAsBytes(),
        ),
      );
      final library = LibraryController(
        databasePath: ':memory:',
        watchFolders: false,
      );
      final appearance = ThemeController(
        settingsPath: '${dir.path}/theme.json',
      );
      await tester.pumpWidget(
        EvrakConvertApp(
          library: library,
          appearance: appearance,
          initialPaths: [file.path],
          initialEdit: true,
        ),
      );
      await helpers.ready(
        tester,
        () => find.text('PDF metnini düzenle').evaluate().isNotEmpty,
      );
      expect(find.text('PDF metnini düzenle'), findsOneWidget);
      expect(find.text('Metni düzenlemeye aktar'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(find.byType(EditorWidget), findsNothing);

      await tester.tap(find.text('Düzenle').first);
      await tester.pumpAndSettle();
      configurePdfiumForTest();
      PdfrxEntryFunctions.instance = nativeRenderer;
      addTearDown(() => PdfrxEntryFunctions.instance = _NoRenderer());
      await tester.tap(find.text('Metni düzenlemeye aktar'));
      await helpers.ready(
        tester,
        () => find.byType(QuillEditor).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(find.text('Düzenle'), findsNothing);
      expect(find.text('PDF metnini düzenle'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 350));
      await tester.runAsync(() async {
        library.dispose();
        appearance.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await dir.delete(recursive: true);
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
