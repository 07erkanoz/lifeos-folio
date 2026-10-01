import 'dart:io';
import 'dart:convert';

import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/doc_delta_map.dart';
import 'package:evrak_convert/services/fonts/document_fonts.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'support/styled_pdf.dart';
import 'support/pdfium.dart';

import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('lifeos_evrak/rich_clipboard');

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(
    ready(),
    isTrue,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .join(' | '),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configurePdfiumForTest();

  for (final usingUyap in [false, true]) {
    for (final fromPdf in [false, true]) {
      for (final contextMenu in [false, true]) {
        testWidgets(
          '${usingUyap ? 'UYAP' : 'HTML'} ${contextMenu ? 'Right-click' : 'Ctrl+V'} rich paste into ${fromPdf ? 'PDF' : 'new document'}',
          (tester) async {
            final directory = (await tester.runAsync(
              () => Directory.systemTemp.createTemp('rich-paste-'),
            ))!;
            addTearDown(() => directory.delete(recursive: true));
            DocumentHistory.instance = DocumentHistory(
              directory: Directory('${directory.path}/history'),
            );
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(_channel, (call) async {
                  expect(call.method, 'getRichData');
                  if (usingUyap) {
                    return {
                      'format': 'uyap',
                      'data': File('test/fixtures/clipboard/uyap-document.bin')
                          .readAsBytesSync(),
                    };
                  }
                  return {
                    'format': 'html',
                    'data': Uint8List.fromList(
                      utf8.encode('''
            <p><span style="font-family: Arial; font-size: 14pt;
              color: rgb(192, 0, 0); font-weight: bold">Biçimli metin</span></p>
            <table><tr><th>Ad</th><th>Değer</th></tr>
              <tr><td>Dosya</td><td>2026/1</td></tr></table>
          '''),
                    ),
                  };
                });
            addTearDown(
              () => TestDefaultBinaryMessengerBinding
                  .instance
                  .defaultBinaryMessenger
                  .setMockMethodCallHandler(_channel, null),
            );

            await tester.runAsync(
              () => DocumentFonts.loadEditorFamilies([
                'Times New Roman',
                'Arial',
                'Helvetica',
                'Courier',
              ]),
            );
            String? sourcePath;
            if (fromPdf) {
              sourcePath = '${directory.path}/source.pdf';
              await tester.runAsync(
                () async => File(sourcePath!).writeAsBytes(await styledPdf()),
              );
            }
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, (
                  call,
                ) async {
                  if (call.method == 'Clipboard.hasStrings') {
                    return {'value': true};
                  }
                  if (call.method == 'Clipboard.getData') {
                    return {'text': 'Biçimli metin'};
                  }
                  return null;
                });
            addTearDown(
              () => TestDefaultBinaryMessengerBinding
                  .instance
                  .defaultBinaryMessenger
                  .setMockMethodCallHandler(SystemChannels.platform, null),
            );

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
                    initialFilePath: sourcePath,
                    initialFormat: fromPdf ? EvrakFormat.pdf : EvrakFormat.udf,
                  ),
                ),
              ),
            );
            await _waitFor(
              tester,
              () => find.byType(QuillEditor).evaluate().isNotEmpty,
            );
            final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
            editor.focusNode.requestFocus();
            await tester.pump();

            if (contextMenu) {
              await tester.tapAt(
                tester.getTopLeft(find.byType(QuillEditor)) +
                    const Offset(25, 20),
                buttons: kSecondaryMouseButton,
              );
              await tester.pumpAndSettle();
              final paste = find.text('Paste');
              expect(paste, findsOneWidget);
              await tester.tap(paste);
            } else {
              await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
              await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
              await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
            }
            await _waitFor(
              tester,
              () => editor.controller.document.toPlainText().contains(
                usingUyap ? 'ÖRNEK DİLEKÇE BAŞLIĞI' : 'Biçimli metin',
              ),
            );

            final operation = editor.controller.document
                .toDelta()
                .toList()
                .firstWhere(
                  (op) => op.data.toString().contains(
                    usingUyap ? 'ÖRNEK DİLEKÇE BAŞLIĞI' : 'Biçimli metin',
                  ),
                );
            expect(
              operation.attributes?['font'],
              usingUyap ? 'Times New Roman' : 'Arial',
            );
            expect(
              double.parse(operation.attributes?['size'] as String),
              closeTo(18.67, .01),
            );
            expect(operation.attributes?['color'], '#c00000');
            expect(operation.attributes?['bold'], isTrue);
            if (usingUyap) {
              expect(
                editor.controller.document.toDelta().toJson().any(
                  (op) => op['attributes']?['align'] == 'center',
                ),
                isTrue,
              );
              expect(
                editor.controller.document.toDelta().toJson().any(
                  (op) =>
                      op['attributes']?['underline'] == true &&
                      op['attributes']?['background'] == '#ffff00',
                ),
                isTrue,
              );
            } else {
              final delta = editor.controller.document.toDelta().toJson();
              expect(
                delta.any(
                  (op) =>
                      op['insert'] is Map &&
                      (op['insert'] as Map).containsKey(
                        DocDeltaMap.kTableEmbed,
                      ),
                ),
                isTrue,
                reason: '$delta',
              );
              await tester.pump();
              expect(find.byKey(const ValueKey('table')), findsOneWidget);
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(milliseconds: 1));
          },
        );
      }
    }
  }
}
