import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
