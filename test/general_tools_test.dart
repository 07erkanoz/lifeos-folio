import 'dart:convert';

import 'package:evrak_convert/services/voice/general_tools.dart';
import 'package:flutter_test/flutter_test.dart';

const _tcmb = '''<?xml version="1.0" encoding="UTF-8"?>
<Tarih_Date Tarih="20.11.2026" Date="11/20/2026">
  <Currency CrossOrder="0" Kod="USD" CurrencyCode="USD">
    <Unit>1</Unit><Isim>ABD DOLARI</Isim>
    <ForexBuying>50.4028</ForexBuying><ForexSelling>50.4936</ForexSelling>
    <BanknoteSelling>50.5694</BanknoteSelling>
  </Currency>
  <Currency CrossOrder="9" Kod="EUR" CurrencyCode="EUR">
    <Unit>1</Unit><Isim>EURO</Isim>
    <ForexBuying>58.1</ForexBuying><ForexSelling>58.2</ForexSelling>
    <BanknoteSelling>58.3</BanknoteSelling>
  </Currency>
</Tarih_Date>''';

const _rss = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
<item><title>Birinci haber</title>
<description><![CDATA[<img src="x.jpg"/>Kısa &amp; öz açıklama.]]></description>
<pubDate>Sun, 22 Nov 2026 12:13:00 +0300</pubDate></item>
<item><title>İkinci haber</title><description>İki</description></item>
</channel></rss>''';

void main() {
  test('kurlar TCMB bülteninden okunur', () async {
    final t = AjanGeneralTools(fetch: (_) async => _tcmb);
    final r = await t.call(AjanGeneralTools.rates, {
      'kodlar': ['usd', 'JPY'],
    });
    expect(r['tarih'], '20.11.2026');
    final kur = (r['kurlar'] as List).single as Map;
    expect(kur['kod'], 'USD');
    expect(kur['satis'], '50.4936');
    expect(kur['efektif_satis'], '50.5694');
    expect(r['bulunamayan'], ['JPY']);
  });

  test('hava durumu yer bulunur, kodlar Türkçeye çevrilir', () async {
    final asked = <Uri>[];
    final t = AjanGeneralTools(
      fetch: (u) async {
        asked.add(u);
        if (u.host.startsWith('geocoding')) {
          return jsonEncode({
            'results': [
              {
                'name': 'Kadıköy',
                'admin1': 'İstanbul',
                'country': 'Türkiye',
                'latitude': 40.99,
                'longitude': 29.03,
              },
            ],
          });
        }
        return jsonEncode({
          'current': {'temperature_2m': 14.2, 'weather_code': 2},
          'daily': {
            'time': ['2026-11-22', '2026-11-23'],
            'weather_code': [61, 0],
            'temperature_2m_max': [15, 17],
            'temperature_2m_min': [8, 9],
            'precipitation_probability_max': [70, 5],
          },
        });
      },
    );
    final r = await t.call(AjanGeneralTools.weather, {'sehir': 'Kadıköy'});
    expect(r['yer'], 'Kadıköy, İstanbul, Türkiye');
    expect((r['simdi'] as Map)['durum'], 'parçalı bulutlu');
    final days = r['gunler'] as List;
    expect(days, hasLength(2));
    expect((days.first as Map)['durum'], 'hafif yağmurlu');
    expect(asked.last.queryParameters['forecast_days'], '3');
  });

  test('il verilince o ildeki yer seçilir, yoksa ilçe merkezi', () async {
    final t = AjanGeneralTools(
      fetch: (u) async => jsonEncode({
        'results': [
          {
            'name': 'Kadıköy',
            'admin1': 'Yalova',
            'country_code': 'TR',
            'feature_code': 'PPL',
            'population': 2741,
          },
          {
            'name': 'Kadıköy',
            'admin1': 'İstanbul',
            'country_code': 'TR',
            'feature_code': 'PPL',
            'population': 1454,
          },
        ],
      }),
    );
    expect((await t.locate('Kadıköy, İstanbul'))!['admin1'], 'İstanbul');
    final best = AjanGeneralTools.bestPlace([
      {
        'name': 'Çankaya',
        'admin1': 'İzmir',
        'admin2': 'Konak',
        'country_code': 'TR',
      },
      {
        'name': 'Çankaya',
        'admin1': 'Ankara',
        'admin2': 'Çankaya',
        'country_code': 'TR',
        'population': 792189,
      },
      {
        'name': 'Bornova',
        'admin1': 'X',
        'country_code': 'GR',
        'feature_code': 'PPLA',
        'population': 9000000,
      },
    ]);
    expect(best['admin1'], 'Ankara');
  });

  test('şehir söylenmezse büronun şehri', () async {
    String? asked;
    final t = AjanGeneralTools(
      homeCity: () async => 'Konya',
      fetch: (u) async {
        asked ??= u.queryParameters['name'];
        return jsonEncode({'results': []});
      },
    );
    final r = await t.call(AjanGeneralTools.weather, {});
    expect(asked, 'Konya');
    expect(r['hata'], contains('Konya'));
  });

  test('haber akışı sade metne döner, kaynaklar sırayla karışır', () async {
    final items = AjanGeneralTools.parseFeed(_rss, 'TRT Haber');
    expect(items, hasLength(2));
    expect(items.first['ozet'], 'Kısa & öz açıklama.');
    final t = AjanGeneralTools(fetch: (_) async => _rss);
    final r = await t.call(AjanGeneralTools.news, {'konu': 'gundem'});
    // The same two items from three feeds: no repeats.
    expect((r['haberler'] as List).map((h) => (h as Map)['baslik']), [
      'Birinci haber',
      'İkinci haber',
    ]);
  });

  test('ulaşılamayan kaynak hata olarak döner, çökmez', () async {
    final t = AjanGeneralTools(fetch: (_) async => throw Exception('yok'));
    final r = await t.call(AjanGeneralTools.news, {});
    expect(r['hata'], isNotNull);
  });

  test('müzik ilk videoyu YouTube Music\'te açar', () async {
    const page =
        'x"videoRenderer":{"videoId":"abcDEF12345","thumbnail":{},'
        '"title":{"runs":[{"text":"Sezen Aksu \\u0026 Gidiyorum"}]}}';
    Uri? opened;
    final t = AjanGeneralTools(
      fetch: (_) async => page,
      open: (u) async => opened = u,
    );
    final r = await t.call(AjanGeneralTools.music, {'sorgu': 'gidiyorum'});
    expect(opened.toString(), 'https://music.youtube.com/watch?v=abcDEF12345');
    expect(r['parca'], 'Sezen Aksu & Gidiyorum');
  });

  test('video bulunmazsa YouTube Music araması açılır', () async {
    Uri? opened;
    final t = AjanGeneralTools(
      fetch: (_) async => '<html></html>',
      open: (u) async => opened = u,
    );
    final r = await t.call(AjanGeneralTools.music, {'sorgu': 'sakin piyano'});
    expect(opened!.path, '/search');
    expect(opened!.queryParameters['q'], 'sakin piyano');
    expect(r['durum'], 'arama açıldı');
  });

  test('medya komutu ilgili işe gider', () async {
    final t = AjanGeneralTools(media: (c) async => 'yapıldı $c');
    final r = await t.call(AjanGeneralTools.player, {'komut': 'durdur'});
    expect(r['durum'], 'yapıldı durdur');
  });

  test('bütün araçlar bildirilmiş', () {
    expect(
      AjanGeneralTools.declarations.map((d) => d['name']).toSet(),
      AjanGeneralTools.names,
    );
  });
}
