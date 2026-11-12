import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

/// Academic writing on law, from TR Dizin (TÜBİTAK ULAKBİM's index of
/// Turkish journals): a search within its law subject, a publication's
/// record with its abstract, and its full text when the journal gave a PDF.
/// Only a search's words and a publication's number go out.
class Doctrine {
  Doctrine({
    @visibleForTesting Future<Object?> Function(Uri uri)? getJson,
    @visibleForTesting Future<List<int>> Function(Uri uri)? getBytes,
    Future<String> Function(String path)? pdfText,
  }) : _getJson = getJson ?? _httpJson,
       _getBytes = getBytes ?? _httpBytes,
       _pdfText = pdfText;

  static const host = 'search.trdizin.gov.tr';
  static const _pdfHost = 'pdf.trdizin.gov.tr';
  static const _subject = 'Sosyal > Sosyal > Hukuk';

  /// The hosts a PDF is fetched from: TR Dizin's own.
  static const _pdfHosts = {'pdf.trdizin.gov.tr', 'download.trdizin.gov.tr'};
  static const mostBytes = 30 * 1024 * 1024;

  final Future<Object?> Function(Uri uri) _getJson;
  final Future<List<int>> Function(Uri uri) _getBytes;
  final Future<String> Function(String path)? _pdfText;

  /// Publications read in this session, by their number.
  final _read = <String, Map<String, Object?>>{};

  /// Publications on [query], the most relevant (or the newest) first.
  Future<Map<String, Object?>> search(
    String query, {
    int count = 8,
    bool newest = false,
  }) async {
    final q = query.trim();
    if (q.length < 2) {
      return {'durum': 'yok', 'aciklama': 'Sorgu en az iki harf olmalı.'};
    }
    final got = await _getJson(
      Uri.https(host, '/api/defaultSearch/publication/', {
        'q': q,
        'order': newest ? 'publicationYear-DESC' : 'relevance-DESC',
        'page': '1',
        'limit': '${count.clamp(1, 12)}',
        'facet-subject': _subject,
      }),
    );
    final hits = (got is Map ? got['hits'] : null) as Map? ?? const {};
    var total = hits['total'];
    if (total is Map) total = total['value'];
    final found = [
      for (final h in hits['hits'] as List? ?? const [])
        if (h is Map) publication(h),
    ].where((x) => '${x['kimlik']}'.isNotEmpty && '${x['baslik']}'.isNotEmpty);
    return {
      'durum': found.isEmpty ? 'yok' : 'bulundu',
      'toplam': total is num ? total.toInt() : 0,
      'sonuclar': [
        for (final x in found) {...x}..remove('ozet_tam'),
      ],
      'not':
          'Doktrin ikna edicidir, bağlayıcı değildir. Dayanacaksan '
          'doktrin_getir ile oku ve yazar, yıl, dergi ve sayfayla an.',
    };
  }

  /// A publication's record, and its full text when it has a PDF.
  Future<Map<String, Object?>> read(String id, {int part = 1}) async {
    final n = id.replaceFirst('doktrin:', '').trim();
    if (!RegExp(r'^\d+$').hasMatch(n)) {
      return {'durum': 'yok', 'aciklama': 'doktrin_ara kimliği gerekli.'};
    }
    final kept = _read[n] ?? await _fetch(n);
    if (kept == null) {
      return {'durum': 'yok', 'aciklama': 'TR Dizin’de bu yayın bulunamadı.'};
    }
    _read[n] = kept;
    final text = '${kept['metin'] ?? ''}';
    const size = 7000;
    final parts = text.isEmpty ? 0 : (text.length / size).ceil();
    final at = parts == 0 ? 0 : part.clamp(1, parts);
    return {
      'durum': 'bulundu',
      ...{...kept}..remove('metin'),
      if (parts > 0) ...{
        'parca': at,
        'toplam_parca': parts,
        'metin': text.substring(
          (at - 1) * size,
          (at * size).clamp(0, text.length),
        ),
        if (at < parts) 'not': 'Devamı için parca=${at + 1}.',
      },
    };
  }

  Future<Map<String, Object?>?> _fetch(String id) async {
    final got = await _getJson(Uri.https(host, '/api/publicationById/$id'));
    final hits =
        ((got is Map ? got['hits'] : null) as Map?)?['hits'] as List? ??
        const [];
    if (hits.isEmpty || hits.first is! Map) return null;
    final record = publication(hits.first as Map);
    final pdf = '${record.remove('pdf') ?? ''}';
    if (pdf.isEmpty) return {...record, 'metin_durumu': 'pdf_yok'};
    try {
      final text = await _pdf(pdf);
      return {
        ...record,
        'metin': text,
        'metin_durumu': text.trim().isEmpty ? 'metin_okunamadi' : 'tam_metin',
      };
    } catch (e) {
      return {...record, 'metin_durumu': 'pdf_alinamadi', 'aciklama': '$e'};
    }
  }

  /// The PDF behind TR Dizin's viewer, as text.
  Future<String> _pdf(String pdfId) async {
    final viewer = await _getJson(
      Uri.https(host, '/api/getFile/${Uri.encodeComponent(pdfId)}', {
        'showViewer': 'true',
      }),
    );
    final v = Uri.tryParse('$viewer');
    if (v == null || !_allowed(v)) {
      throw const HttpException('TR Dizin güvenli bir PDF adresi vermedi');
    }
    final mark = v.path.split('/pdf/').last.replaceAll('/', '');
    if (mark.isEmpty) throw const HttpException('PDF anahtarı çözülemedi');
    final real = utf8
        .decode(await _getBytes(Uri.https(_pdfHost, '/api/$mark')))
        .trim()
        .replaceAll('"', '');
    final url = Uri.tryParse(real);
    if (url == null || !_allowed(url)) {
      throw const HttpException('TR Dizin izinli olmayan bir PDF adresi verdi');
    }
    final bytes = await _getBytes(url);
    if (bytes.length > mostBytes)
      throw const HttpException('PDF 30 MB’ı aşıyor');
    if (bytes.length < 4 ||
        utf8.decode(bytes.take(4).toList(), allowMalformed: true) != '%PDF') {
      throw const HttpException('Dosya geçerli bir PDF değil');
    }
    final dir = await Directory.systemTemp.createTemp('folio-doktrin-');
    try {
      final file = File(p.join(dir.path, 'yayin.pdf'));
      await file.writeAsBytes(bytes);
      return await (_pdfText ?? _noText)(file.path);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  static Future<String> _noText(String path) async => '';

  static bool _allowed(Uri u) =>
      u.scheme == 'https' && _pdfHosts.contains(u.host);

  /// A hit as the tool gives it.
  @visibleForTesting
  static Map<String, Object?> publication(Map hit) {
    final source = (hit['_source'] as Map?) ?? hit;
    String clean(Object? v) =>
        v == null ? '' : '$v'.replaceAll(RegExp(r'\s+'), ' ').trim();
    final abstracts = source['abstracts'] as List? ?? const [];
    final tr = abstracts.whereType<Map>().where(
      (a) => '${a['language'] ?? ''}'.toUpperCase() == 'TUR',
    );
    final abstract = tr.isNotEmpty
        ? tr.first
        : (abstracts.isNotEmpty && abstracts.first is Map
              ? abstracts.first as Map
              : const {});
    final authors = <String>[
      for (final a in source['authors'] as List? ?? const [])
        if (a is Map && clean(a['name'] ?? a['inPublicationName']).isNotEmpty)
          clean(a['name'] ?? a['inPublicationName']),
    ].toSet().toList();
    final journal = source['journal'] as Map? ?? const {};
    final issue = source['issue'] as Map? ?? const {};
    final id = clean(source['id'] ?? hit['_id']);
    final summary = clean(abstract['abstract']);
    return {
      'kimlik': id.isEmpty ? '' : 'doktrin:$id',
      'baslik': clean(
        abstract['title'] ?? source['title'] ?? source['orderTitle'],
      ),
      'yazarlar': authors,
      'dergi': clean(journal['name']),
      'yil': clean(source['publicationYear'] ?? issue['year']),
      'cilt': clean(issue['volume']),
      'sayi': clean(issue['number']),
      'sayfa': [
        clean(source['startPage']),
        clean(source['endPage']),
      ].where((x) => x.isNotEmpty).join('-'),
      if (clean(source['doi']).isNotEmpty) 'doi': clean(source['doi']),
      'ozet': summary.length > 900 ? '${summary.substring(0, 900)}…' : summary,
      'anahtar_kelimeler': clean(abstract['keywords']),
      'atif_sayisi': (source['orderCitationCount'] as num?)?.toInt() ?? 0,
      'pdf': clean(source['pdf']),
      if (id.isNotEmpty) 'adres': 'https://$host/tr/yayin/detay/$id',
    };
  }

  static Future<HttpClientResponse> _get(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final req = await client.getUrl(uri);
    req.headers
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(HttpHeaders.userAgentHeader, 'LifeOS-Folio (hukuk doktrini)');
    final res = await req.close().timeout(const Duration(seconds: 45));
    if (res.statusCode != 200) {
      client.close(force: true);
      throw HttpException('TR Dizin HTTP ${res.statusCode}', uri: uri);
    }
    return res;
  }

  static Future<Object?> _httpJson(Uri uri) async =>
      jsonDecode(await (await _get(uri)).transform(utf8.decoder).join());

  static Future<List<int>> _httpBytes(Uri uri) async {
    final res = await _get(uri);
    final out = <int>[];
    await for (final chunk in res) {
      out.addAll(chunk);
      if (out.length > mostBytes) break;
    }
    return out;
  }
}
