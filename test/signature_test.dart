import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:asn1lib/asn1lib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/udf/signature_parser.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';

const fixtures = 'test/fixtures/signatures';
List<int> fixture(String name) => File('$fixtures/$name').readAsBytesSync();

// Reorder the certificate bag independently of signerInfos. A CA first is
// legitimate and must never cause the CA to be displayed as the document signer.
List<int> caFirst(List<int> cms) {
  final outer =
      ASN1Parser(Uint8List.fromList(cms)).nextObject() as ASN1Sequence;
  final data =
      ASN1Parser(outer.elements[1].valueBytes()).nextObject() as ASN1Sequence;
  final ca = fixture('unrelated-ca.der');
  final replacement = ASN1Sequence(tag: 0xa0)
    ..add(ASN1Object.fromBytes(Uint8List.fromList(ca)));
  final certs = data.elements.indexWhere((f) => f.tag == 0xa0);
  final parser = ASN1Parser(data.elements[certs].valueBytes());
  while (parser.hasNext()) {
    final cert = parser.nextObject();
    if (cert.encodedBytes.toString() != ca.toString()) replacement.add(cert);
  }
  final updated = ASN1Sequence();
  for (var i = 0; i < data.elements.length; i++) {
    updated.add(i == certs ? replacement : data.elements[i]);
  }
  return (ASN1Sequence()
        ..add(outer.elements[0])
        ..add(ASN1Sequence(tag: 0xa0)..add(updated)))
      .encodedBytes;
}

List<int> syntheticCms(void Function(ASN1Sequence) modify) {
  final outer =
      ASN1Parser(Uint8List.fromList(fixture('multiple.sgn'))).nextObject()
          as ASN1Sequence;
  final data =
      ASN1Parser(outer.elements[1].valueBytes()).nextObject() as ASN1Sequence;
  modify(data);
  final rebuilt = ASN1Sequence();
  for (final field in data.elements) {
    rebuilt.add(field);
  }
  return (ASN1Sequence()
        ..add(outer.elements[0])
        ..add(ASN1Sequence(tag: 0xa0)..add(rebuilt)))
      .encodedBytes;
}

void main() {
  test(
    'counter signatures remain distinct and signing time uses X509 year pivot',
    () {
      final bytes = syntheticCms((data) {
        final signers = data.elements.last as ASN1Set;
        final mainSigner = signers.elements.first as ASN1Sequence;
        final updated = ASN1Sequence();
        for (final field in mainSigner.elements) {
          if (field.tag != 0xa0) {
            updated.add(field);
          } else {
            updated.add(
              ASN1Sequence(tag: 0xa0)..add(
                ASN1Sequence()
                  ..add(
                    ASN1ObjectIdentifier.fromComponentString(
                      '1.2.840.113549.1.9.5',
                    ),
                  )
                  ..add(
                    ASN1Set()..add(
                      ASN1Object.preEncoded(
                        0x17,
                        Uint8List.fromList(ascii.encode('600102030405Z')),
                      ),
                    ),
                  ),
              ),
            );
          }
        }
        updated.add(
          ASN1Sequence(tag: 0xa1)..add(
            ASN1Sequence()
              ..add(
                ASN1ObjectIdentifier.fromComponentString(
                  '1.2.840.113549.1.9.6',
                ),
              )
              ..add(ASN1Set()..add(signers.elements.last)),
          ),
        );
        data.elements[data.elements.length - 1] = ASN1Set()..add(updated);
      });
      final infos = UdfSignatureParser.parse(bytes);
      expect(infos, hasLength(2));
      expect(infos.first.counterSignature, isFalse);
      expect(infos.last.counterSignature, isTrue);
      expect(infos.first.signedAt, DateTime.utc(1960, 1, 2, 3, 4, 5));
      expect(infos.first.signerName, isNot(infos.last.signerName));
    },
  );

  test('BMPString Turkish subject name is decoded as UTF16 big endian', () {
    const name = 'Test Şule Çağrı';
    final bytes = syntheticCms((data) {
      final index = data.elements.indexWhere((f) => f.tag == 0xa0);
      final parser = ASN1Parser(data.elements[index].valueBytes());
      final bag = ASN1Sequence(tag: 0xa0);
      while (parser.hasNext()) {
        final cert = parser.nextObject() as ASN1Sequence;
        final tbs = cert.elements.first as ASN1Sequence;
        final offset = tbs.elements.first.tag == 0xa0 ? 1 : 0;
        final modified = ASN1Sequence();
        for (var i = 0; i < tbs.elements.length; i++) {
          if (i != offset + 4) {
            modified.add(tbs.elements[i]);
          } else {
            modified.add(
              ASN1Sequence()..add(
                ASN1Set()..add(
                  ASN1Sequence()
                    ..add(ASN1ObjectIdentifier.fromComponentString('2.5.4.3'))
                    ..add(
                      ASN1Object.preEncoded(
                        0x1e,
                        Uint8List.fromList([
                          for (final unit in name.codeUnits) ...[
                            unit >> 8,
                            unit & 255,
                          ],
                        ]),
                      ),
                    ),
                ),
              ),
            );
          }
        }
        bag.add(
          ASN1Sequence()
            ..add(modified)
            ..add(cert.elements[1])
            ..add(cert.elements[2]),
        );
      }
      data.elements[index] = bag;
    });
    final infos = UdfSignatureParser.parse(bytes);
    expect(infos, hasLength(2));
    expect(infos.every((i) => i.signerName == name), isTrue);
  });

  test('real CMS matches both Turkish signers, not unrelated first CA', () {
    final reordered = caFirst(fixture('multiple.sgn'));
    final signers = UdfSignatureParser.parse(reordered);
    expect(signers, hasLength(2));
    expect(
      signers.map((s) => s.signerName),
      unorderedEquals(['Test İmzacı Şule', 'Test İmzacı Çağrı']),
    );
    expect(
      signers.map((s) => s.certificateSerial),
      unorderedEquals(['65', '66']),
    );
    for (final signer in signers) {
      expect(signer.organization, 'LifeOS Test');
      expect(signer.subjectIdentifier, startsWith('TEST-'));
      expect(signer.signedAt, isNotNull);
      expect(signer.validFrom, isNotNull);
      expect(signer.validUntil!.isAfter(signer.validFrom!), isTrue);
      expect(signer.issue, isNull);
    }
  });

  test('subject key identifier selects the matching certificate', () {
    final signer = UdfSignatureParser.parse(fixture('keyid.sgn')).single;
    expect(signer.signerName, 'Test İmzacı Şule');
    expect(signer.issue, isNull);
  });

  test('missing or malformed certificates never invent signer identity', () {
    final signer = UdfSignatureParser.parse(fixture('missing-certificate.sgn'))
        .single;
    expect(signer.signerName, isNull);
    expect(signer.issue, contains('eşleştirilemedi'));
    expect(UdfSignatureParser.parse([1, 2, 3]), isEmpty);
    expect(
      UdfSignatureParser.parse(fixture('multiple.sgn').sublist(0, 70)),
      isEmpty,
    );
  });

  test(
    'UDF reader includes signer metadata; regenerated copy removes signature',
    () {
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'content.xml',
            fixture('content.xml').length,
            fixture('content.xml'),
          ),
        )
        ..addFile(
          ArchiveFile(
            'sign.sgn',
            fixture('multiple.sgn').length,
            fixture('multiple.sgn'),
          ),
        );
      final bytes = ZipEncoder().encode(archive);
      final original = List<int>.from(bytes);
      final model = UdfReader.readBytes(bytes)!;
      expect(model.metadata['hasSignature'], isTrue);
      expect(model.metadata['signatureInfos'], hasLength(2));
      final copy = UdfReader.readBytes(UdfWriter.writeBytes(model))!;
      expect(copy.metadata['hasSignature'], isFalse);
      expect(bytes, original);
    },
  );
}
