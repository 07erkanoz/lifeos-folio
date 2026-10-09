/// What UYAP's web portal tells of an enforcement file (icra) beyond the
/// other cases' particulars (banaozel's uyapweb.md §10): its account,
/// line by line as the portal's account page lists it, and its debtors.
/// Kept as UYAP gave them and read when shown, so that a label UYAP spells
/// otherwise is shown as it came, never lost.
class UyapEnforcement {
  const UyapEnforcement({this.lines = const [], this.debtors = const []});

  /// `dosya_hesap_bilgileri.ajx`: `[{grupId, textAlan, degerAlan}]`; group
  /// 1 the claim's items, group 2 the money paid in.
  final List<UyapAccountLine> lines;

  /// `dosya_borclu_list.ajx`.
  final List<UyapDebtor> debtors;

  bool get isEmpty => lines.isEmpty && debtors.isEmpty;

  static List<UyapAccountLine> linesFromJson(Object? raw) => [
    for (final row in _rows(raw)) ?UyapAccountLine.fromJson(row),
  ];

  static List<UyapDebtor> debtorsFromJson(Object? raw) => [
    for (final row in _rows(raw)) ?UyapDebtor.fromJson(row),
  ];

  static List<Map> _rows(Object? raw) {
    if (raw is Map) {
      for (final v in raw.values) {
        if (v is List) return _rows(v);
      }
      return const [];
    }
    if (raw is! List) return const [];
    // Some answers come wrapped once more: [[...]].
    if (raw.length == 1 && raw.first is List) return _rows(raw.first);
    return [
      for (final r in raw)
        if (r is Map) r,
    ];
  }

  Map<String, Object?> toJson() => {
    'hesap': [for (final l in lines) l.toJson()],
    'borclular': [for (final d in debtors) d.toJson()],
  };

  factory UyapEnforcement.stored(Map<Object?, Object?> json) => UyapEnforcement(
    lines: [
      for (final r in json['hesap'] as List? ?? const [])
        if (r is Map) ?UyapAccountLine.fromJson(r),
    ],
    debtors: [
      for (final r in json['borclular'] as List? ?? const [])
        if (r is Map) ?UyapDebtor.stored(r),
    ],
  );

  /// The account read: the totals, the claim's items, the fees and taxes.
  UyapAccount get account => UyapAccount.of(lines);
}

/// One line of the account page: its group, its label and its value, as
/// UYAP wrote them ("Bakiye Borc Miktari", "268606.85").
class UyapAccountLine {
  const UyapAccountLine(this.group, this.label, this.value);

  final int group;
  final String label, value;

  static UyapAccountLine? fromJson(Map json) {
    final label = '${json['textAlan'] ?? json['metin'] ?? ''}'.trim();
    final value = '${json['degerAlan'] ?? json['deger'] ?? ''}'.trim();
    if (label.isEmpty) return null;
    final group = json['grupId'] ?? json['grup'];
    return UyapAccountLine(
      group is num ? group.toInt() : int.tryParse('$group') ?? 0,
      label,
      value,
    );
  }

  Map<String, Object?> toJson() => {
    'grupId': group,
    'textAlan': label,
    'degerAlan': value,
  };

  /// The value in lira: "268606.85", "268.606,85" and "268.606,85 TL" alike;
  /// null for a value that is not a sum.
  double? get amount => parseLira(value);

  /// The label as it reads in Turkish: UYAP writes many without their
  /// Turkish letters ("Vekalet Ucreti").
  String get title => readableLabel(label);
}

/// "268606.85", "268.606,85", "268.606,85 TL", "1,5" → lira; null when it
/// is no number.
double? parseLira(String text) {
  var s = text.replaceAll(RegExp(r'tl|₺|\s', caseSensitive: false), '');
  if (s.isEmpty || !RegExp(r'^-?[\d.,]+$').hasMatch(s)) return null;
  final comma = s.lastIndexOf(','), dot = s.lastIndexOf('.');
  if (comma > dot) {
    // Turkish: dots group the thousands, the comma the kuruş.
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (dot > comma && comma >= 0) {
    s = s.replaceAll(',', '');
  } else if (dot >= 0 && s.split('.').length > 2) {
    // "1.250.000": dots grouping alone.
    s = s.replaceAll('.', '');
  }
  return double.tryParse(s);
}

String _fold(String s) => s
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('İ', 'i')
    .replaceAll('i̇', 'i')
    .replaceAll('ş', 's')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c');

/// UYAP's folded words, given back their letters.
const _words = {
  'alacak': 'alacak',
  'alacakli': 'alacaklı',
  'asil': 'asıl',
  'bakiye': 'bakiye',
  'basvurma': 'başvurma',
  'borc': 'borç',
  'borclu': 'borçlu',
  'cezai': 'cezai',
  'faiz': 'faiz',
  'faizi': 'faizi',
  'gider': 'gider',
  'haciz': 'haciz',
  'harc': 'harç',
  'harci': 'harcı',
  'harclar': 'harçlar',
  'icra': 'icra',
  'islemis': 'işlemiş',
  'kesinlesen': 'kesinleşen',
  'masraf': 'masraf',
  'masraflari': 'masrafları',
  'miktari': 'miktarı',
  'odenen': 'ödenen',
  'pesin': 'peşin',
  'sonrasi': 'sonrası',
  'tahsil': 'tahsil',
  'tahsilat': 'tahsilat',
  'takip': 'takip',
  'takipte': 'takipte',
  'tazminat': 'tazminat',
  'toplam': 'toplam',
  'tutari': 'tutarı',
  'ucret': 'ücret',
  'ucreti': 'ücreti',
  'vekalet': 'vekâlet',
  'vergi': 'vergi',
  'yatan': 'yatan',
  'yargilama': 'yargılama',
};

/// "Vekalet Ucreti" → "Vekâlet ücreti"; a word not known stays as it came.
String readableLabel(String label) {
  final words = label.trim().split(RegExp(r'\s+'));
  final out = <String>[];
  for (final (i, w) in words.indexed) {
    final known = _words[_fold(w)];
    final upper = RegExp(r'^[A-ZÇĞİÖŞÜ0-9/().-]{2,5}$').hasMatch(w);
    var word = upper ? w : (known ?? w.toLowerCase());
    if (i == 0 && word.isNotEmpty) {
      word = word[0] == 'i' && !upper
          ? 'İ${word.substring(1)}'
          : '${word[0].toUpperCase()}${word.substring(1)}';
    }
    out.add(word);
  }
  return out.join(' ');
}

/// The account read from its lines: what is owed in all, what was paid in,
/// what is left; the claim's items and the fees and taxes apart.
class UyapAccount {
  const UyapAccount({
    this.total,
    this.paid,
    this.left,
    this.items = const [],
    this.fees = const [],
    this.paidIn = const [],
  });

  factory UyapAccount.of(List<UyapAccountLine> lines) {
    double? total, paid, left;
    final items = <UyapAccountLine>[];
    final fees = <UyapAccountLine>[];
    final paidIn = <UyapAccountLine>[];
    for (final l in lines) {
      final f = _fold(l.label);
      if (f.contains('bakiye')) {
        left = l.amount;
      } else if (f.contains('toplam') && f.contains('alacak')) {
        total = l.amount;
      } else if (l.group == 2 ||
          f.contains('yatan') ||
          (f.contains('tahsil') && !f.contains('harc'))) {
        if (f.contains('toplam') || f.contains('yatan para')) {
          paid = l.amount;
        } else {
          paidIn.add(l);
        }
      } else if (RegExp(r'harc|vergi|bsmv|kkdf|kdv|oiv|damga').hasMatch(f)) {
        fees.add(l);
      } else if (l.amount != null) {
        items.add(l);
      }
    }
    if (paid == null && paidIn.isNotEmpty) {
      paid = paidIn.fold<double>(0, (n, l) => n + (l.amount ?? 0));
    }
    return UyapAccount(
      total: total,
      paid: paid,
      left: left,
      items: items,
      fees: fees,
      paidIn: paidIn,
    );
  }

  final double? total, paid, left;
  final List<UyapAccountLine> items, fees, paidIn;

  /// How much of the whole is paid, 0 to 1; null while not known.
  double? get share {
    final t = total ?? ((paid ?? 0) + (left ?? 0));
    if (t <= 0 || paid == null) return null;
    return (paid! / t).clamp(0, 1).toDouble();
  }
}

/// A debtor of the file: who, and what the population register says that
/// matters to the claim. Their parents' names and birth day, which UYAP
/// sends too, are not kept.
class UyapDebtor {
  const UyapDebtor({
    required this.id,
    required this.name,
    this.idNo = '',
    this.body = false,
    this.dead = false,
    this.moved = false,
    this.movedWhy = '',
    this.warning = false,
  });

  /// `kisiKurumId`: what a debtor's queries are asked by.
  final String id;
  final String name;

  /// The TCKN or VKN, masked but for its first and last digit.
  final String idNo;
  final bool body;

  /// The register knows of their death (`olumKaydi`, `hasOlumKaydi`).
  final bool dead;

  /// Their address changed in the register (`mernisDegisiklikVarmi`).
  final bool moved;
  final String movedWhy;

  /// UYAP's warning on the party (`isTarafUyari`).
  final bool warning;

  static UyapDebtor? fromJson(Map json) {
    final p = json['kisiTumDVO'] is Map
        ? json['kisiTumDVO'] as Map
        : json['kurumDVO'] is Map
        ? json['kurumDVO'] as Map
        : json;
    String s(String k) => '${p[k] ?? ''}'.trim();
    bool yes(String k) => p[k] == true || '${p[k]}'.toLowerCase() == 'true';
    final person = [s('adi'), s('soyadi')].where((x) => x.isNotEmpty).join(' ');
    final name = person.isNotEmpty
        ? person
        : [
            s('kurumAdi'),
            s('unvan'),
            s('adi'),
          ].firstWhere((x) => x.isNotEmpty, orElse: () => '');
    if (name.isEmpty) return null;
    final no = [
      s('tcKimlikNo'),
      s('vergiNo'),
      s('vkn'),
    ].firstWhere((x) => x.isNotEmpty, orElse: () => '');
    return UyapDebtor(
      id: '${json['kisiKurumId'] ?? ''}',
      name: name,
      idNo: mask(no),
      body: person.isEmpty,
      dead: yes('olumKaydi') || yes('hasOlumKaydi'),
      moved: yes('mernisDegisiklikVarmi'),
      movedWhy: s('mernisDegisiklikNedeni'),
      warning: yes('isTarafUyari'),
    );
  }

  /// "12345678904" → "1•••••••••4".
  static String mask(String no) => no.length < 4
      ? no
      : '${no[0]}${'•' * (no.length - 2)}${no[no.length - 1]}';

  Map<String, Object?> toJson() => {
    'id': id,
    'ad': name,
    'kimlik': idNo,
    'kurum': body,
    'olum': dead,
    'adresDegisti': moved,
    'adresNeden': movedWhy,
    'uyari': warning,
  };

  static UyapDebtor? stored(Map json) => json['ad'] is! String
      ? null
      : UyapDebtor(
          id: '${json['id'] ?? ''}',
          name: json['ad'] as String,
          idNo: '${json['kimlik'] ?? ''}',
          body: json['kurum'] == true,
          dead: json['olum'] == true,
          moved: json['adresDegisti'] == true,
          movedWhy: '${json['adresNeden'] ?? ''}',
          warning: json['uyari'] == true,
        );
}

/// "Açık (Durdurulmuş : Takibe İtiraz)" → "Takibe İtiraz"; null when the
/// file is not stopped. UYAP says so only in the words: its code stays
/// that of an open file.
String? stoppedBecause(String state) {
  final m = RegExp(
    r'durdurulmu[şs]\s*:\s*([^)]+)\)',
    caseSensitive: false,
  ).firstMatch(state);
  return m?.group(1)?.trim();
}
