import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/services/editor/document_history.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final format in ['html', 'rtf', 'uyap', 'writer']) {
    for (final contextMenu in [false, true]) {
      testWidgets(
        'native $format clipboard into new UDF with ${contextMenu ? 'context menu' : 'Ctrl+V'}',
        (tester) async {
          final root = Platform.environment['FOLIO_TEST_ROOT']!;
          final dir = await Directory.systemTemp.createTemp(
            'folio-native-paste-',
          );
          DocumentHistory.instance = DocumentHistory(
            directory: Directory('${dir.path}/history'),
          );
          final file = File('${dir.path}/clipboard');
          final String mime;
          if (format == 'html' || format == 'writer') {
            await file.writeAsString(
              '<p style="text-align:center"><b style="font-family:Arial;font-size:18pt;color:#c00000">Bold heading</b></p><p>plain body</p>',
            );
            mime = 'text/html;charset=utf-8';
          } else if (format == 'rtf') {
            await file.writeAsString(
              r'{\rtf1\ansi{\fonttbl{\f0 Arial;}}\f0\fs36\qc\b Bold heading\b0\par\ql plain body}',
            );
            mime = 'text/rtf';
          } else {
            await file.writeAsBytes(
              await File('$root/test/fixtures/clipboard/uyap-document.bin')
                  .readAsBytes(),
            );
            mime = 'JAVA_DATAFLAVOR:application/x-java-serialized-object; class=tr.com.havelsan.uyap.system.editor.common.text.EditorDataFlavor';
          }
          final owner = await Process.start('/usr/bin/python3', [
            '$root/integration_test/${format == 'writer' ? 'libreoffice_copy.py' : 'clipboard_owner.py'}',
            file.path,
            mime,
          ]);
          owner.stderr.transform(utf8.decoder).listen(debugPrint);
          await owner.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 10));
          addTearDown(() async {
            owner.kill();
            await owner.exitCode.timeout(const Duration(seconds: 10));
            await dir.delete(recursive: true);
          });
          await tester.pumpWidget(
            const MaterialApp(
              localizationsDelegates: [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
                FlutterQuillLocalizations.delegate,
              ],
              home: Scaffold(
                body: EditorWidget(initialFormat: EvrakFormat.udf),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
          editor.focusNode.requestFocus();
          await tester.pumpAndSettle();
          if (contextMenu) {
            await tester.tapAt(
              tester.getTopLeft(find.byType(QuillEditor)) +
                  const Offset(25, 20),
              buttons: kSecondaryMouseButton,
            );
            await tester.pumpAndSettle();
            expect(find.text('Paste'), findsOneWidget);
            await tester.tap(find.text('Paste'));
          } else {
            final keyboard = await Process.run('/usr/bin/python3', [
              '$root/integration_test/keyboard_paste.py',
            ]);
            expect(keyboard.exitCode, 0, reason: '${keyboard.stderr}');
          }
          for (
            var i = 0;
            i < 100 && editor.controller.document.length < 5;
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump();
          }
          final delta = editor.controller.document.toDelta().toJson();
          expect(
            delta.first['attributes']?['bold'],
            true,
            reason: '$format $delta',
          );
          expect(
            delta.any((op) => op['attributes']?['align'] == 'center'),
            true,
          );
          expect(
            delta.first['attributes']?['font'],
            format == 'uyap' ? 'Times New Roman' : 'Arial',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
