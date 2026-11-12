import 'dart:io';

import 'package:evrak_convert/services/ai/ai_guide.dart';
import 'package:evrak_convert/services/ai/folio_mcp.dart';
import 'package:evrak_convert/services/legal/bedesten_legislation.dart';
import 'package:flutter_test/flutter_test.dart';

// Folio's legal guide: the topic a question names is found and added by
// Folio; any other is read with the hukuk_rehber tool.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final guide = LegalGuide.parse(
    File('assets/mevzuat/rehber.json').readAsStringSync(),
  );

  test('a question names its kind of case', () {
    expect(
      guide
          .topicsIn(
            'İşverenin haklı neden olmadan feshettiği iş sözleşmesinde işe '
            'iade süresi',
          )
          .first,
      'is',
    );
    expect(
      guide.topicsIn('İlamsız takipte ödeme emrine itiraz süresi'),
      contains('icra'),
    );
    expect(guide.topicsIn('Kira bedelinin artırılma oranı'), ['kira']);
    // How to write is read when asked, never added on its own.
    expect(guide.topicsIn('Bir dilekçe yaz'), isNot(contains('dilekce')));
    expect(guide.topicsIn('Bugün hava nasıl'), isEmpty);
  });

  test('a topic by its own name or another', () {
    expect(guide.read('kira')['durum'], 'bulundu');
    expect(guide.read('İşe İade')['konu'], 'is');
    expect(guide.read('hmk')['konu'], 'usul');
    expect(guide.read('adli tatil')['konu'], 'sure');
    expect(guide.read('uzay hukuku')['durum'], 'yok');
  });

  test('the guide names Folio\'s tools, and each time limit its article', () {
    final all = guide.topics.values.join('\n');
    for (final foreign in [
      'mevzuat_getir',
      'arsiv_ara',
      'canli_ara',
      'dava_evrak',
      'dilekce_yaz',
      'ceza_hesapla',
      'sozlesme_playbook',
      'AvukatOS',
    ]) {
      expect(all, isNot(contains(foreign)), reason: foreign);
    }
    // Checked against the official text (11 Kasım 2026).
    expect(guide.topics['icra'], contains('itiraz 7 GÜN (m.62)'));
    expect(guide.topics['is'], contains('İşK m.20'));
    expect(guide.topics['kira'], contains('(m.344)'));
  });

  test('the fund crisis has its own topic', () {
    expect(
      guide.topicsIn('PBLK fonunun tasfiyesinde TEFAS talimatım gerçekleşmedi'),
      contains('fon-tasfiyesi'),
    );
    expect(
      guide.topicsIn('Tasfiye edilen yatırım fonu için 7596 sayılı Kanun'),
      contains('fon-tasfiyesi'),
    );
    expect(guide.topicOf('fon'), 'fon-tasfiyesi');
    expect(guide.topics['fon-tasfiyesi'], contains('7596'));
    // As corrected against the official texts (12.11.2026).
    final fon = guide.topics['fon-tasfiyesi']!;
    expect(fon, contains('1.661.000'));
    expect(fon, contains('BİR YIL'));
    expect(fon, isNot(contains('500.000 TL')));
    expect(fon, isNot(contains('tazminat istenmedikçe faiz işlemez')));
    expect(fon, isNot(contains('m.36/a')));
    // Kept out of an unrelated question.
    expect(guide.topicsIn('Kira bedelinin artırılma oranı'), ['kira']);
  });

  group('a large topic, part by part', () {
    test('fon-tasfiyesi asked for nothing: its core and the list', () {
      final got = guide.read('fon-tasfiyesi');
      final text = got['metin']! as String;
      expect(text.length, lessThan(LegalGuide.mostOutput));
      expect(text, contains('## B.'));
      expect(text, contains('## G.'));
      expect(text, isNot(contains('## E4.')));
      expect(
        (got['diger_bolumler']! as List).join(' '),
        allOf(contains('E4'), contains('E3')),
      );
    });

    test('the parts asked for come with the core, never over the limit', () {
      final e4 = guide.read('fon-tasfiyesi', parts: 'E4')['metin']! as String;
      expect(e4, contains('## E4.'));
      // The core came with the bare call: not again, unless named.
      expect(e4, isNot(contains('## B.')));
      expect(e4, contains('TMV'));
      expect(
        guide.read('fon-tasfiyesi', parts: 'B, E4')['metin'],
        contains('## B.'),
      );
      // Two large parts, with no core sent again: both fit.
      final two =
          guide.read('fon-tasfiyesi', parts: 'E, E4')['metin']! as String;
      expect(two, allOf(contains('## E. '), contains('## E4.')));
      expect(two.length, lessThanOrEqualTo(LegalGuide.mostOutput));
      final all = guide.read('fon', parts: 'tam');
      expect(
        (all['metin']! as String).length,
        lessThan(LegalGuide.mostOutput + 12000),
      );
      expect(all['aciklama'], contains('Sığmayan'));
    });

    test('el-atma: a letter brings its sub-parts; usul: both appeals', () {
      final c = guide.read('el-atma', parts: 'C')['metin']! as String;
      expect(c, contains('C10'));
      final usul =
          guide.read('usul', parts: 'Kanun yolları')['metin']! as String;
      expect(usul, contains('7589 s.K. ile YENİ'));
    });

    test(
      'a question about the fund crisis is given the core, not the whole',
      () {
        final block = guide.blockFor('PBLK fonunun tasfiyesinde zarar hesabı')!;
        expect(block.length, lessThan(LegalGuide.mostOutput + 3000));
        expect(block, contains('diğer bölümleri'));
      },
    );

    test('the tool lists the parts', () {
      final schema = guide.tool['inputSchema']! as Map;
      final bolum = (schema['properties']! as Map)['bolum']! as Map;
      expect(bolum['description'], contains('E4'));
    });
  });

  test('who must prove what: each kind of case has its part on it', () {
    for (final k in const [
      'icra',
      'kira',
      'ceza',
      'tazminat',
      'aile',
      'is',
      'ticaret',
      'tapu',
      'miras',
      'tuketici',
      'idari',
      'sigorta',
      'usul',
      'dilekce',
    ]) {
      expect(
        RegExp(r'^## İspat', multiLine: true).hasMatch(guide.topics[k]!),
        isTrue,
        reason: k,
      );
    }
    // The articles the parts rest on, as checked against the official text.
    expect(guide.topics['tuketici'], contains('TKHK m.10'));
    expect(guide.topics['kira'], contains('HMK m.201'));
    expect(guide.topics['metodoloji'], contains('TBK m.112'));
    // Folio's tools, none of another program's.
    for (final t in guide.topics.values) {
      expect(t, isNot(contains('mevzuat_getir')));
      expect(t, isNot(contains('arsiv_ara')));
      expect(t, isNot(contains('search_')));
    }
  });

  test('only the named topics go with a question', () {
    final block = guide.blockFor('Ödeme emrine itiraz kaç gün?')!;
    expect(block, contains('<rehber konu="icra">'));
    expect(block, isNot(contains('<rehber konu="kira">')));
    expect(guide.blockFor('Merhaba'), isNull);
  });

  test('the program is given the tool', () async {
    final listed = await FolioMcp().handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/list',
    });
    final names = [
      for (final t in (listed!['result']! as Map)['tools'] as List<Object?>)
        (t! as Map)['name'],
    ];
    expect(names, contains('hukuk_rehber'));
    expect(FolioMcp.names, contains('hukuk_rehber'));
    final got = await FolioMcp().call('hukuk_rehber', {'konu': 'iik'});
    expect(got['konu'], 'icra');
  });

  test('articles with no heading of their own are given their part', () async {
    final mcp = FolioMcp(bank: _Bank());
    final got = await mcp.call('mevzuat_icindekiler', {'kanun': '6098'});
    final articles = got['maddeler']! as List;
    expect(articles[0], {'madde': '338'});
    expect(articles[1], {
      'madde': '339',
      'bolum': 'İKİNCİ AYIRIM - Konut ve Çatılı İşyeri Kiraları',
    });
    // Said once, where the part begins.
    expect(articles[2], {'madde': '344'});
    expect(articles[3], {'madde': '348', 'baslik': 'a. Şekil'});
  });
}

class _Bank extends BedestenLegislation {
  @override
  Future<BedestenLaw?> law(int number) async => const BedestenLaw(
    id: '1',
    name: 'TÜRK BORÇLAR KANUNU',
    tertip: 5,
    url: 'https://www.mevzuat.gov.tr',
  );

  @override
  Future<List<BedestenNode>> tree(String lawId) async => const [
    BedestenNode(id: 'a', number: '338', heading: 'Madde No: 338', updated: ''),
    BedestenNode(
      id: 'b',
      number: '',
      heading: 'İKİNCİ AYIRIM - Konut ve Çatılı İşyeri Kiraları',
      updated: '',
    ),
    BedestenNode(id: 'c', number: '339', heading: 'Madde No: 339', updated: ''),
    BedestenNode(id: 'd', number: '344', heading: 'Madde No: 344', updated: ''),
    BedestenNode(
      id: 'e',
      number: '348',
      heading: 'Madde No: 348 - a. Şekil',
      updated: '',
    ),
  ];
}
