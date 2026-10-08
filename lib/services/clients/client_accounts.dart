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
}

/// A case's account for a client: what was agreed, and the movements.
class CaseAccount {
  CaseAccount(this.caseKey, this.fee, List<ClientRecord> movements)
    : movements = [...movements]..sort((a, b) => b.at.compareTo(a.at)) {
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

/// [records]' accounts by case: each case's fee and movements apart. A
/// movement or fee of no case goes to the account "".
Map<String, CaseAccount> caseAccounts(Iterable<ClientRecord> records) {
  final fees = <String, ClientRecord>{};
  final moves = <String, List<ClientRecord>>{};
  for (final r in records) {
    final key = r.text('dosya');
    if (r.kind == ClientRecordKind.fee) {
      final kept = fees[key];
      if (kept == null || r.updated.isAfter(kept.updated)) fees[key] = r;
    } else if (r.kind == ClientRecordKind.movement) {
      (moves[key] ??= []).add(r);
    }
  }
  return {
    for (final key in {...fees.keys, ...moves.keys})
      key: CaseAccount(key, fees[key], moves[key] ?? const []),
  };
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
