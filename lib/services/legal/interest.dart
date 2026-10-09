import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// What the interest is: by law, a merchant's for default, or one agreed.
enum InterestKind {
  legal('yasal', 'Kanuni (yasal) faiz'),
  commercial('ticari', 'Ticari temerrüt (avans) faizi'),
  fixed('sabit', 'Sözleşmeyle belirlenen oran');

  const InterestKind(this.code, this.label);
  final String code, label;
}

/// The rates (assets/mevzuat/faiz.json): the central bank's rediscount
/// and advance rates by the day they took effect, and each kind's
/// periods, a fixed rate or the bank's by 3095's rule. The law is in the
/// data, not here; a new rate is a line added there.
class InterestRates {
  InterestRates._(this._tcmb, this._kinds, this.verified, this.version);

  final List<({DateTime day, double rediscount, double advance})> _tcmb;
  final Map<String, Map<String, Object?>> _kinds;

  /// The day the data was last checked against its sources: a rate after
  /// it may have changed unseen.
  final DateTime? verified;
  final int version;

  static InterestRates? _loaded;

  static Future<InterestRates> load() async => _loaded ??= parse(
    await rootBundle.loadString('assets/mevzuat/faiz.json'),
  );

  static InterestRates parse(String text) {
    final j = jsonDecode(text) as Map<String, Object?>;
    final tcmb = [
      for (final r in j['tcmb'] as List)
        (
          day: DateTime.parse('${(r as Map)['tarih']}'),
          rediscount: (r['reeskont'] as num).toDouble(),
          advance: (r['avans'] as num).toDouble(),
        ),
    ]..sort((a, b) => a.day.compareTo(b.day));
    return InterestRates._(
      tcmb,
      {
        for (final e in (j['turler'] as Map).entries)
          '${e.key}': Map<String, Object?>.from(e.value as Map),
      },
      DateTime.tryParse('${j['dogrulandi']}'.split(':').first),
      (j['surum'] as num?)?.toInt() ?? 0,
    );
  }

  /// The bank's [series] rate in force on [day]; null before its first.
  double? _bank(String series, DateTime day) {
    double? out;
    for (final r in _tcmb) {
      if (r.day.isAfter(day)) break;
      out = series == 'avans' ? r.advance : r.rediscount;
    }
    return out;
  }

  /// 3095's rule for a year: the rate on the 31st of December before; in
  /// the second half, the rate on the 30th of June when it is five points
  /// or more away from that.
  double? _byRule(String series, DateTime day) {
    final year = _bank(series, DateTime(day.year - 1, 12, 31));
    if (year == null) return null;
    if (day.month < 7) return year;
    final june = _bank(series, DateTime(day.year, 6, 30));
    if (june != null && (june - year).abs() >= 5) return june;
    return year;
  }

  /// The yearly rate in percent of [kind] on [day], and what it rests on;
  /// null where the data does not reach.
  ({double rate, String basis})? rateOn(InterestKind kind, DateTime day) {
    if (kind == InterestKind.fixed) return null;
    final def = _kinds[kind.code];
    if (def == null) return null;
    final d = DateTime(day.year, day.month, day.day);
    ({double rate, String basis})? found;
    for (final p in (def['donemler'] as List).cast<Map>()) {
      final from = DateTime.parse('${p['baslangic']}');
      final to = p['bitis'] == null ? null : DateTime.parse('${p['bitis']}');
      if (d.isBefore(from) || (to != null && d.isAfter(to))) continue;
      final basis = '${p['not'] ?? def['dayanak'] ?? ''}';
      if (p['oran'] is num) {
        found = (rate: (p['oran'] as num).toDouble(), basis: basis);
      } else if (p['tcmb'] is String) {
        final bank = _byRule(p['tcmb'] as String, d);
        if (bank == null) return null;
        final times = (p['carpan'] as num?)?.toDouble() ?? 1;
        found = (
          rate: (bank * times * 100).roundToDouble() / 100,
          basis: basis,
        );
      }
      break;
    }
    if (found == null) return null;
    // Never less than the kind it may not fall under.
    final floor = InterestKind.values
        .where((k) => k.code == def['enAz'])
        .firstOrNull;
    if (floor != null) {
      final least = rateOn(floor, d);
      if (least != null && least.rate > found.rate) return least;
    }
    return found;
  }
}

/// One stretch of the reckoning: [days] days from [from] at [rate] on
/// [principal], earning [interest]; or a payment on [from], [paid] of it
/// to the interest owed and the rest to the principal.
class InterestRow {
  const InterestRow({
    required this.from,
    this.to,
    this.days = 0,
    this.rate = 0,
    this.principal = 0,
    this.interest = 0,
    this.basis = '',
    this.payment = 0,
    this.toInterest = 0,
    this.toPrincipal = 0,
  });

  final DateTime from;

  /// The stretch's last day; null for a payment.
  final DateTime? to;
  final int days;
  final double rate;

  /// Kuruş.
  final int principal, interest, payment, toInterest, toPrincipal;
  final String basis;

  bool get isPayment => to == null;
}

class InterestResult {
  const InterestResult({
    required this.rows,
    required this.accrued,
    required this.interestLeft,
    required this.principalLeft,
    this.beyondData = false,
    this.missing = false,
  });

  final List<InterestRow> rows;

  /// Kuruş: all the interest earned, what of it is still owed, and the
  /// principal left.
  final int accrued, interestLeft, principalLeft;
  int get total => interestLeft + principalLeft;

  /// Reckoned past the day the rates were last checked.
  final bool beyondData;

  /// Some days fell where the data has no rate (before its periods).
  final bool missing;
}

/// The interest on [principal] (kuruş) from [from] to [to], each day at
/// its own rate (365 days a year), a stretch for each rate; [payments]
/// set first against the interest owed, then the principal (TBK m.100);
/// no interest on interest. [fixedRate] for an agreed rate.
InterestResult reckon({
  required InterestRates rates,
  required InterestKind kind,
  required int principal,
  required DateTime from,
  required DateTime to,
  double fixedRate = 0,
  List<({DateTime day, int amount})> payments = const [],
}) {
  DateTime day0(DateTime t) => DateTime(t.year, t.month, t.day);
  final start = day0(from), end = day0(to);
  final paid = [
    for (final p in payments)
      if (!day0(p.day).isBefore(start) && !day0(p.day).isAfter(end))
        (day: day0(p.day), amount: p.amount),
  ]..sort((a, b) => a.day.compareTo(b.day));
  final rows = <InterestRow>[];
  var left = principal;
  var owed = 0.0, accrued = 0;
  var missing = false;
  ({double rate, String basis})? rateOf(DateTime d) =>
      kind == InterestKind.fixed
      ? (rate: fixedRate, basis: 'sözleşme')
      : rates.rateOn(kind, d);

  // The stretch begun and not yet written.
  DateTime? runFrom;
  var runDays = 0;
  ({double rate, String basis})? runRate;
  void close(DateTime next) {
    final from0 = runFrom;
    final r = runRate;
    if (from0 == null || runDays == 0 || r == null) {
      runFrom = null;
      runDays = 0;
      return;
    }
    final earned = (left * r.rate / 100 * runDays / 365).round();
    owed += earned;
    accrued += earned;
    rows.add(
      InterestRow(
        from: from0,
        to: next.subtract(const Duration(days: 1)),
        days: runDays,
        rate: r.rate,
        principal: left,
        interest: earned,
        basis: r.basis,
      ),
    );
    runFrom = null;
    runDays = 0;
  }

  var p = 0;
  for (
    var d = start;
    d.isBefore(end);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    while (p < paid.length && !paid[p].day.isAfter(d)) {
      close(d);
      final amount = paid[p].amount;
      final toInterest = amount < owed.round() ? amount : owed.round();
      owed -= toInterest;
      var toPrincipal = amount - toInterest;
      if (toPrincipal > left) toPrincipal = left;
      left -= toPrincipal;
      rows.add(
        InterestRow(
          from: paid[p].day,
          payment: amount,
          toInterest: toInterest,
          toPrincipal: toPrincipal,
        ),
      );
      p++;
    }
    final r = rateOf(d);
    if (r == null) {
      missing = true;
      close(d);
      continue;
    }
    if (runFrom != null && r.rate != runRate?.rate) close(d);
    if (runFrom == null) {
      runFrom = d;
      runRate = r;
    }
    runDays++;
  }
  close(end);
  // A payment on the last day is set against all that was earned.
  while (p < paid.length) {
    final amount = paid[p].amount;
    final toInterest = amount < owed.round() ? amount : owed.round();
    owed -= toInterest;
    var toPrincipal = amount - toInterest;
    if (toPrincipal > left) toPrincipal = left;
    left -= toPrincipal;
    rows.add(
      InterestRow(
        from: paid[p].day,
        payment: amount,
        toInterest: toInterest,
        toPrincipal: toPrincipal,
      ),
    );
    p++;
  }
  final verified = rates.verified;
  return InterestResult(
    rows: rows,
    accrued: accrued,
    interestLeft: owed.round(),
    principalLeft: left,
    beyondData:
        kind != InterestKind.fixed && verified != null && end.isAfter(verified),
    missing: missing,
  );
}
