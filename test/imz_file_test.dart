import 'dart:io';
import 'dart:typed_data';

import 'package:evrak_convert/services/signing/cades_builder.dart';
import 'package:evrak_convert/services/signing/imz_file.dart';
import 'package:evrak_convert/services/signing/x509_parser.dart';
import 'package:evrak_convert/ui/widgets/file_preview.dart';
import 'package:evrak_convert/ui/widgets/imz_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  Future<void> openssl(List<String> arguments) async {
    final result = await Process.run(
      'openssl',
      arguments,
      workingDirectory: dir.path,
    );
    expect(result.exitCode, 0, reason: result.stderr.toString());
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('folio-imz-');
    await openssl([
      'req', '-x509', '-utf8', '-newkey', 'rsa:2048', '-nodes', //
      '-keyout', 'key.pem', '-out', 'cert.pem',
      '-subj', '/CN=Ayşe Demir/O=Demir Muhasebe/serialNumber=TCKNO12345678901',
      '-days', '1',
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
  });
  tearDown(() => dir.delete(recursive: true));

  test(
    'an .imz another e-signature program wrote: its document, who '
    'signed it, and that the signature holds; changed after, it does not',
    () async {
      final pdf = Uint8List.fromList([
        ...'%PDF-1.4\n'.codeUnits,
        ...List.filled(5000, 65),
      ]);
      await File('${dir.path}/beyan.pdf').writeAsBytes(pdf);
      await openssl([
        'cms',
        '-sign',
        '-binary',
        '-nodetach',
        '-in',
        'beyan.pdf',
        '-signer',
        'cert.pem',
        '-inkey',
        'key.pem',
        '-outform',
        'DER',
        '-out',
        'beyan.pdf.imz',
      ]);
      final bytes = await File('${dir.path}/beyan.pdf.imz').readAsBytes();
      final read = ImzFile.read(bytes, 'beyan.pdf.imz')!;
      expect(read.content, pdf);
      expect(read.name, 'beyan.pdf');
      expect(read.valid, isTrue);
      expect(read.signers.single.signerName, contains('Ayşe Demir'));

      // A byte of the document changed inside the signature: it no longer
      // holds.
      final at = _indexOf(bytes, pdf.sublist(100, 140));
      final changed = Uint8List.fromList(bytes)..[at] = 66;
      expect(ImzFile.read(changed, 'beyan.pdf.imz')!.valid, isFalse);
    },
  );

  test('Folio\'s own attached signature reads back; a name without a kind '
      'is given the one its bytes show', () async {
    final cert = await File('${dir.path}/cert.der').readAsBytes();
    final info = parseX509Certificate(cert)!;
    final document = Uint8List.fromList('{\\rtf1 dilekçe}'.codeUnits);
    final params = CadesSigningParams(
      documentBytes: document,
      signerCertDer: cert,
      issuerDer: info.issuerDer,
      serialNumberDer: info.serialNumberDer,
    );
    await File('${dir.path}/attrs.der')
        .writeAsBytes(CadesBuilder.buildSignedAttributes(params));
    await openssl([
      'dgst',
      '-sha256',
      '-sign',
      'key.pem',
      '-out',
      'sig.bin',
      'attrs.der',
    ]);
    params.signatureValue = await File('${dir.path}/sig.bin').readAsBytes();
    final imz = CadesBuilder.buildCadesSignature(params, attached: true);
    final read = ImzFile.read(imz, 'dilekce.imz')!;
    expect(read.content, document);
    expect(read.valid, isTrue);
    expect(read.name, 'dilekce.rtf');
  });

  test('what is no signature is not read as one', () {
    expect(ImzFile.read(Uint8List.fromList([1, 2, 3]), 'x.imz'), isNull);
    expect(ImzFile.isImz('/a/b/sozlesme.pdf.IMZ'), isTrue);
    expect(ImzFile.isImz('/a/b/sozlesme.pdf'), isFalse);
  });

  testWidgets('an .imz opened: the signature holds, who signed it with the '
      'TC number shown in part, and its document read below', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await File('${dir.path}/not.txt').writeAsString('Kira bedeli 5.000 TL');
      await openssl([
        'cms', '-sign', '-binary', '-nodetach', '-in', 'not.txt', //
        '-signer', 'cert.pem', '-inkey', 'key.pem', '-outform', 'DER',
        '-out', 'not.txt.imz',
      ]);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ImzView(path: '${dir.path}/not.txt.imz')),
      ),
    );
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(FilePreview).evaluate().isNotEmpty) break;
    }
    expect(find.text('E-imza geçerli'), findsOneWidget);
    expect(find.textContaining('Ayşe Demir'), findsWidgets);
    // The document inside, taken out and read as any document is.
    expect(find.byType(FilePreview), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length && ok; j++) {
      ok = haystack[i + j] == needle[j];
    }
    if (ok) return i;
  }
  return -1;
}
