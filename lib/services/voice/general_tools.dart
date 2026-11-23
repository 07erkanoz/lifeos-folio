import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:xml/xml.dart';

import '../editor/lawyer_profile.dart';

/// Folio Ajan's tools for what is not Folio: the exchange rates, the
/// weather, the news, and music on YouTube Music. The lawyer asked for an
/// assistant, not only a case reader (22 Kasım 2026). Every source here is
/// public and needs no key: TCMB, Open-Meteo, the news agencies' RSS.
class AjanGeneralTools {
  AjanGeneralTools({
    Future<String> Function(Uri address)? fetch,
    Future<void> Function(Uri address)? open,
    Future<String> Function(String command)? media,
    Future<String> Function()? homeCity,
  }) : _fetch = fetch ?? _get,
       _open = open ?? _openHere,
       _media = media ?? _mpris,
       _homeCity = homeCity ?? _officeCity;

  final Future<String> Function(Uri address) _fetch;
  final Future<void> Function(Uri address) _open;
  final Future<String> Function(String command) _media;
  final Future<String> Function() _homeCity;

  static const rates = 'doviz_kuru',
      weather = 'hava_durumu',
      news = 'haberler',
      music = 'muzik_ac',
      player = 'medya';

  static const names = {rates, weather, news, music, player};

  static const _readOnly = {
    'readOnlyHint': true,
    'destructiveHint': false,
    'idempotentHint': true,
    'openWorldHint': true,
  };

  static const declarations = <Map<String, Object?>>[
    {
      'name': rates,
      'title': 'Döviz kuru',
      'description':
          'TCMB\'nin bugünkü döviz kurları (alış, satış, efektif satış, TL). '
          'TCMB kurları iş günü 15.30\'da açıklar; hafta sonu son iş gününün '
          'kurudur, tarihini söyle. Altın ve borsa için internet araması yap.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'kodlar': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Döviz kodları, ör. ["USD","EUR"]; boşsa USD, '
                'EUR, GBP',
          },
        },
      },
      'annotations': _readOnly,
    },
    {
      'name': weather,
      'title': 'Hava durumu',
      'description':
          'Bir yerin şimdiki havası ve önümüzdeki günlerin tahmini '
          '(Open-Meteo). Şehir söylenmezse büronun şehri.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'sehir': {
            'type': 'string',
            'description':
                'İlçe ve il, ör. "Kadıköy, İstanbul" ya da yalnız "Konya"; '
                'boşsa büronun şehri',
          },
          'gun': {
            'type': 'integer',
            'description': 'Kaç günlük tahmin, 1-7; varsayılan 3',
          },
        },
      },
      'annotations': _readOnly,
    },
    {
      'name': news,
      'title': 'Haberler',
      'description':
          'Son haber başlıkları ve kısa özetleri (TRT Haber, Anadolu Ajansı, '
          'BBC Türkçe). Avukata en önemlilerini birkaç cümleyle özetle, '
          'hepsini okuma; ayrıntı isterse internette ara.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'konu': {
            'type': 'string',
            'enum': [
              'gundem',
              'son_dakika',
              'ekonomi',
              'spor',
              'dunya',
              'teknoloji',
              'saglik',
            ],
            'description': 'Varsayılan gundem',
          },
          'adet': {'type': 'integer', 'description': 'En çok kaç haber; 8'},
        },
      },
      'annotations': _readOnly,
    },
    {
      'name': music,
      'title': 'Müzik aç',
      'description':
          'YouTube Music\'te bir şarkıyı, sanatçıyı, albümü ya da türü bulup '
          'tarayıcıda çalar. Avukat "müzik aç" dediğinde, onay sormadan kullan.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'sorgu': {
            'type': 'string',
            'description':
                'Ne çalınacak, ör. "Sezen Aksu Gidiyorum", '
                '"sakin piyano", "Barış Manço"',
          },
        },
        'required': ['sorgu'],
      },
      'annotations': {
        'readOnlyHint': false,
        'destructiveHint': false,
        'idempotentHint': false,
        'openWorldHint': true,
      },
    },
    {
      'name': player,
      'title': 'Çalanı denetle',
      'description':
          'Bilgisayarda çalan müziği durdurur, sürdürür, sonrakine ya da '
          'öncekine geçer, sesini açar ya da kısar.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'komut': {
            'type': 'string',
            'enum': [
              'durdur',
              'devam',
              'sonraki',
              'onceki',
              'ses_ac',
              'ses_kis',
            ],
          },
        },
        'required': ['komut'],
      },
      'annotations': {
        'readOnlyHint': false,
        'destructiveHint': false,
        'idempotentHint': false,
        'openWorldHint': false,
      },
    },
  ];

  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> args,
  ) async {
    try {
      switch (name) {
        case rates:
          return await exchangeRates([
            for (final c in (args['kodlar'] as List? ?? const [])) '$c',
          ]);
        case weather:
          return await forecast(
            '${args['sehir'] ?? ''}'.trim(),
            _int(args['gun'], 3).clamp(1, 7),
          );
        case news:
          return await headlines(
            '${args['konu'] ?? 'gundem'}',
            _int(args['adet'], 8).clamp(1, 15),
          );
        case music:
          return await playMusic('${args['sorgu'] ?? ''}'.trim());
        case player:
          return {'durum': await _media('${args['komut'] ?? ''}')};
      }
      return {'hata': 'Böyle bir araç yok: $name'};
    } on TimeoutException {
      return {'hata': 'Kaynak zamanında cevap vermedi.'};
    } on SocketException {
      return {'hata': 'İnternete ulaşılamadı.'};
    } catch (e) {
      return {'hata': '$e'};
    }
  }

  static int _int(Object? v, int fallback) =>
      v is num ? v.toInt() : int.tryParse('$v') ?? fallback;

  // ---- Döviz ---------------------------------------------------------------

  Future<Map<String, Object?>> exchangeRates(List<String> codes) async {
    final wanted = {
      for (final c in codes.isEmpty ? const ['USD', 'EUR', 'GBP'] : codes)
        c.trim().toUpperCase(),
    };
    final doc = XmlDocument.parse(
      await _fetch(Uri.parse('https://www.tcmb.gov.tr/kurlar/today.xml')),
    );
    final root = doc.rootElement;
    String field(XmlElement e, String n) =>
        e.getElement(n)?.innerText.trim() ?? '';
    final found = <Map<String, Object?>>[];
    for (final c in root.findElements('Currency')) {
      final code = c.getAttribute('CurrencyCode') ?? c.getAttribute('Kod');
      if (!wanted.contains(code)) continue;
      found.add({
        'kod': code,
        'ad': field(c, 'Isim'),
        'birim': int.tryParse(field(c, 'Unit')) ?? 1,
        'alis': field(c, 'ForexBuying'),
        'satis': field(c, 'ForexSelling'),
        'efektif_satis': field(c, 'BanknoteSelling'),
      });
    }
    return {
      'kaynak': 'TCMB',
      'tarih': root.getAttribute('Tarih') ?? '',
      'kurlar': found,
      if (found.length < wanted.length)
        'bulunamayan': [
          for (final w in wanted)
            if (!found.any((f) => f['kod'] == w)) w,
        ],
    };
  }

  // ---- Hava ----------------------------------------------------------------

  Future<Map<String, Object?>> forecast(String place, int days) async {
    if (place.isEmpty) place = await _homeCity();
    if (place.isEmpty) place = 'Ankara';
    final hit = await locate(place);
    if (hit == null) return {'hata': '"$place" bulunamadı.'};
    final data = jsonDecode(
      await _fetch(
        Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': '${hit['latitude']}',
          'longitude': '${hit['longitude']}',
          'current':
              'temperature_2m,apparent_temperature,'
              'relative_humidity_2m,weather_code,wind_speed_10m,'
              'precipitation',
          'daily':
              'weather_code,temperature_2m_max,temperature_2m_min,'
              'precipitation_probability_max',
          'forecast_days': '$days',
          'timezone': 'auto',
        }),
      ),
    ) as Map;
    final now = data['current'] as Map? ?? const {};
    final daily = data['daily'] as Map? ?? const {};
    List<Object?> col(String n) => daily[n] as List? ?? const [];
    final dates = col('time');
    return {
      'yer': [
        hit['name'],
        if (hit['admin1'] != null && hit['admin1'] != hit['name'])
          hit['admin1'],
        hit['country'],
      ].whereType<String>().join(', '),
      'simdi': {
        'durum': weatherText(now['weather_code']),
        'sicaklik': now['temperature_2m'],
        'hissedilen': now['apparent_temperature'],
        'nem': now['relative_humidity_2m'],
        'ruzgar_kmh': now['wind_speed_10m'],
        'yagis_mm': now['precipitation'],
      },
      'gunler': [
        for (var i = 0; i < dates.length; i++)
          {
            'tarih': dates[i],
            'durum': weatherText(_at(col('weather_code'), i)),
            'en_yuksek': _at(col('temperature_2m_max'), i),
            'en_dusuk': _at(col('temperature_2m_min'), i),
            'yagis_ihtimali': _at(col('precipitation_probability_max'), i),
          },
      ],
      'birim': '°C',
    };
  }

  Future<List<Map>> _places(String name) async {
    final geo = jsonDecode(
      await _fetch(
        Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
          'name': name,
          'count': '10',
          'language': 'tr',
        }),
      ),
    ) as Map;
    return (geo['results'] as List? ?? const []).whereType<Map>().toList();
  }

  /// [place] on the map: "Konya", "Bornova", "Kadıköy, İstanbul". A
  /// district alone may be a village of the same name elsewhere ("Kadıköy"
  /// was one in Yalova), so a province given is kept to, and without one
  /// a district seat or a province's centre comes first.
  Future<Map?> locate(String place) async {
    final parts = place
        .split(RegExp(r'[,/]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    var name = parts.isEmpty ? place : parts.first;
    var province = parts.length > 1 ? parts.last : '';
    var hits = await _places(place.replaceAll(RegExp(r'[,/]'), ' ').trim());
    if (hits.isEmpty && province.isEmpty) {
      final words = place.split(RegExp(r'\s+'));
      if (words.length > 1) {
        name = words.sublist(0, words.length - 1).join(' ');
        province = words.last;
      }
    }
    if (hits.isEmpty || province.isNotEmpty) hits = await _places(name);
    if (province.isNotEmpty) {
      final p = _fold(province);
      final inside = hits.where((h) => _fold('${h['admin1']}') == p).toList();
      if (inside.isNotEmpty) return bestPlace(inside);
      final whole = await _places(province);
      if (whole.isNotEmpty) return bestPlace(whole);
    }
    return hits.isEmpty ? null : bestPlace(hits);
  }

  /// The place meant: in Türkiye if any is; a province's centre, then a
  /// district seat, then the most populous.
  static Map bestPlace(List<Map> hits) {
    final here = hits.where((h) => h['country_code'] == 'TR').toList();
    final pool = here.isEmpty ? hits : here;
    int rank(Map h) {
      final code = '${h['feature_code']}';
      if (code == 'PPLC' || code == 'PPLA') return 3;
      if (code == 'PPLA2' || _fold('${h['admin2']}') == _fold('${h['name']}')) {
        return 2;
      }
      return 1;
    }

    num people(Map h) => h['population'] is num ? h['population'] as num : 0;
    return pool.reduce((a, b) {
      final ra = rank(a), rb = rank(b);
      if (ra != rb) return rb > ra ? b : a;
      return people(b) > people(a) ? b : a;
    });
  }

  static String _fold(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll('i̇', 'i')
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');

  static Object? _at(List<Object?> l, int i) => i < l.length ? l[i] : null;

  /// WMO weather code, in Turkish.
  static String weatherText(Object? code) {
    final c = code is num ? code.toInt() : int.tryParse('$code') ?? -1;
    return switch (c) {
      0 => 'açık',
      1 => 'çoğunlukla açık',
      2 => 'parçalı bulutlu',
      3 => 'kapalı',
      45 || 48 => 'sisli',
      51 || 53 || 55 => 'çisenti',
      56 || 57 => 'dondurucu çisenti',
      61 => 'hafif yağmurlu',
      63 => 'yağmurlu',
      65 => 'kuvvetli yağmurlu',
      66 || 67 => 'dondurucu yağmur',
      71 => 'hafif kar yağışlı',
      73 => 'kar yağışlı',
      75 => 'yoğun kar yağışlı',
      77 => 'kar taneli',
      80 => 'hafif sağanak',
      81 => 'sağanak yağışlı',
      82 => 'şiddetli sağanak',
      85 || 86 => 'kar sağanağı',
      95 => 'gök gürültülü fırtına',
      96 || 99 => 'dolulu fırtına',
      _ => 'bilinmiyor',
    };
  }

  /// The office's city from the lawyer's profile: "… Kadıköy/İstanbul".
  static Future<String> _officeCity() async {
    try {
      final address = (await LawyerProfile.load()).address.trim();
      if (address.isEmpty) return '';
      final parts = address
          .split(RegExp(r'[/,\n]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final last = parts.last.split(RegExp(r'\s+')).last;
      return last.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
    } catch (_) {
      return '';
    }
  }

  // ---- Haberler -------------------------------------------------------------

  static const _feeds = <String, List<(String, String)>>{
    'gundem': [
      ('TRT Haber', 'https://www.trthaber.com/manset_articles.rss'),
      ('Anadolu Ajansı', 'https://www.aa.com.tr/tr/rss/default?cat=guncel'),
      ('BBC Türkçe', 'https://feeds.bbci.co.uk/turkce/rss.xml'),
    ],
    'son_dakika': [
      ('TRT Haber', 'https://www.trthaber.com/sondakika_articles.rss'),
    ],
    'ekonomi': [('TRT Haber', 'https://www.trthaber.com/ekonomi_articles.rss')],
    'spor': [('TRT Haber', 'https://www.trthaber.com/spor_articles.rss')],
    'dunya': [
      ('TRT Haber', 'https://www.trthaber.com/dunya_articles.rss'),
      ('BBC Türkçe', 'https://feeds.bbci.co.uk/turkce/rss.xml'),
    ],
    'teknoloji': [
      ('TRT Haber', 'https://www.trthaber.com/bilim_teknoloji_articles.rss'),
    ],
    'saglik': [('TRT Haber', 'https://www.trthaber.com/saglik_articles.rss')],
  };

  Future<Map<String, Object?>> headlines(String topic, int most) async {
    final feeds = _feeds[topic] ?? _feeds['gundem']!;
    final fetched = await Future.wait([
      for (final (source, url) in feeds)
        _fetch(Uri.parse(url)).then(
          (body) => parseFeed(body, source),
          onError: (Object _) => const <Map<String, Object?>>[],
        ),
    ]);
    // Round robin, so that one agency does not fill the list.
    final items = <Map<String, Object?>>[];
    final seen = <String>{};
    for (var i = 0; items.length < most; i++) {
      var any = false;
      for (final list in fetched) {
        if (i >= list.length || items.length >= most) continue;
        any = true;
        final key = '${list[i]['baslik']}'.toLowerCase();
        if (seen.add(key)) items.add(list[i]);
      }
      if (!any) break;
    }
    if (items.isEmpty) return {'hata': 'Haber kaynaklarına ulaşılamadı.'};
    return {'konu': topic, 'haberler': items};
  }

  /// An RSS feed's items: title, a short summary, the time.
  static List<Map<String, Object?>> parseFeed(String body, String source) {
    final doc = XmlDocument.parse(body);
    return [
      for (final item in doc.findAllElements('item'))
        {
          'baslik': _plain(item.getElement('title')?.innerText ?? ''),
          'ozet': _short(
            _plain(item.getElement('description')?.innerText ?? ''),
            240,
          ),
          'kaynak': source,
          'zaman': item.getElement('pubDate')?.innerText.trim() ?? '',
        },
    ].where((i) => '${i['baslik']}'.isNotEmpty).toList();
  }

  static String _plain(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _short(String s, int most) =>
      s.length <= most ? s : '${s.substring(0, most).trimRight()}…';

  // ---- Müzik ---------------------------------------------------------------

  Future<Map<String, Object?>> playMusic(String query) async {
    if (query.isEmpty) return {'hata': 'Ne çalınacağı söylenmedi.'};
    String? id, title;
    try {
      final page = await _fetch(
        Uri.https('www.youtube.com', '/results', {
          'search_query': query,
          'hl': 'tr',
        }),
      );
      (id, title) = firstVideo(page);
    } catch (_) {
      // The search page instead.
    }
    if (id == null) {
      await _open(Uri.https('music.youtube.com', '/search', {'q': query}));
      return {
        'durum': 'arama açıldı',
        'aciklama': 'YouTube Music\'te arama açıldı; avukat seçecek.',
      };
    }
    await _open(Uri.https('music.youtube.com', '/watch', {'v': id}));
    return {'durum': 'çalıyor', 'parca': ?title, 'sorgu': query};
  }

  /// The first video in a YouTube results page, and its title.
  static (String?, String?) firstVideo(String page) {
    final m = RegExp(r'"videoRenderer":\{"videoId":"([A-Za-z0-9_-]{11})"')
        .firstMatch(page);
    final any =
        m ?? RegExp(r'"videoId":"([A-Za-z0-9_-]{11})"').firstMatch(page);
    if (any == null) return (null, null);
    final after = page.substring(
      any.end,
      (any.end + 3000).clamp(0, page.length),
    );
    final t = RegExp(r'"title":\{"runs":\[\{"text":"((?:[^"\\]|\\.)*)"')
        .firstMatch(after);
    String? title;
    if (t != null) {
      try {
        title = jsonDecode('"${t.group(1)}"') as String;
      } catch (_) {
        title = t.group(1);
      }
    }
    return (any.group(1), title);
  }

  // ---- Medya (MPRIS) -------------------------------------------------------

  static Future<String> _mpris(String command) async {
    if (Platform.isWindows) return _windowsMedia(command);
    final bus = DBusClient.session();
    try {
      final names = (await bus.listNames())
          .where((n) => n.startsWith('org.mpris.MediaPlayer2.'))
          .toList();
      if (names.isEmpty) return 'Çalan bir şey yok.';
      DBusRemoteObject? chosen;
      for (final n in names) {
        final o = DBusRemoteObject(
          bus,
          name: n,
          path: DBusObjectPath('/org/mpris/MediaPlayer2'),
        );
        try {
          final s = await o.getProperty(_player, 'PlaybackStatus');
          if ((s as DBusString).value == 'Playing') {
            chosen = o;
            break;
          }
          chosen ??= o;
        } catch (_) {
          // Not a player that answers: the next.
        }
      }
      if (chosen == null) return 'Çalan bir şey yok.';
      Future<void> call(String m) => chosen!.callMethod(_player, m, const []);
      switch (command) {
        case 'durdur':
          await call('Pause');
          return 'Durduruldu.';
        case 'devam':
          await call('Play');
          return 'Sürüyor.';
        case 'sonraki':
          await call('Next');
          return 'Sonrakine geçildi.';
        case 'onceki':
          await call('Previous');
          return 'Öncekine geçildi.';
        case 'ses_ac':
        case 'ses_kis':
          await Process.run('wpctl', [
            'set-volume',
            '-l',
            '1.0',
            '@DEFAULT_AUDIO_SINK@',
            command == 'ses_ac' ? '10%+' : '10%-',
          ]);
          return command == 'ses_ac' ? 'Ses açıldı.' : 'Ses kısıldı.';
      }
      return 'Bilinmeyen komut: $command';
    } finally {
      await bus.close();
    }
  }

  static const _player = 'org.mpris.MediaPlayer2.Player';

  /// On Windows: the media keys, as the keyboard's own would press them;
  /// the player playing (Spotify, a browser) takes them. Windows says not
  /// whether something plays: "durdur" and "devam" are the one key.
  static Future<String> _windowsMedia(String command) async {
    final (key, times, said) = switch (command) {
      'durdur' => (0xB3, 1, 'Durduruldu.'),
      'devam' => (0xB3, 1, 'Sürüyor.'),
      'sonraki' => (0xB0, 1, 'Sonrakine geçildi.'),
      'onceki' => (0xB1, 1, 'Öncekine geçildi.'),
      // A press is 2 %: five make Linux's 10 %.
      'ses_ac' => (0xAF, 5, 'Ses açıldı.'),
      'ses_kis' => (0xAE, 5, 'Ses kısıldı.'),
      _ => (0, 0, 'Bilinmeyen komut: $command'),
    };
    if (key == 0) return said;
    final press = DynamicLibrary.open('user32.dll')
        .lookupFunction<
          Void Function(Uint8, Uint8, Uint32, IntPtr),
          void Function(int, int, int, int)
        >('keybd_event');
    const extended = 0x1, up = 0x2;
    for (var i = 0; i < times; i++) {
      press(key, 0, extended, 0);
      press(key, 0, extended | up, 0);
    }
    return said;
  }

  // ---- Ağ ve açıcı ---------------------------------------------------------

  static Future<String> _get(Uri address) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'Mozilla/5.0 (X11; Linux x86_64) Folio';
    try {
      final request = await client.getUrl(address);
      request.headers.set('Accept-Language', 'tr-TR,tr;q=0.9');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400) {
        throw HttpException('${response.statusCode}', uri: address);
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _openHere(Uri address) async {
    if (Platform.isWindows) {
      // The address to Windows' own handler, as a link clicked is: no
      // shell in between to read its `&`.
      await Process.start('rundll32', [
        'url.dll,FileProtocolHandler',
        '$address',
      ], mode: ProcessStartMode.detached);
      return;
    }
    for (final opener in ['xdg-open', 'kde-open', 'gio']) {
      try {
        final args = opener == 'gio' ? ['open', '$address'] : ['$address'];
        await Process.start(opener, args, mode: ProcessStartMode.detached);
        return;
      } catch (_) {
        // Not on this desktop: the next.
      }
    }
    throw const OSError('Tarayıcı açılamadı.');
  }
}
