import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/temp_directory.dart';

import 'package:evrak_convert/ui/widgets/plain_text_editor.dart';

class _SavePicker extends FilePickerPlatform {
  final String target;
  _SavePicker(this.target);
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => target;
}

void main() {
  testWidgets('source text editor saves edited JSON as a separate UTF-8 copy', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('evrak-editor-'),
    ))!;
    final source = File('${dir.path}/not.json');
    final output = File('${dir.path}/not_duzenlendi.json');
    const original = '{"not":"İhtiyati tedbir"}';
    await tester.runAsync(() => source.writeAsString(original));
    FilePickerPlatform.instance = _SavePicker(output.path);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlainTextEditor(path: source.path)),
      ),
    );
    for (var i = 0; i < 30 && find.byType(TextField).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      '{"not":"Düzenlenen Türkçe metin"}',
    );
    await tester.tap(find.text('Farklı kaydet'));
    for (var i = 0; i < 30; i++) {
      await tester.pump();
      final exists = await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return output.exists();
      });
      if (exists == true) break;
    }
    await tester.runAsync(() async {
      expect(await output.readAsString(), '{"not":"Düzenlenen Türkçe metin"}');
      expect(await source.readAsString(), original);
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await removeTemporaryDirectory(tester, dir);
  });
}
