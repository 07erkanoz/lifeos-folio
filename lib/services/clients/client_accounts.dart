import 'client.dart';

/// What a movement is (docs/design/muvekkil-taslak): money in for the fee
/// or as an advance, a cost met from the advance or by the lawyer, a cost
/// the lawyer met paid back, the fee the court gave against the other side.
enum MovementKind {
  feePaid('ucret', 'Ücret tahsilatı', 1),
  advanceIn('avans', 'Avans alındı', 1),
  costFromAdvance('masrafAvans', 'Masraf (avanstan)', -1),
  costByLawyer('masrafAvukat', 'Masraf (avukat ödedi)', -1),
  costRepaid('masrafIade', 'Avukatın masrafı ödendi', 1),
  counterFee('karsiVekalet', 'Karşı vekâlet ücreti', 1);

  const MovementKind(this.code, this.label, this.sign);
  final String code, label;

  /// +1 money in, -1 money out, as the list shows it.
  final int sign;

  static MovementKind? of(Object? code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// The money a record is in: Turkish lira, euro or dollar. Sums of one are
/// never added to another's; each is seen apart.
enum Currency {
  tl('TL', 'TL', 'TL'),
  eur('EUR', '€', 'Euro'),
  usd('USD', r'$', 'Dolar');

  const Currency(this.code, this.sign, this.label);

  /// As kept in a record's `para`; TL's is not written.
  final String code;
  final String sign, label;

  static Currency of(Object? code) {
    for (final c in values) {
      if (c.code == code) return c;
    }
    return tl;
  }
}

/// [cents] in [c]: "12.500 TL", "1.250,50 €", "300 $".
String money(int cents, Currency c) => c == Currency.tl
    ? lira(cents)
    : '${plainMoney(cents, Currency.tl)} ${c.sign}';

/// As a column of lira writes it: TL bare ("15.000"), another with its
/// sign ("1.250 €").
String plainMoney(int cents, Currency c) {
  final t = lira(cents).replaceAll(' TL', '');
  return c == Currency.tl ? t : '$t ${c.sign}';
}

/// Sums kept a currency apart: never added across.
class Amounts {
  Amounts([Map<Currency, int>? by]) : _by = {...?by};

  final Map<Currency, int> _by;

  int operator [](Currency c) => _by[c] ?? 0;

  void add(Currency c, int cents) {
    if (cents != 0) _by[c] = this[c] + cents;
  }

  Amounts operator +(Amounts o) {
    final out = Amounts(_by);
    for (final e in o._by.entries) {
      out.add(e.key, e.value);
    }
    return out;
  }

  /// Only the currencies more than nothing is in.
  Amounts get positive => Amounts({
    for (final e in _by.entries)
      if (e.value > 0) e.key: e.value,
  });

  /// The currencies it holds a sum in, in their order.
  List<Currency> get currencies => [
    for (final c in Currency.values)
      if (this[c] != 0) c,
  ];

  bool get isZero => currencies.isEmpty;
  bool get anyPositive => _by.values.any((v) => v > 0);

  /// "12.500 TL + 1.000 €"; "0 TL" for nothing.
  String get text => isZero
      ? lira(0)
      : [for (final c in currencies) money(this[c], c)].join(' + ');

  /// As a column of lira writes it (see [plainMoney]).
  String get plain => isZero
      ? plainMoney(0, Currency.tl)
      : [for (final c in currencies) plainMoney(this[c], c)].join(' + ');
}

/// A movement's fields, read from its record.
extension Movement on ClientRecord {
  MovementKind? get movement => MovementKind.of(data['hesap']);

  /// Kuruş: a lira's hundredth, never a double's rounding.
  int get amount => data['tutar'] is int ? data['tutar'] as int : 0;

  /// When the money changed hands, to the minute, as the lawyer told it;
  /// [created] is when it was written.
  DateTime get at => DateTime.tryParse(text('zaman')) ?? created;

  /// The movement this one takes back, when it does.
  String get reverses => text('ters');

  /// The money it is in: TL unless told.
  Currency get currency => Currency.of(data['para']);
}

/// A case's account for a client in one currency: what was agreed, and the
/// movements. A case paid in more than one currency has an account in
/// each: its main one (the fee's currency, else TL) and [others].
class CaseAccount {
  CaseAccount(
    this.caseKey,
    this.fee,
    List<ClientRecord> movements, {
    this.currency = Currency.tl,
    this.others = const [],
  }) : movements = [...movements]..sort((a, b) => b.at.compareTo(a.at)) {
    final taken = {
      for (final m in movements)
        if (m.reverses.isNotEmpty) m.reverses,
    };
    for (final m in movements) {
      if (m.reverses.isNotEmpty || taken.contains(m.id)) continue;
      switch (m.movement) {
        case MovementKind.feePaid:
          feeIn += m.amount;
        case MovementKind.advanceIn:
          advanceIn += m.amount;
        case MovementKind.costFromAdvance:
          advanceSpent += m.amount;
        case MovementKind.costByLawyer:
          lawyerSpent += m.amount;
        case MovementKind.costRepaid:
          lawyerRepaid += m.amount;
        case MovementKind.counterFee:
          counterFee += m.amount;
        case null:
          break;
      }
    }
    reversed = taken;
  }

  final String caseKey;
  final Currency currency;

  /// The case's accounts in its other currencies.
  final List<CaseAccount> others;

  /// This one and [others].
  List<CaseAccount> get all => [this, ...others];

  /// The fee agreed, null while none.
  final ClientRecord? fee;
  final List<ClientRecord> movements;
  late final Set<String> reversed;
  int feeIn = 0, advanceIn = 0, advanceSpent = 0;
  int lawyerSpent = 0, lawyerRepaid = 0, counterFee = 0;

  /// The fixed part of the fee agreed, in kuruş.
  int get feeAgreed =>
      fee?.data['tutar'] is int ? fee!.data['tutar'] as int : 0;

  /// The share of what is won, in percent; 0 for none.
  num get feeShare => fee?.data['yuzde'] is num ? fee!.data['yuzde'] as num : 0;

  /// The fixed fee still owed; less than nothing when more was paid.
  int get feeOwed => feeAgreed - feeIn;
  int get advanceLeft => advanceIn - advanceSpent;

  /// What the lawyer met of the costs and was not paid back yet.
  int get lawyerOwed => lawyerSpent - lawyerRepaid;

  /// Across the case's currencies, each apart: the fee owed (none when
  /// overpaid), the advance left, the lawyer's costs not paid back.
  Amounts get feeOwedAll => Amounts({
    for (final a in all)
      if (a.feeOwed > 0) a.currency: a.feeOwed,
  });
  Amounts get advanceLeftAll =>
      Amounts({for (final a in all) a.currency: a.advanceLeft});
  Amounts get lawyerOwedAll =>
      Amounts({for (final a in all) a.currency: a.lawyerOwed});

  /// The instalments, with what is paid laid over them in order.
  List<({DateTime due, int amount, bool paid, bool late})> instalments(
    DateTime now,
  ) {
    final plan = fee?.data['taksitler'];
    if (plan is! List) return const [];
    var paid = feeIn;
    final today = DateTime(now.year, now.month, now.day);
    final out = <({DateTime due, int amount, bool paid, bool late})>[];
    for (final t in plan) {
      if (t is! Map) continue;
      final due = DateTime.tryParse('${t['tarih']}');
      if (due == null) continue;
      final amount = t['tutar'] is int ? t['tutar'] as int : 0;
      final done = paid >= amount;
      paid = done ? paid - amount : 0;
      out.add((
        due: due,
        amount: amount,
        paid: done,
        late: !done && due.isBefore(today),
      ));
    }
    return out;
  }
}

/// [records]' accounts by case: each case's fee and movements apart, its
/// main account by its key, the rest of its currencies in its [others]. A
/// movement or fee of no case goes to the account "".
Map<String, CaseAccount> caseAccounts(Iterable<ClientRecord> records) {
  final fees = <String, ClientRecord>{};
  final moves = <String, Map<Currency, List<ClientRecord>>>{};
  for (final r in records) {
    final key = r.text('dosya');
    if (r.kind == ClientRecordKind.fee) {
      final kept = fees[key];
      if (kept == null || r.updated.isAfter(kept.updated)) fees[key] = r;
    } else if (r.kind == ClientRecordKind.movement) {
      ((moves[key] ??= {})[r.currency] ??= []).add(r);
    }
  }
  final out = <String, CaseAccount>{};
  for (final key in {...fees.keys, ...moves.keys}) {
    final fee = fees[key];
    final byCurrency = moves[key] ?? const {};
    final main =
        fee?.currency ??
        (byCurrency.containsKey(Currency.tl) || byCurrency.isEmpty
            ? Currency.tl
            : byCurrency.keys.first);
    out[key] = CaseAccount(
      key,
      fee,
      byCurrency[main] ?? const [],
      currency: main,
      others: [
        for (final c in Currency.values)
          if (c != main && byCurrency.containsKey(c))
            CaseAccount(key, null, byCurrency[c]!, currency: c),
      ],
    );
  }
  return out;
}

/// "12.500 TL" or "12.500,50 TL", from kuruş: the app's typeface has no
/// lira sign, and the courts write TL.
String lira(int kurus) {
  final negative = kurus < 0;
  final v = kurus.abs();
  final whole = (v ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final cents = v % 100;
  return '${negative ? '−' : ''}$whole'
      '${cents == 0 ? '' : ',${cents.toString().padLeft(2, '0')}'} TL';
}

/// Kuruş from what is typed: "12.500", "12500,50", "12 500 TL".
int? kurusOf(String text) {
  final t = text
      .replaceAll(RegExp(r'tl|[\s₺.]', caseSensitive: false), '')
      .replaceAll(',', '.');
  final v = double.tryParse(t);
  return v == null ? null : (v * 100).round();
}
