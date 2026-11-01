import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/platform/document_write.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';

import 'editor_shortcuts_test.dart' show shortcut, waitFor;
import 'support/temp_directory.dart';

Future<String> _mode(String path) async =>
    ((await File(path).stat()).mode & 0x1ff).toRadixString(8);

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    FlutterQuillLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

/// Waits for [action] while pumping: the history's work moves only when the
/// test pumps (as in editor_signature_test).
Future<T> _pumped<T>(WidgetTester tester, Future<T> Function() action) async {
  var done = false;
  late T value;
  Object? error;
  action().then(
    (result) {
      value = result;
      done = true;
    },
    onError: (Object e) {
      error = e;
      done = true;
    },
  );
  await waitFor(tester, () => done);
  if (error != null) throw error!;
  return value;
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('folio-save-'));
  tearDown(() async {
    if (!Platform.isWindows) {
      await Process.run('chmod', ['-R', 'u+rwx', dir.path]);
    }
    await dir.delete(recursive: true);
  });

  List<String> leftovers() => [
    for (final one in dir.listSync())
      if (p(one).startsWith('.folio-save-')) p(one),
  ];

  test('a document is replaced whole, and nothing is left beside it', () async {
    final file = File('${dir.path}/dilekce.udf');
    await file.writeAsBytes([1, 2, 3]);
    await writeDocument(file.path, [4, 5, 6, 7]);
    expect(await file.readAsBytes(), [4, 5, 6, 7]);
    await writeDocument('${dir.path}/yeni.udf', [8]);
    expect(await File('${dir.path}/yeni.udf').readAsBytes(), [8]);
    expect(leftovers(), isEmpty);
  });

  test('its permissions stay: a private file stays private', () async {
    final file = File('${dir.path}/gizli.udf');
    await file.writeAsBytes([1]);
    await Process.run('chmod', ['600', file.path]);
    await writeDocument(file.path, [2]);
    expect(await file.readAsBytes(), [2]);
    expect(await _mode(file.path), '600');
  }, testOn: 'linux || mac-os');

  test('through a link, the file it points at; the link stays', () async {
    final real = File('${dir.path}/asil.udf');
    await real.writeAsBytes([1]);
    final link = Link('${dir.path}/kisayol.udf');
    await link.create(real.path);
    await writeDocument(link.path, [9, 9]);
    expect(await FileSystemEntity.isLink(link.path), isTrue);
    expect(await real.readAsBytes(), [9, 9]);
    // A link to nothing makes the file it names, as before.
    final dangling = Link('${dir.path}/bos.udf');
    await dangling.create('${dir.path}/olmayan.udf');
    await writeDocument(dangling.path, [3]);
    expect(await File('${dir.path}/olmayan.udf').readAsBytes(), [3]);
  }, testOn: 'linux || mac-os');

  test(
    'a folder that takes no new files: written in place, as before',
    () async {
      final folder = Directory('${dir.path}/kilitli')..createSync();
      final file = File('${folder.path}/dilekce.udf')..writeAsBytesSync([1]);
      await Process.run('chmod', ['500', folder.path]);
      // Root writes anywhere; the case only exists for others.
      final root = (await Process.run('id', ['-u'])).stdout.toString().trim();
      if (root == '0') return;
      await writeDocument(file.path, [5, 5]);
      expect(await file.readAsBytes(), [5, 5]);
    },
    testOn: 'linux || mac-os',
  );

  test('a stamp tells another program\'s change from none', () async {
    final file = File('${dir.path}/dilekce.udf');
    await file.writeAsBytes([1, 2]);
    final stamp = (await DiskStamp.of(file.path))!;
    expect(await stamp.changedAt(file.path), isFalse);
    // Another file, or one that is gone, is not this one changed.
    expect(await stamp.changedAt('${dir.path}/baska.udf'), isFalse);
    await file.writeAsBytes([1, 2, 3]);
    expect(await stamp.changedAt(file.path), isTrue);
    await file.delete();
    expect(await stamp.changedAt(file.path), isFalse);
    expect(await DiskStamp.of(file.path), isNull);
  });

  testWidgets('a document changed by another program is not written over '
      'unasked; when it is, that version is in the history', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('editor-external-change-'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${root.path}/history'),
    );
    final source = File('${root.path}/dilekce.udf');
    await tester.runAsync(
      () => source.writeAsBytes(
        UdfWriter.writeBytes(DocModel(blocks: [DocBlock(plainText: 'Asıl')])),
      ),
    );
    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: source.path,
          initialFormat: EvrakFormat.udf,
        ),
      ),
    );
    await waitFor(tester, () => find.byType(QuillEditor).evaluate().isNotEmpty);
    final controller = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller;
    controller.replaceText(
      0,
      0,
      'Benim ',
      const TextSelection.collapsed(offset: 6),
    );
    await tester.pump();
    tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .focusNode
        .requestFocus();
    await tester.pump();

    // Meanwhile another program writes its own version.
    final theirs = UdfWriter.writeBytes(
      DocModel(blocks: [DocBlock(plainText: 'Onların hâli')]),
    );
    await tester.runAsync(() async {
      await source.writeAsBytes(theirs);
      await source.setLastModified(
        DateTime.now().add(const Duration(minutes: 1)),
      );
    });
    String onDisk() => UdfReader.readFile(source.path)?.toPlainText() ?? '';

    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () =>
          find.text('Belge başka bir yerde değiştirildi').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Vazgeç'));
    await tester.pump();
    expect(onDisk(), startsWith('Onların hâli'));

    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () =>
          find.text('Belge başka bir yerde değiştirildi').evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('external-overwrite')));
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );
    expect(onDisk(), startsWith('Benim Asıl'));
    final versions = await _pumped(
      tester,
      () => DocumentHistory.instance.versions(
        DocumentHistory.documentKey(source.path),
      ),
    );
    final kept = <List<int>>[
      for (final one in versions)
        await _pumped(tester, () => DocumentHistory.instance.read(one)),
    ];
    expect(kept.any((one) => listEquals(one, theirs)), isTrue);

    // Saved here: the next save asks nothing.
    controller.replaceText(
      0,
      0,
      'Yine ',
      const TextSelection.collapsed(offset: 5),
    );
    await tester.pump();
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(tester, () => onDisk().startsWith('Yine Benim'));
    expect(find.text('Belge başka bir yerde değiştirildi'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await removeTemporaryDirectory(tester, root);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

String p(FileSystemEntity one) =>
    one.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
