import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;

/// Folio's criminal-sentence calculator: a faithful port of banaozel's
/// `server/ceza_hesap.py` (its `hesapla` and `metin`). It is deterministic so
/// the AI program never works out a sentence in its head: TCK 61 order
/// (base sentence, qualifying increases, qualifying reductions, attempt,
/// accessory, chain offence, provocation, age, discretionary reduction),
/// every version of the law between the event and the decision (TCK 7/2),
/// the HAGB / suspension / alternative-sanction thresholds, the limitation
/// period, mediation, prepayment, complaint and the court's jurisdiction.
///
/// The tables are not in this file: they come from
/// assets/mevzuat/ceza_tablosu.json, which tool/ceza/disa_aktar.py exports
/// from the Python module, so the two programs share one source of data.
/// The goldens in test/fixtures/ceza_altin.json.gz (tool/ceza/altin_uret.py)
/// hold Python's own answers and the test compares every one of them.
///
/// Input and output keys are Python's (Turkish), so the tool's description
/// and the server's stay the same. In the output a fraction of days is
/// `[numerator, denominator]`, a date "YYYY-MM-DD", a crime and a qualifying
/// circumstance their code. One year is 360 days and one month 30 (TCK 61/6
/// as Yargıtay applies it); life sentences are carried as large sentinels
/// that no rate multiplies.
class CriminalCalculator {
  CriminalCalculator._(this._t);

  static const asset = 'assets/mevzuat/ceza_tablosu.json';

  final _Tables _t;

  static Future<CriminalCalculator>? _loaded;

  static Future<CriminalCalculator> load() => _loaded ??= _read().then(parse);

  /// The asset; read from the project's own folder where there is no
  /// Flutter to give it (a test of the tools that starts none).
  static Future<String> _read() async {
    try {
      return await rootBundle.loadString(asset);
    } on FlutterError {
      return File(asset).readAsString();
    }
  }

  static CriminalCalculator parse(String raw) => CriminalCalculator._(
    _Tables.fromJson(jsonDecode(raw) as Map<String, Object?>),
  );

  /// The crime codes the table knows ("TCK 86/1", "6136 13/1"…), in table order.
  List<String> get crimeCodes => [for (final c in _t.crimes.values) c.code];

  /// Each crime code with its name, for a tool's description.
  Map<String, String> get crimeNames => {
    for (final c in _t.crimes.values) c.code: c.name,
  };

  /// The qualifying circumstances' codes, in TCK 61 order.
  List<String> get circumstanceCodes => [
    for (final n in _t.quals.values) n.code,
  ];

  /// Each circumstance code with the crimes it applies to.
  Map<String, List<String>> get circumstanceCrimes => {
    for (final n in _t.quals.values) n.code: List.unmodifiable(n.appliesTo),
  };

  /// Python's `hesapla(girdi)` in JSON form: {"hata": …} when the input
  /// cannot be computed, otherwise the full result. [today] stands for
  /// Python's `date.today()`, the decision date when the input names none.
  /// Throws [FormatException] where Python raises (a date that does not exist).
  Map<String, Object?> compute(Map<String, Object?> input, {DateTime? today}) {
    final r = _Engine(_t, today ?? DateTime.now()).run(input);
    return r.error != null ? {'hata': r.error} : r.toJson();
  }

  /// Python's `metin(girdi)`: the text the AI program reads. [freshness] is
  /// the table-freshness line; Python builds it from a server-side audit
  /// file Folio does not have, so the default is Python's line for "no audit".
  String text(
    Map<String, Object?> input, {
    DateTime? today,
    String? freshness,
  }) {
    final r = _Engine(_t, today ?? DateTime.now()).run(input);
    if (r.error != null) return r.error!;
    return _text(_t, r, freshness ?? noAuditLine);
  }

  /// `sure_yaz`: days as "X yıl Y ay Z gün", life sentences by name.
  static String formatDays(Rational days) => _duration(days);

  /// `kod_normal`: a crime or circumstance code in the table's spelling.
  String normalCode(Object? code) =>
      _Engine(_t, DateTime.now()).normalCode(code);

  /// `guncellik_satiri` when there is no audit record.
  static const noAuditLine =
      'TABLO GÜNCELLİĞİ: canlı metin denetimi kaydı yok — güncel aralığı '
      'mevzuat_getir ile teyit etmeden kesin sonuç yazma.';
}

// ─── exact arithmetic ─────────────────────────────────────────────────────

/// An exact fraction, always in lowest terms with a positive denominator,
/// like Python's `Fraction`. Days are never doubles: a third of a month must
/// stay ten days, and the flooring rules of TCK 61/6 need the exact value.
class Rational implements Comparable<Rational> {
  const Rational._(this.numerator, this.denominator);

  factory Rational(int numerator, [int denominator = 1]) {
    if (denominator == 0) throw ArgumentError('zero denominator');
    if (denominator < 0) {
      numerator = -numerator;
      denominator = -denominator;
    }
    final g = numerator.gcd(denominator);
    return Rational._(numerator ~/ g, denominator ~/ g);
  }

  factory Rational.fromJson(Object? v) {
    final l = v as List;
    return Rational((l[0] as num).toInt(), (l[1] as num).toInt());
  }

  static const zero = Rational._(0, 1);
  static const one = Rational._(1, 1);

  final int numerator;
  final int denominator;

  Rational operator +(Rational o) => Rational(
    numerator * o.denominator + o.numerator * denominator,
    denominator * o.denominator,
  );
  Rational operator -(Rational o) => Rational(
    numerator * o.denominator - o.numerator * denominator,
    denominator * o.denominator,
  );
  Rational operator *(Rational o) =>
      Rational(numerator * o.numerator, denominator * o.denominator);

  /// Python's `//`: the floor of the quotient.
  int floorDiv(Rational o) =>
      _floor(numerator * o.denominator, denominator * o.numerator);

  /// Python's `%`: what is left after [floorDiv], with the divisor's sign.
  Rational operator %(Rational o) => this - o * Rational(floorDiv(o));

  /// Python's `int(fraction)`: towards zero.
  int truncate() => numerator ~/ denominator;

  bool get isZero => numerator == 0;

  @override
  int compareTo(Rational o) =>
      (numerator * o.denominator).compareTo(o.numerator * denominator);
  bool operator <(Rational o) => compareTo(o) < 0;
  bool operator <=(Rational o) => compareTo(o) <= 0;
  bool operator >(Rational o) => compareTo(o) > 0;
  bool operator >=(Rational o) => compareTo(o) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  /// Python's `str(Fraction)`: "1/2", "-1/3", "2".
  @override
  String toString() =>
      denominator == 1 ? '$numerator' : '$numerator/$denominator';

  List<int> toJson() => [numerator, denominator];

  static int _floor(int a, int b) {
    if (b < 0) {
      a = -a;
      b = -b;
    }
    return (a - a % b) ~/ b;
  }
}

Rational _r(int n, [int d = 1]) => Rational(n, d);
Rational _months(int n) => Rational(n * 30);
Rational _years(int n) => Rational(n * 360);

const _ay = 30;
const _yil = 360;
final _muebbet = Rational(10000000);
final _agirMuebbet = Rational(20000000);
bool _life(Rational d) => d >= _muebbet;

// ─── dates (Python's `date`) ─────────────────────────────────────────────

/// A calendar day; throws where Python's `date(y, m, d)` raises ValueError.
DateTime _day(int y, int m, int d) {
  if (y < 1 || y > 9999 || m < 1 || m > 12 || d < 1 || d > _monthDays(y, m)) {
    throw FormatException('day is out of range for month: $y-$m-$d');
  }
  return DateTime.utc(y, m, d);
}

int _monthDays(int y, int m) {
  const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  final leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);
  return m == 2 && leap ? 29 : days[m - 1];
}

DateTime? _dateJson(Object? v) {
  if (v == null) return null;
  final p = (v as String).split('-');
  return _day(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// `f"{d:%d.%m.%Y}"` (glibc does not pad the year).
String _tr(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

String _two(int n) => n.toString().padLeft(2, '0');

bool _lt(DateTime a, DateTime b) => a.compareTo(b) < 0;
bool _le(DateTime a, DateTime b) => a.compareTo(b) <= 0;

final _d2005 = _day(2005, 6, 1);
final _d5377 = _day(2005, 7, 8);
final _d5560 = _day(2006, 12, 19);
final _d6352 = _day(2012, 7, 5);
final _d6459 = _day(2013, 4, 30);
final _d6455 = _day(2013, 4, 11);
final _d6545 = _day(2014, 6, 28);
final _d7242 = _day(2020, 4, 15);
final _d7255 = _day(2020, 11, 4);
final _d7331 = _day(2021, 7, 14);
final _d7406 = _day(2022, 5, 27);
final _d7593 = _day(2026, 8, 18);

/// `_tarihli`: the value in force on [day] (the last whose start is on or before it).
T _dated<T>(List<(DateTime?, T)> list, DateTime day) {
  var chosen = list.first.$2;
  for (final (start, value) in list) {
    if (start == null || _le(start, day)) chosen = value;
  }
  return chosen;
}

// ─── Python's string and truth rules ─────────────────────────────────────

/// Python's truthiness, for the flags a model may send as anything.
bool _truthy(Object? v) => switch (v) {
  null => false,
  bool b => b,
  num n => n != 0,
  String s => s.isNotEmpty,
  Iterable i => i.isNotEmpty,
  Map m => m.isNotEmpty,
  _ => true,
};

/// Python's `str(x)` for what JSON can carry.
String _str(Object? v) => switch (v) {
  null => 'None',
  true => 'True',
  false => 'False',
  double d when d == d.truncateToDouble() && d.isFinite => '${d.toInt()}.0',
  _ => '$v',
};

/// Python iterates a string by character and a map by key.
Iterable<Object?> _iter(Object? v) => switch (v) {
  String s => s.split(''),
  Map m => m.keys,
  Iterable i => i,
  _ => throw FormatException('not iterable: $v'),
};

const _pySpace = {
  0x09,
  0x0a,
  0x0b,
  0x0c,
  0x0d,
  0x1c,
  0x1d,
  0x1e,
  0x1f,
  0x20,
  0x85,
  0xa0,
  0x1680, //
  0x2000,
  0x2001,
  0x2002,
  0x2003,
  0x2004,
  0x2005,
  0x2006,
  0x2007,
  0x2008,
  0x2009,
  0x200a,
  0x2028, 0x2029, 0x202f, 0x205f, 0x3000,
};

/// Python's `str.strip(chars)`; whitespace by Python's own definition when [chars] is null.
String _strip(String s, [String? chars]) {
  bool drop(int c) =>
      chars == null ? _pySpace.contains(c) : chars.codeUnits.contains(c);
  var a = 0, b = s.length;
  while (a < b && drop(s.codeUnitAt(a))) {
    a++;
  }
  while (b > a && drop(s.codeUnitAt(b - 1))) {
    b--;
  }
  return s.substring(a, b);
}

String _rstrip(String s) {
  var b = s.length;
  while (b > 0 && _pySpace.contains(s.codeUnitAt(b - 1))) {
    b--;
  }
  return s.substring(0, b);
}

/// Python's `upper()`: Dart keeps ß and the ligatures, Python expands them.
String _upper(String s) {
  const special = {
    'ß': 'SS',
    'ﬀ': 'FF',
    'ﬁ': 'FI',
    'ﬂ': 'FL',
    'ﬃ': 'FFI',
    'ﬄ': 'FFL',
    'ﬅ': 'ST',
    'ﬆ': 'ST',
    'ŉ': 'ʼN', //
  };
  final u = s.toUpperCase();
  if (!special.keys.any(u.contains)) return u;
  return [for (final ch in u.split('')) special[ch] ?? ch].join();
}

/// Python's `lower()`: İ becomes i with a combining dot, as Python does.
String _lower(String s) => s.replaceAll('İ', 'i̇').toLowerCase();

// ─── tables ──────────────────────────────────────────────────────────────

class _Version {
  _Version.fromJson(Map<String, Object?> j)
    : start = _dateJson(j['bas']),
      low = Rational.fromJson(j['alt']),
      high = Rational.fromJson(j['ust']),
      fineAlternative = j['adli_para'] as bool,
      womanLow = j['kadin_alt'] == null
          ? null
          : Rational.fromJson(j['kadin_alt']),
      fineWith = j['adli_para_ek'] as String,
      source = j['kaynak'] as String,
      verified = j['dogrulandi'] as bool;

  final DateTime? start;
  final Rational low, high;
  final bool fineAlternative;
  final Rational? womanLow;
  final String fineWith, source;
  final bool verified;

  /// Value identity, as Python's frozen dataclass compares.
  late final String key = [
    start == null ? '' : _iso(start!),
    low,
    high,
    fineAlternative,
    womanLow,
    fineWith,
    source,
    verified,
  ].join('\u0001');

  Map<String, Object?> toJson() => {
    'bas': start == null ? null : _iso(start!),
    'alt': low.toJson(),
    'ust': high.toJson(),
    'adli_para': fineAlternative,
    'kadin_alt': womanLow?.toJson(),
    'adli_para_ek': fineWith,
    'kaynak': source,
    'dogrulandi': verified,
  };
}

class _Remorse {
  _Remorse.fromJson(Map<String, Object?> j)
    : name = j['ad'] as String,
      most = Rational.fromJson(j['en_cok']),
      fixed = j['sabit'] as bool,
      least = j['en_az'] == null ? null : Rational.fromJson(j['en_az']);

  final String name;
  final Rational most;
  final bool fixed;
  final Rational? least;
}

List<(DateTime?, Map<String, Rational>)> _floorTable(Object? v) => [
  for (final e in v as List)
    (
      _dateJson((e as List)[0]),
      {
        for (final x in (e[1] as Map).entries)
          '${x.key}': Rational.fromJson(x.value),
      },
    ),
];

class _Crime {
  _Crime.fromJson(Map<String, Object?> j)
    : code = j['kod'] as String,
      name = j['ad'] as String,
      versions = [
        for (final v in j['surumler'] as List)
          _Version.fromJson(v as Map<String, Object?>),
      ],
      complaint = j['sikayete_bagli'] as bool,
      mediation = j['uzlastirma'] as bool,
      mediationNote = j['uzlastirma_notu'] as String,
      prepaymentListed = j['onodeme_ozel'] as bool,
      complaintNote = j['sikayet_notu'] as String,
      negligent = j['taksirli'] as bool,
      bodilyIntent = j['vucut_kasten'] as bool,
      bentFloor = _floorTable(j['bent_asgari']),
      bentStart = {
        for (final e in (j['bent_baslangic'] as Map).entries)
          '${e.key}': _dateJson(e.value)!,
      },
      tableStart = _dateJson(j['tablo_baslangic']),
      tableNote = j['tablo_notu'] as String,
      remorse = j['etkin_pismanlik'] as bool,
      bentBefore = {
        for (final e in (j['bent_onceki'] as Map).entries)
          '${e.key}': (
            _dateJson((e.value as List)[0])!,
            _Version.fromJson(e.value[1] as Map<String, Object?>),
          ),
      },
      heavyCourtList = j['agir_ceza_listesi'] as bool,
      remorseSpecial = {
        for (final e in (j['etkin_ozel'] as Map).entries)
          '${e.key}': _Remorse.fromJson(e.value as Map<String, Object?>),
      },
      mediationBanned = j['uzlastirma_yasak'] as bool,
      repealedBents = {
        for (final e in (j['mulga_bentler'] as Map).entries)
          '${e.key}': ((e.value as List)[0] as String?, e.value[1] as String),
      },
      notes = j['notlar'] as String;

  final String code, name;
  final List<_Version> versions;
  final bool complaint, mediation;
  final String mediationNote;
  final bool prepaymentListed;
  final String complaintNote;
  final bool negligent, bodilyIntent;
  final List<(DateTime?, Map<String, Rational>)> bentFloor;
  final Map<String, DateTime> bentStart;
  final DateTime? tableStart;
  final String tableNote;
  final bool remorse;
  final Map<String, (DateTime, _Version)> bentBefore;
  final bool heavyCourtList;
  final Map<String, _Remorse> remorseSpecial;
  final bool mediationBanned;
  final Map<String, (String?, String)> repealedBents;
  final String notes;
}

class _Qual {
  _Qual.fromJson(Map<String, Object?> j)
    : code = j['kod'] as String,
      name = j['ad'] as String,
      least = Rational.fromJson(j['en_az']),
      most = Rational.fromJson(j['en_cok']),
      floors = _floorTable(j['asgari']),
      liftsComplaint = j['sikayeti_kaldirir'] as bool,
      liftsMediation = j['uzlastirmayi_kaldirir'] as bool,
      appliesTo = [for (final x in j['uygulanir'] as List) x as String],
      source = j['kaynak'] as String,
      fixedRange = [
        for (final e in j['sabit_ceza'] as List)
          (
            _dateJson((e as List)[0]),
            {
              for (final x in (e[1] as Map).entries)
                '${x.key}': _Version.fromJson(x.value as Map<String, Object?>),
            },
          ),
      ],
      rates = [
        for (final e in j['oran'] as List)
          (
            _dateJson((e as List)[0]),
            (Rational.fromJson((e[1] as List)[0]), Rational.fromJson(e[1][1])),
          ),
      ],
      mediationNote = j['uzlastirma_notu'] as String,
      fineWith = j['adli_para_ek'] as String;

  final String code, name;
  final Rational least, most;
  final List<(DateTime?, Map<String, Rational>)> floors;
  final bool liftsComplaint, liftsMediation;
  final List<String> appliesTo;
  final String source;
  final List<(DateTime?, Map<String, _Version>)> fixedRange;
  final List<(DateTime?, (Rational, Rational))> rates;
  final String mediationNote, fineWith;

  /// `_oran`: the rate on [day] (dated when the table has dated rates).
  (Rational, Rational) rate(DateTime day) =>
      rates.isNotEmpty ? _dated(rates, day) : (least, most);
}

typedef _Age = ({
  List<(DateTime?, Rational)> rate,
  List<(DateTime?, Rational)> cap,
  String text,
});

class _Tables {
  _Tables.fromJson(Map<String, Object?> j)
    : version = (j['surum'] as num).toInt(),
      crimes = {
        for (final c in j['suclar'] as List)
          (c as Map)['kod'] as String: _Crime.fromJson(c.cast()),
      },
      quals = {
        for (final n in j['nitelikli'] as List)
          (n as Map)['kod'] as String: _Qual.fromJson(n.cast()),
      },
      remorse = {
        for (final e in (j['etkin'] as Map).entries)
          '${e.key}': _Remorse.fromJson(e.value as Map<String, Object?>),
      },
      general = {
        for (final e in (j['genel'] as Map).entries)
          '${e.key}': (
            (e.value as Map)['ad'] as String,
            Rational.fromJson(e.value['en_az']),
            Rational.fromJson(e.value['en_cok']),
          ),
      },
      age = {
        for (final e in (j['yas'] as Map).entries)
          '${e.key}': (
            rate: [
              for (final x in (e.value as Map)['oran'] as List)
                (_dateJson((x as List)[0]), Rational.fromJson(x[1])),
            ],
            cap: [
              for (final x in e.value['azami'] as List)
                (_dateJson((x as List)[0]), Rational.fromJson(x[1])),
            ],
            text: e.value['aciklama'] as String,
          ),
      },
      conversion = {
        for (final e in (j['donusum'] as Map).entries)
          '${e.key}': [
            for (final x in e.value as List)
              (
                _dateJson((x as List)[0]),
                {
                  for (final t in (x[1] as Map).entries)
                    '${t.key}': (
                      Rational.fromJson((t.value as List)[0]),
                      Rational.fromJson(t.value[1]),
                    ),
                },
              ),
          ],
      },
      conversionName = {
        for (final e in (j['donusum_ad'] as Map).entries)
          '${e.key}': e.value as String,
      },
      noChain = {for (final x in j['zincirleme_yasak'] as List) x as String},
      baseFloor = {for (final x in j['temel_asgari'] as List) x as String},
      civilService = {
        for (final e in (j['dmk48_turu'] as Map).entries)
          '${e.key}': e.value as String,
      } {
    var i = 0;
    for (final k in quals.keys) {
      order[k] = i++;
    }
  }

  final int version;
  final Map<String, _Crime> crimes;
  final Map<String, _Qual> quals;
  final Map<String, _Remorse> remorse;
  final Map<String, (String, Rational, Rational)> general;
  final Map<String, _Age> age;
  final Map<String, List<(DateTime?, Map<String, (Rational, Rational)>)>>
  conversion;
  final Map<String, String> conversionName;
  final Set<String> noChain, baseFloor;
  final Map<String, String> civilService;
  final Map<String, int> order = {};
}

// ─── computation ─────────────────────────────────────────────────────────

/// `sure_yaz`: days → "X yıl Y ay Z gün" (the fraction of a day is dropped,
/// TCK 61/6); life sentences by name.
String _duration(Rational g) {
  if (g >= _agirMuebbet) return 'ağırlaştırılmış müebbet hapis';
  if (g >= _muebbet) return 'müebbet hapis';
  var days = g.truncate();
  final y = days ~/ _yil;
  final rest = days % _yil;
  final a = rest ~/ _ay;
  days = rest % _ay;
  final parts = [
    if (y != 0) '$y yıl',
    if (a != 0) '$a ay',
    if (days != 0) '$days gün',
  ];
  return parts.isEmpty ? '0 gün' : parts.join(' ');
}

/// `fikra_grubu`: 'TCK 86/3-e' → 'TCK 86/3' (a one-letter bent); null otherwise.
String? _paragraph(String code) =>
    RegExp(r'^(.+/\d+)-([a-zçğıöşü])$').firstMatch(code)?.group(1);

class _Scenario {
  _Scenario(this.value, this.steps);
  Rational value;
  final List<String> steps;
}

class _Entry {
  _Entry(
    this.day,
    this.version,
    this.low,
    this.high,
    this.scenarios,
    this.bentLow,
    this.qualifiedLow,
  );
  final DateTime day;
  final _Version version;
  final Rational low, high;
  final Map<String, _Scenario> scenarios;
  final Rational? bentLow;
  final Rational qualifiedLow;
  bool current = false;

  Map<String, Object?> toJson() => {
    'gun': _iso(day),
    'surum': version.toJson(),
    'alt': low.toJson(),
    'ust': high.toJson(),
    'senaryolar': {
      for (final e in scenarios.entries)
        e.key: {
          'ad': '',
          'deger': e.value.value.toJson(),
          'adimlar': List.of(e.value.steps),
        },
    },
    'bent_alt': bentLow?.toJson(),
    'nitelikli_alt': qualifiedLow.toJson(),
    if (current) 'guncel': true,
  };
}

class _Limitation {
  _Limitation(
    this.article,
    this.years,
    this.rate,
    this.normal,
    this.normalEnd,
    this.extended,
    this.extendedEnd,
  );
  final String article;
  final int years;
  final Rational rate;
  final String normal, extended;
  final DateTime normalEnd, extendedEnd;

  Map<String, Object?> toJson() => {
    'madde': article,
    'sure_yil': years,
    'oran': rate.toJson(),
    'olagan': normal,
    'olagan_bitis': _iso(normalEnd),
    'uzamis': extended,
    'uzamis_bitis': _iso(extendedEnd),
  };
}

class _Result {
  _Result.error(this.error);
  _Result();

  String? error;
  late _Crime crime;
  late DateTime event, decision;
  late List<_Entry> versions;
  late _Entry favourable;
  late _Limitation limitation;
  late bool complaint, mediation;
  late String mediationNote;
  late bool prepayment;
  late List<String> warnings;
  late List<_Qual> quals;
  late Map<String, bool> general;
  String? age, bent, remorse;
  late String hagb, suspension, shortTerm;
  late bool heavyCourt, noDetention;
  late String detentionNote;
  late bool counsel;

  Map<String, Object?> toJson() => {
    'suc': crime.code,
    'olay': _iso(event),
    'karar': _iso(decision),
    'surumler': [for (final x in versions) x.toJson()],
    'lehe': favourable.toJson(),
    'zamanasimi': limitation.toJson(),
    'sikayet': complaint,
    'uzlastirma': mediation,
    'uzlastirma_notu': mediationNote,
    'onodeme': prepayment,
    'uyari': List.of(warnings),
    'nitelikli': [for (final n in quals) n.code],
    'genel': Map.of(general),
    'yas': age,
    'bent': bent,
    'etkin': remorse,
    'hagb': hagb,
    'erteleme': suspension,
    'kisa_sureli': shortTerm,
    'agir_ceza': heavyCourt,
    'tutuklama_yasagi': noDetention,
    'tutuklama_notu': detentionNote,
    'zorunlu_mudafi': counsel,
  };
}

class _Engine {
  _Engine(this.t, DateTime now) : today = _day(now.year, now.month, now.day);

  final _Tables t;
  final DateTime today;

  // ─── input helpers ───

  /// `tarih_coz`.
  DateTime? parseDate(Object? x) {
    final s = _strip(_truthy(x) ? _str(x) : '');
    if (s.isEmpty) return null;
    var m = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(s);
    if (m != null) {
      return _day(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
    }
    m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (m != null) {
      return _day(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }
    return null;
  }

  /// `kod_normal`: 'tck 86/3 e', 'TCK m.86/3-e', '86/1' → 'TCK 86/3-e' / 'TCK 86/1';
  /// a special law keeps its four-digit number: '6136 s.K. m.13/1' → '6136 13/1'.
  String normalCode(Object? x) {
    var s = _upper(_strip(_truthy(x) ? _str(x) : ''))
        .replaceAll('M.', '')
        .replaceAll('MADDE', '');
    s = s.replaceFirst(
      RegExp(
        r'^\s*(5237\s*(SAYILI|S\.?\s*K\.?)?\s*(KANUN(UN)?)?\s*)?(TCK|TÜRK CEZA KANUNU)?\s*',
      ),
      '',
    );
    s = s.replaceFirstMapped(RegExp(r'^(\d{4})\s*/\s*'), (m) => '${m[1]} ');
    s = s.replaceFirstMapped(
      RegExp(r'^(\d{4})\s+(SK|S\.?\s*K\.?)\s+'),
      (m) => '${m[1]} ',
    );
    s = s.replaceFirstMapped(
      RegExp(r'^(\d{4}\s+\d+)-(\d+)$'),
      (m) => '${m[1]}/${m[2]}',
    );
    var prefix = 'TCK';
    final k = RegExp(
      r'\s*(\d{4})\s*(?:SAYILI|S\.\s*K\.?|S\.K\.?)?\s*(?:KANUN(?:UN)?)?\s*[,.]?\s*',
    ).matchAsPrefix(s);
    if (k != null && k.end < _rstrip(s).length) {
      prefix = k[1]!;
      s = s.substring(k.end);
    }
    final m = RegExp(
      r'^(\d+)\s*(?:/\s*(\d+))?\s*(?:[-\s(]*([A-ZÇĞİÖŞÜ])\)?)?\s*(?:-\s*(\d))?$',
    ).firstMatch(_strip(s));
    if (m == null) return '$prefix ${_strip(s)}';
    var code = '$prefix ${m[1]}${m[2] != null ? '/${m[2]}' : ''}';
    if (m[3] != null) {
      code += '-${_lower(m[3]!)}';
    } else if (m[4] != null) {
      code += '-${m[4]}';
    }
    return code;
  }

  /// `suc_coz`: 'TCK 158/1-f' → ('TCK 158/1', 'f'); 'TCK 144/1' → 'TCK 144'.
  (String, String?) parseCrime(Object? x) {
    final code = normalCode(x);
    if (t.crimes.containsKey(code)) return (code, null);
    final m = RegExp(
      r'^(TCK \d+(?:/\d+)?)-([A-Za-zÇĞİÖŞÜçğıöşü](?:-[A-Za-zÇĞİÖŞÜçğıöşü]+)?)$',
    ).firstMatch(code);
    if (m != null && t.crimes.containsKey(m[1])) {
      return (m[1]!, _lower(m[2]!).replaceAll('i̇', 'i'));
    }
    if (code.endsWith('/1') &&
        t.crimes.containsKey(code.substring(0, code.length - 2))) {
      return (code.substring(0, code.length - 2), null);
    }
    return (code, null);
  }

  // ─── `_hesapla`: one version of the law ───

  _Entry computeVersion(
    _Crime crime,
    _Version version,
    List<_Qual> quals,
    Map<String, bool> general,
    String? age,
    bool woman,
    DateTime day,
    String? bent,
    String? remorse,
  ) {
    var low = (woman && version.womanLow != null && !version.womanLow!.isZero)
        ? version.womanLow!
        : version.low;
    final bentLow = (bent != null && crime.bentFloor.isNotEmpty)
        ? _dated(crime.bentFloor, day)[bent]
        : null;
    if (bentLow != null && !bentLow.isZero && low < bentLow) low = bentLow;
    final rates = {for (final n in quals) n.code: n.rate(day)};
    // Several bents of one paragraph (86/3-a + 86/3-e) increase once (CGK 12.07.2023, 2022/171 E.,
    // 2023/396 K.); with different rates the highest. The flags still look at every bent.
    final skip = <String>{};
    for (final group in {
      for (final n in quals) _paragraph(n.code),
    }.whereType<String>()) {
      final members = [
        for (final n in quals)
          if (_paragraph(n.code) == group && rates[n.code]!.$2 > Rational.zero)
            n,
      ];
      if (members.length > 1) {
        var kept = members.first;
        for (final n in members.skip(1)) {
          final a = rates[n.code]!, b = rates[kept.code]!;
          if (a.$2 > b.$2 || (a.$2 == b.$2 && a.$1 > b.$1)) kept = n;
        }
        skip.addAll([
          for (final n in members)
            if (n != kept) n.code,
        ]);
      }
    }
    // TCK 61: the order must not depend on the input's. Circumstances that set the base sentence's floor
    // first, then table order; increases before reductions (61/4).
    final sorted = List.of(quals)
      ..sort((a, b) {
        final ka = t.baseFloor.contains(a.code) ? 0 : 1,
            kb = t.baseFloor.contains(b.code) ? 0 : 1;
        if (ka != kb) return ka.compareTo(kb);
        return (t.order[a.code] ?? 999).compareTo(t.order[b.code] ?? 999);
      });
    final increases = [
      for (final n in sorted)
        if (rates[n.code]!.$1 >= Rational.zero) n,
    ];
    final reductions = [
      for (final n in sorted)
        if (rates[n.code]!.$1 < Rational.zero) n,
    ];
    final third = sorted.any((n) => n.code.startsWith('TCK 86/3'));
    final hasBentLow = bentLow != null && !bentLow.isZero;

    _Scenario walk(
      Rational start,
      String incEnd,
      String redEnd, {
      bool plain = false,
    }) {
      final label = hasBentLow && start == bentLow
          ? ' (${crime.code}-$bent bendi asgari)'
          : '';
      final s = _Scenario(start, ['temel ceza ${_duration(start)}$label']);
      var d = start;

      bool convert(String key) {
        if (!_life(d)) return false;
        final kind = d >= _agirMuebbet ? 'agir' : 'muebbet';
        final (a, u) = _dated(t.conversion[key]!, day)[kind]!;
        d = redEnd == 'cok' ? a : u;
        s.steps.add(
          '${t.conversionName[key]}: ${_duration(kind == 'agir' ? _agirMuebbet : _muebbet)} '
          'yerine ${_duration(a)}–${_duration(u)} → ${_duration(d)}',
        );
        return true;
      }

      for (final n in [...increases, ...reductions]) {
        if (skip.contains(n.code)) {
          s.steps.add(
            '${n.code}: aynı fıkranın başka bendi uygulandı — bir kez artırım',
          );
          continue;
        }
        if (n.fixedRange.isNotEmpty &&
            _dated(n.fixedRange, day).containsKey(crime.code)) {
          s.steps.add(
            '${n.code}: bu tarihte oran değil ayrı ceza aralığı (temel ceza olarak alındı)',
          );
          continue;
        }
        if (_life(d) && n.floors.isEmpty) {
          s.steps.add('${n.code}: müebbet cezada oran uygulanmaz');
          continue;
        }
        final (least, most) = rates[n.code]!;
        if (n.rates.isNotEmpty && least.isZero && most.isZero) {
          s.steps.add('${n.code} bu tarihte yürürlükte değil');
          continue;
        }
        if (plain && least < Rational.zero && least != most) continue;
        var rate = incEnd == 'cok' ? most : least;
        if (least < Rational.zero) rate = redEnd == 'cok' ? least : most;
        if (!rate.isZero) {
          d = d * (Rational.one + rate);
          s.steps.add(
            '${n.code} (${rate > Rational.zero ? '+' : ''}$rate) → ${_duration(d)}',
          );
        }
        if (n.floors.isNotEmpty) {
          final table = _dated(n.floors, day);
          final floor = third && table.containsKey('86/3')
              ? table['86/3']
              : table[crime.code];
          if (floor != null && !floor.isZero && d < floor) {
            d = floor;
            s.steps.add('${n.code} asgari sınır → ${_duration(d)}');
          }
        }
      }
      if (plain) {
        s.value = d;
        return s;
      }
      for (final key in const [
        'tesebbus',
        'yardim_eden',
        'zincirleme',
        'haksiz_tahrik',
      ]) {
        if (general[key] != true) continue;
        if (key != 'zincirleme' && convert(key)) continue;
        if (_life(d)) {
          s.steps.add('Zincirleme suç: müebbet cezada artırım uygulanmaz');
          continue;
        }
        final (name, least, most) = t.general[key]!;
        final rate = key == 'zincirleme'
            ? (incEnd == 'cok' ? most : least)
            : (redEnd == 'cok' ? least : most);
        d = d * (Rational.one + rate);
        s.steps.add('$name ($rate) → ${_duration(d)}');
        if (key == 'yardim_eden' && d > _years(8)) {
          d = _years(8);
          s.steps.add('TCK 39/1: yardım edene ceza sekiz yılı geçemez');
        }
      }
      if (age != null && t.age.containsKey(age) && convert(age)) {
        // converted to the law's range
      } else if (age != null && t.age.containsKey(age)) {
        final a = t.age[age]!;
        final rate = _dated(a.rate, day);
        d = d * (Rational.one + rate);
        s.steps.add('Yaş küçüklüğü ($rate) → ${_duration(d)}');
        final cap = _dated(a.cap, day);
        if (d > cap) {
          d = cap;
          s.steps.add('TCK 31 azami → ${_duration(d)}');
        }
      }
      if (remorse != null && !_life(d)) {
        // Crime-specific reduction, before the discretionary one. "… indirilir" (248, 269/1-2) is fixed;
        // "… kadarı indirilir/indirilebilir" discretionary; 221/4's mandatory range has its own lower end.
        final r = crime.remorseSpecial[remorse] ?? t.remorse[remorse]!;
        final Rational rate;
        if (r.least != null) {
          rate = redEnd == 'cok' ? r.most : r.least!;
        } else {
          rate = (r.fixed || redEnd == 'cok') ? r.most : Rational.zero;
        }
        if (!rate.isZero) {
          d = d * (Rational.one + rate);
          s.steps.add('${r.name} ($rate) → ${_duration(d)}');
        }
      }
      if (general['takdiri_indirim'] == true && _life(d)) {
        if (redEnd == 'cok') {
          // TCK 62: aggravated life → life; life → 25 years.
          final next = d >= _agirMuebbet ? _muebbet : _years(25);
          s.steps.add(
            'Takdiri indirim (TCK 62): ${_duration(d)} yerine ${_duration(next)}',
          );
          d = next;
        }
      } else if (general['takdiri_indirim'] == true) {
        final (name, least, most) = t.general['takdiri_indirim']!;
        final rate = redEnd == 'cok' ? least : most;
        if (!rate.isZero) {
          d = d * (Rational.one + rate);
          s.steps.add('$name ($rate) → ${_duration(d)}');
        }
      }
      if (!_life(d) && d > _years(30) && !_lt(day, _d5377)) {
        d = _years(30);
        s.steps.add(
          'TCK 61/7: süreli hapiste sonuç ceza otuz yılı geçemez → 30 yıl',
        );
      }
      s.value = d;
      return s;
    }

    final scenarios = {
      'en_az': walk(low, 'az', 'cok'),
      'alt_artirim_en_cok': walk(low, 'cok', 'cok'),
      'alt_indirimsiz': walk(low, 'cok', 'az'),
      'en_cok': walk(version.high, 'cok', 'az'),
    };
    // CMK 150/3: the crime type's floor, circumstances at their lowest rate, general rules left out.
    final qualifiedLow = walk(low, 'az', 'az', plain: true).value;
    return _Entry(
      day,
      version,
      low,
      version.high,
      scenarios,
      bentLow,
      qualifiedLow,
    );
  }

  /// `_zamanasimi`: TCK 66/1 (upper limit with the circumstances, 66/3-4), 66/2 age, 67/4 extension.
  _Limitation limitation(Rational upper, String? age, DateTime event) {
    final int years;
    if (upper >= _agirMuebbet) {
      years = 30;
    } else if (upper >= _muebbet) {
      years = 25;
    } else if (upper >= _years(20)) {
      years = 20;
    } else if (upper > _years(5)) {
      years = 15;
    } else {
      years = 8;
    }
    const article = {
      30: '66/1-a',
      25: '66/1-b',
      20: '66/1-c',
      15: '66/1-d',
      8: '66/1-e',
    };
    final rate =
        {'12-15': _r(1, 2), '15-18': _r(2, 3)}[age ?? ''] ?? Rational.one;
    final days = Rational(years) * rate * Rational(_yil);
    final extended = days * _r(3, 2);
    DateTime add(Rational g) {
      final ys = g.floorDiv(Rational(_yil));
      final ms = (g % Rational(_yil)).floorDiv(Rational(_ay));
      var y = event.year + ys, m = event.month + ms;
      y += Rational(m - 1, 12).floorDiv(Rational.one);
      m = (m - 1) % 12 + 1;
      try {
        return _day(y, m, event.day);
      } on FormatException {
        return _day(y, m, 28);
      }
    }

    return _Limitation(
      article[years]!,
      years,
      rate,
      _duration(days),
      add(days),
      _duration(extended),
      add(extended),
    );
  }

  static String threshold(
    Rational least,
    Rational lowMost,
    Rational lowNoReduction,
    Rational limit,
  ) {
    if (lowNoReduction <= limit) {
      return 'alt sınırdan kurulursa artırım oranı ne olursa olsun ve indirim olmasa da eşiğin altında';
    }
    if (lowMost <= limit) {
      return 'alt sınırdan kurulur ve takdire bağlı indirimler (ör. TCK 62) uygulanırsa artırım oranı '
          'ne olursa olsun eşiğin altında; indirim olmazsa üstünde';
    }
    if (least <= limit) {
      return 'ancak alt sınırdan, artırımlar en düşük ve indirimler en yüksek tutulursa eşiğin altında; oranlara bağlı';
    }
    return 'en lehe hesapta bile eşiğin üstünde';
  }

  // ─── `hesapla` ───

  _Result run(Map<String, Object?> input) {
    final event = parseDate(input['olay_tarihi']);
    final decision = parseDate(input['karar_tarihi']) ?? today;
    var (code, bentCode) = parseCrime(input['suc']);
    final bentRaw = _strip(
      _lower(_strip(_truthy(input['bent']) ? _str(input['bent']) : '')),
      '()',
    );
    String? bent = bentRaw.isNotEmpty ? bentRaw : bentCode;
    final preWarnings = <String>[];
    if (t.crimes.containsKey(code) &&
        bent != null &&
        t.crimes[code]!.repealedBents.containsKey(bent)) {
      final (target, note) = t.crimes[code]!.repealedBents[bent]!;
      if (target == null) return _Result.error('$code-$bent: $note.');
      preWarnings.add('$code-$bent: $note.');
      (code, bent) = parseCrime(target);
    }
    if (!t.crimes.containsKey(code)) {
      return _Result.error(
        "'${_str(input['suc'])}' tabloda yok. Tablodaki suçlar: ${t.crimes.keys.join(', ')}. "
        'Tabloda olmayan suçta ceza aralığını canlı madde metninden ver; hesap doğrulanmamış sayılır.',
      );
    }
    if (event == null) {
      return _Result.error(
        'olay_tarihi gerekli (GG.AA.YYYY). Lehe kanun ve zamanaşımı ona göre hesaplanır.',
      );
    }
    final crime = t.crimes[code]!;
    final quals = <_Qual>[];
    final w = List.of(preWarnings);
    final qualInput = _truthy(input['nitelikli'])
        ? _iter(input['nitelikli']).toList()
        : const <Object?>[];
    for (final k in qualInput) {
      final n = t.quals[normalCode(k)];
      if (n == null) {
        w.add("'${_str(k)}' nitelikli hal tablosunda yok; hesaba katılmadı.");
        continue;
      }
      if (n.appliesTo.isNotEmpty && !n.appliesTo.contains(code)) {
        w.add('${n.code} $code için uygulanmaz; hesaba katılmadı.');
        continue;
      }
      if (quals.contains(n)) {
        // The same circumstance twice is not a second increase (TCK 61).
        w.add('${n.code} birden fazla yazılmış; bir kez uygulandı.');
        continue;
      }
      quals.add(n);
    }
    final general = {for (final k in t.general.keys) k: _truthy(input[k])};
    if (general['tesebbus']! && code.startsWith('5607 ')) {
      general['tesebbus'] = false;
      w.add(
        '5607 m.3/22: kaçakçılık fiilleri teşebbüs aşamasında kalsa bile tamamlanmış gibi cezalandırılır; '
        'teşebbüs indirimi uygulanmadı.',
      );
    }
    if (general['zincirleme']! && t.noChain.contains(code)) {
      general['zincirleme'] = false;
      w.add(
        'TCK 43/3: kasten öldürme, kasten yaralama, işkence ve yağmada zincirleme suç hükmü uygulanmaz; '
        'hesaba katılmadı.',
      );
    }
    final ageIn = input['fail_yas_grubu'];
    final String? age = ageIn is String && t.age.containsKey(ageIn)
        ? ageIn
        : null;
    final woman = _truthy(input['kadina_karsi']);
    final remorseIn = input['etkin_pismanlik'];
    String? remorse = _truthy(remorseIn)
        ? (remorseIn is String ? remorseIn : _str(remorseIn))
        : null;
    final special = crime.remorseSpecial;
    if (remorse == 'sorusturma_oncesi' &&
        !special.containsKey(remorse) &&
        (special.containsKey('kovusturma_oncesi') || special.isEmpty)) {
      remorse = 'kovusturma_oncesi'; // 168/1 "before prosecution" also covers the investigation
    }
    if (remorse != null &&
        special.isNotEmpty &&
        !special.containsKey(remorse)) {
      w.add(
        "$code için '$remorse' aşamasında etkin pişmanlık hükmü yok "
        '(var olanlar: ${special.keys.join(', ')}); uygulanmadı.',
      );
      remorse = null;
    }
    if (remorse != null &&
        code.startsWith('5607 ') &&
        (code == '5607 3/7' ||
            qualInput.map(normalCode).contains('5607 4/1'))) {
      w.add(
        '5607 m.5/2: ithali yasak eşya (3/7) ve örgüt faaliyeti (4/1) hâlinde etkin pişmanlık indirimi yok; '
        'mükerrirde de uygulanmaz.',
      );
      remorse = null;
    }
    if (remorse != null && code.startsWith('5607 ') && _lt(event, _d7242)) {
      w.add(
        '5607 m.5/2 7242 ile (15.04.2020) yeniden düzenlendi; olay öncesi rejim tabloda yok — teyit et.',
      );
    }
    if (remorse == 'kovusturmada' && code.startsWith('5607 ')) {
      w.add(
        '5607 m.5/2: soruşturmada savcı ihtar YAPMADIYSA kovuşturmadaki ödeme 1/2 indirim gerektirir '
        "(7. CD 27.11.2025, 2022/632 E., 2025/14650 K.) — o hâlde 'kovusturmada_ihtarsiz' ile hesapla.",
      );
    }
    if (remorse != null && code.startsWith('5607 ')) {
      w.add(
        '5607 m.5/3: fail mükerrirse m.5/2 etkin pişmanlık indirimi uygulanmaz.',
      );
    }
    if ((code == '5607 3/16' || code == '5607 3/18') && _lt(event, _d7255)) {
      w.add(
        "Makaron ve yaprak sigara kâğıdı 3/16 ve 3/18'e 7255 s.K. ile 04.11.2020'de eklendi; konu bunlarsa "
        'öncesindeki fiil bu fıkradan cezalandırılamaz (TCK 7/1).',
      );
    }
    if (remorse != null &&
        ((!t.remorse.containsKey(remorse) && !special.containsKey(remorse)) ||
            !crime.remorse)) {
      w.add(
        "Etkin pişmanlık ('$remorse') $code için TCK 168 kapsamında hesaplanmadı"
        "${t.remorse.containsKey(remorse) ? '' : " (değer: 'kovusturma_oncesi' | 'kovusturmada')"}.",
      );
      remorse = null;
    }
    if (crime.tableStart != null && _lt(event, crime.tableStart!)) {
      w.add('Olay ${_tr(crime.tableStart!)} öncesi: ${crime.tableNote}');
    }
    if (bent != null &&
        bent.isNotEmpty &&
        crime.bentStart.containsKey(bent) &&
        _lt(event, crime.bentStart[bent]!)) {
      w.add(
        "$code-$bent bendi olay tarihinde yoktu (${_tr(crime.bentStart[bent]!)}'de eklendi); "
        'fiil olay tarihinde temel suç kapsamında olabilir — lehe kanun ayrıca değerlendirilmeli.',
      );
    }
    if (crime.bentFloor.isNotEmpty && bent == null) {
      w.add(
        '$code: bent verilmedi; (e), (f), (j), (k), (l) bentlerinde alt sınır yükselir — bent belirt.',
      );
    }
    final codes = {for (final n in quals) n.code};
    if (codes.contains('TCK 87/3') && _lt(event, _d5560)) {
      w.add(
        "87/3 5560 s.K. (RG 19.12.2006) öncesi oran değil 'bir yıldan altı yıla' sabit aralıktı — o "
        'sürüm bu aralıkla hesaplandı; 86/3 artırımının eski 87/3 aralığına uygulanışını teyit et.',
      );
    }
    if (quals.any(
          (n) => n.floors.isNotEmpty && !t.baseFloor.contains(n.code),
        ) &&
        quals.any((n) => n.rate(event).$1 < Rational.zero)) {
      w.add(
        'Asgari sınır koyan nitelikli hâl ile nitelikli indirim birlikte: TCK 61/4 sırasıyla önce artırım ve '
        'asgari sınır, SONRA indirim uygulandı (sonuç asgari sınırın altına inebilir). İndirimden sonra da '
        'asgari sınırın korunup korunmadığını içtihatla teyit et.',
      );
    }
    if (code == 'TCK 235/1' && _lt(event, _d6459)) {
      w.add(
        '6459 (30.04.2013) öncesi cebir/tehdit cezayı ARTIRMIYORDU; yarı artırım yalnız ZARAR doğmuşsa '
        '(eski 235/3). Eski sürüm satırı (7 yıl 6 ay–18 yıl) zarar doğmuş hâldir; zarar doğmamış cebir/'
        "tehditte eski aralık beş yıldan on iki yıla — o hâlde 'TCK 235/3-b' ile karşılaştır.",
      );
    }
    if (code == '5607 3/18' && _le(_d6455, event) && _lt(event, _d6545)) {
      w.add(
        '6455 döneminde (11.04.2013–27.06.2014) TAKLİT/sahte bandrollü ürünü ticari amaçla bulundurma/satma '
        'ayrı fıkradaydı (3/19 ikinci cümle): iki yıldan beş yıla ve on bin güne kadar adlî para — fiil '
        'buysa lehe olan o aralıktır; tablo bandrolsüz hâli (üç yıldan altı yıla) hesapladı.',
      );
    }
    if (_le(_d2005, event) && _lt(event, _d5377)) {
      w.add(
        'Olay 01.06–07.07.2005: 5377 öncesi TCK ilk metni. 125/4, 150/2, 168 (kovuşturmadan önce zorunlu '
        '⅓–⅔, yağmada ⅙–⅓ indirim), 43/3, 87/1-2 atfı ve 82/1-h/i farklıydı; tablo 5377 sonrasını hesaplar — '
        'ilk metin (özellikle 168) lehe olabilir, teyit et.',
      );
    }
    if (codes.contains('TCK 86/3-a') && _lt(event, _d7331)) {
      w.add(
        "86/3-a'ya 'boşandığı eş' 7331 s.K. ile 14.07.2021'de eklendi; mağdur boşandığı eşse öncesindeki "
        "olayda 86/3-a artırımı uygulanmaz (TCK 7/1) — o hâlde 86/3-a'yı çıkararak hesapla.",
      );
    }
    if (code == 'TCK 133/3' && _lt(event, _d6352)) {
      w.add(
        "133/3'ün fiil kapsamı 6352 (05.07.2012) ile değişti: ilk metin 133/1-2 yoluyla elde edilen bilgiden "
        "'yarar sağlama' ve 'başkasına verme'yi (salt dinlemeyle elde edilen dâhil) cezalandırıyordu; bugünkü "
        'metin yalnız KAYIT suretiyle elde edilen verilerin hukuka aykırı İFŞASINI kapsar. Eski fiil bugünkü '
        'metne girmiyorsa TCK 7/1 — iki metni fiile göre karşılaştır.',
      );
    }
    if (code == 'TCK 191/1' && _lt(event, _d6545)) {
      w.add(
        '6545 (28.06.2014) öncesi uyuşturucu KULLANMA fiili ayrıca suç değildi; yalnız kullanmak için '
        'satın alma, kabul ve bulundurma cezalandırılıyordu (TCK 7/1).',
      );
    }
    // Counter keeps the order in which each paragraph first appears.
    final groups = <String?, int>{};
    for (final n in quals) {
      if (n.rate(event).$2 > Rational.zero) {
        final g = _paragraph(n.code);
        groups[g] = (groups[g] ?? 0) + 1;
      }
    }
    for (final e in groups.entries) {
      if (e.key != null && e.value > 1 && e.key != 'TCK 188/4') {
        w.add(
          "${e.key}'ün birden fazla bendi birlikte: aynı fıkradaki bentler için bir kez artırım yapıldı "
          '(CGK 12.07.2023, 2022/171 E., 2023/396 K.; oranlar farklıysa en yükseği). Diğer bent temel '
          'cezanın alt sınırdan uzaklaştırılmasında gözetilebilir — zincirleme suçta gözetilemez; teyit et.',
        );
      }
    }
    if (codes.contains('TCK 188/4-a') && codes.contains('TCK 188/4-b')) {
      quals.removeWhere((n) => n.code == 'TCK 188/4-b');
      codes.remove('TCK 188/4-b');
      const cgk = 'CGK 12.07.2023, 2022/171 E., 2023/396 K.';
      w.add(
        "188/4'ün (a) ve (b) bentleri birlikte: aynı fıkradaki bentler için bir kez artırım yapılır ($cgk); "
        '${general['zincirleme'] == true ? 'ZİNCİRLEME suçta (a) ve (b) farklı tarihlerde ihlal edildiyse bu, 43. madde kapsamında '
                  'değerlendirilir — temel cezanın alt sınırdan uzaklaştırılmasında AYRICA gözetilemez '
                  '(mükerrer değerlendirme yasağı, aynı karar).' : 'ikinci hâlin temel cezanın belirlenmesinde gözetilip gözetilemeyeceği somut olaya bağlı — '
                  'zincirleme suçta gözetilemez (aynı karar); teyit et.'}',
      );
    }
    if (_lt(event, _d2005)) {
      w.add(
        'Olay 01.06.2005 öncesi: 765 sayılı TCK yürürlükteydi; lehe kanun için 765 ile 5237 (5252 m.9) '
        'karşılaştırılmalı — bu araç yalnız 5237 sürümlerini hesaplar.',
      );
    }
    if (code == 'TCK 82/1' && (bent == null || bent.isEmpty)) {
      if (woman) {
        bent = 'f';
        w.add(
          "82/1: bent verilmedi, kadına karşı işaretli → 'f' (kadına karşı) sayıldı.",
        );
      } else {
        w.add(
          "82/1: bent verilmedi — sonradan genişleyen bentlerde ('d-bosanmis', 'f') eski olay 81 "
          '(müebbet) olabilir; bendi belirt.',
        );
      }
    }
    if (code == 'TCK 82/1' && bent == 'f' && _lt(event, _d7406)) {
      w.add(
        "82/1-f olay tarihinde yalnız 'gebe olduğu bilinen kadına karşı' idi (7406, 27.05.2022): gebe "
        'olmayan kadına karşı eski metin 81 (müebbet) — öyle hesaplandı. Mağdur gebe ve fail biliyorsa '
        "bent='f-gebe' ver (ilk metinden beri ağırlaştırılmış müebbet).",
      );
    }
    if (code == 'TCK 82/1' && bent == 'd' && _lt(event, _d7331)) {
      w.add(
        "82/1-d'de 'boşandığı eş' 7331 ile 14.07.2021'de eklendi: mağdur boşanılmış eşse bent='d-bosanmis' "
        "ver (öncesi 81 — müebbet); üstsoy/altsoy/eş/kardeş için 'd' doğru.",
      );
    }
    final consciousNegligence =
        code.startsWith('TCK 89') &&
        codes.contains('TCK 22/3') &&
        (code != 'TCK 89/1' ||
            codes.contains('TCK 89/2') ||
            codes.contains('TCK 89/3'));
    if (consciousNegligence) {
      w.add(
        'TCK 89/5: birinci fıkradaki yalın yaralama dışında bilinçli taksirde şikâyet aranmaz.',
      );
    }
    if (const [
          'TCK 103',
          'TCK 104',
          'TCK 105/1-2',
          'TCK 233/1',
          'TCK 233/3',
        ].any(code.startsWith) ||
        const ['TCK 102/3', 'TCK 86/3-a', 'TCK 109/3'].any(codes.contains) ||
        (code == 'TCK 82/1' && (bent == 'd' || bent == 'e'))) {
      w.add(
        'TCK 66/6: çocuğa karşı üstsoy ya da üzerinde hüküm ve nüfuzu olan kişi tarafından işlendiyse '
        'dava zamanaşımı çocuğun on sekiz yaşını bitirdiği günden işler — çıktıdaki bitiş tarihlerini '
        'buna göre düzelt.',
      );
    }
    if (general['tesebbus'] == true) {
      w.add(
        'Teşebbüste dava zamanaşımı: tamamlanmış suçun üst sınırına mı, 35/2 ile indirilmiş üst sınıra mı '
        'göre belirleneceğine dair yerleşik içtihat bulunamadı (1 Ekim 2026 arşiv taraması) — araç '
        'tamamlanmış suçun üst sınırını esas aldı; teyit et.',
      );
    }
    if (codes.contains('TCK 109/3') && _lt(event, _d7331)) {
      w.add(
        "109/3-e'deki 'boşandığı eş' 7331 s.K. ile 14.07.2021'de eklendi; öncesinde boşanılan eşe karşı "
        'işlenmesi 109/3 artırımı gerektirmez.',
      );
    }
    if (codes.contains('TCK 188/3-2') && _lt(event, _d6545)) {
      w.add(
        "188/3 ikinci cümle (çocuğa satış, on beş yıl) 6545 ile 28.06.2014'te geldi; öncesinde yok.",
      );
    }
    if (code == 'TCK 191/1' && _lt(event, _d6545) && _le(_d6545, decision)) {
      w.add(
        "6545 geçici m.7: 28.06.2014'te süren 191 kovuşturmalarında tedbire devam edilir ya da HAGB "
        'verilir — geçiş hükmünü uygula.',
      );
    }
    if (codes.contains('TCK 188/4-a')) {
      w.add(
        '188/4-a madde listesi değişti: sentetik kannabinoid 04.04.2015 (6638), sentetik katinon/opioid/'
        'amfetamin 05.04.2023 (7445) — madde olay tarihinde listede değilse artırım uygulanmaz.',
      );
    }
    if (codes.contains('TCK 142/3-2') && _lt(event, _d6352)) {
      w.add(
        "6352 (05.07.2012) öncesi 142/3 örgüt hâli artırım değil 'onbeş yıla kadar hapis ve onbin güne kadar "
        "adlî para' idi — tablodaki eski sürüm satırı bunu göstermez (üst sınır 15 yıl; alt sınır içtihatla "
        'doğrulanmadı). Zamanaşımı her iki hâlde 15 yıl.',
      );
    }
    if (age != null &&
        (codes.contains('TCK 87/2') ||
            code == 'TCK 81' ||
            code == 'TCK 82/1') &&
        !_lt(event, _d7593)) {
      w.add(
        "TCK 31/4 (7593, 18.08.2026): kasten öldürme ve 87/2-4'te 15-18 yaşa 31/3 indirimi UYGULANMAYABİLİR; "
        '12-15 yaşa 31/2 yerine 31/3 uygulanabilir — hesap indirimli kuruldu, mahkemenin '
        'takdirine bağlı.',
      );
    }
    if (code == 'TCK 151/1' &&
        codes.contains('TCK 152/3') &&
        !codes.contains('TCK 152/2')) {
      w.add(
        "152/3 'yukarıdaki fıkralar' (152/1-2) cezasını artırır; 151/1 ile tek başına uygulanması teyit edilmeli.",
      );
    }

    // Every version in force from the EVENT to the DECISION is computed (an intermediate law may be the
    // milder one). The circumstances' floors and rates are dated too, so their change days count.
    final days = <DateTime>{event};
    void addDay(DateTime? d) {
      if (d != null && _lt(event, d) && _le(d, decision)) days.add(d);
    }

    for (final s in crime.versions) {
      addDay(s.start);
    }
    for (final n in quals) {
      for (final x in n.floors) {
        addDay(x.$1);
      }
      for (final x in n.rates) {
        addDay(x.$1);
      }
      for (final x in n.fixedRange) {
        addDay(x.$1);
      }
    }
    for (final x in crime.bentFloor) {
      addDay(x.$1);
    }
    if (bent != null && crime.bentBefore.containsKey(bent)) {
      addDay(crime.bentBefore[bent]!.$1);
    }
    addDay(_d5377); // TCK 61/7 (5377) thirty-year cap — a favourable rule
    // Life sentences convert to dated ranges (35/2: 7550; 31: 7593); those days are compared too.
    final conversionKeys = [
      for (final k in const ['tesebbus', 'yardim_eden', 'haksiz_tahrik'])
        if (general[k] == true) k,
      ?age,
    ];
    if (age != null) {
      for (final x in t.age[age]!.rate) {
        addDay(x.$1);
      }
      for (final x in t.age[age]!.cap) {
        addDay(x.$1);
      }
    }
    if (crime.versions.any((x) => _life(x.low))) {
      for (final k in conversionKeys) {
        for (final x
            in t.conversion[k] ??
                const <(DateTime?, Map<String, (Rational, Rational)>)>[]) {
          addDay(x.$1);
        }
      }
    }
    final versions = <_Entry>[];
    final seen = <String>{};
    for (final g in days.toList()..sort()) {
      var s = _currentVersion(crime.versions, g);
      if (bent != null &&
          crime.bentBefore.containsKey(bent) &&
          _lt(g, crime.bentBefore[bent]!.$1)) {
        s = crime.bentBefore[bent]!.$2;
      }
      for (final n in quals) {
        // a circumstance whose own range replaces the base range on that day
        if (n.fixedRange.isNotEmpty &&
            _dated(n.fixedRange, g).containsKey(crime.code)) {
          s = _dated(n.fixedRange, g)[crime.code]!;
        }
      }
      final key = [
        s.key,
        [
          for (final n in quals)
            if (n.floors.isNotEmpty)
              (_dated(n.floors, g).entries.toList()
                    ..sort((a, b) => a.key.compareTo(b.key)))
                  .map((e) => '${e.key}=${e.value}')
                  .join(','),
        ].join(';'),
        [for (final n in quals) '${n.rate(g).$1},${n.rate(g).$2}'].join(';'),
        (bent != null && crime.bentFloor.isNotEmpty)
            ? '${_dated(crime.bentFloor, g)[bent]}'
            : '-',
        !_lt(g, _d5377),
        [
          for (final k in conversionKeys)
            if (t.conversion.containsKey(k))
              _dated(t.conversion[k]!, g).entries
                  .map((e) => '${e.key}=${e.value.$1},${e.value.$2}')
                  .join(','),
        ].join(';'),
        age != null
            ? '${_dated(t.age[age]!.rate, g)},${_dated(t.age[age]!.cap, g)}'
            : '-',
      ].join('\u0002');
      if (!seen.add(key)) continue;
      versions.add(
        computeVersion(crime, s, quals, general, age, woman, g, bent, remorse),
      );
    }
    versions.last.current = true;
    // FAVOURABLE LAW: the mildest result from the floor in the worst scenario (TCK 7/2).
    var favourable = versions.first;
    for (final x in versions.skip(1)) {
      final a = x.scenarios['alt_artirim_en_cok']!.value,
          b = favourable.scenarios['alt_artirim_en_cok']!.value;
      if (a < b ||
          (a == b &&
              x.scenarios['en_cok']!.value <
                  favourable.scenarios['en_cok']!.value)) {
        favourable = x;
      }
    }
    // Ranges that cross (one milder at the floor, the other at the top) make the favourable law depend
    // on the concrete sentence; only crossing with the chosen version matters.
    for (final b in versions) {
      if (favourable.scenarios['alt_artirim_en_cok']!.value <
              b.scenarios['alt_artirim_en_cok']!.value &&
          favourable.scenarios['en_cok']!.value >
              b.scenarios['en_cok']!.value) {
        w.add(
          '${_tr(favourable.day)} ve ${_tr(b.day)} metinlerinin aralıkları kesişiyor: '
          'lehe kanun somut cezaya göre değişir, işaretli sürümü alt sınır ölçütüyle seçtim — '
          'somut cezayla iki metni ayrı karşılaştır.',
        );
      }
    }
    // Limitation's upper limit: qualifying increases at most, a fixed qualifying reduction (158/4)
    // included, general reductions left out (66/3-4); each version's own rate.
    Rational upperOf(_Entry x) {
      var u = x.high;
      final skip = <String>{};
      for (final group in {
        for (final n in quals) _paragraph(n.code),
      }.whereType<String>()) {
        final members = [
          for (final n in quals)
            if (_paragraph(n.code) == group && n.rate(x.day).$2 > Rational.zero)
              n,
        ];
        if (members.length > 1) {
          var kept = members.first;
          for (final n in members.skip(1)) {
            final a = n.rate(x.day), b = kept.rate(x.day);
            if (a.$1 > b.$1 || (a.$1 == b.$1 && a.$2 > b.$2)) kept = n;
          }
          skip.addAll([
            for (final n in members)
              if (n != kept) n.code,
          ]);
        }
      }
      for (final n in quals) {
        if (skip.contains(n.code)) continue;
        if ((n.fixedRange.isNotEmpty &&
                _dated(n.fixedRange, x.day).containsKey(crime.code)) ||
            _life(u)) {
          continue;
        }
        final (least, most) = n.rate(x.day);
        if (most > Rational.zero) {
          u = u * (Rational.one + most);
        } else if (least == most && most < Rational.zero) {
          u = u * (Rational.one + least);
        }
      }
      return u;
    }

    // Limitation is favourable-law too: the version giving the SHORTEST period.
    final candidates = [
      for (final x in versions)
        (limitation(upperOf(x), age, event), upperOf(x)),
    ];
    var best = candidates.first;
    for (final c in candidates.skip(1)) {
      if (c.$1.years < best.$1.years ||
          (c.$1.years == best.$1.years && c.$2 < best.$2)) {
        best = c;
      }
    }
    final lim = best.$1, upperQualified = best.$2;
    final favLim = candidates[versions.indexOf(favourable)].$1;
    if (favLim.years != lim.years) {
      w.add(
        'Zamanaşımı en kısa süreyi veren metne göre (${lim.years} yıl) hesaplandı; ceza bakımından '
        'lehe seçilen metne göre ${favLim.years} yıl olurdu. TCK 7/2\'de zamanaşımının lehe '
        'kanunla BÜTÜN olarak mı ayrı mı değerlendirileceğini içtihatla teyit et.',
      );
    }
    final upperNow = upperOf(versions.last);

    final childOffenderMolestation =
        code == 'TCK 103/1-2' &&
        (age == '12-15' || age == '15-18') &&
        !_lt(event, _d6545);
    final complaint =
        (crime.complaint || childOffenderMolestation) &&
        !quals.any((n) => n.liftsComplaint) &&
        !consciousNegligence;
    var mediation = crime.mediation && !quals.any((n) => n.liftsMediation);
    var mediationNote = crime.mediationNote;
    if (crime.mediation && quals.any((n) => n.code.startsWith('TCK 87'))) {
      mediationNote +=
          ' | 87 ile birlikte uzlaştırma uygulaması içtihatla teyit edilmeli';
    }
    for (final n in quals) {
      if (n.mediationNote.isNotEmpty) mediationNote += ' | ${n.mediationNote}';
    }
    if (!mediation &&
        !crime.mediationBanned &&
        (age == '12-15' || age == '15-18') &&
        !quals.any((n) => n.liftsMediation) &&
        upperOf(versions.last) <= _years(3)) {
      mediation = true;
      mediationNote +=
          ' | CMK 253/1-c: adli süreçteki çocuk failde üst sınırı üç yılı geçmeyen suç — mağdurun gerçek '
          'kişi ya da özel hukuk tüzel kişisi olması şartıyla';
    }
    final others = _truthy(input['ayni_magdura_diger_suclar'])
        ? _iter(input['ayni_magdura_diger_suclar']).toList()
        : const <Object?>[];
    for (final other in others) {
      final d = t.crimes[parseCrime(other).$1];
      if (d == null && t.quals.containsKey(normalCode(other))) {
        // a circumstance code such as '125/3-a' → its crime
        final nk = t.quals[normalCode(other)]!;
        final main = nk.appliesTo.isNotEmpty
            ? t.crimes[nk.appliesTo.first]
            : null;
        final outside = main == null || !main.mediation || nk.liftsMediation;
        final prepaid =
            main != null && main.prepaymentListed && nk.code != 'TCK 125/3-a';
        if (mediation && outside && !prepaid) {
          mediation = false;
          mediationNote +=
              ' | CMK 253/3: aynı mağdura kapsam dışı ${nk.code} ile birlikte → uzlaşma uygulanmaz';
        }
        continue;
      }
      if (d == null) {
        w.add(
          "Aynı mağdura '${_str(other)}' tabloda yok: uzlaştırma ya da önödeme kapsamında değilse CMK 253/3 "
          'uzlaştırmayı kapatır — uzlaştırma sonucunu teyit et.',
        );
        continue;
      }
      if (mediation && !d.mediation && !d.prepaymentListed) {
        mediation = false;
        mediationNote +=
            ' | CMK 253/3: aynı mağdura kapsam dışı ${d.code} ile birlikte → uzlaşma uygulanmaz';
      }
    }
    // TCK 75/1: "only a judicial fine" or imprisonment up to six months; an alternative
    // (imprisonment OR fine) is not "only a judicial fine".
    final prepayment = crime.prepaymentListed
        ? !quals.any((n) => n.code == 'TCK 125/3-a')
        : !mediation && upperQualified <= _months(6);

    final least = favourable.scenarios['en_az']!.value;
    final lowMost = favourable.scenarios['alt_artirim_en_cok']!.value;
    final lowNoReduction = favourable.scenarios['alt_indirimsiz']!.value;
    final suspensionLimit =
        const ['12-15', '15-18', '65+'].contains(input['fail_yas_grubu'])
        ? _months(36)
        : _months(24);
    final bodilyCatalogue =
        crime.bodilyIntent &&
        (_truthy(input['kadina_karsi']) ||
            quals.any(
              (n) =>
                  const [
                    'TCK 86/3-b',
                    'TCK 86/3-e',
                    'TCK 86/3-f',
                  ].contains(n.code) ||
                  n.code.startsWith('TCK 87'),
            ));
    return _Result()
      ..crime = crime
      ..event = event
      ..decision = decision
      ..versions = versions
      ..favourable = favourable
      ..limitation = lim
      ..complaint = complaint
      ..mediation = mediation
      ..mediationNote = mediationNote
      ..prepayment = prepayment
      ..warnings = w
      ..quals = quals
      ..general = general
      ..age = age
      ..bent = bent
      ..remorse = remorse
      ..hagb = threshold(least, lowMost, lowNoReduction, _months(24))
      ..suspension = threshold(least, lowMost, lowNoReduction, suspensionLimit)
      ..shortTerm = threshold(least, lowMost, lowNoReduction, _months(12))
      // Procedure follows the text at trial (the current one). 5235 m.14: the jurisdiction ignores
      // aggravating and mitigating causes, so rate increases (143, 158/3, 155/3 …) do not move it.
      ..heavyCourt = versions.last.high > _years(10) || crime.heavyCourtList
      // CMK 100/4 (6352): only-fine crimes, or up to two years unless intentionally against the body.
      ..noDetention =
          (upperNow <= _years(2) && !crime.bodilyIntent) ||
          (age == '12-15' && upperNow <= _years(5))
      ..detentionNote =
          (crime.bodilyIntent && upperNow <= _years(2)
              ? 'CMK 100/4 istisnası: vücut dokunulmazlığına karşı kasten işlenen suç'
              : '') +
          (bodilyCatalogue
              ? ' · CMK 100/3 katalog (86/3-b,e,f; 87; kadına karşı kasten yaralama): tutuklama nedeni var sayılabilir'
              : '')
      // CMK 150/3 by the current text's floor of the crime type; 150/2 children.
      ..counsel =
          versions.last.qualifiedLow > _years(5) ||
          age == '12-15' ||
          age == '15-18';
  }

  /// `surum_sec`: the version in force on [day].
  static _Version _currentVersion(List<_Version> versions, DateTime day) {
    var chosen = versions.first;
    for (final s in versions) {
      if (s.start == null || _le(s.start!, day)) chosen = s;
    }
    return chosen;
  }
}

// ─── `metin` ─────────────────────────────────────────────────────────────

String _text(_Tables t, _Result r, String freshness) {
  final crime = r.crime;
  final bent = r.bent != null && r.bent!.isNotEmpty ? '-${r.bent}' : '';
  final p = <String>[
    'CEZA HESABI v${t.version} — ${crime.code}$bent ${crime.name} · olay ${_tr(r.event)} · karar ${_tr(r.decision)}',
  ];
  if (r.quals.isNotEmpty) {
    p.add(
      'Nitelikli haller: ${r.quals.map((n) => '${n.code} (${n.name})').join('; ')}',
    );
  }
  final chosen = [
    for (final e in r.general.entries)
      if (e.value && e.key != 'takdiri_indirim') t.general[e.key]!.$1,
  ];
  if (r.age != null) chosen.add(t.age[r.age]!.text);
  if (r.remorse != null) {
    final label =
        (crime.remorseSpecial[r.remorse] ?? t.remorse[r.remorse]!).name;
    chosen.add(
      label +
          (label.contains('168')
              ? ' — 168/4: kısmi gidermede mağdurun rızası gerekir'
              : ''),
    );
  }
  if (r.general['takdiri_indirim'] == true) {
    chosen.add(t.general['takdiri_indirim']!.$1);
  }
  if (chosen.isNotEmpty) {
    p.add('Genel hükümler (TCK 61/5 sırasıyla): ${chosen.join('; ')}');
  }
  final many = r.versions.length > 1;
  for (final x in r.versions) {
    final s = x.version;
    var mark = identical(x, r.favourable) && many ? ' ← LEHE (TCK 7/2)' : '';
    mark += x.current && many ? ' · güncel metin' : '';
    final unverified = s.verified ? '' : ' [sürüm tarihi DOĞRULANMADI]';
    final range = _life(x.low) && x.low == x.high
        ? _duration(x.low)
        : '${_duration(x.low)} – ${_duration(x.high)}';
    final bentLow = x.bentLow;
    p.add(
      '\n— ${_tr(x.day)} tarihinden itibaren metin: $range'
      '${_life(x.low) ? '' : (s.fineAlternative ? ' hapis veya adlî para' : ' hapis')}'
      '${s.fineWith.isNotEmpty ? ' ve ${s.fineWith}' : ''}'
      '${r.quals.where((n) => n.fineWith.isNotEmpty).map((n) => ' ve ${n.fineWith}').join()}'
      '$mark$unverified\n  kaynak: ${s.source}'
      '${bentLow != null && !bentLow.isZero ? '\n  ${crime.code}-${r.bent} bendi: hapsin alt sınırı ${_duration(bentLow)}'
                '${crime.code == 'TCK 158/1' ? ', adlî para menfaatin iki katından az olamaz' : ''}' : ''}',
    );
    for (final (name, label) in const [
      ('en_az', 'En az (alt sınır, artırım en az, indirim en çok)'),
      ('alt_artirim_en_cok', 'Alt sınırdan, artırım EN ÇOK, indirim en çok'),
      (
        'alt_indirimsiz',
        'Alt sınırdan, artırım en çok, takdire bağlı indirim YOK',
      ),
      ('en_cok', 'En çok (üst sınır, artırım en çok, indirim yok)'),
    ]) {
      final sen = x.scenarios[name]!;
      p.add('  $label: ${_duration(sen.value)}   [${sen.steps.join(' → ')}]');
    }
  }
  p.add(
    '\nHAGB (CMK 231/5, ≤ 2 yıl): ${r.hagb} — 231/6 koşulları (sabıka, kanaat, zararın giderilmesi) ayrıca.'
    '${r.favourable.version.fineAlternative ? ' Seçimlik adlî para cezası seçilirse HAGB süreden bağımsız mümkündür (231/5: hapis VEYA adlî para).' : ''}',
  );
  p.add('Erteleme (TCK 51): ${r.suspension} — 51/1-a,b koşulları ayrıca.');
  p.add(
    'Kısa süreli hapis / seçenek yaptırım (TCK 49/2, 50, ≤ 1 yıl): ${r.shortTerm}'
    '${crime.negligent ? ' · taksirli suçta uzun süreli de olsa adlî paraya çevrilebilir (50/4)' : ''}',
  );
  final z = r.limitation;
  final rate = z.rate == Rational.one ? '' : ' × ${z.rate} (TCK 66/2, yaş)';
  p.add(
    'Dava zamanaşımı: TCK ${z.article} → ${z.years} yıl$rate = ${z.normal}; olağan bitiş '
    '${_tr(z.normalEnd)}; kesilmeyle uzamış azami (67/4) ${z.extended} → ${_tr(z.extendedEnd)}. '
    'Durma sebepleri (67/1) hesaba katılmadı.',
  );
  p.add(
    'Şikâyet: ${r.complaint ? 'şikâyete bağlı (TCK 73: altı ay)' : 'şikâyete bağlı değil'}'
    '${crime.complaintNote.isNotEmpty ? ' · ${crime.complaintNote}' : ''}',
  );
  p.add(
    'Uzlaştırma (güncel CMK 253): ${r.mediation ? 'kapsamda' : 'kapsam dışı'} — '
    '${r.mediationNote.isNotEmpty ? r.mediationNote : 'CMK 253 listesinde yok'}'
    ' · olay tarihindeki 253 listesi farklıysa lehe olan uygulanır; teyit et.',
  );
  p.add('Önödeme (TCK 75): ${r.prepayment ? 'mümkün' : 'kapsam dışı'}');
  p.add(
    'Görev: ${r.heavyCourt ? 'ağır ceza' : 'asliye ceza'} (5235 m.12 ve m.14: ağırlaştırıcı/hafifletici '
    'nedenler gözetilmeksizin suçun kanundaki üst sınırı; adıyla sayılan suçlar ayrıca) · '
    'Tutuklama yasağı (CMK 100/4): ${r.noDetention ? 'evet' : 'hayır'}'
    '${r.detentionNote.isNotEmpty ? ' (${_strip(r.detentionNote, ' ·')})' : ''} · '
    'Zorunlu müdafi (CMK 150/3 alt sınır > 5 yıl — nitelikli artırımlar en az oranla dâhil, bu sayımı '
    'içtihatla teyit et; 150/2 çocuk): ${r.counsel ? 'evet' : 'hayır (150/2 malul, sağır-dilsiz ayrıca)'}'
    '${r.age == '12-15' ? ' · ÇKK m.21: 15 yaşından küçükte üst sınırı beş yılı aşmayan suçta tutuklama yasağı' : ''}',
  );
  if (crime.notes.isNotEmpty) p.add('NOT: ${crime.notes}');
  if (t.civilService.containsKey(crime.code)) {
    p.add(
      'Memuriyet (657 DMK m.48/A-5): ${t.civilService[crime.code]} suçundan mahkûmiyet, ceza miktarı ve af '
      'fark etmeksizin memuriyete engel; HAGB kurulan hükmün hukuki sonuç doğurmamasıdır (CMK 231/5).',
    );
  } else if (!crime.negligent) {
    p.add(
      'Memuriyet (657 DMK m.48/A-5): kasten işlenen suçtan bir yıl veya daha fazla hapis memuriyete '
      'engel; HAGB kurulan hükmün hukuki sonuç doğurmamasıdır (CMK 231/5).'
      '${const ['TCK 206', 'TCK 209/1', 'TCK 210/2'].contains(crime.code) ? " Bu suç Belgelerde Sahtecilik bölümünde: 48/A-5'teki 'sahtecilik' kapsamında olup olmadığı "
                '(miktardan bağımsız engel) içtihada bağlı — teyit et.' : ''}',
    );
  }
  if (r.warnings.isNotEmpty) p.add('UYARI: ${r.warnings.join(' ')}');
  p.add('\n$freshness');
  p.add(
    'Bu bir hesap aracıdır: nitelendirme, artırım/indirim oranının takdiri ve koşullar hukuki '
    'değerlendirmedir. Sonucu yazarken tarihli metni ve dayandığın maddeleri göster. Aracın verdiği '
    'bir aralık ya da oran, mevzuat_getir ile okuduğun canlı metinle çelişirse CANLI METİN esastır — '
    "çelişkiyi kullanıcıya açıkça yaz; 'teyit et' notlarını sonuç gibi sunma.",
  );
  return p.join('\n');
}
