import 'dart:io';

import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
import 'package:flutter_test/flutter_test.dart';

const _hukuk = UyapCaseLink(
  jurisdiction: '1',
  courtType: '0101',
  courtId: 'h1',
  court: 'Antalya 3. Asliye Hukuk Mahkemesi',
  number: '2025/80',
);

const _icra = UyapCaseLink(
  jurisdiction: '2',
  courtType: '0202',
  courtId: 'i1',
  court: 'Antalya 5. İcra Dairesi',
  number: '2025/4410',
);

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('folio-baglar-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  // Folio and each LifeOS Editör window are processes of their own, each
  // with its own copy of the ties: two instances on one folder are two
  // windows.
  test('a tie made in one window is not lost when another window ties '
      'another document, and each sees the other\'s', () async {
    final folio = UyapCaseLinks(directory: root);
    final editor = UyapCaseLinks(directory: root);
    final dilekce = '${root.path}/dilekce.udf';
    final takip = '${root.path}/takip.udf';
    await File(dilekce).writeAsString('x');
    await File(takip).writeAsString('x');

    // Both have read the ties (none yet) before either writes.
    expect(await folio.of(dilekce), isNull);
    expect(await editor.of(takip), isNull);

    await editor.link(dilekce, _hukuk);
    await folio.link(takip, _icra);

    // A third window, reading the file afresh, finds both.
    final fresh = UyapCaseLinks(directory: root);
    expect((await fresh.of(dilekce))?.number, '2025/80');
    expect((await fresh.of(takip))?.number, '2025/4410');
    // And each window sees what the other tied, without starting again.
    expect((await folio.of(dilekce))?.number, '2025/80');
    expect(await editor.documentsOf(_icra.court, _icra.number), [
      File(takip).absolute.path,
    ]);

    // Untying in one keeps the other's.
    await editor.link(takip, null);
    expect(await fresh.of(takip), isNull);
    expect((await fresh.of(dilekce))?.number, '2025/80');
  });

  test('ties made at once in one window are all kept', () async {
    final links = UyapCaseLinks(directory: root);
    final paths = [for (var i = 0; i < 6; i++) '${root.path}/belge$i.udf'];
    await Future.wait([for (final path in paths) links.link(path, _hukuk)]);
    final fresh = UyapCaseLinks(directory: root);
    for (final path in paths) {
      expect(await fresh.of(path), isNotNull, reason: path);
    }
  });
}
