import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;

/// Folio's legal guide (assets/mevzuat/rehber.json): for each kind of case
/// which laws and articles govern it, its time limits and its traps, and
/// which of Folio's tools to use. The AI program reads it before it writes
/// a legal answer: the topic named by a question is added to the question
/// by Folio itself, any other read with the `hukuk_rehber` tool. Only the
/// list of topics goes with every question; a topic's text only when it is
/// asked for. Every time limit in it names its article, checked against the
/// official text; the answer still reads the article itself.
class LegalGuide {
  LegalGuide._(this.summary, this.topics, this._aliases);

  static const asset = 'assets/mevzuat/rehber.json';

  /// What each topic holds, in a few words each: in the tool's description.
  final String summary;

  /// Each topic's text, by its key ("is", "icra", "kira"…).
  final Map<String, String> topics;
  final Map<String, String> _aliases;

  static Future<LegalGuide>? _loaded;

  static Future<LegalGuide> load() => _loaded ??= _read().then(parse);

  /// The asset; read from the project's own folder where there is no
  /// Flutter to give it (a test of the tools that starts none).
  static Future<String> _read() async {
    try {
      return await rootBundle.loadString(asset);
    } on FlutterError {
      return File(asset).readAsString();
    }
  }

  static LegalGuide parse(String raw) {
    final json = jsonDecode(raw) as Map<String, Object?>;
    return LegalGuide._(
      '${json['konular'] ?? ''}',
      {
        for (final e in (json['rehber'] as Map? ?? const {}).entries)
          '${e.key}': '${e.value}',
      },
      {
        for (final e in (json['takma'] as Map? ?? const {}).entries)
          _fold('${e.key}'): '${e.value}',
      },
    );
  }

  /// The topics that are about how to write or reason in general, not a
  /// kind of case: read when asked, never added by Folio on its own.
  static const general = {'dilekce', 'usul', 'metodoloji', 'atif'};

  /// [name] as a topic's key: the key itself or one of its other names
  /// ("hmk" → usul, "işe iade" → is); null when it names none.
  String? topicOf(String name) {
    final k = _fold(name).trim().replaceAll(' ', '-');
    if (topics.containsKey(k)) return k;
    return _aliases[k] ?? _aliases[k.replaceAll('-', ' ')];
  }

  /// The large topics, read part by part: the parts always given with any
  /// ([core]), whether a part is known by its own letter ("A.", "E2.", "C4
  /// —") or by its place, whether only `##` headings divide it, and whether
  /// a bare call gives the core and the list rather than the whole. The
  /// rest are read whole: a method's guide is meant to be read through, and
  /// the criminal guide's amendments change rules in its other parts.
  static const sectioned =
      <String, ({List<String> core, bool letters, bool h2, bool listFirst})>{
        'el-atma': (
          core: ['A', 'B'],
          letters: true,
          h2: false,
          listFirst: false,
        ),
        'usul': (core: [], letters: false, h2: false, listFirst: false),
        'fon-tasfiyesi': (
          core: ['B', 'G'],
          letters: true,
          h2: true,
          listFirst: true,
        ),
      };

  /// The most one call gives, in characters: about 40 KB as the tool's
  /// answer. Claude's program does not hand the model a tool's answer much
  /// above 45 KB (measured: one of 63.5 KB came as a file and a 2 KB
  /// preview).
  static const mostOutput = 36000;

  /// [key]'s text before its first part, and its parts.
  ({String intro, List<({String id, String title, String text})> parts})
  partsOf(String key) {
    final text = topics[key] ?? '';
    final how = sectioned[key];
    final heads = RegExp(
      (how?.h2 ?? false) ? r'^## (.+)$' : r'^#{2,3} (.+)$',
      multiLine: true,
    ).allMatches(text).toList();
    if (heads.isEmpty) return (intro: text, parts: const []);
    final out = <({String id, String title, String text})>[];
    for (var i = 0; i < heads.length; i++) {
      final end = i + 1 < heads.length ? heads[i + 1].start : text.length;
      var title = heads[i][1]!.trim();
      var id = '${i + 1}';
      if (how?.letters ?? false) {
        id = RegExp(r'^([A-Z]\d*)\b').firstMatch(title)?[1] ?? title;
        title = title.replaceFirst(RegExp(r'^[A-Z]\d*\s*[.—-]\s*'), '');
      }
      out.add((
        id: id,
        title: title,
        text: text.substring(heads[i].start, end),
      ));
    }
    return (intro: text.substring(0, heads.first.start), parts: out);
  }

  /// A part with a body of its own: not a bare heading over its sub-parts
  /// (el-atma's "C. ÖZEL DURUMLAR").
  static bool _hasBody(String text) => '\n'.allMatches(text).length > 2;

  /// The parts of the large topics, as the tool's description lists them.
  String get index => [
    for (final MapEntry(key: key, value: how) in sectioned.entries)
      if (topics.containsKey(key))
        '$key'
            '${how.core.isEmpty ? '' : ' (her zaman gelir: ${how.core.join(', ')})'}: '
            '${[for (final p in partsOf(key).parts)
              if (!how.core.contains(p.id) && _hasBody(p.text)) '${p.id} ${p.title.split(' — ').first.replaceAll(RegExp(r'\s*\([^)]*\)'), '')}'].join('; ')}',
  ].join(' | ');

  /// A topic's text for the tool, or the list of topics when [name] names
  /// none. A large topic ([sectioned]) is given by the [parts] asked for
  /// ("C1, C4", "tam" for all of it) with its core, never more than
  /// [mostOutput]; fon-tasfiyesi asked for nothing gives its core and the
  /// list of the rest.
  Map<String, Object?> read(String name, {String parts = ''}) {
    final key = topicOf(name);
    if (key == null) {
      return {
        'durum': 'yok',
        'aciklama': 'Bu adla bir rehber konusu yok.',
        'konular': topics.keys.toList(),
      };
    }
    final text = topics[key]!;
    final how = sectioned[key];
    final asked = [
      for (final p in parts.split(','))
        if (p.trim().isNotEmpty) p.trim(),
    ];
    final whole = asked.any(
      (p) => const {'tam', 'hepsi', 'tümü', 'tumu', '*'}.contains(_fold(p)),
    );
    final plain = how == null || (asked.isEmpty && !how.listFirst) || whole;
    if (plain && text.length <= mostOutput) {
      return {'durum': 'bulundu', 'konu': key, 'metin': text};
    }
    final (:intro, parts: all) = partsOf(key);
    final chosen = <String>{...?how?.core};
    final unknown = <String>[];
    if (plain) {
      chosen.addAll([for (final x in all) x.id]);
    } else {
      for (final p in asked) {
        final hit = [
          for (final x in all)
            if (_fold(x.id) == _fold(p)) x.id,
        ];
        final byTitle = hit.isNotEmpty
            ? const <String>[]
            : [
                for (final x in all)
                  if (_fold(x.title).contains(_fold(p))) x.id,
              ];
        if (hit.isEmpty && byTitle.isEmpty) unknown.add(p);
        chosen
          ..addAll(hit)
          ..addAll(byTitle);
      }
    }
    // A part brings its own: el-atma's "C" its C1…C11; usul's appeals as
    // they were and as Law 7589 made them.
    if (key == 'el-atma') {
      for (final id in [...chosen]) {
        if (id.length == 1) {
          chosen.addAll([
            for (final x in all)
              if (x.id.startsWith(id)) x.id,
          ]);
        }
      }
    }
    if (key == 'usul' &&
        all.any(
          (x) => chosen.contains(x.id) && x.title.startsWith('Kanun yolları'),
        )) {
      chosen.addAll([
        for (final x in all)
          if (x.title.startsWith('Kanun yolları')) x.id,
      ]);
    }
    // A topic listed first gave its core at the bare call: asked for parts,
    // it is not sent again unless asked for by name.
    if ((how?.listFirst ?? false) && asked.isNotEmpty && !whole) {
      chosen.removeWhere(
        (id) =>
            how!.core.contains(id) && !asked.any((p) => _fold(p) == _fold(id)),
      );
    }
    final out = StringBuffer(intro.trimRight());
    final left = <String>[];
    for (final x in all) {
      if (!chosen.contains(x.id)) continue;
      final core = how?.core.contains(x.id) ?? false;
      if (!core && out.length + x.text.length > mostOutput) {
        left.add(x.id);
        continue;
      }
      out.write('\n\n${x.text.trimRight()}');
    }
    final others = [
      for (final x in all)
        if (!chosen.contains(x.id) && _hasBody(x.text)) '${x.id} ${x.title}',
    ];
    return {
      'durum': 'bulundu',
      'konu': key,
      'metin': out.toString(),
      if (others.isNotEmpty) 'diger_bolumler': others,
      if (left.isNotEmpty)
        'aciklama':
            'Sığmayan bölümler: ${left.join(', ')}. Bunları ayrıca iste.',
      if (unknown.isNotEmpty) 'bilinmeyen_bolum': unknown,
      if (others.isNotEmpty || left.isNotEmpty)
        'not':
            'Gereken bölümü hukuk_rehber(konu, bolum) ile iste; birden '
            'çoğunu virgülle.',
    };
  }

  /// The kinds of case [text] names, the most named first: by the topics'
  /// own names and their other names, as whole words or (four letters and
  /// more) as the start of a word.
  List<String> topicsIn(String text) {
    final folded = _fold(text).replaceAll(RegExp(r'\s+'), ' ');
    final words = RegExp(r'[a-z0-9-]+')
        .allMatches(_fold(text))
        .map((m) => m[0]!)
        .toSet();
    final count = <String, int>{};
    void hit(String topic) => count[topic] = (count[topic] ?? 0) + 1;
    for (final MapEntry(key: alias, value: topic) in _aliases.entries) {
      if (alias.contains(' ') || alias.contains('-')) {
        // "odeme-emri" in "ödeme emrine itiraz".
        if (folded.contains(alias.replaceAll('-', ' '))) hit(topic);
      } else if (words.contains(alias) ||
          (alias.length >= 4 && words.any((w) => w.startsWith(alias)))) {
        hit(topic);
      }
    }
    for (final topic in topics.keys) {
      if (words.contains(topic)) hit(topic);
    }
    final found = [
      for (final e in count.entries)
        if (!general.contains(e.key) && topics.containsKey(e.key)) e,
    ]..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in found) e.key];
  }

  /// The guide's text for the topics [text] names, to go with a question;
  /// null when it names none. At most [most] topics.
  String? blockFor(String text, {int most = 2}) {
    final found = topicsIn(text).take(most).toList();
    final crime = asksCrime(text);
    if (found.isEmpty && !crime) return null;
    String block(String k) {
      final got = read(k);
      final others = got['diger_bolumler'] as List?;
      return [
        '<rehber konu="$k">\n${got['metin']}',
        if (others != null)
          'Bu konunun diğer bölümleri (hukuk_rehber("$k", bolum) ile oku): '
              '${others.join('; ')}',
        '</rehber>',
      ].join('\n');
    }

    return [
      for (final k in found) block(k),
      if (found.isNotEmpty)
        'Folio bu konunun rehberini ekledi. Hangi maddeye dayanacağını önce '
            'rehberden bul, sonra o maddeyi mevzuat_madde ile oku. Rehberde '
            'olmayan bir maddeye dayanmadan önce onu da oku.',
      if (crime) crimeNote,
    ].join('\n\n');
  }

  /// Said to the model when the question is about a sentence: the range,
  /// HAGB, suspension, limitation and mediation come from Folio's engine.
  static const crimeNote =
      'Bu soru bir cezanın hesabını içeriyor. Ceza aralığını, HAGB\'yi, '
      'ertelemeyi, seçenek yaptırımı, dava zamanaşımını, uzlaştırmayı ve '
      'önödemeyi kafandan ya da madde metninden hesaplama: önce ceza_hesapla '
      'aracını çağır (suç kodunu ve olay tarihini ver), sonucunu kullan. Suç '
      'tabloda yoksa aralığı mevzuat_madde ile olay tarihindeki metinden oku. '
      'Madde metnini aktaracaksan mevzuat_madde ile okuduğun metinden aynen al.';

  /// Whether [text] asks for a sentence's reckoning.
  static bool asksCrime(String text) {
    final t = text
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase();
    return RegExp(
      r'hagb|hükmün açıklanmasının geri|hukmun aciklanmasinin geri|'
      r'cezanın ertelen|cezanin ertelen|erteleme|seçenek yaptırım|'
      r'secenek yaptirim|adli para cezasına çevr|uzlaştırma|uzlastirma|'
      r'önödeme|onodeme|dava zamanaşımı|dava zamanasimi|ceza aralığı|'
      r'ceza araligi|kaç yıl ceza|kac yil ceza|ne kadar ceza|hapis cezası|'
      r'hapis cezasi|tck\s*m?\.?\s*\d|5237',
    ).hasMatch(t);
  }

  /// The tool, as `tools/list` gives it.
  Map<String, Object?> get tool => {
    'name': 'hukuk_rehber',
    'title': 'Hukuk rehberi',
    'description':
        'Folio\'nun hukuk rehberi: konuya göre hangi kanunun hangi '
        'maddeleri, süreler, tuzaklar ve izlenecek yol. Hukuki bir '
        'değerlendirmeye başlarken, madde numarası yazmadan önce ilgili '
        'konuyu oku. $summary',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'konu': {
          'type': 'string',
          'description': 'Konu: ${topics.keys.join(', ')}',
        },
        'bolum': {
          'type': 'string',
          'description':
              'Büyük konularda yalnız gereken bölümler, virgülle: "E, E4". '
              'Boş bırakırsan konu tam gelir; fon-tasfiyesi boşsa çekirdek '
              've bölüm listesi gelir, tamamı için "tam". Bölümler: $index',
        },
      },
      'required': ['konu'],
    },
    'annotations': const {
      'readOnlyHint': true,
      'idempotentHint': true,
      'openWorldHint': false,
    },
  };

  /// [text] lower-cased with Turkish letters as plain ones, as the aliases
  /// are kept: "İşe İade" → "ise iade".
  static String _fold(String text) {
    const from = 'çğıöşüÇĞİÖŞÜ', to = 'cgiosuCGIOSU';
    final out = StringBuffer();
    for (final r in text.replaceAll('İ', 'i').replaceAll('I', 'ı').runes) {
      final c = String.fromCharCode(r);
      final i = from.indexOf(c);
      out.write(i < 0 ? c : to[i]);
    }
    return out.toString().toLowerCase();
  }
}
