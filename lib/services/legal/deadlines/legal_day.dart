/// A calendar day as the law counts it: a year, a month and a day, with no
/// hour and no time zone. Deadlines are counted in these (HMK m.92: the day
/// of the event is not counted), never in hours added to a local clock, so
/// that a computer set to another zone, or one whose zone keeps summer
/// time, reaches the same last day as one in Turkey.
///
/// Inside it is midnight UTC, where a day is always twenty-four hours.
class LegalDay implements Comparable<LegalDay> {
  LegalDay(int year, int month, int day)
    : _utc = DateTime.utc(year, month, day);

  LegalDay._(this._utc);

  /// The day [d] falls on, read from its own fields: a local date stays the
  /// date it shows.
  factory LegalDay.of(DateTime d) => LegalDay(d.year, d.month, d.day);

  final DateTime _utc;

  int get year => _utc.year;
  int get month => _utc.month;
  int get day => _utc.day;
  int get weekday => _utc.weekday;

  LegalDay addDays(int days) => LegalDay._(_utc.add(Duration(days: days)));

  /// [months] later, on the corresponding day, or on the month's last day
  /// when it has none (HMK m.92/2): 31 January and a month is 28 February.
  LegalDay addMonths(int months) {
    final first = DateTime.utc(year, month + months, 1);
    final last = DateTime.utc(first.year, first.month + 1, 0).day;
    return LegalDay(first.year, first.month, day > last ? last : day);
  }

  LegalDay addYears(int years) => addMonths(years * 12);

  /// Whole days from [other] to this one; negative when this one is before.
  int daysSince(LegalDay other) => _utc.difference(other._utc).inDays;

  bool isBefore(LegalDay other) => _utc.isBefore(other._utc);
  bool isAfter(LegalDay other) => _utc.isAfter(other._utc);

  /// Local midnight of this day, for the code that shows or stores dates
  /// as [DateTime].
  DateTime toLocal() => DateTime(year, month, day);

  /// 'yyyy-mm-dd'.
  String get key =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(LegalDay other) => _utc.compareTo(other._utc);

  @override
  bool operator ==(Object other) => other is LegalDay && other._utc == _utc;

  @override
  int get hashCode => _utc.hashCode;

  @override
  String toString() => key;
}

/// The day an instant falls on in Turkey. Turkey has kept UTC+3 the year
/// round since September 2016; before that it kept summer time, which this
/// does not follow ([turkeyOffsetKnown] says so).
LegalDay turkeyDay(DateTime instant) {
  final t = instant.toUtc().add(const Duration(hours: 3));
  return LegalDay(t.year, t.month, t.day);
}

/// Whether [turkeyDay] is exact for [instant]: from 7 September 2016, when
/// Turkey stopped turning its clocks back.
bool turkeyOffsetKnown(DateTime instant) =>
    !instant.toUtc().isBefore(DateTime.utc(2016, 9, 6, 21));
