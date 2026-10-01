import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/signing/cades_builder.dart';
import 'package:evrak_convert/services/signing/x509_parser.dart';
import 'package:evrak_convert/services/signing/udf_signing_service.dart';

void main() {
  test(
    'CAdES envelope verifies with OpenSSL and UDF preserves original XML bytes',
    () async {
      final dir = await Directory.systemTemp.createTemp('evrak-cades-');
      addTearDown(() => dir.delete(recursive: true));
      Future<void> openssl(List<String> arguments) async {
        final result = await Process.run(
          'openssl',
          arguments,
          workingDirectory: dir.path,
        );
        expect(result.exitCode, 0, reason: result.stderr.toString());
      }

      await openssl([
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        'key.pem',
        '-out',
        'cert.pem',
        '-subj',
        '/CN=LifeOS Test/O=Test',
        '-days',
        '1',
      ]);
      await openssl([
        'x509',
        '-in',
        'cert.pem',
        '-outform',
        'DER',
        '-out',
        'cert.der',
      ]);
      final cert = await File('${dir.path}/cert.der').readAsBytes();
      final info = parseX509Certificate(cert)!;
      final xml = Uint8List.fromList(
        utf8.encode('<template>İmza test belgesi</template>'),
      );
      final params = CadesSigningParams(
        documentBytes: xml,
        signerCertDer: cert,
        issuerDer: info.issuerDer,
        serialNumberDer: info.serialNumberDer,
        signingTime: DateTime.now().toUtc(),
      );
      final signed = CadesBuilder.buildSignedAttributes(params);
      await File('${dir.path}/attrs.der').writeAsBytes(signed);
      await openssl([
        'dgst',
        '-sha256',
        '-sign',
        'key.pem',
        '-out',
        'signature.bin',
        'attrs.der',
      ]);
      params.signatureValue = await File('${dir.path}/signature.bin')
          .readAsBytes();
      expect(
        UdfSigningService.verifyRsa(cert, signed, params.signatureValue!),
        isTrue,
      );
      expect(
        UdfSigningService.verifyRsa(
          cert,
          Uint8List.fromList([1, 2, 3]),
          params.signatureValue!,
        ),
        isFalse,
      );
      final cms = CadesBuilder.buildCadesSignature(params);
      await File('${dir.path}/sign.sgn').writeAsBytes(cms);
      await File('${dir.path}/content.xml').writeAsBytes(xml);
      await openssl([
        'cms',
        '-verify',
        '-binary',
        '-inform',
        'DER',
        '-in',
        'sign.sgn',
        '-content',
        'content.xml',
        '-noverify',
        '-out',
        'verified.xml',
      ]);
      expect(await File('${dir.path}/verified.xml').readAsBytes(), xml);
      final archive = Archive()
        ..addFile(ArchiveFile('content.xml', xml.length, xml))
        ..addFile(ArchiveFile('metadata.xml', 3, [1, 2, 3]));
      final original = Uint8List.fromList(ZipEncoder().encode(archive));
      final result = UdfSigningService.embed(original, cms);
      final decoded = ZipDecoder().decodeBytes(result);
      expect(decoded.findFile('content.xml')!.content, xml);
      expect(decoded.findFile('metadata.xml')!.content, [1, 2, 3]);
      expect(decoded.findFile('sign.sgn')!.content, cms);
      expect(() => UdfSigningService.embed(result, cms), throwsStateError);
      expect(ZipDecoder().decodeBytes(original).findFile('sign.sgn'), isNull);
    },
  );
}
