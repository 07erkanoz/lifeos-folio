import 'dart:io';

import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_accounts.dart';
import 'package:evrak_convert/services/clients/client_documents.dart';
import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final client = Client(
    id: 'k1',
    name: 'Ayşe Karaca',
    address: 'Muratpaşa / Antalya',
    phone: '0532 000 00 41',
    updated: DateTime(2026),
  );
  final fee = ClientRecord(
    id: 'f',
    clientId: 'k1',
    kind: ClientRecordKind.fee,
    data: {
      'dosya': 'a',
      'tutar': 4500000,
      'yuzde': 10,
      'taksitler': [
        {'tarih': DateTime(2026, 3, 12).toIso8601String(), 'tutar': 2250000},
        {'tarih': DateTime(2026, 6, 12).toIso8601String(), 'tutar': 2250000},
      ],
    },
    created: DateTime(2026),
    by: 'Av. Deniz Kaya',
    updated: DateTime(2026),
  );
  final paid = ClientRecord(
    id: 'h',
    clientId: 'k1',
    kind: ClientRecordKind.movement,
    data: {
      'dosya': 'a',
      'hesap': MovementKind.feePaid.code,
      'tutar': 2250000,
      'zaman': DateTime(2026, 3, 12, 16, 38).toIso8601String(),
      'odeme': 'Nakit',
      'makbuz': '0098',
    },
    created: DateTime(2026, 3, 12, 16, 40),
    by: 'Av. Deniz Kaya',
    updated: DateTime(2026, 3, 12, 16, 40),
  );

  test('an amount in words, as a receipt writes it', () {
    expect(inWords(1500000), 'on beş bin Türk lirası');
    expect(inWords(100000), 'bin Türk lirası');
    expect(
      inWords(123456789),
      'bir milyon iki yüz otuz dört bin beş yüz '
      'altmış yedi Türk lirası seksen dokuz kuruş',
    );
  });

  test('the fee agreement, the receipt and the release are written as UDF '
      'that opens again, filled from what is kept', () async {
    final root = Directory.systemTemp.createTempSync('folio_belge_');
    addTearDown(() => root.deleteSync(recursive: true));
    final texts = <String>[];
    for (final (name, model) in [
      (
        'Sözleşme',
        feeAgreementDocument(
          client: client,
          profile: const LawyerProfile(address: 'Antalya'),
          lawyer: 'Av. Deniz Kaya',
          work: '2024/318 · Antalya 3. Asliye Hukuk',
          fee: fee,
          now: DateTime(2026, 3, 12),
        ),
      ),
      (
        'Tahsilat',
        receiptDocument(
          client: client,
          movement: paid,
          lawyer: 'Av. Deniz Kaya',
          caseTitle: '2024/318',
        ),
      ),
      (
        'İbra',
        releaseDocument(
          client: client,
          account: caseAccounts([fee, paid])['a']!,
          lawyer: 'Av. Deniz Kaya',
          caseTitle: '2024/318',
        ),
      ),
    ]) {
      final path = await writeClientDocument(root, 'k1', name, model);
      final back = UdfReader.readFile(path);
      expect(back, isNotNull, reason: name);
      texts.add(back!.toPlainText());
    }
    expect(texts[0], contains('AVUKATLIK ÜCRET SÖZLEŞMESİ'));
    expect(texts[0], contains('45.000 TL (kırk beş bin Türk lirası)'));
    expect(texts[0], contains('12.06.2026 tarihinde 22.500 TL'));
    expect(texts[0], contains('0532 000 00 41'));
    expect(texts[1], contains('12.03.2026 16:38'));
    expect(texts[1], contains('yirmi iki bin beş yüz Türk lirası'));
    expect(texts[2], contains('22.500 TL avukatlık ücreti'));
  });
}
