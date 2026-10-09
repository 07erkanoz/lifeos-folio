import '../portal/portal_database.dart';
import '../uyap/uyap_web_service.dart';
import 'client.dart';
import 'client_accounts.dart';

/// Where a case stands, as UYAP says it: still worked on, stopped (an
/// enforcement held), at a higher court, or done with.
enum CaseStage { open, stopped, appeal, closed }

/// [status] as UYAP writes it ("Açık", "Açık (Durdurulmuş : Takibe
/// İtiraz)", "İstinafta", "Karara Çıkmış", …); a case UYAP has not told
/// of is open.
CaseStage stageOf(String status) {
  final s = status.trim();
  if (s.isEmpty || s == 'Açık') return CaseStage.open;
  if (s.startsWith('Açık (Durdurulmuş')) return CaseStage.stopped;
  if (s.startsWith('Açık')) return CaseStage.open;
  if (s.contains('İstinaf') || s.contains('Yargıtay')) return CaseStage.appeal;
  if (s.startsWith('Karara') ||
      s.startsWith('Kapalı') ||
      s.startsWith('Başka Birime') ||
      s.startsWith('Düşmüş')) {
    return CaseStage.closed;
  }
  return CaseStage.open;
}

/// [status] shortened for a label: "Durdurulmuş · Takibe İtiraz",
/// "İstinafta", "Karara çıktı".
String stageLabel(String status) {
  final s = status.trim();
  if (s.isEmpty) return 'Açık';
  final stopped = RegExp(r'^Açık \(Durdurulmuş\s*:\s*(.+)\)$').firstMatch(s);
  if (stopped != null) return 'Durdurulmuş · ${stopped.group(1)!.trim()}';
  if (s == 'Karara Çıkmış') return 'Karara çıktı';
  return s;
}

/// What kind of file a case is, from its details: "Hukuk Dava", "İcra",
/// "Ceza Dava"; empty when UYAP did not say.
String caseKindOf(Map<String, Object?>? details) {
  final kind = '${details?['tur'] ?? ''}'.trim();
  return kind.replaceAll(RegExp(r'\s*Dosyası$'), '');
}

/// The year in a UYAP date ("2024-05-21 10:25:10.0"); null without one.
int? yearOf(Object? date) => DateTime.tryParse('${date ?? ''}')?.year;

/// The other side of a case for a client of [role]: the first party of the
/// role facing it (a defendant for a plaintiff, a debtor for a creditor),
/// else the first who is not the client nor a third party.
UyapParty? otherSide(
  List<UyapParty> parties,
  String role,
  bool Function(UyapParty p) isClient,
) {
  final r = UyapWebService.fold(role);
  final facing = switch (r) {
    _ when r.contains('davaci') => ['davali'],
    _ when r.contains('davali') => ['davaci'],
    _ when r.contains('alacakli') => ['borclu'],
    _ when r.contains('borclu') => ['alacakli'],
    _ when r.contains('sanik') => ['musteki', 'katilan', 'magdur'],
    _ when r.contains('musteki') || r.contains('katilan') => [
      'sanik',
      'supheli',
    ],
    _ when r.contains('talep eden') => ['karsi taraf'],
    _ when r.contains('karsi taraf') => ['talep eden'],
    _ => const <String>[],
  };
  const aside = ['ucuncu', 'diger', 'tanik', 'bilirkisi'];
  final others = [
    for (final p in parties)
      if (!isClient(p) &&
          !aside.any((a) => UyapWebService.fold(p.role).contains(a)))
        p,
  ];
  return others
          .where((p) => facing.any(UyapWebService.fold(p.role).contains))
          .firstOrNull ??
      others.firstOrNull;
}

/// A client at a glance, for the list: how many cases and how many still
/// worked on, the nearest hearing or deadline, what is owed, whether they
/// can be reached, and when the last of a client done with closed.
class ClientGlance {
  const ClientGlance({
    required this.cases,
    required this.open,
    this.next,
    this.owed = 0,
    this.reachable = false,
    this.closedYear,
  });

  final int cases, open;
  final ({DateTime at, bool hearing, String caseKey})? next;

  /// The fee still owed, in kuruş; 0 for one who may not see the money.
  final int owed;
  final bool reachable;
  final int? closedYear;

  /// Every case of theirs done with.
  bool get done => cases > 0 && open == 0;
}

/// Each of [entries] at a glance, by key: the cases, the hearings, the
/// deadlines and the money read once for all, not once a client.
Map<String, ClientGlance> clientGlances(
  PortalDatabase db,
  List<ClientEntry> entries,
  DateTime now, {
  bool money = false,
}) {
  final cases = db.cases();
  final today = DateTime(now.year, now.month, now.day);
  final soonest = <String, ({DateTime at, bool hearing, String caseKey})>{};
  void soon(String key, DateTime at, bool hearing) {
    final kept = soonest[key];
    if (kept == null || at.isBefore(kept.at)) {
      soonest[key] = (at: at, hearing: hearing, caseKey: key);
    }
  }

  for (final h in db.hearings(
    from: now,
    to: now.add(const Duration(days: 400)),
  )) {
    soon(h.caseKey, h.at, true);
  }
  for (final d in db.deadlines(decidedOnly: true)) {
    final key = d.record.caseKey;
    final day = DateTime.tryParse(d.day ?? '');
    if (key == null || day == null || !d.onAgenda) continue;
    if (d.user?.done ?? false) continue;
    if (day.isBefore(today)) continue;
    soon(key, day, false);
  }
  final owedBy = <String, int>{};
  if (money) {
    final byClient = <String, List<ClientRecord>>{};
    for (final r in db.allClientRecords()) {
      if (!r.removed && r.kind.money) (byClient[r.clientId] ??= []).add(r);
    }
    for (final e in entries) {
      final records = [for (final id in e.ids) ...?byClient[id]];
      if (records.isEmpty) continue;
      owedBy[e.key] = caseAccounts(records).values
          .fold(0, (n, a) => n + (a.feeOwed > 0 ? a.feeOwed : 0));
    }
  }
  return {
    for (final e in entries)
      e.key: () {
        var open = 0;
        int? closed;
        ({DateTime at, bool hearing, String caseKey})? next;
        for (final c in e.cases) {
          final kase = cases[c.caseKey];
          final stage = stageOf(kase?.status?.value ?? '');
          if (stage == CaseStage.closed) {
            final year = yearOf(kase?.details?.value['kapanis']);
            if (year != null && (closed == null || year > closed)) {
              closed = year;
            }
          } else {
            open++;
          }
          final s = soonest[c.caseKey];
          if (s != null && (next == null || s.at.isBefore(next.at))) next = s;
        }
        final client = e.client;
        return ClientGlance(
          cases: e.cases.length,
          open: open,
          next: next,
          owed: owedBy[e.key] ?? 0,
          reachable:
              (client?.phone ?? '').trim().isNotEmpty ||
              (client?.email ?? '').trim().isNotEmpty,
          closedYear: closed,
        );
      }(),
  };
}

/// The groups the lawyer has given clients, A to Z.
List<String> clientGroups(PortalDatabase db) {
  final groups = {
    for (final c in db.clientCards())
      if (!c.removed && c.group.trim().isNotEmpty) c.group.trim(),
  }.toList();
  groups.sort(
    (a, b) => UyapWebService.fold(a).compareTo(UyapWebService.fold(b)),
  );
  return groups;
}

/// What a notice's subject says beyond its court and case, which UYAP
/// repeats in it ("Antalya 9. Aile Mahkemesi [2020/801] [Antalya 9. Aile
/// Mahkemesi-5000…-0-2020/801]"): empty when nothing more.
String noticeTopic(String subject, String court) {
  var s = subject.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  if (court.isNotEmpty) {
    s = s.replaceAll(court, ' ');
  }
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceAll(RegExp(r'^[-–·:,\s]+|[-–·:,\s]+$'), '');
  return s;
}
