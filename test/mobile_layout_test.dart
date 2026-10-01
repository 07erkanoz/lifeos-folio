import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';

void main() {
  testWidgets(
    'phone search options remain usable with keyboard and both themes',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-mobile-'),
      ))!;
      final library = LibraryController(
        databasePath: ':memory:',
        watchFolders: false,
      );
      final appearance = ThemeController(
        settingsPath: '${dir.path}/theme.json',
      );
      await tester.runAsync(library.initialize);
      await tester.pumpWidget(
        EvrakConvertApp(library: library, appearance: appearance),
      );
      await tester.pumpAndSettle();
      expect(find.text('Belge aç'), findsOneWidget);
      expect(find.text('Yeni belge oluştur'), findsOneWidget);
      await tester.tap(find.text('Arşivde ara'));
      await tester.pumpAndSettle();
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        appearance.setMode(mode);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Arama seçenekleri'));
        await tester.pumpAndSettle();
        expect(find.text('Tam ifade'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Tamam'));
        await tester.pumpAndSettle();
      }
      await tester.showKeyboard(find.byType(TextField).first);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      tester.view.physicalSize = const Size(740, 360);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        library.dispose();
        appearance.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
  testWidgets(
    'phone editor has readable page and accessible toolbar in portrait and landscape',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('folio-phone-editor-'),
      ))!;
      final file = File('${dir.path}/deneme.udf');
      await tester.runAsync(
        () => file.writeAsBytes(
          UdfWriter.writeBytes(
            DocModel(
              blocks: [DocBlock(plainText: 'Duruşma tutanağı ve örnek metin')],
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
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
        i < 100 && find.byType(QuillEditor).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.byType(QuillEditor), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
}
