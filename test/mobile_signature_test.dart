import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/signing/mobile_signature.dart';
import 'package:evrak_convert/services/signing/signed_data.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _der(int tag, List<int> body) {
  final n = body.length;
  final length = n < 0x80
      ? [n]
      : n < 0x100
      ? [0x81, n]
      : [0x82, n >> 8, n & 0xFF];
  return [tag, ...length, ...body];
}

List<int> _seq(List<List<int>> items) =>
    _der(0x30, items.expand((e) => e).toList());
List<int> _set(List<List<int>> items) =>
    _der(0x31, items.expand((e) => e).toList());
List<int> _oid(List<int> encoded) => _der(0x06, encoded);
final _sha256 = _oid([0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]);
final _data = _oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01]);
final _signedDataOid = _oid([
  0x2A,
  0x86,
  0x48,
  0x86,
  0xF7,
  0x0D,
  0x01,
  0x07,
  0x02,
]);
final _contentTypeOid = _oid([
  0x2A,
  0x86,
  0x48,
  0x86,
  0xF7,
  0x0D,
  0x01,
  0x09,
  0x03,
]);
final _messageDigestOid = _oid([
  0x2A,
  0x86,
  0x48,
  0x86,
  0xF7,
  0x0D,
  0x01,
  0x09,
  0x04,
]);

/// A SignedData shaped like the ones UYAP's service returns: content inside,
/// one signer, a certificate. Nothing in it is a real person's.
Uint8List signatureForTest(
  List<int> signedOver, {
  int serial = 7,
  bool embedded = true,
}) {
  final certificate = _seq([
    _der(0x02, [serial]),
    _der(0x0C, utf8.encode('Deneme İmzacı $serial')),
  ]);
  final signer = _seq([
    _der(0x02, [1]),
    _seq([
      _seq([_der(0x0C, utf8.encode('Deneme ESHS'))]),
      _der(0x02, [serial]),
    ]),
    _seq([_sha256]),
    _der(0xA0, [
      ..._seq([
        _contentTypeOid,
        _set([_data]),
      ]),
      ..._seq([
        _messageDigestOid,
        _set([_der(0x04, sha256.convert(signedOver).bytes)]),
      ]),
    ]),
    _seq([
      _oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]),
    ]),
    _der(0x04, List.filled(16, serial)),
  ]);
  final encapsulated = _seq([
    _data,
    if (embedded) _der(0xA0, _der(0x04, signedOver)),
  ]);
  return Uint8List.fromList(
    _seq([
      _signedDataOid,
      _der(
        0xA0,
        _seq([
          _der(0x02, [1]),
          _set([
            _seq([_sha256]),
          ]),
          encapsulated,
          _der(0xA0, certificate),
          _set([signer]),
        ]),
      ),
    ]),
  );
}

Uint8List _udf() => Uint8List.fromList(
  UdfWriter.writeBytes(
    DocModel(blocks: [DocBlock(plainText: 'Arabuluculuk son tutanağı')]),
  ),
);

int _signers(Uint8List udf) => SignedData.signerCount(
  Uint8List.fromList(
    ZipDecoder().decodeBytes(udf).findFile('sign.sgn')!.content,
  ),
);

void main() {
  final udf = _udf();
  final content = SignedData.content(udf);

  test('a signature over the document is detached and kept beside its '
      'untouched content.xml', () {
    final embedded = signatureForTest(content);
    expect(SignedData.covers(embedded, content), isTrue);
    final detached = SignedData.detach(embedded);
    expect(detached.length, lessThan(embedded.length - content.length + 8));
    expect(SignedData.covers(detached, content), isTrue);
    expect(SignedData.detach(detached), detached, reason: 'zaten ayrık');

    final signed = SignedData.sign(udf, embedded);
    final archive = ZipDecoder().decodeBytes(signed);
    expect(
      archive.files.map((f) => f.name),
      unorderedEquals(['content.xml', 'sign.sgn']),
    );
    expect(archive.findFile('content.xml')!.content, content);
    expect(archive.findFile('sign.sgn')!.content, detached);
    expect(UdfReader.readBytes(signed)!.metadata['hasSignature'], isTrue);
  });

  test('a signature over data with its first 100 bytes zeroed is refused, '
      'and nothing is produced', () {
    // What UYAP's service returns to a client it does not recognise.
    final zeroed = [...List.filled(100, 0), ...content.skip(100)];
    final broken = signatureForTest(zeroed);
    expect(SignedData.covers(broken, content), isFalse);
    expect(() => SignedData.sign(udf, broken), throwsFormatException);
  });

  test('a second signer joins the first in one sign.sgn; the same one twice '
      'keeps one certificate', () {
    final first = SignedData.sign(udf, signatureForTest(content, serial: 7));
    final second = SignedData.sign(first, signatureForTest(content, serial: 9));
    expect(_signers(second), 2);
    expect(
      ZipDecoder().decodeBytes(second).findFile('content.xml')!.content,
      content,
    );
    final sgn = Uint8List.fromList(
      ZipDecoder().decodeBytes(second).findFile('sign.sgn')!.content,
    );
    expect(SignedData.covers(sgn, content), isTrue);

    final again = SignedData.sign(first, signatureForTest(content, serial: 7));
    expect(
      _signers(again),
      1,
      reason: 'aynı imzacı aynı imzayı tekrar eklemez',
    );
    expect(
      () => SignedData.merge(
        signatureForTest(content),
        signatureForTest(utf8.encode('başka bir metin')),
      ),
      throwsFormatException,
    );
  });

  test('phone numbers are read however they are typed', () {
    for (final typed in [
      '0532 123 45 67',
      '5321234567',
      '+90 (532) 123-45-67',
    ]) {
      expect(MobileUdfSigner.phone(typed), '05321234567');
    }
    expect(MobileUdfSigner.phone('0212 123 45 67'), isNull);
    expect(MobileUdfSigner.phone('532'), isNull);
  });

  test('the service is asked the way the UYAP editor asks it, and the signed '
      'file replaces the unsigned one', () async {
    final dir = await Directory.systemTemp.createTemp('folio-mobile-sign-');
    addTearDown(() => dir.delete(recursive: true));
    final previous = DocumentHistory.instance;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    addTearDown(() => DocumentHistory.instance = previous);
    final file = File('${dir.path}/tutanak.udf');
    await file.writeAsBytes(udf);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seen = <(String?, String?, String)>[];
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      seen.add((
        request.headers.value('user-agent'),
        request.headers.value('soapaction'),
        body,
      ));
      final operation = request.headers
          .value('soapaction')!
          .replaceAll('"', '');
      final answer = operation == 'getHash'
          ? '<resultCode>0</resultCode><apTransId>T-42</apTransId>'
                '<fingerPrint>7A1B</fingerPrint>'
          : '<resultCode>0</resultCode><identityNo>11111111110</identityNo>'
                '<data>${base64Encode(signatureForTest(content))}</data>';
      request.response
        ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
        ..write(
          '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">'
          '<soapenv:Body><p1:${operation}Response xmlns:p1="x"><${operation}Return>'
          '$answer</${operation}Return></p1:${operation}Response></soapenv:Body>'
          '</soapenv:Envelope>',
        );
      await request.response.close();
    });

    final signer = MobileUdfSigner(
      client: MobileSignatureClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
      ),
    );
    final request = await signer.start(
      file.path,
      '05321234567',
      MobileOperator.vodafone,
    );
    expect(request.code, '7A1B');
    expect(request.alreadySigned, isFalse);
    final path = await signer.finish(request);
    expect(path, file.path);

    expect(seen, hasLength(2));
    expect(seen.map((s) => s.$1), everyElement('Axis/1.3'));
    expect(seen.map((s) => s.$2), ['"getHash"', '"getSignature"']);
    expect(
      seen.first.$3,
      contains(
        '<getHash xmlns="http://client.mimza.uyap.gov.tr">'
        '<dataToBeSigned xmlns="">${base64Encode(content)}</dataToBeSigned>'
        '<telNo xmlns="">05321234567</telNo>'
        '<gsmOperator xmlns="">3</gsmOperator></getHash>',
      ),
    );
    expect(seen.last.$3, contains('<apTransId xmlns="">T-42</apTransId>'));
    expect(seen.last.$3, contains('Evrak Mobil Imza Talebi'));

    final signed = await file.readAsBytes();
    expect(UdfReader.readBytes(signed)!.metadata['hasSignature'], isTrue);
    final versions = await DocumentHistory.instance.versions(
      DocumentHistory.documentKey(file.path),
    );
    expect(versions.map((v) => v.kind), containsAll(['before-sign', 'signed']));
  });

  test('a refusal from the service is shown as its own message', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.write(
        '<Envelope><Body><r><resultCode>5</resultCode>'
        '<message>Kullanıcı işlemi iptal etti</message></r></Body></Envelope>',
      );
      await request.response.close();
    });
    final client = MobileSignatureClient(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    await expectLater(
      client.awaitSignature('T-1'),
      throwsA(
        isA<MobileSignatureException>().having(
          (e) => e.message,
          'message',
          'Kullanıcı işlemi iptal etti',
        ),
      ),
    );
  });
}
