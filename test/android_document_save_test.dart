import 'dart:io';

import 'package:evrak_convert/services/platform/phone_document_save.dart';
import 'package:evrak_convert/ui/widgets/default_viewer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('folio-save-'),
  );
  tearDown(() async {
    messenger.setMockMethodCallHandler(PhoneDocumentSave.channel, null);
    await root.delete(recursive: true);
  });

  test('SAF content URI becomes a readable preview copy with explicit MIME', () async {
    final expected = {
      'udf': 'application/x-uyap-udf',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pdf': 'application/pdf',
      'txt': 'text/plain',
    };
    for (final entry in expected.entries) {
      messenger.setMockMethodCallHandler(PhoneDocumentSave.channel, (
        call,
      ) async {
        expect(call.method, 'saveDocument');
        expect(call.arguments['mimeType'], entry.value);
        expect(await File(call.arguments['path'] as String).readAsBytes(), [
          1,
          2,
          3,
        ]);
        return 'content://external.documents/document/primary%3ABelgeler%2Ftest.${entry.key}';
      });
      final path = await PhoneDocumentSave.save(
        fileName: 'Türkçe belge.${entry.key}',
        bytes: [1, 2, 3],
        supportDirectory: root,
      );
      expect(await File(path!).readAsBytes(), [1, 2, 3]);
      expect(path, contains('Türkçe belge.${entry.key}'));
      expect(path, isNot(contains('content:')));
    }
  });

  test(
    'cancel and provider errors leave no falsely saved preview copies',
    () async {
      messenger.setMockMethodCallHandler(
        PhoneDocumentSave.channel,
        (_) async => null,
      );
      expect(
        await PhoneDocumentSave.save(
          fileName: 'test.udf',
          bytes: [1],
          supportDirectory: root,
        ),
        isNull,
      );
      expect(
        await Directory('${root.path}/saved-documents').list().toList(),
        isEmpty,
      );
      messenger.setMockMethodCallHandler(PhoneDocumentSave.channel, (
        _,
      ) async {
        throw PlatformException(
          code: 'SAVE_DOCUMENT',
          message: 'Konuma yazılamıyor',
        );
      });
      await expectLater(
        PhoneDocumentSave.save(
          fileName: 'test.udf',
          bytes: [1],
          supportDirectory: root,
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(
        await Directory('${root.path}/saved-documents').list().toList(),
        isEmpty,
      );
    },
  );

  testWidgets('Android defaults start document-based resolver flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = 0;
    messenger.setMockMethodCallHandler(PhoneDocumentSave.channel, (
      call,
    ) async {
      expect(call.method, 'configureDefaultViewer');
      opened++;
      if (opened == 2) {
        throw PlatformException(
          code: 'DEFAULT_VIEWER',
          message: 'Belge seçimi açılamadı',
        );
      }
      return 'Android uygulama seçimi açıldı. LifeOS Folio’yu seçin.';
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DefaultViewerDialog())),
    );
    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('Seçilenleri varsayılan yap'), findsNothing);
    final button = find.text('Belge seç ve varsayılanı ayarla');
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(
      find.textContaining('Android uygulama seçimi açıldı.'),
      findsOneWidget,
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('Belge seçimi açılamadı'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));
}
