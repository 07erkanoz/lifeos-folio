import 'package:flutter/material.dart';

import '../../services/portal/observed.dart';
import '../../services/portal/portal_case.dart';
import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_hearing.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../../services/uyap/uyap_web_service.dart';

/// The kinds of file the portfolio is coloured by.
enum CaseKind {
  hukuk('Hukuk', Color(0xFF2B5EA8), Color(0xFFEAF0F9)),
  ceza('Ceza', Color(0xFFB2453E), Color(0xFFFBF0EF)),
  icra('İcra', Color(0xFF97600D), Color(0xFFFDF4E6)),
  idari('İdari', Color(0xFF5B4BB7), Color(0xFFF1EEFB)),
  diger('Diğer', Color(0xFF6B7383), Color(0xFFF1F3F7));

  const CaseKind(this.label, this.ink, this.fill);
  final String label;
  final Color ink, fill;

  static CaseKind of(PortalCase kase) {
    if (kase.family == CaseFamily.danistay) return CaseKind.idari;
    final code = '${kase.details?.value['yargiTuru'] ?? ''}';
    switch (code) {
      case '0':
        return CaseKind.ceza;
      case '1':
        return CaseKind.hukuk;
      case '2':
        return CaseKind.icra;
      case '6':
        return CaseKind.idari;
    }
    final court = UyapWebService.fold(kase.court);
    if (court.contains('icra dairesi')) return CaseKind.icra;
    if (court.contains('ceza') || court.contains('bassavcilig')) {
      return CaseKind.ceza;
    }
    if (court.contains('idare') || court.contains('vergi')) {
      return CaseKind.idari;
    }
    if (court.contains('mahkeme') || court.contains('daire')) {
      return CaseKind.hukuk;
    }
    return CaseKind.diger;
  }
}

/// A case's state, in three tones: open green, closed grey, the rest
/// (decided, on appeal, enforcement under way) amber.
enum StatusTone { open, closed, other }

StatusTone toneOf(String status) {
  final s = status.trim().toLowerCase();
  if (s.isEmpty || s.startsWith('açık') || s.startsWith('acik')) {
    return StatusTone.open;
  }
  if (isClosedStatus(status)) return StatusTone.closed;
  return StatusTone.other;
}

/// "Açık (12.03.2024)" → "Açık".
String shortStatus(String status) =>
    status.replaceFirst(RegExp(r'\s*\(.*\)\s*$'), '').trim();

/// "12.03.2024", "2024-03-12T…": the day, or null.
DateTime? parseDay(Object? raw) {
  final s = '${raw ?? ''}'.trim();
  final tr = RegExp(r'(\d{1,2})[./](\d{1,2})[./](\d{4})').firstMatch(s);
  if (tr != null) {
    return DateTime(
      int.parse(tr.group(3)!),
      int.parse(tr.group(2)!),
      int.parse(tr.group(1)!),
    );
  }
  return DateTime.tryParse(s);
}

String _two(int v) => v.toString().padLeft(2, '0');
String dayText(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';
String clockText(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// "08:47", "dün 21:14", "05.10.2026".
String whenText(DateTime at, DateTime now) {
  final local = at.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) return clockText(local);
  if (day == today.subtract(const Duration(days: 1))) {
    return 'dün ${clockText(local)}';
  }
  return dayText(local);
}

/// ALL CAPS names as a reader writes them: "AYŞE KARACA" → "Ayşe Karaca".
String titleName(String name) {
  if (name != name.toUpperCase()) return name;
  return name
      .split(RegExp(r'\s+'))
      .map((w) {
        if (w.isEmpty) return w;
        if (const {'A.Ş.', 'LTD.', 'ŞTİ.', 'A.Ş', 'LTD', 'ŞTİ'}.contains(w)) {
          return w == 'LTD' || w == 'LTD.'
              ? 'Ltd.'
              : w == 'ŞTİ' || w == 'ŞTİ.'
              ? 'Şti.'
              : 'A.Ş.';
        }
        final lower = w.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
        final first = lower.substring(0, 1);
        return (first == 'i' ? 'İ' : first.toUpperCase()) + lower.substring(1);
      })
      .join(' ');
}

/// One case of the portfolio as the list shows it: what the portals said
/// of it, what Folio kept of it, and what is new in it.
class PortfolioRow {
  PortfolioRow({
    required this.kase,
    required this.state,
    this.record,
    this.hearing,
    required this.ours,
    required this.others,
  });

  final PortalCase kase;
  final CaseState state;
  final UyapCaseRecord? record;
  final PortalHearing? hearing;

  /// The parties the lawyer acts for, and the rest.
  final List<UyapParty> ours, others;

  String get key => kase.key;
  CaseKind get kind => CaseKind.of(kase);

  String get status {
    final s = kase.status?.value ?? '';
    if (s.trim().isNotEmpty) return s;
    return record?.details.status ?? '';
  }

  bool get closed => toneOf(status) == StatusTone.closed;

  /// "Alacak (İtirazın İptali)", "İcra Dosyası".
  String get type {
    final d = kase.details?.value ?? const <String, Object?>{};
    final kind = record?.details.kind ?? '';
    if (kind.isNotEmpty) return kind;
    return '${d['davaTuru'] ?? d['tur'] ?? ''}'.trim();
  }

  DateTime? get opened =>
      parseDay(kase.details?.value['acilis']) ??
      parseDay(record?.details.openedOn);

  /// The documents not yet looked at.
  List<UyapCaseDocument> get freshDocuments {
    final r = record;
    if (r == null || r.fresh.isEmpty) return const [];
    return [
      for (final d in r.documents) ...[
        if (r.fresh.contains(d.key)) d,
        for (final a in d.attachments)
          if (r.fresh.contains(a.key)) a,
      ],
    ];
  }

  int get freshCount {
    final kept = freshDocuments.length;
    return kept > state.fresh ? kept : state.fresh;
  }

  /// "Davacı", "Alacaklı": the role the lawyer stands in.
  String? get ourRole => ours.isEmpty ? null : titleName(ours.first.role);

  /// "Antalya Adliyesi": the city the court sits in.
  String get place {
    final first = kase.court.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? 'Diğer' : '$first Adliyesi';
  }

  /// When something last happened in it, for "Son gelişme önce".
  DateTime get lastChange {
    final times = <DateTime>[
      ?state.changeAt,
      ?state.firstSeen,
      ?record?.fetchedAt,
      ?opened,
    ];
    if (freshCount > 0) times.add(DateTime.now());
    times.sort();
    return times.isEmpty ? DateTime(1900) : times.last;
  }

  /// What a search looks in, folded: number, court, type and parties.
  late final String haystack = UyapWebService.fold(
    [
      kase.number,
      kase.court,
      type,
      for (final p in [...ours, ...others]) p.name,
    ].join(' '),
  );

  /// The same, a field at a time, for a search kept to one of them.
  late final String partyHaystack = UyapWebService.fold(
    [
      for (final p in [...ours, ...others]) p.name,
    ].join(' '),
  );
  late final String numberHaystack = UyapWebService.fold(kase.number);
  late final String courtHaystack = UyapWebService.fold(kase.court);
}

/// The lawyer's own side of a case: the parties whose lawyer is [lawyer],
/// by surname. When none is known, the parties a lawyer of the same
/// surname stands for are taken; failing that, none.
(List<UyapParty>, List<UyapParty>) splitParties(
  List<UyapParty> parties,
  String lawyer,
) {
  final words = UyapWebService.fold(lawyer)
      .replaceAll(RegExp(r'^av\.?\s*'), '')
      .split(RegExp(r'\s+'));
  final surname = words.where((w) => w.length > 1).lastOrNull;
  if (surname == null) return (const [], parties);
  final ours = [
    for (final p in parties)
      if (UyapWebService.fold(p.lawyer).contains(surname)) p,
  ];
  return (
    ours,
    [
      for (final p in parties)
        if (!ours.contains(p)) p,
    ],
  );
}

/// Reads the portfolio for the list: every case kept, what Folio fetched of
/// each, its next hearing and its news.
Future<List<PortfolioRow>> loadPortfolio({
  required String lawyer,
  PortalDatabase? database,
  UyapCaseStore? store,
}) async {
  final db = database ?? await PortalDatabase.shared();
  final kept = <String, UyapCaseRecord>{};
  try {
    for (final (record, _) in await (store ?? UyapCaseStore.instance).cases()) {
      kept[caseKey(record.number, record.court)] = record;
    }
  } catch (_) {}
  final states = db.caseStates();
  final now = DateTime.now();
  final next = <String, PortalHearing>{};
  for (final h in db.hearings(
    from: DateTime(now.year, now.month, now.day),
    to: now.add(const Duration(days: 400)),
  )) {
    next.putIfAbsent(h.caseKey, () => h);
  }
  return [
    for (final kase in db.cases().values)
      () {
        final record = kept[kase.key];
        final (ours, others) = splitParties(
          record?.parties ?? const [],
          lawyer,
        );
        return PortfolioRow(
          kase: kase,
          state: states[kase.key] ?? const CaseState(),
          record: record,
          hearing: next[kase.key],
          ours: ours,
          others: others,
        );
      }(),
  ];
}
