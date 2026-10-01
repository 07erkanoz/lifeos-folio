import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/signature_banner.dart';

import 'editor_shortcuts_test.dart' show shortcut, waitFor;
import 'support/temp_directory.dart';

/// Stands in for the platform save dialog, answering with a chosen path.
class _Picker extends FilePickerPlatform {
  String? answer;
  String? asked;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    asked = fileName;
    return answer;
  }
}

/// A UDF that carries a signature, the way one downloaded from UYAP does.
List<int> _signed(DocModel model) {
  final archive = Archive();
  final unsigned = ZipDecoder().decodeBytes(UdfWriter.writeBytes(model));
  for (final file in unsigned.files) {
    archive.addFile(ArchiveFile(file.name, file.size, file.content));
  }
  final signature = List<int>.filled(64, 7);
  archive.addFile(ArchiveFile('sign.sgn', signature.length, signature));
  return ZipEncoder().encode(archive);
}

/// Waits for [action] while pumping. The history runs its work one piece at a
/// time, and the editor's pieces ahead in the queue only move when the test
/// pumps — waiting in real time alone waits for ever.
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

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    FlutterQuillLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  test('saving a signed document writes an unsigned one', () {
    // Everything below rests on this: the writer never carries a signature
    // over, because the signature covers the bytes that were replaced.
    final bytes = _signed(
      DocModel(blocks: [DocBlock(plainText: 'İmzalı belge')]),
    );
    expect(UdfReader.readBytes(bytes)!.metadata['hasSignature'], isTrue);
    final rewritten = UdfWriter.writeBytes(UdfReader.readBytes(bytes)!);
    expect(
      ZipDecoder().decodeBytes(rewritten).files.map((f) => f.name),
      isNot(contains('sign.sgn')),
    );
    expect(UdfReader.readBytes(rewritten)!.metadata['hasSignature'], isFalse);
  });

  testWidgets('a signed document can be re-saved and then signed again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final picker = _Picker();
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);

    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('editor-signed-'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final source = File('${dir.path}/karar.udf');
    await tester.runAsync(
      () => source.writeAsBytes(
        _signed(DocModel(blocks: [DocBlock(plainText: 'İmzalı belge')])),
      ),
    );
    final copy = '${dir.path}/karar_imzasiz.udf';
    picker.answer = copy;

    var signedPath = '';
    await tester.pumpWidget(
      _app(
        EditorWidget(
          initialFilePath: source.path,
          initialFormat: EvrakFormat.udf,
          onSigned: (path) => signedPath = path,
        ),
      ),
    );
    await waitFor(tester, () => find.byType(QuillEditor).evaluate().isNotEmpty);

    // While it is still the signed original, the banner says so.
    expect(find.byType(SignatureBanner), findsWidgets);

    final controller = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller;
    controller.replaceText(
      0,
      0,
      'Ek: ',
      const TextSelection.collapsed(offset: 4),
    );
    await tester.pump();
    tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .focusNode
        .requestFocus();
    await tester.pump();
    await shortcut(tester, LogicalKeyboardKey.keyS);

    // Asked what becomes of the signed file; a copy, this time.
    await waitFor(
      tester,
      () => find.text('Bu belge e-imzalı').evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('save-unsigned-copy')));
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );

    // The signed original is untouched and the copy carries no signature.
    final original = (await tester.runAsync(
      () async => UdfReader.readFile(source.path),
    ))!;
    expect(original.metadata['hasSignature'], isTrue);
    expect(original.toPlainText(), 'İmzalı belge');
    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(copy),
    ))!;
    expect(saved.metadata['hasSignature'], isFalse);
    expect(saved.toPlainText(), startsWith('Ek: '));

    // ...and the editor agrees: no banner claiming a signature that is not in
    // the file, and the button to sign the copy that was just written.
    await tester.pump();
    expect(find.byType(SignatureBanner), findsNothing);
    expect(find.byTooltip('UDF e-imzala'), findsOneWidget);
    expect(signedPath, isEmpty, reason: 'imzalama daha başlatılmadı');
    expect(picker.asked, 'karar_imzasiz.udf');
    await tester.pumpAndSettle();
    // Signing is a desktop action, so the test has to run as one.
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a signed document is saved in place when asked to, and the '
      'signed file stays in its history', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final picker = _Picker();
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);

    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('editor-overwrite-signed-'),
    ))!;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final source = File('${dir.path}/dilekce.udf');
    final original = _signed(
      DocModel(blocks: [DocBlock(plainText: 'İmzalı belge')]),
    );
    await tester.runAsync(() => source.writeAsBytes(original));
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
    Future<void> edit(String text) async {
      controller.replaceText(
        0,
        0,
        text,
        TextSelection.collapsed(offset: text.length),
      );
      await tester.pump();
      tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .focusNode
          .requestFocus();
      await tester.pump();
    }

    String onDisk() => UdfReader.readFile(source.path)?.toPlainText() ?? '';

    await edit('Ek: ');
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(
      tester,
      () => find.text('Bu belge e-imzalı').evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('overwrite-signed')));
    // The notice comes last, once the history is written too; a save asked
    // for before that is one the editor rightly ignores.
    await waitFor(
      tester,
      () => find.textContaining('Başarıyla kaydedildi:').evaluate().isNotEmpty,
    );
    expect(onDisk(), startsWith('Ek: '));

    // Written in place, without the signature the edit invalidated, and
    // without a save dialog...
    final saved = (await tester.runAsync(
      () async => UdfReader.readFile(source.path),
    ))!;
    expect(saved.metadata['hasSignature'], isFalse);
    expect(picker.asked, isNull);
    // ...while the signed file, byte for byte, is kept in the history.
    final versions = await _pumped(
      tester,
      () => DocumentHistory.instance.versions(
        DocumentHistory.documentKey(source.path),
      ),
    );
    final signed = versions.where((version) => version.signed).toList();
    expect(signed, hasLength(1));
    expect(
      await _pumped(tester, () => DocumentHistory.instance.read(signed.single)),
      original,
    );

    // The file carries no signature any more: the next save just saves.
    await edit('İkinci ');
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await waitFor(tester, () => onDisk().startsWith('İkinci Ek: '));
    expect(find.text('Bu belge e-imzalı'), findsNothing);
    expect(picker.asked, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await removeTemporaryDirectory(tester, dir);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
