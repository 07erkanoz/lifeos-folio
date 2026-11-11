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

  /// A topic's text for the tool, or the list of topics when [name] names
  /// none.
  Map<String, Object?> read(String name) {
    final key = topicOf(name);
    if (key == null) {
      return {
        'durum': 'yok',
        'aciklama': 'Bu adla bir rehber konusu yok.',
        'konular': topics.keys.toList(),
      };
    }
    return {'durum': 'bulundu', 'konu': key, 'metin': topics[key]};
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
    if (found.isEmpty) return null;
    return [
      for (final k in found) '<rehber konu="$k">\n${topics[k]}\n</rehber>',
      'Folio bu konunun rehberini ekledi. Hangi maddeye dayanacağını önce '
          'rehberden bul, sonra o maddeyi mevzuat_madde ile oku. Rehberde '
          'olmayan bir maddeye dayanmadan önce onu da oku.',
    ].join('\n\n');
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
