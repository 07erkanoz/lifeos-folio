import '../portal/portal_database.dart';
import 'client.dart';
import 'client_accounts.dart';

/// What a line of the office's book is: money earned, money spent, a
/// client's money held, or a cost met for a client and owed back.
enum CashSide {
  income('Gelir'),
  expense('Gider'),
  trust('Emanet'),

  /// A cost the lawyer met for a client, and its paying back.
  onBehalf('Müvekkil masrafı');

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
    this.currency = Currency.tl,
  });

  final ClientRecord record;
  final CashSide side;

  /// The money it is in: its sums are never added to another's.
  final Currency currency;
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
  // A line is taken back once, as a client's account takes it
  // (docs/senkron-plan.md R3): by the first reversal of it, of a line that
  // is no reversal itself. Another reversal of it, or one of a reversal, is
  // shown struck and counts for nothing.
  final byId = {for (final r in records) r.id: r};
  final firstBack = <String, String>{};
  for (final r
      in [...records]..sort((a, b) {
        final c = a.created.compareTo(b.created);
        return c != 0 ? c : a.id.compareTo(b.id);
      })) {
    final target = byId[r.reverses];
    if (r.reverses.isEmpty || target == null || target.reverses.isNotEmpty) {
      continue;
    }
    firstBack.putIfAbsent(r.reverses, () => r.id);
  }
  final out = <CashLine>[];
  for (final r in records) {
    final back = r.reverses.isNotEmpty;
    final struck = back || reversed.contains(r.id);
    // What this line counts for: its own sum, its reversal's taken off,
    // nothing for a reversal that takes back nothing more.
    final counts = !back || firstBack[r.reverses] == r.id;
    if (r.kind == ClientRecordKind.cash) {
      final income = r.text('tur') == 'gelir';
      final sign = (income ? 1 : -1) * (back ? -1 : 1) * (counts ? 1 : 0);
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
          currency: r.currency,
        ),
      );
      continue;
    }
    final kind = r.movement;
    if (kind == null) continue;
    final side = switch (kind) {
      MovementKind.feePaid || MovementKind.counterFee => CashSide.income,
      MovementKind.advanceIn ||
      MovementKind.costFromAdvance ||
      MovementKind.collected ||
      MovementKind.toFee ||
      MovementKind.toCounterFee => CashSide.trust,
      MovementKind.costByLawyer || MovementKind.costRepaid => CashSide.onBehalf,
    };
    final e = owner[r.clientId];
    // Held money taken as a fee is two lines: out of what is held, and
    // the office's income.
    if (kind.isApplied) {
      out.add(
        CashLine(
          record: r,
          side: CashSide.income,
          at: r.at,
          title: [
            kind == MovementKind.toFee
                ? 'Vekâlet ücreti (emanetten)'
                : 'Karşı vekâlet ücreti (emanetten)',
            if (r.text('aciklama').isNotEmpty) r.text('aciklama'),
            if (back) 'ters kayıt',
          ].join(' · '),
          amount: (back ? -1 : 1) * (counts ? 1 : 0) * r.amount,
          client: e?.name ?? db.clientCard(r.clientId)?.name ?? '',
          clientKey: e?.key,
          caseKey: r.text('dosya'),
          way: 'Mahsup',
          category: kind.label,
          struck: struck,
          currency: r.currency,
        ),
      );
    }
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
        amount: kind.sign * (back ? -1 : 1) * (counts ? 1 : 0) * r.amount,
        client: e?.name ?? db.clientCard(r.clientId)?.name ?? '',
        clientKey: e?.key,
        caseKey: r.text('dosya'),
        way: r.text('odeme'),
        category: kind.label,
        struck: struck,
        currency: r.currency,
      ),
    );
  }
  return out..sort((a, b) => b.at.compareTo(a.at));
}

/// The currencies [lines] are in, TL always first.
List<Currency> cashCurrencies(Iterable<CashLine> lines) {
  final used = {Currency.tl, for (final l in lines) l.currency};
  return [
    for (final c in Currency.values)
      if (used.contains(c)) c,
  ];
}

/// What the office has in each currency by its book: all it earned less
/// all it spent. A client's advance held is not the office's.
Amounts cashBalance(Iterable<CashLine> lines) {
  final out = Amounts();
  for (final l in lines) {
    if (l.side == CashSide.income || l.side == CashSide.expense) {
      out.add(l.currency, l.amount);
    }
  }
  return out;
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

/// A client's accounts together, each currency apart: the fee still owed,
/// the costs the lawyer met and was not paid back, and the advance held.
typedef ClientBalance = ({
  String key,
  String name,
  Amounts owed,
  Amounts costs,
  Amounts held,
  bool late,
});

/// Each client's accounts together (see [ClientBalance]), by the client's
/// key in the list.
List<ClientBalance> clientBalances(
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
  final out = <ClientBalance>[];
  for (final e in all) {
    final ids = {...e.ids, ?e.client?.id};
    final mine = [for (final id in ids) ...?records[id]];
    if (mine.isEmpty) continue;
    var owed = Amounts(), costs = Amounts(), held = Amounts();
    var late = false;
    for (final a in caseAccounts(mine).values) {
      owed += a.feeOwedAll;
      costs += a.lawyerOwedAll.positive;
      held += a.advanceLeftAll;
      if (a.instalments(now).any((t) => t.late)) late = true;
    }
    if (!owed.isZero || !costs.isZero || !held.isZero) {
      out.add((
        key: e.key,
        name: e.name,
        owed: owed,
        costs: costs,
        held: held,
        late: late,
      ));
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
            'para': ?t.data['para'],
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

/// A bank account the lawyer chose to keep beside the book: its name, its
/// currency and its balance as last told. Nothing is asked of a bank; the
/// balance is what the lawyer wrote, with when.
class BankAccount {
  const BankAccount(this.record);

  final ClientRecord record;

  String get id => record.id;
  String get name => record.text('ad');
  Currency get currency => record.currency;

  /// Kuruş, or the currency's hundredth.
  int get balance =>
      record.data['bakiye'] is int ? record.data['bakiye'] as int : 0;
  DateTime get told =>
      DateTime.tryParse(record.text('tarih')) ?? record.updated;
}

/// The bank accounts kept, by name.
List<BankAccount> bankAccounts(PortalDatabase db) => [
  for (final r in db.allClientRecords())
    if (!r.removed &&
        r.kind == ClientRecordKind.bank &&
        r.clientId == officeCashId)
      BankAccount(r),
]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// The banks' balances together, each currency apart.
Amounts bankTotal(Iterable<BankAccount> banks) {
  final out = Amounts();
  for (final b in banks) {
    out.add(b.currency, b.balance);
  }
  return out;
}
