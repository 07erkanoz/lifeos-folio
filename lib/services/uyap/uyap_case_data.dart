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

/// A sum as UYAP gives it, a number or the text of one.
double? _amount(Object? v) {
  if (v is num) return v.toDouble();
  final s = _str(v).trim();
  return s.isEmpty ? null : double.tryParse(s.replaceAll(',', '.'));
}

/// A date as the case list gives it: a map of `date` and `time`, or text.
String? _day(Object? v) {
  if (v is Map) {
    final date = v['date'];
    if (date is Map) {
      String two(Object? n) => '${n ?? ''}'.padLeft(2, '0');
      return '${two(date['day'])}.${two(date['month'])}.${date['year']}';
    }
    return null;
  }
  final s = _str(v).trim();
  return s.isEmpty ? null : s;
}

/// "12.345,67 TL": a sum written as a Turkish reader reads it.
String formatTl(double amount) {
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final whole = fixed.substring(0, fixed.length - 3);
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write('.');
    grouped.write(whole[i]);
  }
  return '${negative ? '-' : ''}$grouped,${fixed.substring(fixed.length - 2)} TL';
}

/// The case's particulars: what kind of case, where it stands, and the days
/// set for it. Shown, not followed: the calendar is banaozel's.
///
/// The portal answers in two shapes. A court case's particulars name the
/// kind of case and its days; an enforcement file's name the kind of
/// proceedings and the sums owed instead. Both are read, whichever came.
class UyapCaseDetails {
  const UyapCaseDetails({
    this.kind = '',
    this.opening = '',
    this.status = '',
    this.hearing,
    this.inspection,
    this.preliminary,
    this.related = const [],
    this.decision = const [],
    this.enforcement = const [],
    this.fileType = '',
    this.state = '',
    this.openedOn,
    this.closedOn,
  });

  factory UyapCaseDetails.fromJson(Object? raw) {
    final json = _one(raw);
    String? date(Object? v) {
      final s = _str(v).trim();
      return s.isEmpty ? null : s;
    }

    String text(String key) => _str(json[key]).trim();
    String? sum(String key) {
      final v = _amount(json[key]);
      return v == null ? null : formatTl(v);
    }

    return UyapCaseDetails(
      kind: text('davaTurleriStr'),
      opening: text('davaAcilisTuruStr'),
      status: text('dosyaDurumu'),
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
          if (text(field).isNotEmpty) (label, text(field)),
      ],
      // Only a case decided has these: the court's own decision, and when
      // the case is on appeal, the decision appealed.
      decision: [
        if (text('kararNo').isNotEmpty || text('kararTarihi').isNotEmpty)
          (
            'Karar',
            [
              text('kararNo'),
              text('kararTarihi'),
            ].where((v) => v.isNotEmpty).join(' · '),
          ),
        if (text('mahkemeKararNo').isNotEmpty ||
            text('mahkemeKararTarihi').isNotEmpty)
          (
            'Yerel mahkeme kararı',
            [
              text('mahkemeKararNo'),
              text('mahkemeKararTarihi'),
            ].where((v) => v.isNotEmpty).join(' · '),
          ),
      ],
      enforcement: [
        for (final (field, label) in const [
          ('takibinTuruAciklama', 'Takip türü'),
          ('takibinSekliAciklama', 'Takip şekli'),
          ('takibinYoluAciklama', 'Takip yolu'),
        ])
          if (text(field).isNotEmpty) (label, text(field)),
        for (final (field, label) in const [
          ('alacakKalemToplamTutar', 'Alacak toplamı'),
          ('alacakKalemFaizTutar', 'Faiz'),
          ('takipSonrasiMasraf', 'Takip sonrası masraf'),
          ('vekaletUcreti', 'Vekâlet ücreti'),
          ('tahsilHarci', 'Tahsil harcı'),
          ('yapilmisBorcTahsilati', 'Yapılmış tahsilat'),
        ])
          if (sum(field) != null) (label, sum(field)!),
      ],
    );
  }

  final String kind, opening, status;

  /// "31/03/2026 09:45", as UYAP writes it.
  final String? hearing, inspection, preliminary;

  /// Cases tied to this one, each with what ties it: a merged case and a
  /// related one are not the same thing in law.
  final List<(String, String)> related;

  /// The decision, once there is one, and the one appealed.
  final List<(String, String)> decision;

  /// An enforcement file's proceedings and sums, each with its name.
  final List<(String, String)> enforcement;

  /// From the list the case was found in: "Hukuk Dava Dosyası", "İcra
  /// Dosyası"; where it stands, in full ("Açık (Durdurulmuş : Takibe
  /// İtiraz)", "İstinafta"); and when it was opened and closed.
  final String fileType, state;
  final String? openedOn, closedOn;

  /// These particulars, with what the case list says of [row].
  UyapCaseDetails withListing(UyapCaseListing? row) => row == null
      ? this
      : UyapCaseDetails(
          kind: kind,
          opening: opening,
          status: status,
          hearing: hearing,
          inspection: inspection,
          preliminary: preliminary,
          related: related,
          decision: decision,
          enforcement: enforcement,
          fileType: row.type.isEmpty ? fileType : row.type,
          state: row.state.isEmpty ? state : row.state,
          openedOn: row.openedOn ?? openedOn,
          closedOn: row.closedOn ?? closedOn,
        );

  static List<List<String>> _pairs(List<(String, String)> list) => [
    for (final (label, value) in list) [label, value],
  ];

  static List<(String, String)> _unpairs(Object? json) => [
    for (final r in (json as List? ?? const []))
      if (r is List && r.length == 2) (_str(r[0]), _str(r[1])),
  ];

  Map<String, Object?> toJson() => {
    'kind': kind,
    'opening': opening,
    'status': status,
    'hearing': hearing,
    'inspection': inspection,
    'preliminary': preliminary,
    'related': _pairs(related),
    'decision': _pairs(decision),
    'enforcement': _pairs(enforcement),
    'fileType': fileType,
    'state': state,
    'openedOn': openedOn,
    'closedOn': closedOn,
  };

  factory UyapCaseDetails.stored(Map<String, Object?> json) => UyapCaseDetails(
    kind: _str(json['kind']),
    opening: _str(json['opening']),
    status: _str(json['status']),
    hearing: json['hearing'] as String?,
    inspection: json['inspection'] as String?,
    preliminary: json['preliminary'] as String?,
    related: _unpairs(json['related']),
    decision: _unpairs(json['decision']),
    enforcement: _unpairs(json['enforcement']),
    fileType: _str(json['fileType']),
    state: _str(json['state']),
    openedOn: json['openedOn'] as String?,
    closedOn: json['closedOn'] as String?,
  );
}

/// What the case list says of a case beside its number: its kind, where it
/// stands in full, and its dates. Comes with the search; no request of its
/// own.
class UyapCaseListing {
  const UyapCaseListing({
    this.type = '',
    this.typeCode,
    this.state = '',
    this.openedOn,
    this.closedOn,
  });

  factory UyapCaseListing.fromJson(Map<Object?, Object?> row) =>
      UyapCaseListing(
        type: _str(row['dosyaTur']).trim(),
        typeCode: int.tryParse(_str(row['dosyaTurKod']).split('#').first),
        state: _str(row['dosyaDurum']).trim(),
        openedOn: _day(row['dosyaAcilisTarihi']),
        closedOn: _day(row['dosyaKapanisTarihi']),
      );

  final String type, state;

  /// 15 a court case, 35 an enforcement file, 3 a criminal case, 1 a
  /// letter rogatory: what the money of a case is asked with.
  final int? typeCode;
  final String? openedOn, closedOn;
}

/// What UYAP lets be seen of a case, and its kind, asked before the rest:
/// a criminal case has no particulars to ask for, and asking only earns an
/// error.
class UyapCasePermissions {
  const UyapCasePermissions(this.typeCode, this.allowed);

  /// `{"15": "ayrinti_bilgileri,taraf_bilgileri,…"}`.
  factory UyapCasePermissions.fromJson(Object? raw) {
    final json = _one(raw);
    if (json.isEmpty) return const UyapCasePermissions(null, null);
    final entry = json.entries.first;
    return UyapCasePermissions(int.tryParse(entry.key.split('#').first), {
      for (final p in _str(entry.value).split(','))
        if (p.trim().isNotEmpty) p.trim(),
    });
  }

  final int? typeCode;

  /// Null when UYAP did not say: then everything is asked for, as before.
  final Set<String>? allowed;

  bool allows(String what) => allowed == null || allowed!.contains(what);
}

/// One line of a case's money: a fee paid, a sum collected or paid out.
class UyapMoneyItem {
  const UyapMoneyItem({
    required this.kind,
    required this.date,
    required this.amount,
    this.receipt = '',
    this.payer = '',
  });

  factory UyapMoneyItem.fromJson(Map<Object?, Object?> json) => UyapMoneyItem(
    kind: _first([
      json['tahsilatTuru'],
      json['reddiyatNedeni'],
      json['harcTuru'],
    ]).trim(),
    date: _first([json['tahsilatTarihi'], json['reddiyatTarihi']]).trim(),
    amount: _amount(json['yatirilanMiktar'] ?? json['miktar']) ?? 0,
    receipt: _str(json['makbuzNo']).trim(),
    payer: _str(json['odeyenKisi']).trim(),
  );

  final String kind, date, receipt, payer;
  final double amount;

  Map<String, Object?> toJson() => {
    'tur': kind,
    'tarih': date,
    'tutar': amount,
    'makbuz': receipt,
    'odeyen': payer,
  };

  factory UyapMoneyItem.stored(Map<Object?, Object?> json) => UyapMoneyItem(
    kind: _str(json['tur']),
    date: _str(json['tarih']),
    amount: _amount(json['tutar']) ?? 0,
    receipt: _str(json['makbuz']),
    payer: _str(json['odeyen']),
  );
}

/// The fees, collections and payments out of a case, as its money page in
/// the portal shows them: shown, not reckoned with.
class UyapCaseMoney {
  const UyapCaseMoney({
    this.collected,
    this.paidOut,
    this.deposit,
    this.remaining,
    this.fees = const [],
    this.collections = const [],
    this.payments = const [],
  });

  factory UyapCaseMoney.fromJson(Object? raw) {
    final json = _one(raw);
    List<UyapMoneyItem> items(String key) => [
      for (final item in (json[key] as List? ?? const []))
        if (item is Map) UyapMoneyItem.fromJson(item),
    ];
    return UyapCaseMoney(
      collected: _amount(json['toplamTahsilat']),
      // Lower-case r, as it comes over the wire.
      paidOut: _amount(json['toplamreddiyat'] ?? json['toplamReddiyat']),
      deposit: _amount(json['toplamTeminat']),
      remaining: _amount(json['toplamKalan']),
      fees: items('harcList'),
      collections: items('tahsilatList'),
      payments: items('reddiyatList'),
    );
  }

  final double? collected, paidOut, deposit, remaining;
  final List<UyapMoneyItem> fees, collections, payments;

  bool get isEmpty =>
      fees.isEmpty &&
      collections.isEmpty &&
      payments.isEmpty &&
      [
        collected,
        paidOut,
        deposit,
        remaining,
      ].every((v) => v == null || v == 0);

  Map<String, Object?> toJson() => {
    'tahsilat': collected,
    'reddiyat': paidOut,
    'teminat': deposit,
    'kalan': remaining,
    'harclar': [for (final i in fees) i.toJson()],
    'tahsilatlar': [for (final i in collections) i.toJson()],
    'reddiyatlar': [for (final i in payments) i.toJson()],
  };

  factory UyapCaseMoney.stored(Map<Object?, Object?> json) {
    List<UyapMoneyItem> items(String key) => [
      for (final item in (json[key] as List? ?? const []))
        if (item is Map) UyapMoneyItem.stored(item),
    ];
    return UyapCaseMoney(
      collected: _amount(json['tahsilat']),
      paidOut: _amount(json['reddiyat']),
      deposit: _amount(json['teminat']),
      remaining: _amount(json['kalan']),
      fees: items('harclar'),
      collections: items('tahsilatlar'),
      payments: items('reddiyatlar'),
    );
  }
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
