import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';

void main() {
  test('Adalet tray login challenge stays byte exact', () {
    expect(UyapWebService.loginContent.length, 123);
    expect(UyapWebService.loginContent.sublist(0, 6), [
      65,
      100,
      97,
      108,
      101,
      116,
    ]);
  });

  test('send gate rejects an unsigned or changed UDF', () {
    final content = File('test/fixtures/signatures/content.xml')
        .readAsBytesSync();
    final signature = File('test/fixtures/signatures/rsa-valid.sgn')
        .readAsBytesSync();
    Uint8List udf(List<int> body, {List<int>? sign}) => Uint8List.fromList(
      ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile('content.xml', body.length, body))
          ..addFile(
            ArchiveFile(
              'sign.sgn',
              sign?.length ?? signature.length,
              sign ?? signature,
            ),
          ),
      ),
    );
    expect(
      () => UyapWebService.validateSignedUdf(udf(content)),
      returnsNormally,
    );
    expect(
      () => UyapWebService.validateSignedUdf(
        udf(
          content,
          sign: File('test/fixtures/signatures/multiple.sgn').readAsBytesSync(),
        ),
      ),
      returnsNormally,
    );
    expect(
      () => UyapWebService.validateSignedUdf(udf([...content, 32])),
      throwsStateError,
    );
    expect(
      () => UyapWebService.validateSignedUdf(udf(content, sign: [])),
      throwsStateError,
    );
    final tampered = Uint8List.fromList(signature);
    tampered[tampered.length - 1] ^= 1;
    expect(
      () => UyapWebService.validateSignedUdf(udf(content, sign: tampered)),
      throwsStateError,
    );
  });

  test('portal document type controls attachments and accepted formats', () {
    final withoutAttachments = UyapDocumentType.fromMap({
      'turKodu': 'DILEKCE',
      'aciklama': 'Dilekçe',
      'islemTipi': '1',
      'ekEvrakMax': 0,
      'acceptTypeList': ['.UDF'],
    });
    expect(withoutAttachments.attachmentMax, 0);
    expect(withoutAttachments.acceptedExtensions, {'.udf'});
    expect(withoutAttachments.toOptionJson()['ekEvrakMax'], 0);
  });

  test('case identity accepts UYAP number labels without mixing courts', () {
    const selected = UyapCase('session-1', '2021/191 Esas', 'court-1', 'Aile');
    const refreshed = UyapCase('session-2', '2021 / 191', 'court-1', 'Aile');
    const differentCourt = UyapCase('session-3', '2021/191', 'court-2', 'Aile');
    expect(selected.parsedNumber, (year: 2021, sequence: 191));
    expect(selected.sameCase(refreshed), isTrue);
    expect(selected.sameCase(differentCourt), isFalse);
  });

  test('web party fields keep role and lawyer for target verification', () {
    final party = UyapParty.fromMap({
      'adi': 'Örnek Davacı',
      'rol': 'Davacı',
      'vekil': 'Örnek Vekil',
      'kisiKurum': 'Kişi',
    });
    expect(party.name, 'Örnek Davacı');
    expect(party.role, 'Davacı');
    expect(party.lawyer, 'Örnek Vekil');
    expect(party.identity, 'Davacı|Örnek Davacı|Örnek Vekil|Kişi');
  });

  test('operations tell continuing from completed work', () {
    UyapOperation op(String status) => UyapOperation.fromMap({
      'isEmirNo': 12345,
      'isEmirTarihi': '2026-09-29 10:20:00.0',
      'birimAdi': 'Kemer 1. Aile Mahkemesi',
      'dosyaNo': '2026/123',
      'name': 'Avukat Evrak Kaydi (Beyan Dilekçesi)',
      'isinDurumu': status,
      'isinSahibi': 'Yazı İşleri Müdürü',
    });
    expect(op('Devam Ediyor').pending, isTrue);
    expect(op('Devam Ediyor').completed, isFalse);
    expect(op('Tamamlandı').completed, isTrue);
    expect(op('Tamamlandı').pending, isFalse);
    expect(op('Devam Ediyor').owner, 'Yazı İşleri Müdürü');
    expect(op('Tamamlandı').time, DateTime(2026, 9, 29, 10, 20));
  });

  group('sent documents pair with İşlemlerim records', () {
    const target = UyapCase(
      'handle-at-send',
      '2026/123 Esas',
      'court-1',
      'Kemer 1. Aile Mahkemesi',
    );
    UyapSendReceipt sent(DateTime at, {String type = 'Beyan Dilekçesi'}) =>
        UyapSendReceipt(
          target: target,
          documentName: 'beyan.udf',
          documentType: type,
          startedAt: at,
          confirmed: true,
        );
    UyapOperation record(
      String date, {
      String name = 'Avukat Evrak Kaydi (Beyan Dilekçesi)',
      String court = 'KEMER 1. AİLE MAHKEMESİ',
      String number = '2026/123',
      String status = 'Devam Ediyor',
    }) => UyapOperation.fromMap({
      'isEmirTarihi': date,
      'birimAdi': court,
      'dosyaNo': number,
      'name': name,
      'isinDurumu': status,
      // A fresh handle: never the one the send response carried.
      'evrakId': 'other-handle',
    });

    test('by case, time window and document type, not by evrakId', () {
      final receipt = sent(DateTime(2026, 9, 29, 10, 20, 30));
      final hit = record('2026-09-29 10:20:10.0', status: 'Tamamlandı');
      final matches = UyapSendReceipt.match(
        [receipt],
        [
          record('2026-09-29 10:20:10.0', number: '2026/192'),
          record('2026-09-29 10:20:10.0', court: 'Kemer 2. Aile Mahkemesi'),
          record('2026-09-28 10:20:10.0'),
          hit,
        ],
      );
      expect(matches[receipt], same(hit));
      expect(matches[receipt]!.completed, isTrue);
    });

    test('no record in the window leaves the receipt unmatched', () {
      final receipt = sent(DateTime(2026, 9, 29, 10, 20));
      expect(
        UyapSendReceipt.match(
          [receipt],
          [record('2026-09-29 11:00:00.0'), record('2026-09-29 10:00:00.0')],
        ),
        isEmpty,
      );
    });

    test('two sends to one case each claim their own record', () {
      final first = sent(DateTime(2026, 9, 29, 10, 20));
      final second = sent(
        DateTime(2026, 9, 29, 10, 22),
        type: 'Delil Dilekçesi',
      );
      final beyan = record('2026-09-29 10:20:05.0');
      final delil = record(
        '2026-09-29 10:22:05.0',
        name: 'Avukat Evrak Kaydı (Delil Dilekçesi)',
      );
      final matches = UyapSendReceipt.match([second, first], [delil, beyan]);
      expect(matches[first], same(beyan));
      expect(matches[second], same(delil));
    });
  });
}
