import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'citation.dart';
import 'rich_text.dart';

/// A law as the Ministry's legislation bank files it.
@immutable
class BedestenLaw {
  const BedestenLaw({
    required this.id,
    required this.name,
    required this.tertip,
    required this.url,
  });

  final String id;

  /// As the bank writes it, in capitals: "TÜRK BORÇLAR KANUNU".
  final String name;
  final int tertip;

  /// Its page on mevzuat.gov.tr.
  final String url;

  Map<String, Object?> toJson() => {
    'id': id,
    'ad': name,
    'tertip': tertip,
    'adres': url,
  };

  static BedestenLaw fromJson(Map<String, Object?> json) => BedestenLaw(
    id: '${json['id']}',
    name: '${json['ad'] ?? ''}',
    tertip: (json['tertip'] as num?)?.toInt() ?? 0,
    url: '${json['adres'] ?? ''}',
  );
}

/// One node of a law's tree: an article, or a part or chapter above them.
@immutable
class BedestenNode {
  const BedestenNode({
    required this.id,
    required this.number,
    required this.heading,
    required this.updated,
  });

  final String id;

  /// "97"; empty for a part or a chapter.
  final String number;

  /// The bank's own heading for it: "Madde No: 1 - Görevin belirlenmesi".
  final String heading;

  final String updated;

  bool get isArticle => number.isNotEmpty;

  /// The side heading the bank gives an article, when it gives one.
  String get sideHeading {
    final m = RegExp(r'^Madde No:\s*\S+\s*-\s*(.+)$')
        .firstMatch(heading.trim());
    return m?.group(1)?.trim() ?? '';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'no': number,
    'baslik': heading,
    'tarih': updated,
  };

  static BedestenNode fromJson(Map<String, Object?> json) => BedestenNode(
    id: '${json['id']}',
    number: '${json['no'] ?? ''}',
    heading: '${json['baslik'] ?? ''}',
    updated: '${json['tarih'] ?? ''}',
  );
}

/// The bank's collections that carry a tree of articles, in the order they
/// are preferred: the law in force before its repealed record.
const _collections = [
  'KANUN',
  'CB_KARARNAME',
  'KHK',
  'TUZUK',
  'MULGA',
  'MULGA_KHK',
  'MULGA_CBK',
];

/// Where an article is asked to begin.
///
/// Anchored at the start of a paragraph and naming the kind: a plain "MADDE
/// 1" must not find "GEÇİCİ MADDE 1", nor 68 find 68/a — each of those is an
/// article of its own, and taking one for the other would show the reader
/// the wrong law without a word of warning.
RegExp openingOf(Citation citation) {
  final kind = switch (citation.kind) {
    ArticleKind.provisional => '(?:GEÇİCİ|Geçici|geçici)\\s+',
    ArticleKind.additional => '(?:EK|Ek|ek)\\s+',
    ArticleKind.plain => '',
  };
  final letter = citation.letter;
  final after = letter == null
      ? '(?!\\s*/\\s*[A-Za-zÇĞİÖŞÜçğıöşü])'
      : '\\s*/\\s*${trLoose(letter)}(?![A-Za-zÇĞİÖŞÜçğıöşü])';
  return RegExp(
    '^$kind(?:MADDE|Madde)\\s*0*${citation.article}$after\\s*[-‐‑‒–—−]',
    caseSensitive: false,
  );
}

/// The article's paragraphs in [page], with the headings that stand before
/// it there; null when the page does not hold it.
({List<RichParagraph> body, List<String> before})? cutArticle(
  List<RichParagraph> page,
  Citation citation,
) {
  final opening = openingOf(citation);
  final start = page.indexWhere((p) => opening.hasMatch(p.text.trim()));
  if (start < 0) return null;
  var end = page.length;
  for (var i = start + 1; i < page.length; i++) {
    if (opensArticle(page[i])) {
      end = i;
      break;
    }
  }
  final body = page.sublist(start, end);
  // Headings at the foot belong to the article after this one.
  while (body.length > 1 && _isHeading(body.last)) {
    body.removeLast();
  }
  return (body: body, before: trailingHeadings(page.sublist(0, start)));
}

/// The headings a page ends with: the bank files the headings of an article
/// at the foot of the article before it.
List<String> trailingHeadings(List<RichParagraph> page) {
  final out = <String>[];
  for (final paragraph in page.reversed) {
    if (!_isHeading(paragraph)) break;
    out.insert(0, _withoutNoteMarks(paragraph.text).trim());
  }
  return out;
}

/// The mark of a footnote, "[9]". The bank sets it in plain type even after
/// a bold heading: HMK m. 106's node ends "**Belirsiz alacak davası**[9]",
/// which is m. 107's heading and nothing of 106.
final _noteMark = RegExp(r'\s*\[\d{1,3}\]');

String _withoutNoteMarks(String text) => text.replaceAll(_noteMark, '');

/// A heading is set wholly in bold, short, and does not open an article. A
/// bold note in brackets — "(Mülga: …)" — is part of the article's text.
/// Neither the space around the bold nor a footnote's mark counts against it.
bool _isHeading(RichParagraph paragraph) {
  final text = _withoutNoteMarks(paragraph.text).trim();
  final runs = [
    for (final run in paragraph.runs)
      if (_withoutNoteMarks(run.text).trim().isNotEmpty) run,
  ];
  return runs.isNotEmpty &&
      runs.every((run) => run.bold) &&
      text.isNotEmpty &&
      text.length <= 140 &&
      !'([{'.contains(text[0]) &&
      !opensArticle(paragraph);
}

/// The Ministry's legislation bank, which answers for a single article.
///
/// The whole of a law is a large page — the Commercial Code runs to three
/// megabytes — and cutting an article out of it by its text is how the
/// older way came to show the next article's heading at the foot of this
/// one and this one's heading at the foot of the last. The bank keeps each
/// article on its own, set in the Official Gazette's own bold, and its tree
/// says which part and chapter the article is in.
///
/// It carries its oddities, measured on 26 September 2026: the headings of
/// an article are at the foot of the article before it (TBK m. 96 ends with
/// "VI. Karşılıklı borç yükleyen sözleşmelerde / 1. İfada sıra", which open
/// m. 97); a lettered article is inside the article it follows (İİK 68/a
/// in 68); and a repealed record can share its number with the law in force
/// (2004 is also "the repealed provisions of the İcra ve İflas Kanunu").
class BedestenLegislation {
  BedestenLegislation({
    @visibleForTesting Future<String> Function(String path, String body)? send,
    @visibleForTesting Duration between = const Duration(milliseconds: 350),
    // `this._send` cannot be called: a named argument may not begin with an
    // underscore.
    // ignore: prefer_initializing_formals
  }) : _send = send,
       // ignore: prefer_initializing_formals
       _between = between;

  final Future<String> Function(String path, String body)? _send;
  final Duration _between;

  static const _host = 'bedesten.adalet.gov.tr';

  Future<void> _queue = Future.value();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// The law filed under [number], the one in force before a repealed one.
  Future<BedestenLaw?> law(int number) async {
    final data = await _post('/mevzuat/searchDocuments', {
      'pageSize': 10,
      'pageNumber': 1,
      'sortFields': ['RESMI_GAZETE_TARIHI'],
      'sortDirection': 'desc',
      'mevzuatNo': '$number',
      'mevzuatTurList': _collections,
    }, paging: true);
    final rows = data['mevzuatList'];
    if (rows is! List) return null;
    final ours = <Map<String, Object?>>[
      for (final row in rows)
        if (row is Map && '${row['mevzuatNo']}' == '$number')
          row.cast<String, Object?>(),
    ];
    int rank(Map<String, Object?> row) {
      final type = row['mevzuatTur'];
      final name = type is Map ? '${type['name']}' : '$type';
      final at = _collections.indexOf(name);
      return at < 0 ? _collections.length : at;
    }

    if (ours.isEmpty) return null;
    ours.sort((a, b) => rank(a).compareTo(rank(b)));
    final row = ours.first;
    return BedestenLaw(
      id: '${row['mevzuatId']}',
      name: '${row['mevzuatAdi'] ?? ''}'.trim(),
      tertip: int.tryParse('${row['mevzuatTertip']}') ?? 0,
      url: '${row['url'] ?? ''}'.trim(),
    );
  }

  /// The law's tree, in the order of its text.
  Future<List<BedestenNode>> tree(String lawId) async {
    final data = await _post('/mevzuat/mevzuatMaddeTree', {'mevzuatId': lawId});
    final out = <BedestenNode>[];
    void walk(Object? nodes) {
      if (nodes is! List) return;
      for (final node in nodes) {
        if (node is! Map) continue;
        final number = '${node['maddeNo'] ?? ''}'.trim();
        out.add(
          BedestenNode(
            id: '${node['maddeId'] ?? ''}',
            number: number == 'null' ? '' : number,
            heading: '${node['maddeBaslik'] ?? node['title'] ?? ''}'.trim(),
            updated: '${node['guncellemeTarihi'] ?? ''}',
          ),
        );
        walk(node['children']);
      }
    }

    walk(data['children']);
    return out;
  }

  /// One node's page, as HTML.
  Future<String> page(String nodeId) async {
    final data = await _post('/mevzuat/getDocumentContent', {
      'documentType': 'MADDE',
      'id': nodeId,
    });
    final encoded = data['content'];
    if (encoded is! String || encoded.isEmpty) return '';
    return utf8.decode(base64.decode(encoded), allowMalformed: true);
  }

  /// The nodes that may hold [citation], the likeliest first.
  static List<BedestenNode> candidates(
    List<BedestenNode> nodes,
    Citation citation,
  ) {
    final wanted = '${citation.article}';
    final letter = citation.letter == null
        ? null
        : '$wanted/${upperTr(citation.letter!)}';
    final out = [
      for (final node in nodes)
        if (node.isArticle &&
            (node.number == wanted ||
                (letter != null &&
                    upperTr(node.number.replaceAll(' ', '')) == letter)))
          node,
    ];
    if (citation.kind != ArticleKind.plain) {
      // A provisional or added article is sometimes filed at the foot of
      // the law's last articles rather than on its own.
      final numbered = [
        for (final node in nodes)
          if (int.tryParse(node.number) != null) node,
      ]..sort((a, b) => int.parse(b.number).compareTo(int.parse(a.number)));
      for (final node in numbered.take(8)) {
        if (!out.contains(node)) out.add(node);
      }
    }
    // The same number can stand twice, an older reading beside the one in
    // force; the latest is tried first and its text decides.
    out.sort((a, b) => b.updated.compareTo(a.updated));
    return out.take(12).toList();
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> data, {
    bool paging = false,
  }) {
    final body = jsonEncode({
      'data': data,
      'applicationName': 'UyapMevzuat',
      if (paging) 'paging': true,
    });
    final next = _queue.then((_) async {
      final since = DateTime.now().difference(_last);
      if (since < _between) await Future<void>.delayed(_between - since);
      try {
        final answer = await (_send ?? _http)(path, body);
        final json = jsonDecode(answer);
        if (json is! Map) {
          throw const FormatException('Bedesten cevabı okunamadı');
        }
        final meta = json['metadata'];
        if (meta is Map && meta['FMTY'] != 'SUCCESS') {
          throw FormatException('${meta['FMTE'] ?? 'Bedesten hatası'}');
        }
        final result = json['data'];
        return result is Map
            ? result.cast<String, Object?>()
            : <String, Object?>{};
      } finally {
        _last = DateTime.now();
      }
    });
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  static Future<String> _http(String path, String body) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.https(_host, path);
      final request = await client.postUrl(uri);
      request.headers
        ..contentType = ContentType('application', 'json', charset: 'utf-8')
        ..set(HttpHeaders.userAgentHeader, 'Folio')
        ..set('AdaletApplicationName', 'UyapMevzuat')
        ..set('Origin', 'https://mevzuat.adalet.gov.tr')
        ..set('Referer', 'https://mevzuat.adalet.gov.tr/');
      request.write(body);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('${response.statusCode}', uri: uri);
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }
}
