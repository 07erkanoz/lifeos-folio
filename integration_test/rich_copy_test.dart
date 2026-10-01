import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/services/editor/document_history.dart';

/// Copies a document out of Folio with real keys on a real X11 clipboard and
/// reads back what another program would find there. Run as docs/editor.md
/// describes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a copy in Folio offers HTML, RTF and text to other programs', (
    tester,
  ) async {
    final root = Platform.environment['FOLIO_TEST_ROOT']!;
    final dir = await Directory.systemTemp.createTemp('folio-native-copy-');
    addTearDown(() => dir.delete(recursive: true));
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final source = '${dir.path}/belge.udf';
    await File('$root/test/fixtures/clipboard/uyap-document.udf').copy(source);
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
            initialFilePath: source,
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
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The body's editor holds the table, whose cells are editors too.
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor).first);
    editor.focusNode.requestFocus();
    await tester.pumpAndSettle();

    final keys = await Process.run('/usr/bin/python3', [
      '$root/integration_test/keyboard_copy.py',
    ]);
    expect(keys.exitCode, 0, reason: '${keys.stderr}');
    var targets = <String>[];
    for (var i = 0; i < 50 && !targets.contains('text/rtf'); i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final listed = await Process.run('xclip', [
        '-selection',
        'clipboard',
        '-t',
        'TARGETS',
        '-o',
      ]);
      targets = (listed.stdout as String).split('\n');
    }
    expect(targets, containsAll(['text/html', 'text/rtf', 'UTF8_STRING']));
    final html = await Process.run('xclip', [
      '-selection',
      'clipboard',
      '-t',
      'text/html',
      '-o',
    ]);
    expect(html.stdout as String, contains('name="folio-clipboard"'));
    final text = await Process.run('xclip', ['-selection', 'clipboard', '-o']);
    expect(text.stdout as String, contains('ÖRNEK DİLEKÇE BAŞLIĞI'));
    expect(text.stdout as String, contains('Taraf\tDeğer'));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
