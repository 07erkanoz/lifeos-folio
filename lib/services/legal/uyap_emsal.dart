import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'html_text.dart';

/// One decision as UYAP Emsal lists it.
@immutable
class EmsalRecord {
  const EmsalRecord({
    required this.id,
    required this.court,
    required this.esas,
    required this.karar,
    required this.date,
    this.state = '',
  });

  final String id;

  /// "İstanbul Bölge Adliye Mahkemesi 35. Hukuk Dairesi".
  final String court;
  final String esas, karar;

  /// "08.07.2026".
  final String date;

  /// "KESİNLEŞTİ", when the bank says.
  final String state;

  static EmsalRecord? fromJson(Map<String, Object?> row) {
    final id = row['id'];
    if (id == null) return null;
    String field(String name) => '${row[name] ?? ''}'.trim();
    return EmsalRecord(
      id: '$id',
      court: field('daire'),
      esas: field('esasNo'),
      karar: field('kararNo'),
      date: field('kararTarihi'),
      state: field('durum'),
    );
  }
}

/// UYAP Emsal, the Ministry's second case bank.
///
/// It publishes the regional courts of appeal far more fully than Bedesten
/// does — two hundred civil chambers of the Bölge Adliye Mahkemeleri and
/// the commercial courts beneath them — and so is asked after Bedesten has
/// answered with nothing. Like every bank it publishes a selection, not
/// everything decided. Its search takes the case numbers as ranges; the same
/// number at both ends finds the one decision.
class UyapEmsal {
  UyapEmsal({
    @visibleForTesting Future<String> Function(String path, String? body)? send,
    // `this._send` cannot be called: a named argument may not begin with an
    // underscore.
    // ignore: prefer_initializing_formals
  }) : _send = send;

  final Future<String> Function(String path, String? body)? _send;

  static const host = 'emsal.uyap.gov.tr';

  /// Its own search page. It shows a decision only inside the page, so
  /// this is where a reader is sent to look one up for themselves.
  static const site = 'https://$host/';

  /// The decisions filed under these numbers.
  Future<List<EmsalRecord>> find({
    required int esasYear,
    required int esasNumber,
    required int kararYear,
    required int kararNumber,
  }) async {
    final body = jsonEncode({
      'data': {
        'arananKelime': '',
        'esasYil': '$esasYear',
        'esasIlkSiraNo': '$esasNumber',
        'esasSonSiraNo': '$esasNumber',
        'kararYil': '$kararYear',
        'kararIlkSiraNo': '$kararNumber',
        'kararSonSiraNo': '$kararNumber',
        'siralama': '1',
        'siralamaDirection': 'desc',
        'pageSize': 10,
        'pageNumber': 1,
      },
    });
    final json = jsonDecode(await (_send ?? _http)('/aramadetaylist', body));
    if (json is! Map) return const [];
    final data = json['data'];
    final rows = data is Map ? data['data'] : null;
    return [
      if (rows is List)
        for (final row in rows)
          if (row is Map) ?EmsalRecord.fromJson(row.cast<String, Object?>()),
    ];
  }

  /// "2024/1642" as its year and number; null when it is not one.
  static (int, int)? numbers(String v) {
    final m = RegExp(r'^\s*(\d{4})\s*/\s*0*(\d+)\s*$').firstMatch(v);
    return m == null ? null : (int.parse(m[1]!), int.parse(m[2]!));
  }

  /// Decisions with [words], or under the case [esas] and decision [karar]
  /// numbers ("2024/1642"), the newest first; for the AI's tools, as they
  /// give them.
  Future<({int total, List<Map<String, Object?>> rows})> search({
    String words = '',
    String esas = '',
    String karar = '',
    int page = 1,
  }) async {
    final e = numbers(esas), k = numbers(karar);
    final body = jsonEncode({
      'data': {
        'arananKelime': words.trim(),
        if (e != null) ...{
          'esasYil': '${e.$1}',
          'esasIlkSiraNo': '${e.$2}',
          'esasSonSiraNo': '${e.$2}',
        },
        if (k != null) ...{
          'kararYil': '${k.$1}',
          'kararIlkSiraNo': '${k.$2}',
          'kararSonSiraNo': '${k.$2}',
        },
        'siralama': '1',
        'siralamaDirection': 'desc',
        'pageSize': 10,
        'pageNumber': page < 1 ? 1 : page,
      },
    });
    final json = jsonDecode(await (_send ?? _http)('/aramadetaylist', body));
    final data = json is Map ? json['data'] : null;
    if (data is! Map) {
      throw const FormatException('UYAP Emsal cevabı okunamadı');
    }
    final rows = [
      for (final row in data['data'] as List? ?? const [])
        if (row is Map) ?EmsalRecord.fromJson(row.cast<String, Object?>()),
    ];
    final total = data['recordsTotal'];
    return (
      total: total is num ? total.toInt() : rows.length,
      rows: [
        for (final r in rows)
          {
            'kimlik': 'emsal:${r.id}',
            'mahkeme': r.court,
            'esas': r.esas,
            'karar': r.karar,
            'tarih': r.date,
            if (r.state.isNotEmpty) 'kesinlesme': r.state,
          },
      ],
    );
  }

  /// A decision's text, as plain text; empty when the bank gives none.
  Future<String> text(String id) async {
    final n = id.replaceFirst('emsal:', '').trim();
    if (!RegExp(r'^\d+$').hasMatch(n)) return '';
    final html = await page(n);
    return html == null ? '' : plainTextOf(html).trim();
  }

  /// The decision's page, as HTML.
  Future<String?> page(String id) async {
    final json = jsonDecode(
      await (_send ?? _http)(
        '/getDokuman?id=${Uri.encodeQueryComponent(id)}',
        null,
      ),
    );
    if (json is! Map) return null;
    final html = json['data'];
    return html is String && html.trim().isNotEmpty ? html : null;
  }

  static Future<String> _http(String path, String? body) async {
    // A connection the line cut is tried again before giving up.
    for (var attempt = 1; ; attempt++) {
      try {
        return await _httpOnce(path, body);
      } on IOException {
        if (attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
      }
    }
  }

  static Future<String> _httpOnce(String path, String? body) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse('https://$host$path');
      final request = body == null
          ? await client.getUrl(uri)
          : await client.postUrl(uri);
      request.headers
        ..set('X-Requested-With', 'XMLHttpRequest')
        ..set(HttpHeaders.acceptHeader, 'application/json, text/plain, */*')
        ..set(HttpHeaders.userAgentHeader, 'Folio');
      if (body != null) {
        request.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        request.write(body);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 40),
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
