import 'dart:io';

import 'package:evrak_convert/services/platform/phone_document_save.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('folio_test/kayit_klasoru');
  late Directory dir;
  late List<MethodCall> calls;
  var usable = true;
  var fails = false;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('folio-kayit-');
    calls = [];
    usable = true;
    fails = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'pickSaveFolder':
              return {'uri': 'content://agac/Dilekceler', 'name': 'Dilekçeler'};
            case 'saveFolderUsable':
              return usable;
            case 'writeToSaveFolder':
              if (fails) {
                throw PlatformException(code: 'SAVE_FOLDER', message: 'yok');
              }
              final args = call.arguments as Map;
              return 'Dilekçeler/${args['name']}';
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    dir.deleteSync(recursive: true);
  });

  PhoneSaveFolder folder() => PhoneSaveFolder(
    file: () async => File('${dir.path}/kayit-klasoru.json'),
    channel: channel,
  );

  test('chosen once, remembered while it may be written to, and asked '
      'again once its grant is taken back', () async {
    expect(await folder().current(), isNull);
    final chosen = await folder().choose();
    expect(chosen?.name, 'Dilekçeler');
    // Another run: the same folder.
    expect((await folder().current())?.uri, 'content://agac/Dilekceler');
    usable = false;
    expect(await folder().current(), isNull);
  });

  test('a document saved into the folder: a local copy kept, written there '
      'under its own name and type, and said where it went', () async {
    final f = folder();
    await f.choose();
    final saved = await PhoneDocumentSave.saveToFolder(
      fileName: 'İtiraz dilekçesi.udf',
      bytes: [1, 2, 3],
      folder: f,
      supportDirectory: dir,
    );
    expect(saved.shown, 'Dilekçeler/İtiraz dilekçesi.udf');
    expect(File(saved.path).readAsBytesSync(), [1, 2, 3]);
    final write = calls.lastWhere((c) => c.method == 'writeToSaveFolder');
    final args = write.arguments as Map;
    expect(args['uri'], 'content://agac/Dilekceler');
    expect(args['name'], 'İtiraz dilekçesi.udf');
    expect(args['path'], saved.path);
    expect(args['mimeType'], isNot('application/octet-stream'));
  });

  test(
    'a failed write keeps no copy, and no folder chosen is said so',
    () async {
      final f = folder();
      await expectLater(
        PhoneDocumentSave.saveToFolder(
          fileName: 'Cevap.udf',
          bytes: [9],
          folder: f,
          supportDirectory: dir,
        ),
        throwsStateError,
      );
      await f.choose();
      fails = true;
      await expectLater(
        PhoneDocumentSave.saveToFolder(
          fileName: 'Cevap.udf',
          bytes: [9],
          folder: f,
          supportDirectory: dir,
        ),
        throwsA(isA<PlatformException>()),
      );
      final kept = Directory('${dir.path}/saved-documents')
          .listSync(recursive: true)
          .whereType<File>();
      expect(kept, isEmpty);
    },
  );
}
