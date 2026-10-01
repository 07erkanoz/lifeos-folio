import 'dart:io';

import 'package:evrak_convert/services/platform/file_actions.dart';
import 'package:evrak_convert/ui/widgets/share_document_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File source;
  final calls = <MethodCall>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('evrak-share-');
    source = await File('${root.path}/İmzalı belge & özel.udf')
        .writeAsBytes([80, 75, 0, 1, 255]);
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FileActions.channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FileActions.channel, null);
    await root.delete(recursive: true);
  });

  test('file transfer uses original absolute path and MIME without conversion', () async {
    for (final action in [
      'openDefault',
      'openWith',
      'share',
      'copyFile',
      'showFolder',
    ]) {
      await FileActions.invoke(action, source.path);
      expect(calls.last.method, action);
      expect(calls.last.arguments, {
        'path': source.absolute.path,
        'mimeType': 'application/x-uyap-udf',
      });
    }
    expect(
      FileActions.mimeType('BELGE.DOCX'),
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
    expect(FileActions.mimeType('görsel.TIFF'), 'image/tiff');
    expect(FileActions.mimeType('unknown'), 'application/octet-stream');
  });

  test('copy preserves all bytes, source and existing names', () async {
    final target = await Directory('${root.path}/Hedef').create();
    final first = await FileActions.copyToDirectory(source.path, target.path);
    final second = await FileActions.copyToDirectory(source.path, target.path);
    final local = await FileActions.copyToDirectory(source.path, root.path);
    expect(first, isNot(second));
    expect(local, isNot(source.path));
    for (final path in [first, second, local, source.path]) {
      expect(await File(path).readAsBytes(), [80, 75, 0, 1, 255]);
    }
  });

  test('missing source never reaches external application', () async {
    await expectLater(
      FileActions.invoke('share', '${root.path}/missing.pdf'),
      throwsA(isA<FileSystemException>()),
    );
    expect(calls, isEmpty);
  });

  testWidgets(
    'Windows share UI invokes native share, not text or URL sharing',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) => ShareDocumentDialog(path: source.path),
                ),
                child: const Text('Paylaş'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Paylaş'));
      await tester.pumpAndSettle();
      expect(find.text('Windows ile paylaş'), findsOneWidget);
      expect(find.text('Dosyayı kopyala'), findsOneWidget);
      expect(find.text('Klasöre kopyala'), findsOneWidget);
      expect(find.text('E-postaya ekle'), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.text('Windows ile paylaş'));
        for (var i = 0; i < 100 && calls.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(calls.single.method, 'share');
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
