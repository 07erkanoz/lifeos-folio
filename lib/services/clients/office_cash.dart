import '../portal/portal_database.dart';
import 'client.dart';
import 'client_accounts.dart';

/// What a line of the office's book is: money earned, money spent, a
/// client's money held, or a cost met for a client and owed back.
enum CashSide {
  income('Gelir'),
  expense('Gider'),
  trust('Emanet'),
  onBehalf('Müvekkil adına');

  const CashSide(this.label);
  final String label;
}

/// The kinds of the office's own spending.
const expenseCategories = [
  'Kira',
  'Maaş ve SGK',
  'Vergi ve harç',
  'Ulaşım',
  'Kırtasiye',
  'Abonelik',
  'Diğer',
];

/// Where money is paid from or into.
const cashWays = ['Nakit', 'Banka', 'Kredi kartı'];

/// One line of the office's book: a client's movement, or the office's
/// own income or expense. [amount] in kuruş, money in above nothing.
class CashLine {
  const CashLine({
    required this.record,
    required this.side,
    required this.at,
    required this.title,
    required this.amount,
    this.client = '',
    this.clientKey,
    this.caseKey = '',
    this.way = '',
    this.category = '',
    this.struck = false,
  });

  final ClientRecord record;
  final CashSide side;
  final DateTime at;
  final String title, client, caseKey, way, category;

  /// The client's key in the list, for opening them; null for the office's.
  final String? clientKey;
  final int amount;

  /// Taken back by a reversal, or one itself: both stay, struck out.
  final bool struck;

  /// Written on a client's card, and corrected there.
  bool get fromClient => record.clientId != officeCashId;
}

extension OfficeCash on ClientRecord {
  bool get isOfficeCash =>
      clientId == officeCashId && kind == ClientRecordKind.cash;
}

/// The month key of [t]: "2026-10".
String monthKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}';

/// The office's book: every client's movement, every income and expense
/// of the office's own, the latest first.
List<CashLine> cashLines(PortalDatabase db, {List<ClientEntry>? entries}) {
  final all = entries ?? db.clientEntries();
  final owner = <String, ClientEntry>{
    for (final e in all)
      for (final id in [...e.ids, ?e.client?.id]) id: e,
  };
  final records = [
    for (final r in db.allClientRecords())
      if (!r.removed &&
          (r.kind == ClientRecordKind.movement ||
              (r.kind == ClientRecordKind.cash && r.clientId == officeCashId)))
        r,
  ];
  final reversed = {
    for (final r in records)
      if (r.reverses.isNotEmpty) r.reverses,
  };
  final out = <CashLine>[];
  for (final r in records) {
    final back = r.reverses.isNotEmpty;
    final struck = back || reversed.contains(r.id);
    if (r.kind == ClientRecordKind.cash) {
      final income = r.text('tur') == 'gelir';
      final sign = (income ? 1 : -1) * (back ? -1 : 1);
      out.add(
        CashLine(
          record: r,
          side: income ? CashSide.income : CashSide.expense,
          at: r.at,
          title: [
            r.text('aciklama').isEmpty
                ? r.text('kategori')
                : r.text('aciklama'),
            if (back) 'ters kayıt',
          ].join(' · '),
          amount: sign * r.amount,
          way: r.text('odeme'),
          category: r.text('kategori'),
          struck: struck,
        ),
      );
      continue;
    }
    final kind = r.movement;
    if (kind == null) continue;
    final side = switch (kind) {
      MovementKind.feePaid || MovementKind.counterFee => CashSide.income,
      MovementKind.advanceIn || MovementKind.costFromAdvance => CashSide.trust,
      MovementKind.costByLawyer || MovementKind.costRepaid => CashSide.onBehalf,
    };
    final e = owner[r.clientId];
    out.add(
      CashLine(
        record: r,
        side: side,
        at: r.at,
        title: [
          kind.label,
          if (r.text('aciklama').isNotEmpty) r.text('aciklama'),
          if (back) 'ters kayıt',
        ].join(' · '),
        amount: kind.sign * (back ? -1 : 1) * r.amount,
        client: e?.name ?? db.clientCard(r.clientId)?.name ?? '',
        clientKey: e?.key,
        caseKey: r.text('dosya'),
        way: r.text('odeme'),
        category: kind.label,
        struck: struck,
      ),
    );
  }
  return out..sort((a, b) => b.at.compareTo(a.at));
}

/// What the lines say together: earned, spent, and their difference.
({int income, int expense, int net}) cashTotals(Iterable<CashLine> lines) {
  var income = 0, expense = 0;
  for (final l in lines) {
    if (l.side == CashSide.income) income += l.amount;
    if (l.side == CashSide.expense) expense -= l.amount;
  }
  return (income: income, expense: expense, net: income - expense);
}

/// Each client's accounts together: the fee still owed and the costs the
/// lawyer met, and the advance held, by the client's key in the list.
List<({String key, String name, int owed, int held, bool late})> clientBalances(
  PortalDatabase db,
  DateTime now, {
  List<ClientEntry>? entries,
}) {
  final all = entries ?? db.clientEntries();
  final records = <String, List<ClientRecord>>{};
  for (final r in db.allClientRecords()) {
    if (!r.removed && r.kind.money && r.clientId != officeCashId) {
      (records[r.clientId] ??= []).add(r);
    }
  }
  final out = <({String key, String name, int owed, int held, bool late})>[];
  for (final e in all) {
    final ids = {...e.ids, ?e.client?.id};
    final mine = [for (final id in ids) ...?records[id]];
    if (mine.isEmpty) continue;
    var owed = 0, held = 0;
    var late = false;
    for (final a in caseAccounts(mine).values) {
      if (a.feeOwed > 0) owed += a.feeOwed;
      if (a.lawyerOwed > 0) owed += a.lawyerOwed;
      held += a.advanceLeft;
      if (a.instalments(now).any((t) => t.late)) late = true;
    }
    if (owed != 0 || held != 0) {
      out.add((key: e.key, name: e.name, owed: owed, held: held, late: late));
    }
  }
  return out;
}

/// The monthly expenses told to repeat, written for every month come
/// since, once: their ids are the month's, the same on every device.
/// Returns how many were written.
int writeRepeats(PortalDatabase db, DateTime now, {String person = ''}) {
  var made = 0;
  for (final t in db.allClientRecords()) {
    if (t.removed ||
        t.kind != ClientRecordKind.cashRepeat ||
        t.clientId != officeCashId) {
      continue;
    }
    final start = DateTime.tryParse(t.text('baslangic'));
    if (start == null) continue;
    final stop = DateTime.tryParse(t.text('bitis'));
    for (
      var m = DateTime(start.year, start.month);
      !m.isAfter(now);
      m = DateTime(m.year, m.month + 1)
    ) {
      final last = DateTime(m.year, m.month + 1, 0).day;
      final day = DateTime(
        m.year,
        m.month,
        start.day.clamp(1, last),
        start.hour,
        start.minute,
      );
      if (day.isAfter(now) || day.isBefore(start)) continue;
      if (stop != null && !day.isBefore(stop)) break;
      final id = '${t.id}-${monthKey(day)}';
      if (db.clientRecord(id) != null) continue;
      db.saveClientRecord(
        ClientRecord(
          id: id,
          clientId: officeCashId,
          kind: ClientRecordKind.cash,
          data: {
            'tur': 'gider',
            'kategori': t.text('kategori'),
            'tutar': t.data['tutar'],
            'zaman': day.toIso8601String(),
            'aciklama': t.text('aciklama'),
            'odeme': t.text('odeme'),
            'tekrar': t.id,
          },
          created: now,
          by: t.by,
          updated: now,
          locked: true,
          person: t.person.isNotEmpty ? t.person : person,
        ),
      );
      made++;
    }
  }
  return made;
}
