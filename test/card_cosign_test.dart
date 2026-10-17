import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:evrak_convert/services/signing/cades_builder.dart';
import 'package:evrak_convert/services/signing/signed_data.dart';
import 'package:evrak_convert/services/signing/udf_signing_service.dart';
import 'package:evrak_convert/services/signing/x509_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/signatures/$name').readAsBytesSync();

Uint8List _udf(List<int> content, [List<int>? signature]) => Uint8List.fromList(
  ZipEncoder().encode(
    Archive()
      ..addFile(ArchiveFile('content.xml', content.length, content))
      ..addFile(ArchiveFile('metadata.xml', 3, [1, 2, 3]))
      ..addFile(
        ArchiveFile('sign.sgn', signature?.length ?? 0, signature ?? []),
      ),
  ),
);

Uint8List _unsigned(List<int> content) => Uint8List.fromList(
  ZipEncoder().encode(
    Archive()..addFile(ArchiveFile('content.xml', content.length, content)),
  ),
);

void main() {
  final content = _fixture('content.xml');

  test('a card\'s signature is the first on an unsigned document, as the '
      'card builds it', () {
    final cert = _fixture('unrelated-ca.der');
    final info = parseX509Certificate(cert)!;
    final params = CadesSigningParams(
      documentBytes: content,
      signerCertDer: cert,
      issuerDer: info.issuerDer,
      serialNumberDer: info.serialNumberDer,
      signingTime: DateTime.now().toUtc(),
    )..signatureValue = Uint8List(256);
    final cades = CadesBuilder.buildCadesSignature(params);
    final original = _unsigned(content);
    UdfSigningService.ensureCanAdd(original);
    final out = UdfSigningService.signedWith(original, cades);
    final archive = ZipDecoder().decodeBytes(out);
    expect(archive.findFile('content.xml')!.content, content);
    expect(SignedData.signerCount(SignedData.signatureOf(out)!), 1);
  });

  test('on a document signed before, a card\'s signature goes beside the '
      'others, the text as it was', () {
    final signed = _udf(content, _fixture('rsa-valid.sgn'));
    UdfSigningService.ensureCanAdd(signed);
    final out = UdfSigningService.signedWith(signed, _fixture('multiple.sgn'));
    final archive = ZipDecoder().decodeBytes(out);
    expect(archive.findFile('content.xml')!.content, content);
    expect(archive.findFile('metadata.xml')!.content, [1, 2, 3]);
    final signature = SignedData.signatureOf(out)!;
    expect(SignedData.signerCount(signature), 3);
    expect(SignedData.covers(signature, content), isTrue);
  });

  test('a document whose signature is not over its text takes none, '
      'before the card is asked', () {
    final changed = _udf([...content, 0x20], _fixture('rsa-valid.sgn'));
    expect(() => UdfSigningService.ensureCanAdd(changed), throwsStateError);
    expect(
      () => UdfSigningService.signedWith(
        _unsigned([...content, 0x20]),
        _fixture('multiple.sgn'),
      ),
      throwsStateError,
    );
  });
}
