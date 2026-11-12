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
