import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'citation.dart' show titleCaseTr;

/// Which of the Constitutional Court's two banks a decision is in.
enum ConstitutionalKind {
  /// Constitutional review of a law: cited by esas and karar.
  norm('NormDenetimi', 'normkararlarbilgibankasi.anayasa.gov.tr'),

  /// An individual application: cited by its application number.
  individual('BireyselBasvuru', 'kararlarbilgibankasi.anayasa.gov.tr');

  const ConstitutionalKind(this.code, this.host);

  /// What the bank calls it, "kararTipi".
  final String code;

  /// Where its own site shows it. Either host answers for both.
  final String host;

  static ConstitutionalKind? of(String code) {
    for (final kind in values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}

/// One decision as the Constitutional Court's bank describes it.
@immutable
class ConstitutionalRecord {
  const ConstitutionalRecord({
    required this.kind,
    required this.id,
    this.esas = '',
    this.karar = '',
    this.application = '',
    this.applicant = '',
    this.date = '',
    this.gazetteDate = '',
    this.gazetteNumber = '',
    this.outcome = '',
    this.body = '',
    this.subject = '',
    this.html,
  });

  final ConstitutionalKind kind;
  final String id;
  final String esas, karar;

  /// The application number of an individual application, "2019/19126".
  final String application;

  /// Whose application it was, as the Court names it: "Hasan Durmuş".
  final String applicant;

  /// "26/1/2022": the Court's own way of writing a date in a reference.
  final String date;
  final String gazetteDate, gazetteNumber;

  /// "Esas - Ret", "Esas (İhlal)".
  final String outcome;

  /// Which part of the Court decided: "Genel Kurul", "İkinci Bölüm".
  final String body;

  /// What it was about, as plain text.
  final String subject;

  /// The decision itself. Only fetched when it is opened.
  final String? html;

  /// The Court's own page for the decision.
  String get url {
    final token = base64Url.encode(utf8.encode('kbb:$id')).replaceAll('=', '');
    return 'https://${kind.host}/kbb/pages/search/${kind.code}'
        '?id=$token&type=${kind.code}';
  }

  /// How the Court itself asks to be cited, with AYM in front so that a
  /// reference pasted into a document is marked again: "AYM, E.2020/95,
  /// K.2022/3, 26/1/2022" and "AYM, Hasan Durmuş [GK], B. No: 2019/19126,
  /// 23/1/2025".
  String get reference {
    final parts = <String>['AYM'];
    if (kind == ConstitutionalKind.individual) {
      final grand = body == 'Genel Kurul' ? ' [GK]' : '';
      if (applicant.isNotEmpty) parts.add('$applicant$grand');
      parts.add('B. No: $application');
    } else {
      parts.add('E.$esas');
      parts.add('K.$karar');
    }
    if (date.isNotEmpty) parts.add(date);
    return parts.join(', ');
  }

  static ConstitutionalRecord? fromJson(Map<String, Object?> row) {
    final kind = ConstitutionalKind.of('${row['kararTipi'] ?? ''}');
    final id = row['id'];
    if (kind == null || id == null) return null;
    String field(String name) {
      final value = row[name];
      return value == null ? '' : '$value'.trim();
    }

    return ConstitutionalRecord(
      kind: kind,
      id: '$id',
      esas: field('esasNo'),
      karar: field('kararNo'),
      application: field('basvuruNo'),
      applicant: titleCaseTr(field('basvuruAdi')),
      date: courtDate(field('kararTarihi')),
      gazetteDate: courtDate(field('resmiGazeteTarihi')),
      gazetteNumber: field('resmiGazeteSayisi'),
      outcome: kind == ConstitutionalKind.individual
          ? field('kararTuruBasvuruSonucuLabel')
          : field('kararTuruDosyaSonucuLabel'),
      body: field('kararVerenBirimLabel'),
      subject: _plain(field('kararKonusu')),
      html: row['icerik'] is String ? row['icerik'] as String : null,
    );
  }
}

/// "2022-01-26" as the Court writes it in a reference, "26/1/2022".
@visibleForTesting
String courtDate(String value) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (m == null) return value;
  return '${int.parse(m.group(3)!)}/${int.parse(m.group(2)!)}/${m.group(1)}';
}

String _plain(String html) => html
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// A page of a search of the Court's bank.
@immutable
class ConstitutionalPage {
  const ConstitutionalPage({required this.records, required this.total});

  const ConstitutionalPage.empty() : records = const [], total = 0;

  final List<ConstitutionalRecord> records;
  final int total;
}

/// The Constitutional Court's decision bank.
///
/// The Court publishes nowhere else: neither Bedesten nor UYAP Emsal carries
/// its decisions, so an AYM citation asked of them was always "not found".
/// Its bank answers a structured question exactly — measured, "esasNo"
/// 2020/95 with "kararNo" 2022/3 gives the one decision, and "basvuruNo"
/// 2019/19126 the one application — where its free text search for the same
/// numbers gives two hundred.
///
/// What goes out is the numbers of the decision, and nothing of the document
/// they were read from.
class ConstitutionalCourt {
  ConstitutionalCourt({
    @visibleForTesting
    Future<String> Function(ConstitutionalKind kind, String body)? send,
    // `this._send` cannot be called: a named argument may not begin with an
    // underscore.
    // ignore: prefer_initializing_formals
  }) : _send = send;

  final Future<String> Function(ConstitutionalKind kind, String body)? _send;

  static const _path = '/api/core/public/search';

  /// The decisions filed under these numbers: [esas] and [karar] for a
  /// review of a law, [application] for an individual application.
  Future<List<ConstitutionalRecord>> find({
    String? esas,
    String? karar,
    String? application,
  }) async {
    final kind = application != null
        ? ConstitutionalKind.individual
        : ConstitutionalKind.norm;
    final page = await _ask(kind, {
      'esasNo': ?esas,
      'kararNo': ?karar,
      'basvuruNo': ?application,
      'page': 1,
      'size': 5,
    });
    return page.records;
  }

  /// One decision with its text.
  Future<ConstitutionalRecord?> byId(ConstitutionalKind kind, String id) async {
    final page = await _ask(kind, {'id': id, 'page': 1, 'size': 1});
    return page.records.isEmpty ? null : page.records.first;
  }

  /// A search of the bank's text. [page] counts from one.
  Future<ConstitutionalPage> search(
    ConstitutionalKind kind, {
    String words = '',
    String? esas,
    String? karar,
    String? application,
    int page = 1,
    int size = 10,
  }) => _ask(kind, {
    if (words.trim().isNotEmpty) 'query': words.trim(),
    'esasNo': ?esas,
    'kararNo': ?karar,
    'basvuruNo': ?application,
    'page': page,
    'size': size,
  });

  Future<ConstitutionalPage> _ask(
    ConstitutionalKind kind,
    Map<String, Object?> fields,
  ) async {
    final body = jsonEncode({'kararTipi': kind.code, ...fields});
    final answer = await (_send ?? _http)(kind, body);
    final json = jsonDecode(answer);
    if (json is! Map) return const ConstitutionalPage.empty();
    final rows = json['data'];
    return ConstitutionalPage(
      records: [
        if (rows is List)
          for (final row in rows)
            if (row is Map)
              ?ConstitutionalRecord.fromJson(row.cast<String, Object?>()),
      ],
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<String> _http(ConstitutionalKind kind, String body) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.https(kind.host, _path);
      final request = await client.postUrl(uri);
      request.headers
        ..contentType = ContentType('application', 'json', charset: 'utf-8')
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.userAgentHeader, 'Folio');
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
