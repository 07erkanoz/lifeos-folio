import 'dart:io';
import 'dart:typed_data';

import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

UyapCaseDocument doc(String key) => UyapCaseDocument(
  key: key,
  documentId: '',
  caseId: '',
  type: 'Evrak $key',
  number: key,
  approved: '05/10/2026 10:00',
  sender: '',
  description: '',
);

void main() {
  test('one content saved as several documents is dropped, to be fetched '
      'again; a different one stays', () async {
    final root = Directory.systemTemp.createTempSync('folio-same-');
    addTearDown(() => root.deleteSync(recursive: true));
    final store = UyapCaseStore(
      directory: Directory('${root.path}/destek'),
      settings: UyapSettings(
        directory: Directory('${root.path}/destek'),
        home: '${root.path}/ev',
      ),
    );
    var record = await store.keep(
      target: const UyapCase(
        '',
        '2024/700',
        '',
        'İstanbul Anadolu 75. Asliye Ceza Mahkemesi',
      ),
      details: const UyapCaseDetails(),
      parties: const [],
      documents: UyapCaseDocuments([doc('1'), doc('2'), doc('3')]),
    );
    final wrong = Uint8List.fromList(List.filled(64, 7));
    (record, _) = await store.save(record, doc('1'), wrong);
    expect(store.sameAsAnother(record, '2', wrong), isTrue);
    (record, _) = await store.save(record, doc('2'), wrong);
    (record, _) = await store.save(
      record,
      doc('3'),
      Uint8List.fromList(List.filled(64, 9)),
    );
    final kept = record.files['3']!;
    final fixed = await store.dropSameContent(record);
    expect(fixed.files.keys, ['3']);
    expect(File(kept).existsSync(), isTrue);
    expect((await store.load(record.court, record.number))!.files.keys, ['3']);
  });
}
