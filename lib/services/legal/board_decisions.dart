import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'html_text.dart';

/// The bodies other than the courts whose decisions a lawyer reads, each
/// from its own site: the Court of Jurisdictional Disputes (Uyuşmazlık
/// Mahkemesi: which branch of the judiciary hears a case) and the
/// Competition Board (Rekabet Kurulu). Their decisions are PDFs; their text
/// is read by Folio's own reader. Only the search's words go out.
enum Board {
  uyusmazlik('Uyuşmazlık Mahkemesi', 'kararlar.uyusmazlik.gov.tr'),
  rekabet('Rekabet Kurulu', 'www.rekabet.gov.tr');

  const Board(this.label, this.host);
  final String label, host;
}

class BoardDecisions {
  BoardDecisions({
    this.pdfText,
    @visibleForTesting
    Future<String> Function(Uri uri, {Map<String, String>? form})? fetch,
    @visibleForTesting Future<List<int>> Function(Uri uri)? download,
  }) : _fetch = fetch ?? _get,
       _download = download ?? _bytes;

  /// A PDF's text: Folio's own reader.
  final Future<String> Function(String path)? pdfText;
  final Future<String> Function(Uri uri, {Map<String, String>? form}) _fetch;
  final Future<List<int>> Function(Uri uri) _download;

  /// The decisions found, by their id: their record, for the reading.
  final _found = <String, Map<String, Object?>>{};
  final _texts = <String, String>{};

  Future<Map<String, Object?>> search(Board board, String words) async {
    final q = words.trim();
    if (q.length < 2) {
      return {'durum': 'yok', 'aciklama': 'Sorgu en az iki harf olmalı.'};
    }
    final (total, rows) = switch (board) {
      Board.uyusmazlik => await _uyusmazlik(q),
      Board.rekabet => await _rekabet(q),
    };
    for (final r in rows) {
      _found['${r['kimlik']}'] = r;
    }
    return {
      'durum': rows.isEmpty ? 'yok' : 'bulundu',
      'kurum': board.label,
      'toplam': total,
      'sonuclar': rows,
      if (rows.isNotEmpty)
        'not':
            'En yeni ${rows.length} karar. Dayanmadan önce kurul_karar_getir '
            'ile oku.',
    };
  }

  /// A decision's text, in parts.
  Future<Map<String, Object?>> read(String id, {int part = 1}) async {
    final m = RegExp(r'^(uyusmazlik|rekabet):(.+)$').firstMatch(id.trim());
    if (m == null) {
      return {'durum': 'yok', 'aciklama': 'kurul_karar_ara kimliği gerekli.'};
    }
    final board = Board.values.byName(m[1]!);
    final key = m[2]!;
    final Uri? url = switch (board) {
      Board.uyusmazlik when RegExp(r'^\d{4}-\d+$').hasMatch(key) => Uri.https(
        board.host,
        '/Uploads/$key.pdf',
      ),
      Board.rekabet when RegExp(r'^[0-9a-f-]{36}$').hasMatch(key) => Uri.https(
        board.host,
        '/Karar',
        {'kararId': key},
      ),
      _ => null,
    };
    if (url == null) return {'durum': 'yok', 'aciklama': 'Kimlik okunamadı.'};
    var text = _texts[id];
    if (text == null) {
      final bytes = await _download(url);
      if (bytes.length < 5 || String.fromCharCodes(bytes.take(4)) != '%PDF') {
        return {'durum': 'yok', 'aciklama': 'Kararın PDF’i alınamadı.'};
      }
      final dir = await Directory.systemTemp.createTemp('folio-kurul-');
      try {
        final file = File(p.join(dir.path, 'karar.pdf'));
        await file.writeAsBytes(bytes);
        text = (await (pdfText ?? (_) async => '')(file.path)).trim();
      } finally {
        await dir.delete(recursive: true);
      }
      if (text.isEmpty) {
        return {
          'durum': 'yok',
          'aciklama': 'Kararın metni okunamadı (taranmış PDF olabilir).',
          'adres': '$url',
        };
      }
      _texts[id] = text;
    }
    const size = 7000;
    final parts = (text.length / size).ceil();
    final at = part.clamp(1, parts);
    return {
      'durum': 'bulundu',
      ...?_found[id],
      'kurum': board.label,
      'parca': at,
      'toplam_parca': parts,
      'metin': text.substring(
        (at - 1) * size,
        (at * size).clamp(0, text.length),
      ),
      'adres': '$url',
      if (at < parts) 'not': 'Devamı için parca=${at + 1}.',
    };
  }

  /// An ASP.NET form: the page first, for its state, then the search.
  Future<(int, List<Map<String, Object?>>)> _uyusmazlik(String q) async {
    final home = Uri.https(Board.uyusmazlik.host, '/');
    final page = await _fetch(home);
    String field(String name) =>
        RegExp('id="$name" value="([^"]*)"').firstMatch(page)?[1] ?? '';
    final html = await _fetch(
      home,
      form: {
        '__EVENTTARGET': '',
        '__EVENTARGUMENT': '',
        '__VIEWSTATE': field('__VIEWSTATE'),
        '__VIEWSTATEGENERATOR': field('__VIEWSTATEGENERATOR'),
        '__EVENTVALIDATION': field('__EVENTVALIDATION'),
        'txtSearch': q,
        'rblSearchScope': 'All',
        'btnSearch': 'Ara',
      },
    );
    return uyusmazlikRows(html);
  }

  @visibleForTesting
  static (int, List<Map<String, Object?>>) uyusmazlikRows(String html) {
    final total =
        int.tryParse(
          RegExp(r'sonuçları:\s*(\d+)\s*dosya').firstMatch(html)?[1] ?? '',
        ) ??
        0;
    final rows = <Map<String, Object?>>[];
    for (final m in RegExp(
      r'<td>\s*(\d{4}/\d+)\s*</td>\s*<td>\s*(\d{4}/\d+)\s*</td>\s*<td>\s*([\d/.]+)\s*</td>\s*<td>.*?Uploads/([\w-]+)\.pdf',
      dotAll: true,
    ).allMatches(html)) {
      rows.add({
        'kimlik': 'uyusmazlik:${m[4]}',
        'mahkeme': 'Uyuşmazlık Mahkemesi',
        'esas': m[1],
        'karar': m[2],
        'tarih': m[3]!.replaceAll('/', '.'),
      });
    }
    return (total, rows);
  }

  Future<(int, List<Map<String, Object?>>)> _rekabet(String q) async =>
      rekabetRows(
        await _fetch(
          Uri.https(Board.rekabet.host, '/tr/Kararlar', {
            'PdfText': q,
            'KararTuruID': '',
            'KararSayisi': '',
            'YayinlanmaTarihi': '',
            'KararTarihi': '',
          }),
        ),
      );

  @visibleForTesting
  static (int, List<Map<String, Object?>>) rekabetRows(String html) {
    final total =
        int.tryParse(
          RegExp(r'Toplam\s*:\s*(\d+)').firstMatch(html)?[1] ?? '',
        ) ??
        0;
    final rows = <Map<String, Object?>>[];
    // Each decision a block from its "Yayımlanma Tarihi" to the next.
    final starts = RegExp('Yayımlanma Tarihi').allMatches(html).toList();
    for (var i = 0; i < starts.length; i++) {
      final end = i + 1 < starts.length ? starts[i + 1].start : html.length;
      final block = html.substring(starts[i].start, end);
      final id = RegExp(r'/Karar\?kararId=([0-9a-f-]{36})')
          .firstMatch(block)?[1];
      if (id == null) continue;
      String after(String label) {
        final m = RegExp('$label\\s*:?\\s*(?:</[^>]+>\\s*|<[^>]+>\\s*)*([^<]+)')
            .firstMatch(block);
        return (m?[1] ?? '').trim();
      }

      final cells = [
        for (final c in RegExp(
          r'<td[^>]*>(.*?)</td>',
          dotAll: true,
        ).allMatches(block))
          plainTextOf(c[1]!).trim(),
      ].where((c) => c.isNotEmpty).toList();
      final subject = cells.isEmpty
          ? ''
          : cells.reduce((a, b) => a.length >= b.length ? a : b);
      rows.add({
        'kimlik': 'rekabet:$id',
        'mahkeme': 'Rekabet Kurulu',
        'karar': after('Karar Sayısı'),
        'tarih': after('Karar Tarihi'),
        'tur': after('Karar Türü'),
        if (subject.length > 30) 'konu': subject,
      });
    }
    return (total, rows);
  }

  static Future<String> _get(Uri uri, {Map<String, String>? form}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = form == null
          ? await client.getUrl(uri)
          : await client.postUrl(uri);
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (LifeOS-Folio)',
      );
      if (form != null) {
        req.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        req.write(Uri(queryParameters: form).query);
      }
      final res = await req.close().timeout(const Duration(seconds: 45));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}', uri: uri);
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<int>> _bytes(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (LifeOS-Folio)',
      );
      final res = await req.close().timeout(const Duration(seconds: 60));
      final out = <int>[];
      await for (final c in res) {
        out.addAll(c);
        if (out.length > 30 * 1024 * 1024) break;
      }
      return res.statusCode == 200 ? out : const [];
    } finally {
      client.close(force: true);
    }
  }
}
