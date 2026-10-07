import 'dart:io';

import 'package:evrak_convert/services/search/library_controller.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/shortcuts_dialog.dart';

import 'editor_drafts_test.dart' as helpers;
import 'support/fake_path_provider.dart';
import 'support/temp_directory.dart';

Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool alt = false,
  bool shift = false,
}) async {
  if (control) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  }
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('a phone goes back on a swipe from the left edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-swipe-'),
    ))!;
    useFakePathProvider();
    final history = DocumentHistory.instance;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    addTearDown(() => DocumentHistory.instance = history);
    final file = File('${dir.path}/tek.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'Telefon belgesi')]),
        ),
      ),
    );

    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    await tester.runAsync(library.initialize);
    addTearDown(
      () => tester.runAsync(() async {
        library.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }),
    );
    await tester.pumpWidget(
      EvrakConvertApp(initialPaths: [file.path], library: library),
    );
    await helpers.ready(
      tester,
      () => find.byTooltip('Belge işlemleri').evaluate().isNotEmpty,
    );
    // Just that the document is what is on screen: how many places its name
    // is written differs with the layout.
    expect(find.text('tek.udf'), findsWidgets);
    // The phone's first page, which going back comes out to, has the menu
    // button in its heading.
    final home = find.byKey(const ValueKey('mobile-menu'));
    expect(home, findsNothing, reason: 'the first page is not on screen yet');

    // From the very edge, so that a drag across the page still turns it.
    final edge = find.byKey(const ValueKey('edge-back'));
    expect(edge, findsOneWidget, reason: 'the edge strip is only on phones');
    await tester.flingFrom(tester.getCenter(edge), const Offset(220, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await helpers.ready(tester, () => home.evaluate().isNotEmpty);
    expect(
      home,
      findsOneWidget,
      reason: 'an edge swipe should come back out to the first page',
    );
    // Not the menu opened over the document by the same swipe, which is
    // what this used to pass on while the menu held the archive's folders.
    expect(
      tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
      isFalse,
    );
    expect(find.byKey(const ValueKey('workspace-title')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await removeTemporaryDirectory(tester, dir);
  });

  testWidgets('Ctrl+E goes into the editor and back, Alt+arrow walks the '
      'documents, F1 names the keys', (tester) async {
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-keys-'),
    ))!;
    useFakePathProvider();
    final history = DocumentHistory.instance;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    addTearDown(() => DocumentHistory.instance = history);

    final paths = <String>[];
    for (final name in ['bir', 'iki']) {
      final file = File('${dir.path}/$name.udf');
      await tester.runAsync(
        () => file.writeAsBytes(
          UdfWriter.writeBytes(
            DocModel(blocks: [DocBlock(plainText: 'Belge $name')]),
          ),
        ),
      );
      paths.add(file.path);
    }

    await tester.pumpWidget(EvrakConvertApp(initialPaths: paths));
    await helpers.ready(
      tester,
      () => find.byTooltip('Belge işlemleri').evaluate().isNotEmpty,
    );

    // Escape only ever came out of the editor; this goes in as well. The
    // button says which side of the door we are on.
    expect(find.text('Düzenle'), findsWidgets);
    // The preview prints from its own bar; the editor, from its toolbar.
    expect(find.byKey(const ValueKey('preview-print')), findsOneWidget);
    // A document with text can be read aloud where it is previewed.
    expect(find.byKey(const ValueKey('preview-read-aloud')), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyE, control: true, shift: true);
    expect(find.text('Önizlemeye Dön'), findsWidgets);
    expect(find.byKey(const ValueKey('preview-print')), findsNothing);
    expect(find.byKey(const ValueKey('preview-read-aloud')), findsNothing);
    // Opening the editor writes a recovery draft, and the app refuses to let
    // a document go while that write is still in flight — rightly, so the
    // key is pressed again until the write is done with.
    for (var i = 0; i < 8 && find.text('Düzenle').evaluate().isEmpty; i++) {
      await press(tester, LogicalKeyboardKey.keyE, control: true, shift: true);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump();
    }
    expect(
      find.text('Düzenle'),
      findsWidgets,
      reason: 'Ctrl+Shift+E should come back out to the preview',
    );

    // Walking the open documents without going back to the list. The
    // function was there already and only a swipe could reach it.
    String shown() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((t) => t.endsWith('.udf'), orElse: () => '');
    final first = shown();
    expect(first, isNotEmpty);
    await press(tester, LogicalKeyboardKey.arrowRight, alt: true);
    expect(shown(), isNot(first), reason: 'Alt+→ should open the next one');
    await press(tester, LogicalKeyboardKey.arrowLeft, alt: true);
    expect(shown(), first);

    await press(tester, LogicalKeyboardKey.f1);
    expect(find.byType(ShortcutsDialog), findsOneWidget);
    expect(find.text('Alt+← / Alt+→'), findsOneWidget);
    expect(find.text('Ctrl+Shift+E'), findsOneWidget);
    await tester.tap(find.text('Kapat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ShortcutsDialog), findsNothing);

    // Take the app down and let its own timers run out, the way the other
    // whole-app tests here do.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await removeTemporaryDirectory(tester, dir);
  });
}
