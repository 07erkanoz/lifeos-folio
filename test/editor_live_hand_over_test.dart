import 'dart:io';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/editor/document_lock.dart';
import 'package:evrak_convert/services/live/live_share.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_file_menu.dart';
import 'package:evrak_convert/ui/widgets/editor_ribbon.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> ready(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 150 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

void main() {
  testWidgets('in a window of its own, sharing live hands the document to '
      'Folio\'s window, let go of first, and joins no network here', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-live-hand-'),
    ))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final lockFolder = DocumentLock.folder;
    DocumentLock.folder = () async => Directory('${dir.path}/acik');
    addTearDown(() => DocumentLock.folder = lockFolder);
    final file = File('${dir.path}/dilekce.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'Davacı vekili')]),
        ),
      ),
    );
    // As in LifeOS Editör: no network listened for here.
    expect(LiveShare.instance.listening, isFalse);
    final handed = <String>[];
    bool? heldWhenHanded;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: Column(
            children: [
              const EditorRibbonTabs(height: 38),
              Expanded(
                child: EditorWidget(
                  hostTabs: true,
                  initialFilePath: file.path,
                  initialFormat: EvrakFormat.udf,
                  fileHost: EditorFileHost(
                    onShareInFolio: (path) async {
                      handed.add(path);
                      heldWhenHanded = DocumentLock.holdsDocument(path);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await ready(tester, () => DocumentLock.holdsDocument(file.path));
    await ready(
      tester,
      () =>
          find.byKey(const ValueKey('editor-file-menu')).evaluate().isNotEmpty,
    );

    await tester.tap(find.byKey(const ValueKey('editor-file-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canlı paylaş…'));
    await tester.pumpAndSettle();
    // Said where it is shared, and asked first.
    expect(find.text('Folio’da paylaşılır'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-in-folio')));
    await ready(tester, () => handed.isNotEmpty);
    expect(handed, [file.path]);
    // Let go of before it was handed: Folio's window opens it to edit.
    expect(heldWhenHanded, isFalse);
    // The sharing dialog never opened here, nor the network with it.
    expect(find.text('Canlı paylaş'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });
}
