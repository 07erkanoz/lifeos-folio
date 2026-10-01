import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/editor/document_lock.dart';
import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_file_menu.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';

import 'editor_drafts_test.dart' show ready;

/// Two editor windows, one document: the second only reads it, and says so.
void main() {
  testWidgets('a document being edited in another window opens to be read '
      'only, and is not saved over from here', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-pencere-'),
    ))!;
    final history = DocumentHistory.instance;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/gecmis'),
    );
    final folder = DocumentLock.folder;
    DocumentLock.folder = () async => Directory('${dir.path}/acik');
    addTearDown(() {
      DocumentHistory.instance = history;
      DocumentLock.folder = folder;
    });

    final file = File('${dir.path}/dilekce.udf');
    final original = UdfWriter.writeBytes(
      DocModel(blocks: [DocBlock(plainText: 'Sayın Mahkemeye')]),
    );
    await tester.runAsync(() => file.writeAsBytes(original));

    // The other window: a process holding the document's claim.
    final other = (await tester.runAsync(() async {
      await Directory('${dir.path}/acik').create(recursive: true);
      final key = DocumentHistory.documentKey(file.path);
      final process = await Process.start('python3', [
        '-c',
        'import fcntl, sys, time\n'
            'f = open(sys.argv[1], "a")\n'
            'fcntl.lockf(f, fcntl.LOCK_EX)\n'
            'print("held", flush=True)\n'
            'time.sleep(60)\n',
        '${dir.path}/acik/belge-$key.lock',
      ]);
      await process.stdout.transform(utf8.decoder).first;
      return process;
    }))!;
    addTearDown(() => other.kill(ProcessSignal.sigkill));

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
            draft: EditorDrafts().draft(file.path, 'dilekce.udf'),
            initialFilePath: file.path,
            initialFormat: EvrakFormat.udf,
          ),
        ),
      ),
    );
    await ready(
      tester,
      () => find.byKey(const ValueKey('held-elsewhere')).evaluate().isNotEmpty,
    );
    final controller = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller;
    expect(controller.readOnly, isTrue);

    // Ctrl+S says why, and leaves the file as the other window has it.
    await tester.tap(find.byType(QuillEditor));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await ready(
      tester,
      () =>
          find.text('Bu belge başka bir pencerede açık').evaluate().isNotEmpty,
    );
    expect(await tester.runAsync(file.readAsBytes), original);

    // Once the other window is closed, this one can take the document.
    await tester.runAsync(() async {
      other.kill(ProcessSignal.sigkill);
      await other.exitCode;
    });
    await tester.tap(find.text('Yeniden dene'));
    await ready(
      tester,
      () => find.byKey(const ValueKey('held-elsewhere')).evaluate().isEmpty,
    );
    expect(controller.readOnly, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() => dir.delete(recursive: true));
  }, skip: !Platform.isLinux);

  testWidgets('the File menu opens a new window', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorFileMenu(
            host: null,
            currentPath: null,
            busy: false,
            onSave: () {},
            onSaveAs: () {},
            onSaveIn: (_) {},
            onPrint: () {},
            onHistory: () {},
            onNewWindow: () => opened++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(EditorFileMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni pencere'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
}
