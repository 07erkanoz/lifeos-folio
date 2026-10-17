// Builds assets/mevzuat/karar_kaliplari.json, the marks of the sentences
// that many decisions say word for word: a tool, not part of the suite.
//
//   flutter test tool/olcum/karar_kaliplari_test.dart
//
// Counted over decisions fetched for the purpose and never over the ones
// in test/fixtures/decisions, which are what the anatomy is measured
// against: marking a sentence stock because it repeats among the measured
// decisions themselves would grade the work with its own answers. The
// texts are kept outside the repository (KARAR_DERLEMI, by default a
// folder in the system temp), so a second run needs no network.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/legal/case_law.dart';
import 'package:evrak_convert/services/legal/case_law_search.dart';
import 'package:evrak_convert/services/legal/decision_anatomy.dart';
import 'package:flutter_test/flutter_test.dart';

const _host = 'bedesten.adalet.gov.tr';

Future<String> _send(String path, String? body) async {
  for (var attempt = 0; attempt < 6; attempt++) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(Uri.parse('https://$_host$path'));
      request.headers.set(HttpHeaders.userAgentHeader, 'Folio');
      request.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      if (body != null) request.write(body);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final refused =
          response.statusCode == 429 || text.trimLeft().startsWith('<');
      if (!refused && response.statusCode == HttpStatus.ok) return text;
      stdout.writeln('  ${response.statusCode}: bekleniyor (${attempt + 1})');
    } on IOException catch (e) {
      stdout.writeln('  ağ hatası: $e');
    } finally {
      client.close(force: true);
    }
    await Future<void>.delayed(Duration(seconds: 8 * (attempt + 1)));
  }
  return '<refused/>';
}

void main() {
  test(
    'karar kalıpları',
    timeout: const Timeout(Duration(minutes: 60)),
    () async {
      final store = Directory(
        Platform.environment['KARAR_DERLEMI'] ??
            '${Directory.systemTemp.path}/folio_karar_derlemi',
      )..createSync(recursive: true);
      // Both the decisions tuned on and the ones held back to check them.
      final measured = {
        for (final name in ['index.json', 'index_dogrulama.json'])
          if (File('test/fixtures/decisions/$name').existsSync())
            for (final row
                in jsonDecode(
                      File('test/fixtures/decisions/$name').readAsStringSync(),
                    )
                    as List)
              (row as Map)['documentId'] as String,
      };

      final y = {CourtKind.yargitay};
      // Each civil chamber twice: as the bank ranks it, which is mostly the
      // older form, and since 2024, when the sectioned form brought stock
      // sentences of its own.
      final recent = DateTime.utc(2024, 1, 1);
      final asks = <(String, Set<CourtKind>, String?, DateTime?)>[
        for (final (words, chamber) in [
          ('fazla mesai', '9. Hukuk Dairesi'),
          ('ecrimisil', '1. Hukuk Dairesi'),
          ('velayet', '2. Hukuk Dairesi'),
          ('tahliye', '3. Hukuk Dairesi'),
          ('haksız fiil', '4. Hukuk Dairesi'),
          ('kamulaştırma bedel', '5. Hukuk Dairesi'),
          ('ortaklığın giderilmesi', '7. Hukuk Dairesi'),
          ('sigorta', '11. Hukuk Dairesi'),
          ('icra takibi', '12. Hukuk Dairesi'),
          ('direnme', 'Hukuk Genel Kurulu'),
          ('hizmet tespiti', '10. Hukuk Dairesi'),
        ])
          ('$words|$chamber|yeni', y, chamber, recent),
        for (final words in ['alacak', 'tazminat', 'kira'])
          ('$words|bam|yeni', {CourtKind.istinaf}, null, recent),
        for (final words in ['ruhsat', 'vergi'])
          ('$words|danıştay|yeni', {CourtKind.danistay}, null, recent),
        for (final (words, chamber) in [
          ('fazla mesai', '9. Hukuk Dairesi'),
          ('yıllık izin', '9. Hukuk Dairesi'),
          ('ecrimisil', '1. Hukuk Dairesi'),
          ('muris muvazaası', '1. Hukuk Dairesi'),
          ('velayet', '2. Hukuk Dairesi'),
          ('tahliye', '3. Hukuk Dairesi'),
          ('haksız fiil', '4. Hukuk Dairesi'),
          ('kamulaştırma bedel', '5. Hukuk Dairesi'),
          ('ortaklığın giderilmesi', '6. Hukuk Dairesi'),
          ('kadastro', '8. Hukuk Dairesi'),
          ('sigorta', '11. Hukuk Dairesi'),
          ('icra takibi', '12. Hukuk Dairesi'),
          ('vekalet ücreti', '13. Hukuk Dairesi'),
          ('rücu', '17. Hukuk Dairesi'),
          ('direnme', 'Hukuk Genel Kurulu'),
          ('hizmet tespiti', '10. Hukuk Dairesi'),
        ])
          ('$words|$chamber', y, chamber, null),
        for (final words in [
          'alacak',
          'tazminat',
          'kira',
          'tapu',
          'işçilik',
          'boşanma',
        ])
          (words, {CourtKind.istinaf}, null, null),
        for (final words in ['ruhsat', 'vergi', 'atama', 'ihale'])
          (words, {CourtKind.danistay}, null, null),
        for (final words in ['alacak', 'itiraz'])
          (words, {CourtKind.yerel}, null, null),
      ];

      final bank = CaseLaw(
        send: _send,
        between: const Duration(milliseconds: 2500),
      );
      for (final (label, kinds, chamber, from) in asks) {
        final words = label.split('|').first;
        stdout.writeln(label);
        final results = await bank.search(
          CaseLawQuery(
            words: words,
            kinds: kinds,
            chamber: chamber,
            from: from,
            to: from == null ? null : DateTime.utc(2026, 10, 1),
            pageSize: 20,
          ),
        );
        var got = 0;
        for (final hit in results.hits) {
          if (got >= 6) break;
          if (measured.contains(hit.documentId)) continue;
          final file = File('${store.path}/${hit.documentId}.txt');
          if (file.existsSync()) {
            got++;
            continue;
          }
          final decision = await bank.byId(hit);
          if (decision == null) continue;
          file.writeAsStringSync(decision.text);
          got++;
        }
        stdout.writeln('  $got');
      }

      final texts = [
        for (final file in store.listSync().whereType<File>())
          if (file.path.endsWith('.txt') &&
              !measured.contains(
                file.uri.pathSegments.last.replaceAll('.txt', ''),
              ))
            file.readAsStringSync(),
      ];
      final keys = DecisionBoilerplate.repeatedIn(texts, inAtLeast: 3).toList()
        ..sort();
      File('assets/mevzuat/karar_kaliplari.json').writeAsStringSync(
        '${const JsonEncoder.withIndent(' ').convert({
          'aciklama':
              'Birçok kararda kelimesi kelimesine geçen cümlelerin işaretleri '
              '(DecisionBoilerplate.keyOf). tool/olcum/karar_kaliplari_test.dart '
              'üretir; ölçülen kararlar (test/fixtures/decisions) sayılmaz.',
          'karar_sayisi': texts.length,
          'esik': 3,
          'anahtarlar': keys,
        })}\n',
      );
      stdout.writeln('${texts.length} karar, ${keys.length} kalıp cümle');
    },
  );
}
