/// What the Avukat Portal says about a case, as it says it.
///
/// The portal is inconsistent: the same field comes under different names
/// in different answers, a number where text was expected, a list where a
/// map was. Each reader here takes the names in the order they were found
/// to come, and turns whatever came into text, so a field that has moved
/// is read rather than silently left empty.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

String _str(Object? v) => v?.toString() ?? '';

/// Ids are base64 and come quoted now and then, which breaks them.
String _id(Object? v) => _str(v).replaceAll('"', '').replaceAll("'", '').trim();

/// The first of [values] that says something.
String _first(List<Object?> values) {
  for (final v in values) {
    if (v == null || v == false || (v is num && v == 0)) continue;
    final s = _str(v);
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// Answers come as a map, or as a list holding one.
Map<String, Object?> _one(Object? raw) {
  if (raw is Map) return raw.cast<String, Object?>();
  if (raw is List && raw.isNotEmpty && raw.first is Map) {
    return (raw.first as Map).cast<String, Object?>();
  }
  return const {};
}

/// The case's particulars: what kind of case, where it stands, and the days
/// set for it. Shown, not followed: the calendar is banaozel's.
class UyapCaseDetails {
  const UyapCaseDetails({
    this.kind = '',
    this.opening = '',
    this.status = '',
    this.hearing,
    this.inspection,
    this.preliminary,
    this.related = const [],
  });

  factory UyapCaseDetails.fromJson(Object? raw) {
    final json = _one(raw);
    String? date(Object? v) {
      final s = _str(v).trim();
      return s.isEmpty ? null : s;
    }

    return UyapCaseDetails(
      kind: _str(json['davaTurleriStr']).trim(),
      opening: _str(json['davaAcilisTuruStr']).trim(),
      status: _str(json['dosyaDurumu']).trim(),
      hearing: date(json['durusmaTarihiStr']),
      inspection: date(json['kesifTarihiStr']),
      // UYAP writes it without the second e; both are read in case it is
      // ever put right.
      preliminary: date(
        json['onIncelemTarihiStr'] ?? json['onIncelemeTarihiStr'],
      ),
      related: [
        for (final (field, label) in const [
          ('ilgiliDosyaListesiStr', 'İlgili dosya'),
          ('ilgiliDavaListesiStr', 'İlgili dava'),
          ('birlesenDosyaListStr', 'Birleşen dosya'),
          ('ilgiliSeriDavaListesiStr', 'Seri dava'),
        ])
          if (_str(json[field]).trim().isNotEmpty)
            (label, _str(json[field]).trim()),
      ],
    );
  }

  final String kind, opening, status;

  /// "31/03/2026 09:45", as UYAP writes it.
  final String? hearing, inspection, preliminary;

  /// Cases tied to this one, each with what ties it: a merged case and a
  /// related one are not the same thing in law.
  final List<(String, String)> related;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'opening': opening,
    'status': status,
    'hearing': hearing,
    'inspection': inspection,
    'preliminary': preliminary,
    'related': [
      for (final (label, value) in related) [label, value],
    ],
  };

  factory UyapCaseDetails.stored(Map<String, Object?> json) => UyapCaseDetails(
    kind: _str(json['kind']),
    opening: _str(json['opening']),
    status: _str(json['status']),
    hearing: json['hearing'] as String?,
    inspection: json['inspection'] as String?,
    preliminary: json['preliminary'] as String?,
    related: [
      for (final r in (json['related'] as List? ?? const []))
        if (r is List && r.length == 2) (_str(r[0]), _str(r[1])),
    ],
  );
}

/// One document in a case: what it is, who sent it, and the ids to fetch
/// it by in this session.
class UyapCaseDocument {
  const UyapCaseDocument({
    required this.key,
    required this.documentId,
    required this.caseId,
    required this.type,
    required this.number,
    required this.approved,
    required this.sender,
    required this.description,
    this.source = '',
    this.sentToSystem = '',
    this.parentKey,
    this.attachments = const [],
  });

  /// What it is known by from one session to the next. The ids UYAP fetches
  /// it by are the session's and change with every login; the number its
  /// unit gave it does not.
  final String key;

  /// This session's ids; empty in a list kept from an earlier one.
  final String documentId, caseId;

  final String type, number, approved, sender, description;

  /// The case it came from, which need not be the one opened: the list
  /// brings the documents of merged cases, of the case's earlier number
  /// before an appeal, of instructions and of the prosecution file too.
  final String source;

  final String sentToSystem;

  /// The document this one is attached to.
  final String? parentKey;

  final List<UyapCaseDocument> attachments;

  /// What the list shows it as.
  String get title => description.isEmpty || description == type
      ? type
      : type.isEmpty
      ? description
      : '$type — $description';

  /// Its date, as a sortable value: UYAP writes "31/03/2026 09:45" or
  /// "2026-03-31 09:45:00.0".
  DateTime? get date =>
      parseUyapDate(approved.isNotEmpty ? approved : sentToSystem);

  UyapCaseDocument withKey(String key, {String? parentKey}) => UyapCaseDocument(
    key: key,
    documentId: documentId,
    caseId: caseId,
    type: type,
    number: number,
    approved: approved,
    sender: sender,
    description: description,
    source: source,
    sentToSystem: sentToSystem,
    parentKey: parentKey ?? this.parentKey,
    attachments: attachments,
  );

  /// Kept from one session to the next: everything but the session's ids.
  Map<String, Object?> toJson() => {
    'key': key,
    'type': type,
    'number': number,
    'approved': approved,
    'sender': sender,
    'description': description,
    'source': source,
    'sentToSystem': sentToSystem,
    'parentKey': parentKey,
    'attachments': [for (final a in attachments) a.toJson()],
  };

  factory UyapCaseDocument.stored(Map<String, Object?> json) =>
      UyapCaseDocument(
        key: _str(json['key']),
        documentId: '',
        caseId: '',
        type: _str(json['type']),
        number: _str(json['number']),
        approved: _str(json['approved']),
        sender: _str(json['sender']),
        description: _str(json['description']),
        source: _str(json['source']),
        sentToSystem: _str(json['sentToSystem']),
        parentKey: json['parentKey'] as String?,
        attachments: [
          for (final a in (json['attachments'] as List? ?? const []))
            if (a is Map) UyapCaseDocument.stored(a.cast<String, Object?>()),
        ],
      );

  /// Reads one entry of `list_dosya_evraklar`; [group] is the key it came
  /// under, `2014/88(Hukuk Dava Dosyası)##` and the session's id.
  factory UyapCaseDocument.fromJson(
    Map<String, Object?> json, {
    String group = '',
  }) {
    final caseId = _id(json['dosyaId']);
    final sep = group.indexOf('##');
    final source = (sep < 0 ? group : group.substring(0, sep)).trim();
    final raw = json['ekEvrakListesi'] ?? json['ekEvraklar'];
    final attachments = <UyapCaseDocument>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final a = e.cast<String, Object?>();
        final order = int.tryParse(_str(a['sira']));
        attachments.add(
          UyapCaseDocument(
            // Keyed once its parent's key is known.
            key: '${order == null || order < 0 ? 1 : order + 1}',
            documentId: _id(
              _first([
                a['evrakId'],
                a['id'],
                a['dosyaEvrakId'],
                a['evrakBilgiId'],
              ]),
            ),
            caseId: caseId,
            type: _first([
              a['ekTuru'],
              a['evrakTuruAciklama'],
              a['evrakTuru'],
              a['tur'],
            ]),
            number: '',
            approved: '',
            sender: '',
            description: _str(a['aciklama']),
            source: source,
          ),
        );
      }
    }
    return UyapCaseDocument(
      key: '',
      documentId: _id(
        _first([
          json['evrakId'],
          json['id'],
          json['dosyaEvrakId'],
          json['evrakBilgiId'],
        ]),
      ),
      caseId: caseId,
      type: _first([
        json['evrakTuruAciklama'],
        json['dagitimPlanTuruAciklama'],
        json['evrakTuru'],
        json['tur'],
      ]),
      number: _str(json['birimEvrakNo']).trim(),
      approved: _first([json['onayTarihi'], json['onaylandigiTarih']]),
      sender: _first([json['gonderenYerKisi'], json['gonderen_yer_kisi']]),
      description: _first([json['aciklama'], json['evrakAciklamasi']]),
      source: source,
      sentToSystem: _first([
        json['sistemeGonderildigiTarih'],
        json['sisteme_gonderildigi_tarih'],
      ]),
      attachments: attachments,
    );
  }
}

/// One page of `list_dosya_evraklar`.
class UyapDocumentPage {
  const UyapDocumentPage({
    required this.grouped,
    required this.latest,
    required this.pages,
    this.message = '',
  });

  /// Every document, each with the case it came from.
  final List<UyapCaseDocument> grouped;

  /// The last twenty, without the case they came from.
  final List<UyapCaseDocument> latest;
  final int pages;

  /// Said only when the documents are withheld: an empty list with a
  /// message is "not shown", not "none".
  final String message;

  factory UyapDocumentPage.fromJson(Object? raw) {
    final json = _one(raw);
    final count = int.tryParse(_str(json['pageTotal'] ?? 0));
    if (count == null || count < 0 || count > 1000) {
      throw const FormatException('UYAP evrak sayfa sayısı geçersiz.');
    }
    final groups = json['tumEvraklar'];
    if (groups != null && groups is! Map) {
      throw const FormatException('UYAP evrak grupları geçersiz.');
    }
    final grouped = <UyapCaseDocument>[];
    if (groups is Map) {
      for (final entry in groups.entries) {
        final list = entry.value;
        if (list is! List || list.any((e) => e is! Map)) {
          throw const FormatException('UYAP evrak sayfası eksik geldi.');
        }
        for (final e in list) {
          grouped.add(
            UyapCaseDocument.fromJson(
              (e as Map).cast<String, Object?>(),
              group: '${entry.key}',
            ),
          );
        }
      }
    }
    final rawLatest = json['son20Evrak'];
    final latest = [
      for (final e
          in rawLatest is List
              ? rawLatest
              : rawLatest is Map
              ? rawLatest.values
              : const [])
        if (e is Map) UyapCaseDocument.fromJson(e.cast<String, Object?>()),
    ];
    return UyapDocumentPage(
      grouped: grouped,
      latest: latest,
      pages: count,
      message: _str(json['message']).trim(),
    );
  }
}

/// The documents of every page, each once, each with the key it keeps
/// from one session to the next.
///
/// The number its unit gave a document is its key. Merged cases can bring
/// two documents with one number, so a number seen in two source cases is
/// told apart by the case; and a document without a number is known by
/// what it is. The last twenty are dropped where the full list has them.
List<UyapCaseDocument> keyDocuments(List<UyapDocumentPage> pages) {
  final all = [for (final page in pages) ...page.grouped];
  final numbered = {
    for (final d in all)
      if (_hasNumber(d)) d.number,
  };
  for (final d
      in pages.isEmpty ? const <UyapCaseDocument>[] : pages.first.latest) {
    if (!_hasNumber(d) || !numbered.contains(d.number)) all.add(d);
  }
  final sources = <String, Set<String>>{};
  for (final d in all) {
    if (_hasNumber(d)) (sources[d.number] ??= {}).add(d.source);
  }
  final used = <String>{};
  final out = <UyapCaseDocument>[];
  for (final d in all) {
    var key = !_hasNumber(d)
        ? '~${_digest(d)}'
        : (sources[d.number]!.length > 1
              ? '${d.number}@${_slug(d.source)}'
              : d.number);
    if (!used.add(key)) {
      key = '$key~${_digest(d)}';
      if (!used.add(key)) continue; // The same document twice.
    }
    final attachmentKeys = <String>{};
    out.add(
      UyapCaseDocument(
        key: key,
        documentId: d.documentId,
        caseId: d.caseId,
        type: d.type,
        number: d.number,
        approved: d.approved,
        sender: d.sender,
        description: d.description,
        source: d.source,
        sentToSystem: d.sentToSystem,
        attachments: [
          for (final a in d.attachments)
            () {
              var k = '$key:ek:${a.key}';
              if (!attachmentKeys.add(k)) {
                k = '$k~${_digest(a)}';
                attachmentKeys.add(k);
              }
              return a.withKey(k, parentKey: key);
            }(),
        ],
      ),
    );
  }
  return out;
}

bool _hasNumber(UyapCaseDocument d) => d.number.isNotEmpty && d.number != '0';

String _digest(UyapCaseDocument d) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          d.type,
          d.approved,
          d.sentToSystem,
          d.description,
          d.sender,
        ]),
      ),
    )
    .toString()
    .substring(0, 12);

String _slug(String source) =>
    source.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ıüöçşğ]+'), '-');

/// "31/03/2026 09:45", "31.03.2026", "2026-03-31 09:45:00.0".
DateTime? parseUyapDate(String value) {
  final s = value.trim();
  final dmy = RegExp(
    r'^(\d{1,2})[./](\d{1,2})[./](\d{4})(?:\s+(\d{1,2}):(\d{2}))?',
  ).firstMatch(s);
  if (dmy != null) {
    return DateTime(
      int.parse(dmy[3]!),
      int.parse(dmy[2]!),
      int.parse(dmy[1]!),
      int.parse(dmy[4] ?? '0'),
      int.parse(dmy[5] ?? '0'),
    );
  }
  final ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?')
      .firstMatch(s);
  if (ymd != null) {
    return DateTime(
      int.parse(ymd[1]!),
      int.parse(ymd[2]!),
      int.parse(ymd[3]!),
      int.parse(ymd[4] ?? '0'),
      int.parse(ymd[5] ?? '0'),
    );
  }
  return null;
}
