import 'dart:io';

import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/temp_directory.dart';

import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/ui/library/search_results.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:evrak_convert/ui/widgets/data_preview_widget.dart';

class _FolderPicker extends FilePickerPlatform {
  final String folder;
  _FolderPicker(this.folder);
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
  }) async => folder;
}

void main() {
  testWidgets(
    'settings add folder, index content, search and toggle black theme',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('library-ui-'),
      ))!;
      await tester.runAsync(
        () =>
            File('${dir.path}/duruşma.json')
                .writeAsString('{"not":"İhtiyati tedbir talebi"}'),
      );
      final library = LibraryController(
        databasePath: ':memory:',
        watchFolders: false,
      );
      final theme = ThemeController(
        settingsPath: '${dir.path}/appearance.json',
        mode: ThemeMode.light,
      );
      FilePickerPlatform.instance = _FolderPicker(dir.path);
      await tester.runAsync(library.initialize);
      await tester.pumpWidget(
        EvrakConvertApp(library: library, appearance: theme),
      );
      await tester.pump();
      await tester.tap(find.text('Ayarlar'));
      await tester.pumpAndSettle();
      expect(find.text('Arşiv klasörleri'), findsOneWidget);
      // Ayar listesi uzadıkça düğme katlanın altına iniyor; kullanıcı
      // kaydırarak ulaşıyor, test de öyle yapmalı.
      await tester.ensureVisible(find.text('Klasör seç ve ekle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Klasör seç ve ekle'));
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && library.sources.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await library.waitForIdle();
      });
      await tester.pumpAndSettle();
      expect(library.searchable, 1);
      expect(library.sources.single.folder, isTrue);
      expect(library.sources.single.recursive, isTrue);
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'ihtiyati');
      await tester.runAsync(library.searchNow);
      await tester.pumpAndSettle();
      expect(library.matches, 1);
      expect(find.byType(SearchHighlight), findsWidgets);
      await tester.tap(find.textContaining('duruşma.json').first);
      await tester.pump();
      expect(find.byType(DataPreviewWidget), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Siyah tema'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      final scaffold = tester.element(find.byType(Scaffold).first);
      expect(
        Theme.of(scaffold).scaffoldBackgroundColor,
        const Color(0xFF000000),
      );
      expect(theme.mode, ThemeMode.dark);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        library.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      theme.dispose();
      await removeTemporaryDirectory(tester, dir);
    },
  );

  testWidgets('phone layout has search, file opening and settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const EvrakConvertApp());
    await tester.pumpAndSettle();
    expect(find.text('Belge aç'), findsOneWidget);
    expect(find.text('Yeni belge'), findsOneWidget);
    await tester.tap(find.text('Arşivde ara'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Dosya aç'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Menü'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayarlar'));
    await tester.pumpAndSettle();
    // A phone's settings are a page of their own, not a dialog.
    expect(find.text('BAĞLANTILAR'), findsOneWidget);
    expect(find.text('Arşiv klasörleri'), findsOneWidget);
    await tester.tap(find.text('Arşiv klasörleri'));
    await tester.pumpAndSettle();
    expect(find.text('Klasör ekle'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compact layout remains usable at minimum desktop width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const EvrakConvertApp());
    await tester.pump();
    expect(find.byTooltip('Ayarlar'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Ayarlar'));
    await tester.pumpAndSettle();
    expect(find.text('Klasör seç ve ekle'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
