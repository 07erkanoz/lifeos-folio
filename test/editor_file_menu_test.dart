import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/ui/widgets/editor_file_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  EvrakFile file(String path) => EvrakFile(
    path: path,
    name: path.split('/').last,
    sizeInBytes: 1,
    format: EvrakFormat.fromExtension(path.split('.').last),
  );

  Future<void> pump(
    WidgetTester tester, {
    EditorFileHost? host,
    String? current,
    ValueChanged<EvrakFormat>? onSaveIn,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: EditorFileMenu(
              host: host,
              currentPath: current,
              busy: false,
              onSave: () {},
              onSaveAs: () {},
              onSaveIn: onSaveIn ?? (_) {},
              onPrint: () {},
              onHistory: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('editor-file-menu')));
    await tester.pumpAndSettle();
  }

  testWidgets('recent documents open from the menu, the open one left out', (
    tester,
  ) async {
    EvrakFile? opened;
    await pump(
      tester,
      current: '/dava/dilekce.udf',
      host: EditorFileHost(
        recent: () => [
          file('/dava/dilekce.udf'),
          file('/dava/cevap.docx'),
          file('/icra/takip.udf'),
        ],
        onOpenRecent: (f) => opened = f,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('editor-recent-menu')));
    await tester.pumpAndSettle();
    expect(find.text('dilekce.udf'), findsNothing);
    expect(find.text('cevap.docx'), findsOneWidget);
    expect(find.text('/icra'), findsOneWidget);
    await tester.tap(find.text('takip.udf'));
    await tester.pumpAndSettle();
    expect(opened?.path, '/icra/takip.udf');
  });

  testWidgets('an empty recents list says so', (tester) async {
    await pump(
      tester,
      host: EditorFileHost(recent: () => const [], onOpenRecent: (_) {}),
    );
    await tester.tap(find.byKey(const ValueKey('editor-recent-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Henüz açılmış belge yok'), findsOneWidget);
  });

  testWidgets('DOCX and PDF commands save in their format', (tester) async {
    final formats = <EvrakFormat>[];
    await pump(tester, onSaveIn: formats.add);
    await tester.tap(find.text('Word (DOCX) Olarak Kaydet'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-file-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF’e dönüştür'));
    await tester.pumpAndSettle();
    expect(formats, [EvrakFormat.docx, EvrakFormat.pdf]);
  });

  testWidgets('without a host only the editor’s own commands show', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Kaydet'), findsOneWidget);
    expect(find.text('Son açılanlar'), findsNothing);
    expect(find.text('Yeni belge'), findsNothing);
  });
}
