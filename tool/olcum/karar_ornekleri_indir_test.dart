// Fetches the decisions the decision-anatomy measurement is run against:
// a tool, not part of the test suite.
//
//   flutter test tool/olcum/karar_ornekleri_indir_test.dart
//
// Asks Bedesten through Folio's own client, one request every two and a
// half seconds, and waits out a refusal rather than giving up on it. The
// texts land in test/fixtures/decisions/ beside an index of where each came
// from; the expected answers for each are written by hand afterwards, in
// expected.json, and are not touched by this.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/legal/case_law.dart';
import 'package:evrak_convert/services/legal/case_law_search.dart';
import 'package:flutter_test/flutter_test.dart';

const _host = 'bedesten.adalet.gov.tr';

/// The bank, asked politely: a refusal (429, or the web page it answers a
/// hurried caller with) is waited out, longer each time.
Future<String> _send(String path, String? body) async {
  for (var attempt = 0; attempt < 6; attempt++) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.parse('https://$_host$path');
      final request = await client.postUrl(uri);
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

typedef _Ask = ({
  String group,
  String words,
  Set<CourtKind> kinds,
  String? chamber,
  DateTime? from,
  DateTime? to,
  int take,
});

_Ask _ask(
  String group,
  String words,
  Set<CourtKind> kinds, {
  String? chamber,
  DateTime? from,
  DateTime? to,
  int take = 2,
}) => (
  group: group,
  words: words,
  kinds: kinds,
  chamber: chamber,
  from: from,
  to: to,
  take: take,
);

void main() {
  test(
    'Bedesten örnek kararları',
    timeout: const Timeout(Duration(minutes: 40)),
    () async {
      // The decisions measured against have been read by hand since; a
      // second fetch would replace them under the same names.
      if (File('test/fixtures/decisions/index.json').existsSync() &&
          Platform.environment['YENIDEN'] != '1') {
        markTestSkipped('index.json var; yeniden indirmek için YENIDEN=1');
        return;
      }
      final y = {CourtKind.yargitay};
      final newFrom = DateTime.utc(2025, 1, 1);
      final newTo = DateTime.utc(2026, 10, 1);
      final oldFrom = DateTime.utc(2015, 1, 1);
      final oldTo = DateTime.utc(2019, 12, 31);
      final asks = <_Ask>[
        // The Court of Cassation's civil chambers, in the sectioned form
        // they have written in since 2023.
        _ask(
          'yargitay_yeni',
          'kıdem tazminatı',
          y,
          chamber: '9. Hukuk Dairesi',
          from: newFrom,
          to: newTo,
        ),
        _ask(
          'yargitay_yeni',
          'tapu iptal tescil',
          y,
          chamber: '1. Hukuk Dairesi',
          from: newFrom,
          to: newTo,
        ),
        _ask(
          'yargitay_yeni',
          'nafaka boşanma',
          y,
          chamber: '2. Hukuk Dairesi',
          from: newFrom,
          to: newTo,
        ),
        _ask(
          'yargitay_yeni',
          'kira tespit',
          y,
          chamber: '3. Hukuk Dairesi',
          from: newFrom,
          to: newTo,
        ),
        _ask(
          'yargitay_yeni',
          'manevi tazminat',
          y,
          chamber: '4. Hukuk Dairesi',
          from: newFrom,
          to: newTo,
        ),
        _ask(
          'yargitay_yeni',
          'kamulaştırmasız el atma',
          y,
          chamber: '5. Hukuk Dairesi',
          from: newFrom,
          to: newTo,
        ),
        _ask(
          'yargitay_yeni',
          'ortaklığın giderilmesi',
          y,
          chamber: '7. Hukuk Dairesi',
          from: newFrom,
          to: newTo,
        ),
        _ask(
          'yargitay_yeni',
          'itirazın iptali',
          y,
          chamber: '11. Hukuk Dairesi',
          from: newFrom,
          to: newTo,
        ),
        _ask(
          'yargitay_yeni',
          'menfi tespit icra',
          y,
          chamber: '12. Hukuk Dairesi',
          from: newFrom,
          to: newTo,
          take: 1,
        ),
        _ask(
          'yargitay_yeni',
          'trafik kazası değer kaybı',
          y,
          chamber: '17. Hukuk Dairesi',
          from: newFrom,
          to: newTo,
          take: 1,
        ),
        // And in the older, unsectioned form.
        _ask(
          'yargitay_eski',
          'kıdem tazminatı',
          y,
          chamber: '9. Hukuk Dairesi',
          from: oldFrom,
          to: oldTo,
        ),
        _ask(
          'yargitay_eski',
          'tapu iptal tescil',
          y,
          chamber: '1. Hukuk Dairesi',
          from: oldFrom,
          to: oldTo,
        ),
        _ask(
          'yargitay_eski',
          'kira tespit',
          y,
          chamber: '3. Hukuk Dairesi',
          from: oldFrom,
          to: oldTo,
        ),
        _ask(
          'yargitay_eski',
          'itirazın iptali',
          y,
          chamber: '11. Hukuk Dairesi',
          from: oldFrom,
          to: oldTo,
        ),
        _ask(
          'yargitay_eski',
          'trafik kazası tazminat',
          y,
          chamber: '17. Hukuk Dairesi',
          from: oldFrom,
          to: oldTo,
        ),
        // The Civil General Assembly.
        _ask(
          'hgk',
          'işe iade',
          y,
          chamber: 'Hukuk Genel Kurulu',
          from: newFrom,
          to: newTo,
        ),
        _ask(
          'hgk',
          'tazminat',
          y,
          chamber: 'Hukuk Genel Kurulu',
          from: newFrom,
          to: newTo,
        ),
        _ask(
          'hgk',
          'tapu iptal',
          y,
          chamber: 'Hukuk Genel Kurulu',
          from: DateTime.utc(2022, 1, 1),
          to: newTo,
        ),
        _ask(
          'hgk',
          'direnme kararı',
          y,
          chamber: 'Hukuk Genel Kurulu',
          from: oldFrom,
          to: oldTo,
        ),
        // Regional courts of appeal, civil.
        for (final words in [
          'kıdem tazminatı',
          'kira tahliye',
          'itirazın iptali',
          'boşanma',
          'menfi tespit',
          'trafik kazası',
        ])
          _ask(
            'bam',
            words,
            {CourtKind.istinaf},
            from: DateTime.utc(2024, 1, 1),
            to: newTo,
          ),
        // First instance.
        for (final words in ['alacak', 'tazminat', 'tapu iptal', 'kira'])
          _ask('yerel', words, {CourtKind.yerel}, take: 2),
        // The Council of State.
        for (final words in [
          'imar para cezası',
          'disiplin cezası',
          'vergi ziyaı',
          'tam yargı',
        ])
          _ask(
            'danistay',
            words,
            {CourtKind.danistay},
            from: DateTime.utc(2022, 1, 1),
            to: newTo,
          ),
      ];

      await _fetch(asks, prefix: '', index: 'index.json');
    },
  );

  // A second, smaller set fetched after the work was tuned on the first,
  // and never tuned on: what the figures are for decisions not seen.
  //
  //   flutter test tool/olcum/karar_ornekleri_indir_test.dart   //     --plain-name "doğrulama"
  test(
    'Bedesten doğrulama kararları',
    timeout: const Timeout(Duration(minutes: 30)),
    () async {
      final y = {CourtKind.yargitay};
      final newFrom = DateTime.utc(2025, 1, 1);
      final newTo = DateTime.utc(2026, 10, 1);
      final asks = <_Ask>[
        _ask(
          'yargitay_yeni',
          'işe iade',
          y,
          chamber: '9. Hukuk Dairesi',
          from: newFrom,
          to: newTo,
        ),
        _ask(
          'yargitay_yeni',
          'ecrimisil',
          y,
          chamber: '1. Hukuk Dairesi',
          from: newFrom,
          to: newTo,
          take: 1,
        ),
        _ask(
          'yargitay_yeni',
          'tahliye',
          y,
          chamber: '3. Hukuk Dairesi',
          from: newFrom,
          to: newTo,
          take: 1,
        ),
        _ask(
          'yargitay_eski',
          'muris muvazaası',
          y,
          chamber: '1. Hukuk Dairesi',
          from: DateTime.utc(2014, 1, 1),
          to: DateTime.utc(2018, 12, 31),
        ),
        _ask(
          'yargitay_eski',
          'fazla mesai',
          y,
          chamber: '9. Hukuk Dairesi',
          from: DateTime.utc(2014, 1, 1),
          to: DateTime.utc(2018, 12, 31),
          take: 1,
        ),
        _ask(
          'hgk',
          'manevi tazminat',
          y,
          chamber: 'Hukuk Genel Kurulu',
          from: DateTime.utc(2020, 1, 1),
          to: newTo,
        ),
        for (final words in ['ecrimisil', 'işçilik alacağı', 'vekalet ücreti'])
          _ask(
            'bam',
            words,
            {CourtKind.istinaf},
            from: DateTime.utc(2024, 1, 1),
            to: newTo,
            take: 1,
          ),
        for (final words in ['menfi tespit', 'itirazın iptali'])
          _ask('yerel', words, {CourtKind.yerel}, take: 1),
        for (final words in ['yıkım kararı', 'öğrenci disiplin', 'ihale'])
          _ask(
            'danistay',
            words,
            {CourtKind.danistay},
            from: DateTime.utc(2022, 1, 1),
            to: newTo,
            take: 1,
          ),
      ];
      await _fetch(asks, prefix: 'dogrulama_', index: 'index_dogrulama.json');
    },
  );
}

Future<void> _fetch(
  List<_Ask> asks, {
  required String prefix,
  required String index,
}) async {
  final known = <String>{};
  for (final name in ['index.json', 'index_dogrulama.json']) {
    final file = File('test/fixtures/decisions/$name');
    if (name == index || !file.existsSync()) continue;
    for (final row in jsonDecode(file.readAsStringSync()) as List) {
      known.add((row as Map)['documentId'] as String);
    }
  }
  final out = Directory('test/fixtures/decisions')..createSync(recursive: true);
  final bank = CaseLaw(
    send: _send,
    between: const Duration(milliseconds: 2500),
  );
  final rows = <Map<String, Object?>>[];
  final taken = <String>{};
  final texts = <String>{
    for (final kept in out.listSync().whereType<File>())
      if (kept.path.endsWith('.txt') &&
          !kept.uri.pathSegments.last.startsWith(prefix.isEmpty ? '#' : prefix))
        kept.readAsStringSync(),
  };
  final counts = <String, int>{};

  for (final ask in asks) {
    stdout.writeln('${ask.group}: ${ask.words} ${ask.chamber ?? ''}');
    final results = await bank.search(
      CaseLawQuery(
        words: ask.words,
        kinds: ask.kinds,
        chamber: ask.chamber,
        from: ask.from,
        to: ask.to,
        pageSize: 20,
      ),
    );
    stdout.writeln('  ${results.total} sonuç');
    var got = 0;
    for (final hit in results.hits) {
      if (got >= ask.take) break;
      if (known.contains(hit.documentId)) continue;
      if (!taken.add(hit.documentId)) continue;
      final decision = await bank.byId(hit);
      if (decision == null) continue;
      // Too short to have parts worth finding: a one-line correction
      // or a returned file.
      if (decision.text.length < 1200) continue;
      // The first instance collection answered three different
      // document ids with the text of a neighbouring decision, byte for
      // byte. A text already kept is a wrong answer, not a sample.
      if (!texts.add(decision.text)) continue;
      final n = (counts[ask.group] ?? 0) + 1;
      counts[ask.group] = n;
      final id = '$prefix${ask.group}_${n.toString().padLeft(2, '0')}';
      File('${out.path}/$id.txt').writeAsStringSync(decision.text);
      rows.add({
        'id': id,
        'documentId': hit.documentId,
        'court': hit.court,
        'kind': hit.kind,
        'esas': hit.esas,
        'karar': hit.karar,
        'date': hit.date,
        'query': ask.words,
      });
      stdout.writeln('  $id ${hit.title}');
      got++;
    }
  }

  File('${out.path}/$index')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
  stdout.writeln('${rows.length} karar: $counts');
}
