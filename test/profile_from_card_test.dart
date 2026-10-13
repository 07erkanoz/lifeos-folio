import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/editor/profile_autofill.dart';
import 'package:evrak_convert/services/signing/pkcs11/pkcs11_session.dart';
import 'package:evrak_convert/services/signing/udf_signing_service.dart';
import 'package:evrak_convert/services/signing/x509_parser.dart';
import 'package:evrak_convert/ui/widgets/profile_from_card.dart';

SigningCertificate _cert(String name, String? serial, {bool expired = false}) {
  final now = DateTime.now();
  final empty = Uint8List(0);
  return SigningCertificate(
    CertificateInfo(
      keyId: empty,
      derBytes: empty,
      label: name,
      issuerDer: empty,
      serialNumberDer: empty,
      subjectDer: empty,
    ),
    X509CertInfo(
      subjectCN: name,
      issuerCN: 'Kamu SM',
      serialNumber: '01',
      notBefore: now.subtract(const Duration(days: 400)),
      notAfter: expired
          ? now.subtract(const Duration(days: 1))
          : now.add(const Duration(days: 400)),
      subjectSerialNumber: serial,
      issuerDer: empty,
      serialNumberDer: empty,
    ),
  );
}

void main() {
  test('the card\'s name and TC number: a valid certificate with a number '
      'before an expired one, the name in Turkish title case', () {
    final identity = identityOf([
      _cert('ESKİ SERTİFİKA', 'TCKN11111111111', expired: true),
      _cert('NİTELİKLİ OLMAYAN', null),
      _cert('DENİZ IŞIK YILMAZ', 'TCKN12345678901'),
    ]);
    expect(identity?.name, 'Deniz Işık Yılmaz');
    expect(identity?.tc, '12345678901');
    expect(identityOf([_cert('KİMLİKSİZ', null)]), isNull);
  });

  test('filling from an identity leaves the bar, its numbers and the '
      'office as they were', () {
    const current = LawyerProfile(
      lawyers: [Lawyer(name: '', bar: 'Antalya Barosu', barNumber: '1234')],
      phone: '0242 000 00 00',
      officeName: 'Kaya Hukuk Bürosu',
    );
    final filled = fillFromIdentity(
      current,
      name: 'Deniz Yılmaz',
      tc: '12345678901',
    );
    expect(filled.lawyer?.name, 'Deniz Yılmaz');
    expect(filled.lawyer?.idNumber, '12345678901');
    expect(filled.lawyer?.bar, 'Antalya Barosu');
    expect(filled.lawyer?.barNumber, '1234');
    expect(filled.phone, '0242 000 00 00');
    expect(filled.officeName, 'Kaya Hukuk Bürosu');
  });

  test('a portal filling the blanks keeps the office\'s name', () {
    const current = LawyerProfile(officeName: 'Kaya Hukuk Bürosu');
    final filled = fillProfileBlanks(current, name: 'Deniz Yılmaz');
    expect(filled.lawyer?.name, 'Deniz Yılmaz');
    expect(filled.officeName, 'Kaya Hukuk Bürosu');
  });
}
