import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:evrak_convert/services/legal/legislation_annexes.dart';
import 'package:flutter_test/flutter_test.dart';

// A document's annexes filed apart (the Avukatlık Asgari Ücret Tarifesi's
// amounts are all in its "-Ek.doc"): only mevzuat.gov.tr's own files, set
// after the text with where they are from; a regulation's zip package by
// its directory and one annex at a time.
void main() {
  test('only the Mevzuat Bilgi Sistemi\'s own files', () {
    bool ok(String u) => LegislationAnnexes.allowed(Uri.parse(u));
    expect(
      ok('https://www.mevzuat.gov.tr/MevzuatMetin/yonetmelik/9.5.42687-Ek.doc'),
      isTrue,
    );
    expect(ok('http://www.mevzuat.gov.tr/MevzuatMetin/a.doc'), isFalse);
    expect(ok('https://ornek.com/MevzuatMetin/a.doc'), isFalse);
    expect(ok('https://www.mevzuat.gov.tr/baska/a.doc'), isFalse);
    expect(ok('https://www.mevzuat.gov.tr/MevzuatMetin/a.exe'), isFalse);
    final links = LegislationAnnexes.linksIn(
      '<p>Eki için <a href="9.5.42687-Ek.doc">tıklayınız</a> '
      '<a href="https://kotu.example/MevzuatMetin/x.doc">x</a> '
      '<a href="#ust">üst</a></p>',
    );
    expect(links.map((u) => '$u'), [
      'https://www.mevzuat.gov.tr/MevzuatMetin/yonetmelik/9.5.42687-Ek.doc',
    ]);
  });

  test('the annex set after the text; one that fails said so', () async {
    final asked = <Uri>[];
    final annexes = LegislationAnnexes(
      textOf: (path) async => File(path).readAsStringSync(),
      download: (u) async {
        asked.add(u);
        if (u.path.contains('bozuk')) throw const HttpException('zaman aşımı');
        return utf8.encode(
          'Asliye Mahkemelerinde takip edilen davalar için\n45.000,00 TL',
        );
      },
    );
    const base = 'https://www.mevzuat.gov.tr/MevzuatMetin/yonetmelik/';
    final text = await annexes.withAnnexes('MADDE 1 – Genel hükümler.', [
      '${base}9.5.42687-Ek.txt',
      '${base}9.5.42687-Ek.txt',
      '${base}bozuk.txt',
    ]);
    expect(text, startsWith('MADDE 1'));
    expect(text, contains('EK BELGE 1/2 — 9.5.42687-Ek.txt'));
    expect(text, contains('45.000,00 TL'));
    expect(text, contains('EK BELGE 2/2 — bozuk.txt'));
    expect(text, contains('Ek okunamadı'));
    expect(text, contains('tahmin etme'));
    // Read once; the failed one tried again next time.
    await annexes.withAnnexes('', ['${base}9.5.42687-Ek.txt']);
    expect(asked.where((u) => u.path.endsWith('Ek.txt')), hasLength(1));
  });

  test('a regulation\'s package: its directory, an annex by number or '
      'name, the main text\'s copies left out', () async {
    final zip = Archive()
      ..addFile(ArchiveFile.string('7- Yapım İşleri Sözleşme.txt', 'TİP'))
      ..addFile(
        ArchiveFile.string(
          '8- Yapım İşleri Genel Şartname.txt',
          'Madde 29 Mücbir sebepler',
        ),
      )
      ..addFile(ArchiveFile.string('7.5.12916.htm', '<html>ana</html>'));
    final bytes = Uint8List.fromList(ZipEncoder().encode(zip));
    final annexes = LegislationAnnexes(
      textOf: (path) async => File(path).readAsStringSync(),
      download: (_) async => bytes,
    );
    expect(
      LegislationAnnexes.packageUrl('12916', 'KKY'),
      endsWith('/yonetmelik/7.5.12916-Ek.zip'),
    );
    expect(LegislationAnnexes.packageUrl('12916', 'KANUN'), isNull);
    final package = await annexes.package('12916', 'KKY');
    expect(package.map((a) => a.name), [
      '7- Yapım İşleri Sözleşme.txt',
      '8- Yapım İşleri Genel Şartname.txt',
    ]);
    expect(LegislationAnnexes.pick(package, '8')!.text, contains('Mücbir'));
    expect(
      LegislationAnnexes.pick(package, 'GENEL ŞARTNAME')!.name,
      startsWith('8-'),
    );
    expect(LegislationAnnexes.pick(package, '3'), isNull);
    expect(
      await annexes.openPackage(Uint8List.fromList('<html>404'.codeUnits), ''),
      isEmpty,
    );
    // A DOS name: cp857's ş and İ.
    expect(
      LegislationAnnexes.turkishName(String.fromCharCodes([0x9F, 0x98])),
      'şİ',
    );
  });
}
