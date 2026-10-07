import '../editor/suggestions/phrases.dart';
import 'observed.dart';

/// Where a UYAP notification came from. The two keep their own rows: one
/// channel's reading never writes over the other's.
enum UyapNoticeSource { mobile, web }

/// One notification as one channel gave it (UYAP Mobil's
/// `bildirim/bildirimlerim`, the portal's `get_kullanici_tum_bildirimleri`).
class UyapNoticeRow {
  final UyapNoticeSource source;

  /// The channel's own id: UYAP Mobil's is an opaque string
  /// ("0NpvSKnSEjWwHEHny+xBHg=="), the portal's a number.
  final String id;

  /// UYAP Mobil's message id, which its body is asked for by and its list
  /// is paged by; the portal's, kept as it came.
  final String messageId;
  final String title;

  /// Empty in UYAP Mobil's list: its body is asked for one by one.
  final String body;

  /// Turkish time, as UYAP writes it; UYAP Mobil's to the minute.
  final DateTime? sentAt;

  /// Whether UYAP counts it read; null when it did not say.
  final bool? remoteRead;

  /// The lawyer's own word in Folio: read, unread, or null to follow UYAP.
  final bool? localRead;

  const UyapNoticeRow({
    required this.source,
    required this.id,
    this.messageId = '',
    required this.title,
    this.body = '',
    this.sentAt,
    this.remoteRead,
    this.localRead,
  });

  /// A row of UYAP Mobil's list; null when it has no id.
  static UyapNoticeRow? fromMobile(Map<String, Object?> row) {
    final id = _text(row['bildirimId']);
    if (id.isEmpty) return null;
    return UyapNoticeRow(
      source: UyapNoticeSource.mobile,
      id: id,
      messageId: _text(row['mesajId']),
      title: _text(row['baslik']),
      body: _plain(_text(row['mesaj'])),
      sentAt: parseUyapNoticeTime(
        _text(row['gonderilmeTarihi']).isNotEmpty
            ? _text(row['gonderilmeTarihi'])
            : _text(row['tarihSaat']),
      ),
      remoteRead: _flag(row['okundumu'] ?? row['okunduMu']),
    );
  }

  /// A row of the portal's list, which has its body; null when it has no
  /// id.
  static UyapNoticeRow? fromWeb(Map<String, Object?> row) {
    final id = _text(row['bildirimId']);
    if (id.isEmpty || id == '0') return null;
    return UyapNoticeRow(
      source: UyapNoticeSource.web,
      id: id,
      messageId: _text(row['mesajId']),
      title: _text(row['baslik']),
      body: _plain(_text(row['mesaj'])),
      sentAt: parseUyapNoticeTime(_text(row['gonderilmeTarihi'])),
      remoteRead: _flag(row['okunduMu'] ?? row['okundumu']),
    );
  }

  static String _text(Object? v) {
    final s = v == null ? '' : '$v'.trim();
    return s == 'null' ? '' : s;
  }

  static bool? _flag(Object? v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = '$v'.trim().toUpperCase();
    if (s.isEmpty || s == 'NULL') return null;
    return s == 'E' || s == 'TRUE' || s == '1' || s == 'EVET';
  }

  static String _plain(String s) => s
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// UYAP's times: UYAP Mobil's "14/05/2026 13:39", the portal's "Mar 3,
/// 2026 1:05:47 PM", and the dotted "14.05.2026 13:39:05" now and then.
/// Turkish time, taken as the computer's own (as hearings are).
DateTime? parseUyapNoticeTime(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final dmy = RegExp(
    r'^(\d{1,2})[./](\d{1,2})[./](\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
  ).firstMatch(s);
  if (dmy != null) {
    int g(int i) => int.tryParse(dmy.group(i) ?? '') ?? 0;
    return DateTime(g(3), g(2), g(1), g(4), g(5), g(6));
  }
  const months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  final en = RegExp(
    r'^([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),\s*(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?',
  ).firstMatch(s);
  if (en != null) {
    final month = months[en.group(1)!.toLowerCase()];
    if (month == null) return null;
    var hour = int.parse(en.group(4)!);
    final half = en.group(7)?.toUpperCase();
    if (half == 'PM' && hour < 12) hour += 12;
    if (half == 'AM' && hour == 12) hour = 0;
    return DateTime(
      int.parse(en.group(3)!),
      month,
      int.parse(en.group(2)!),
      hour,
      int.parse(en.group(5)!),
      int.tryParse(en.group(6) ?? '') ?? 0,
    );
  }
  final iso = DateTime.tryParse(s);
  return iso?.isUtc == true ? iso!.toLocal() : iso;
}

/// The case a notification's body names: its number, and the unit before
/// it. UYAP writes it three ways (measured in Banaozel on live
/// notifications): `UNIT Biriminde Bulunan NO …`, `UNIT nin NO Hukuk Dava
/// Dosyası nda …`, `UNIT birimi, NO dosyasında …`. Null when it names none
/// for certain: no case is guessed.
({String number, String court})? uyapNoticeCase(String body) {
  final m = RegExp(r'(?<!\d)(\d{4}\s*/\s*\d+)(?!\d)').firstMatch(body);
  if (m == null) return null;
  final number = m.group(1)!.replaceAll(' ', '');
  var before = body.substring(0, m.start).trim();
  final tie = RegExp(
    r"\s*(?:biriminde\s+bulunan|['’`´]?\s*n[ıi]n|birimi\s*,?|['’`´]?\s*nde|['’`´]?\s*nda)\s*$",
    caseSensitive: false,
    unicode: true,
  );
  for (var i = 0; i < 3; i++) {
    final next = before
        .replaceFirst(tie, '')
        .replaceAll(RegExp(r'^[\s,.]+|[\s,.]+$'), '');
    if (next == before) break;
    before = next;
  }
  // A sentence before the unit is not the unit: the unit is what follows
  // the last full stop after a word ("… eklendi. Antalya 3. Asliye …"),
  // not the one after a number in its name.
  final stops = RegExp(
    r'(?<=\p{L}{2})[.:;]\s',
    unicode: true,
  ).allMatches(before).toList();
  if (stops.isNotEmpty) before = before.substring(stops.last.end).trim();
  if (before.length < 6) return null;
  return (number: number, court: before);
}

/// What a notification is about, read from UYAP's title, for the list's
/// filter and the choice of which kinds pop up on the desktop.
enum UyapNoticeKind {
  decision('Karar'),
  money('Tahsilat ve reddiyat'),
  report('Bilirkişi ve rapor'),
  appeal('Kanun yolu'),
  finality('Kesinleşme'),
  writ('Müzekkere ve tebligat'),
  hearing('Duruşma'),
  party('Taraf ve vekil'),
  other('Diğer');

  const UyapNoticeKind(this.label);
  final String label;

  static UyapNoticeKind of(String title) {
    final t = foldPhrase(title);
    bool any(List<String> words) => words.any(t.contains);
    if (any(['istinaf', 'temyiz', 'kanun yolu', 'itiraz'])) return appeal;
    if (any(['kesinles'])) return finality;
    if (any(['karar', 'hukum', 'ilam'])) return decision;
    if (any(['tahsil', 'reddiyat', 'odeme', 'harc', 'masraf', 'avans'])) {
      return money;
    }
    if (any(['bilirkisi', 'rapor', 'kesif'])) return report;
    if (any(['muzekkere', 'teblig', 'davetiye', 'yazi'])) return writ;
    if (any(['durusma', 'celse', 'erteleme'])) return hearing;
    if (any(['vekil', 'taraf', 'katilan', 'mudahil'])) return party;
    return other;
  }
}

/// One notification as the lawyer sees it: a row of one channel, or the
/// same notification from both, shown once.
class UyapNotice {
  final List<UyapNoticeRow> rows;

  /// The case it is tied to in the portfolio; null when its body names
  /// none, or one the portfolio does not have.
  final String? caseKey;

  /// The case its body names, as written, kept or not.
  final ({String number, String court})? named;

  const UyapNotice(this.rows, {this.caseKey, this.named});

  UyapNoticeRow get _first => rows.first;

  /// The same while its rows stay; a twin arriving later makes a new one.
  String get key => rows.map((r) => '${r.source.name}:${r.id}').join('+');
  String get title => _first.title;

  /// The portal's body when there is one: UYAP Mobil's comes later.
  String get body {
    for (final r in rows) {
      if (r.body.isNotEmpty) return r.body;
    }
    return '';
  }

  /// The portal's time when there is one: it has the seconds.
  DateTime? get sentAt {
    for (final r in rows) {
      if (r.source == UyapNoticeSource.web && r.sentAt != null) {
        return r.sentAt;
      }
    }
    return _first.sentAt;
  }

  Set<UyapNoticeSource> get sources => {for (final r in rows) r.source};

  /// The same for both channels' rows of one notification: its title and
  /// minute, which the desktop is told of once by.
  String get signature {
    final t = sentAt;
    return '${foldPhrase(title)}|'
        '${t == null ? '' : '${t.year}-${t.month}-${t.day} ${t.hour}:${t.minute}'}';
  }

  UyapNoticeKind get kind => UyapNoticeKind.of(title);

  /// The lawyer's word in Folio first, then UYAP's: read on UYAP is read
  /// here too.
  bool get read {
    for (final r in rows) {
      if (r.localRead != null) return r.localRead!;
    }
    return rows.any((r) => r.remoteRead == true);
  }
}

/// [rows] of both channels as the lawyer sees them, newest first: a UYAP
/// Mobil row and a portal row with the same title in the same minute are
/// one notification when their bodies agree, or when they are the only
/// two left there and one has no body yet. Each case named is looked up
/// in [caseKeys] (a portfolio's keys, [caseKey]'s).
List<UyapNotice> mergeUyapNotices(
  Iterable<UyapNoticeRow> rows, {
  Set<String> caseKeys = const {},
}) {
  String minute(DateTime? t) =>
      t == null ? '' : '${t.year}-${t.month}-${t.day} ${t.hour}:${t.minute}';
  final groups = <String, List<UyapNoticeRow>>{};
  for (final r in rows) {
    (groups['${foldPhrase(r.title)}|${minute(r.sentAt)}'] ??= []).add(r);
  }
  final out = <UyapNotice>[];
  for (final group in groups.values) {
    final mobile = [
      for (final r in group)
        if (r.source == UyapNoticeSource.mobile) r,
    ];
    final web = [
      for (final r in group)
        if (r.source == UyapNoticeSource.web) r,
    ];
    final made = <List<UyapNoticeRow>>[];
    String plain(String s) => foldPhrase(s).replaceAll(RegExp(r'\s+'), ' ');
    for (final m in [...mobile]) {
      if (m.body.isEmpty) continue;
      final twin = web.where((w) => plain(w.body) == plain(m.body)).firstOrNull;
      if (twin == null) continue;
      made.add([m, twin]);
      mobile.remove(m);
      web.remove(twin);
    }
    if (mobile.length == 1 &&
        web.length == 1 &&
        (mobile.single.body.isEmpty || web.single.body.isEmpty)) {
      made.add([mobile.single, web.single]);
      mobile.clear();
      web.clear();
    }
    made.addAll([
      for (final r in [...mobile, ...web]) [r],
    ]);
    for (final pair in made) {
      final notice = UyapNotice(pair);
      final named = uyapNoticeCase(notice.body);
      out.add(
        UyapNotice(
          pair,
          named: named,
          caseKey: named == null ? null : _caseIn(named, caseKeys),
        ),
      );
    }
  }
  out.sort((a, b) {
    final x = a.sentAt, y = b.sentAt;
    if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
    return y.compareTo(x);
  });
  return out;
}

/// [named]'s key among [keys]: the same number and unit; else the one
/// case of that number whose unit's name holds the named one or is held
/// by it ("Antalya 6. İcra Dairesi" and "Antalya 6. İcra"). Two such, or
/// none, and the notice is tied to no case.
String? _caseIn(({String number, String court}) named, Set<String> keys) {
  final key = caseKey(named.number, named.court);
  if (keys.contains(key)) return key;
  final number = key.split('|').first;
  final court = key.substring(number.length + 1);
  final near = [
    for (final k in keys)
      if (k.startsWith('$number|') &&
          (k.substring(number.length + 1).contains(court) ||
              court.contains(k.substring(number.length + 1))))
        k,
  ];
  return near.length == 1 ? near.single : null;
}
