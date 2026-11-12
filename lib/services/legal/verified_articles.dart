import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

/// Articles the Ministry's bank (Bedesten) is known to have behind the
/// official text, given from the official text itself
/// (assets/mevzuat/dogrulanmis.json): each cut from mevzuat.gov.tr's text
/// of the law, word for word, on [cutOn]. Measured: Bedesten gave 1512
/// m.55 as it was before Law 7589, 2918 ek 17 with "bir yıl" where the law
/// now says "iki yıl", and had no 1211 m.68/A or m.68/B at all.
///
/// Only the [targets] are given from here. One asked for whose text cannot
/// be read is not asked of Bedesten instead: it would be the old text,
/// given as the law. The list is kept in the code, not taken from the
/// file, so that a file that cannot be read cannot empty it.
class VerifiedArticles {
  VerifiedArticles._(this.cutOn, this._texts);

  static const asset = 'assets/mevzuat/dogrulanmis.json';

  /// By law, the articles as Legislation.keyOf files them.
  static const targets = <int, Set<String>>{
    1211: {'68/a', '68/b'},
    1219: {'28', '45'},
    1512: {'55'},
    2252: {'5'},
    2464: {'19'},
    2813: {'8'},
    2873: {'2', '4', '8', '12', '15', '16', '17', '18', '21'},
    2918: {'ek 17'},
    2981: {'geçici 5'},
    6458: {'121/a'},
  };

  static bool isTarget(int law, String key) =>
      targets[law]?.contains(key) ?? false;

  /// When the texts were cut ("2026-09-21").
  final String cutOn;
  final Map<String, VerifiedText> _texts;

  VerifiedText? of(int law, String key) => _texts['$law|$key'];

  static Future<VerifiedArticles>? _loaded;

  /// The texts; null when the file cannot be read.
  static Future<VerifiedArticles?> load() async {
    try {
      return await (_loaded ??= _read().then(parse));
    } catch (_) {
      _loaded = null;
      return null;
    }
  }

  static Future<String> _read() async {
    try {
      return await rootBundle.loadString(asset);
    } on FlutterError {
      return File(asset).readAsString();
    }
  }

  @visibleForTesting
  static VerifiedArticles parse(String raw) {
    final json = jsonDecode(raw) as Map;
    final texts = <String, VerifiedText>{};
    for (final MapEntry(key: law, value: one)
        in (json['kanunlar'] as Map).entries) {
      final official = (one as Map)['resmi'] != false;
      final url = '${one['kaynak'] ?? ''}';
      for (final MapEntry(key: label, value: a)
          in (one['maddeler'] as Map).entries) {
        final text = '${(a as Map)['metin'] ?? ''}'.trim();
        if (text.isEmpty) continue;
        texts['$law|${keyOf('$label')}'] = VerifiedText(
          text,
          heading: '${a['baslik'] ?? ''}'.trim(),
          official: official,
          url: url.startsWith('http') ? url : '',
        );
      }
    }
    return VerifiedArticles._('${json['kesim_tarihi'] ?? ''}', texts);
  }

  /// The file's label as Legislation.keyOf has it: "madde 68/A" → "68/a",
  /// "ek 17" → "ek 17", "geçici 5" → "geçici 5".
  @visibleForTesting
  static String keyOf(String label) => label
      .replaceFirst(RegExp(r'^madde\s+'), '')
      .replaceAll('I', 'ı')
      .replaceAll('İ', 'i')
      .toLowerCase();
}

class VerifiedText {
  const VerifiedText(
    this.text, {
    this.heading = '',
    this.official = true,
    this.url = '',
  });
  final String text, heading, url;

  /// Cut from mevzuat.gov.tr; false for a repealed law it no longer gives,
  /// cut from a copy of its official text.
  final bool official;
}
