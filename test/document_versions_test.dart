import 'dart:io';

import 'package:archive/archive.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:evrak_convert/ui/widgets/document_versions_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _ready(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(condition(), isTrue);
}

List<int> _udf(String text, {bool signed = false}) {
  final bytes = UdfWriter.writeBytes(
    DocModel(blocks: [DocBlock(plainText: text)]),
  );
  if (!signed) return bytes;
  final archive = Archive();
  for (final file in ZipDecoder().decodeBytes(bytes).files) {
    archive.addFile(ArchiveFile(file.name, file.size, file.content));
  }
  archive.addFile(ArchiveFile('sign.sgn', 3, [1, 2, 3]));
  return ZipEncoder().encode(archive);
}

void main() {
  testWidgets('a version is read against the document as it is now, and '
      'handed back to be restored', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-versions-'),
    ))!;
    final previous = DocumentHistory.instance;
    DocumentHistory.instance = DocumentHistory(directory: dir);
    addTearDown(() => DocumentHistory.instance = previous);
    const path = '/belgeler/dilekce.udf';
    final key = DocumentHistory.documentKey(path);
    Future<void> keep(List<int> bytes, String kind) => tester.runAsync(
      () => DocumentHistory.instance.capture(
        document: key,
        name: 'dilekce.udf',
        sourcePath: path,
        format: 'udf',
        bytes: bytes,
        kind: kind,
      ),
    );
    await keep(_udf('Davacının eski talebi', signed: true), 'original');
    await keep(_udf('Davacının yeni talebi'), 'saved');

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    DocumentRevision? chosen;
    var closed = false;
    showDocumentVersions(
      context,
      document: key,
      title: 'dilekce.udf',
      currentText: () async => 'Davacının güncel talebi\n',
      restoreLabel: 'Bu sürüme dön',
    ).then((entry) {
      chosen = entry;
      closed = true;
    });
    await tester.pump();
    const older = 'Üzerine yazılmadan önceki hali';
    await _ready(tester, () => find.textContaining(older).evaluate().isNotEmpty);
    expect(find.text('E-imzalı'), findsOneWidget);
    expect(find.textContaining('Folio’da kaydedildi'), findsWidgets);

    await tester.tap(find.textContaining(older).first);
    await tester.pump();
    await _ready(
      tester,
      () => find
          .textContaining('1 kelime eklenmiş, 1 kelime silinmiş')
          .evaluate()
          .isNotEmpty,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('restore-version')));
    await _ready(tester, () => closed);
    expect(chosen?.kind, 'original');
    expect(chosen?.signed, isTrue);
    await tester.pumpAndSettle();
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('a document without versions says how they come to be', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-versions-empty-'),
    ))!;
    final previous = DocumentHistory.instance;
    DocumentHistory.instance = DocumentHistory(directory: dir);
    addTearDown(() => DocumentHistory.instance = previous);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    showDocumentVersions(
      context,
      document: DocumentHistory.documentKey('/yok.udf'),
      title: 'yok.udf',
    );
    await tester.pump();
    await _ready(
      tester,
      () => find
          .text('Bu belgenin henüz saklanmış bir sürümü yok.')
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byTooltip('Kapat · Esc'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
