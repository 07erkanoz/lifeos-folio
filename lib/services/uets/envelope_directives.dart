import '../legal/deadlines/sure_katalogu.dart';

/// A time the envelope of a notice, or a court's document, gives: "rapora
/// karşı itirazlarınızı tebliğden itibaren iki hafta içinde …", "davacıya
/// … iki haftalık kesin süre verilmesine". Read by rule, never by a model;
/// a clause is taken only when it gives an amount and a unit with
/// "içinde" or "süre", and speaks to its reader or of the service.
class EnvelopeDirective {
  /// The sentence, as the envelope has it.
  final String quote;
  final int amount;
  final SureBirimi unit;

  /// Whether the sentence says the time runs from the service; otherwise
  /// the service is taken, and said to be taken.
  final bool fromService;

  /// What is to be done, as far as the sentence tells: 'kanunYolu',
  /// 'itiraz', 'cevap', 'beyan', 'odeme', 'delil' or 'genel'.
  final String act;

  /// Another event the sentence says the time runs from: 'tefhim',
  /// 'karar', 'ilan' or 'ogrenme'; null for the service, said or not.
  /// Never stood in for by the service.
  final String? startsFrom;

  /// The party the sentence lays the duty on, when it names one instead of
  /// speaking to its reader ("Davalı tarafa … ihtar olunur"): 'davaci',
  /// 'davali', 'alacakli' or 'borclu'. A notice served on the lawyer does
  /// not make every duty written in it the lawyer's.
  final String? party;

  /// Whether the sentence speaks to its reader ("… sununuz", "hakkınız");
  /// one that only tells of the service ("kararın tebliğinden itibaren iki
  /// hafta içinde istinaf yolu açık") lays its duty on no one in
  /// particular.
  final bool toReader;

  /// Every act its part of the clause names, the nearest being [act].
  final Set<String> acts;

  /// The court calls it a "kesin süre". Whether the warning that makes it
  /// so was given is another question (HMK m.94), not decided here.
  final bool strict;

  /// When the sentence writes the time twice and the two disagree ("iki
  /// (3) hafta"): the other; [amount] is the shorter, never chosen
  /// silently.
  final int? otherAmount;

  const EnvelopeDirective({
    required this.quote,
    required this.amount,
    required this.unit,
    required this.fromService,
    required this.act,
    this.startsFrom,
    this.party,
    this.toReader = true,
    this.strict = false,
    this.otherAmount,
    this.acts = const {},
  });

  /// Days for comparing with a catalogue's rule: weeks are seven days;
  /// months and years only equal themselves.
  ({int n, String unit}) get span => switch (unit) {
    SureBirimi.hafta => (n: amount * 7, unit: 'gun'),
    SureBirimi.gun => (n: amount, unit: 'gun'),
    SureBirimi.isGunu => (n: amount, unit: 'isGunu'),
    SureBirimi.ay => (n: amount, unit: 'ay'),
    SureBirimi.yil => (n: amount, unit: 'yil'),
  };

  String get text => switch (unit) {
    SureBirimi.gun => '$amount gün',
    SureBirimi.isGunu => '$amount iş günü',
    SureBirimi.hafta => '$amount hafta',
    SureBirimi.ay => '$amount ay',
    SureBirimi.yil => '$amount yıl',
  };
}

/// Number words as they read with Turkish letters folded (see [_fold]).
const _words = {
  'bir': 1,
  'iki': 2,
  'uc': 3,
  'dort': 4,
  'bes': 5,
  'alti': 6,
  'yedi': 7,
  'sekiz': 8,
  'dokuz': 9,
  'on': 10,
  'on bes': 15,
  'onbes': 15,
  'yirmi': 20,
  'otuz': 30,
  'kirk bes': 45,
  'altmis': 60,
  'doksan': 90,
};

final _number =
    '(?:\\(?\\d{1,3}\\)?|${(_words.keys.toList()..sort((a, b) => b.length.compareTo(a.length))).join('|')})';

/// On the folded text: "iki (2) hafta içinde", "(30) gün içinde", "15
/// (onbeş) gün içerisinde", "3 iş günü zarfında", and the court's own "iki
/// haftalık kesin süre verilmesine", "iki hafta kesin süre", "on günlük
/// süre içinde" (the audit's B03); an OCR's "icinde" reads the same.
final _span = RegExp(
  '(?<![a-z\\d])($_number)(?:\\s*\\(\\s*(\\d{1,3}|[a-z ]{2,12})\\s*\\))?\\s+'
  '(is\\s+gunu|gun|hafta|ay|yil)(?:luk|lik)?\\s+'
  '(?:(kesin\\s+)?sure[a-z]*|icinde|icerisinde|zarfinda)',
);

/// "aynı sürede", "aynı süre içinde": the time of the directive before.
final _same = RegExp(r'ayni\s+sure[a-z]*');

/// The envelope's directives, in its order; the same time for the same act
/// once.
List<EnvelopeDirective> envelopeDirectives(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final out = <EnvelopeDirective>[];
  final seen = <String>{};
  EnvelopeDirective? last;
  // Sentences, and the numbered items of a decision ("…, 2-Davanın …").
  for (final sentence in flat.split(
    RegExp(
      r'(?<=[.!?;])\s+(?=[A-ZÇĞİÖŞÜ0-9("“])|(?<=[,;.])\s*(?=\d{1,2}\s*[-)]\s*[A-ZÇĞİÖŞÜ])',
    ),
  )) {
    // Folded letter for letter, so that what is found in it is found at the
    // same place in the sentence.
    var own = _fold(sentence);
    // A law quoted in the letter ("… kazadan sonraki 3 iş günü içinde …
    // bildirimde bulunur.") is not a directive to its reader; a warning
    // the court puts in quotes is (B04): "İHTAR: “…”", "“…” ihtarına".
    own = own.replaceAllMapped(RegExp(r'"[^"]*"|“[^”]*”'), (q) {
      final before = own.substring(q.start < 40 ? 0 : q.start - 40, q.start);
      final after = own.substring(
        q.end,
        q.end + 25 > own.length ? own.length : q.end + 25,
      );
      return before.contains('ihtar') || after.contains('ihtar')
          ? q[0]!
          : ' ' * q[0]!.length;
    });
    final spans = [
      for (final m in _span.allMatches(own)) (m.start, m.end, m),
      for (final m in _same.allMatches(own)) (m.start, m.end, null),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (var k = 0; k < spans.length; k++) {
      final (at, end, m) = spans[k];
      // Each time read by its own clause, not by the whole sentence: a
      // service, an act or a past omission in another clause ("…
      // verilmediğinden ceza verildi; tebliğden itibaren 30 gün içinde
      // itiraz hakkınız vardır") says nothing of this time.
      final from = own.lastIndexOf(RegExp(r'[;:]'), at);
      final to = own.indexOf(RegExp(r'[;:]'), end);
      final clauseFrom = from < 0 ? 0 : from + 1;
      final clauseTo = to < 0 ? own.length : to;
      final clause = own.substring(clauseFrom, clauseTo);
      // And within the clause, by its own part (B05): "beş gün içinde
      // itiraz etmeniz ve on gün içinde ödemeniz" are two acts, split at
      // the "ve" or the comma between the two times.
      int cut(int a, int b) {
        final between = own.substring(a, b);
        final m = RegExp(r'.*(?:\sve\s|,\s|;)').firstMatch(between);
        return m == null ? b : a + m.end;
      }

      final partFrom = k == 0
          ? clauseFrom
          : [
              clauseFrom,
              cut(spans[k - 1].$2, at),
            ].reduce((a, b) => a > b ? a : b);
      final partTo = k == spans.length - 1
          ? clauseTo
          : [
              clauseTo,
              cut(end, spans[k + 1].$1),
            ].reduce((a, b) => a < b ? a : b);
      final part = own.substring(partFrom, partTo);
      // A directive: spoken to its reader, of the service, or the court's
      // warning ("… ihtar olunur", "… ihtarına") the clause belongs to.
      // The court's own order "… süre verilmesine" is a directive too,
      // with no word of the service (measured on a real box, 8 October
      // 2026: "taraflara … iki hafta kesin süre verilmesine").
      if (!_speaksToReader(clause) &&
          !clause.contains('tebli') &&
          !own.contains('ihtar') &&
          !clause.contains('verilmesine')) {
        continue;
      }
      if (RegExp(
        r'yapilmadigindan|verilmediginden|bildirilmediginden|verilmemesi nedeniyle',
      ).hasMatch(clause)) {
        continue;
      }
      // "kazadan sonraki 3 iş günü içinde": another event's time.
      if (RegExp(r'sonraki\s*$').hasMatch(own.substring(0, at).trimRight())) {
        continue;
      }
      int? amount;
      int? other;
      SureBirimi unit;
      bool strict;
      if (m == null) {
        // "aynı sürede": the one before, if there is one in the sentence.
        final before = last;
        if (before == null || k == 0) continue;
        amount = before.amount;
        unit = before.unit;
        strict = before.strict;
      } else {
        amount = _amount(m.group(1)!);
        // "iki (3) hafta": the two do not agree, and neither is chosen
        // silently; the earlier is kept, and the other told.
        final paren = m.group(2) == null ? null : _amount(m.group(2)!);
        if (amount != null && paren != null && paren != amount) {
          other = paren > amount ? paren : amount;
          amount = paren < amount ? paren : amount;
        }
        unit = switch (m.group(3)!.replaceAll(RegExp(r'\s+'), ' ')) {
          'is gunu' => SureBirimi.isGunu,
          'gun' => SureBirimi.gun,
          'hafta' => SureBirimi.hafta,
          'ay' => SureBirimi.ay,
          _ => SureBirimi.yil,
        };
        strict = m.group(4) != null;
      }
      if (amount == null || amount <= 0) continue;
      final act = _act(part, at - partFrom, end - partFrom);
      // A time the court gives an expert or a buyer at an auction is
      // theirs, no party's: "raporunu sunmak üzere bilirkişiye 15 günlük
      // süre". Only when it is said to them just before the time, and not
      // a payment, which is a party's ("bilirkişi ücretini yatırması").
      if (act != 'odeme' &&
          RegExp(r'bilirkisi(?:ye|lere)\b|ihale alicisi|alicisinin').hasMatch(
            own.substring(at - 80 < partFrom ? partFrom : at - 80, at),
          )) {
        continue;
      }
      final startsFrom = _startsFrom(part) ?? _startsFrom(clause);
      final toReader = _speaksToReader(part) || _speaksToReader(clause);
      final party = toReader ? null : _party(part) ?? _party(clause);
      final key = '$amount|${unit.name}|$act|$startsFrom|$party';
      final quote = sentence.length > 400
          ? '${sentence.substring(0, 400)}…'
          : sentence;
      final d = EnvelopeDirective(
        quote: quote,
        amount: amount,
        unit: unit,
        // The start the sentence says once ("Davacıya, tebliğden itibaren
        // …; davalıya aynı sürede …") is every clause's that says none.
        fromService:
            _fromService.hasMatch(part) ||
            _fromService.hasMatch(clause) ||
            (_startsFrom(part) == null &&
                _fromService.hasMatch(own) &&
                _startsFrom(own) == null),
        act: act,
        startsFrom: startsFrom,
        party: party,
        toReader: toReader,
        strict: strict,
        otherAmount: other,
        acts: _acts(part),
      );
      last = d;
      if (!seen.add(key)) continue;
      out.add(d);
    }
  }
  return out;
}

/// [s] lowercased with Turkish letters folded to their plain ones, one
/// letter for one: "Tebliğden İTİBAREN" and an OCR's "Tebligden itibaren"
/// read alike, at the same places.
String _fold(String s) {
  final out = StringBuffer();
  for (final c in s.split('')) {
    out.write(switch (c) {
      'İ' || 'I' || 'ı' || 'î' || 'Î' => 'i',
      'Ş' || 'ş' => 's',
      'Ğ' || 'ğ' => 'g',
      'Ü' || 'ü' || 'û' || 'Û' => 'u',
      'Ö' || 'ö' => 'o',
      'Ç' || 'ç' => 'c',
      'Â' || 'â' => 'a',
      _ when c.codeUnitAt(0) < 128 => c.toLowerCase(),
      _ => c,
    });
  }
  return out.toString();
}

/// "tebliğinden itibaren", "tebliğ tarihinden itibaren", "tebellüğden
/// itibaren", "tebliğden başlayarak": the time runs from the service. A
/// bare "ihtar ve tebliğ olunur" is the serving, not a start.
final _fromService = RegExp(
  r'(tebli|tebellu)[a-z]*\s+(tarihinden\s+)?(itibaren|basla)',
);

/// "tefhimden itibaren", "kararın tebliğinden" is the service; "karar
/// tarihinden itibaren", "ilandan itibaren", "öğrenmeden itibaren" are not.
String? _startsFrom(String lower) {
  final m = RegExp(
    r'(tefhim|karar\s+tarihi|ilan|ogrenme)[a-z]*\s+(?:tarihinden\s+)?'
    r'(?:itibaren|basla)',
  ).firstMatch(lower);
  if (m == null) return null;
  final w = m.group(1)!;
  if (w.startsWith('tefhim')) return 'tefhim';
  if (w.startsWith('karar')) return 'karar';
  if (w.startsWith('ilan')) return 'ilan';
  return 'ogrenme';
}

/// The parties a text gives a duty to: "davalı tarafa", "davacıya",
/// "borçlu vekiline".
Set<String> _parties(String folded) => {
  for (final m in RegExp(
    r'(davaci|davali|alacakli|borclu)'
    r'(?:\s+(?:tarafa|vekiline|vekillerine)|ya|ye|lara|lere)\b',
  ).allMatches(folded))
    m.group(1)!,
};

/// The party a part of a clause gives its duty to; two named, or none:
/// null.
String? _party(String folded) {
  final found = _parties(folded);
  return found.length == 1 ? found.single : null;
}

bool _speaksToReader(String folded) =>
    folded.contains('hakkiniz') ||
    RegExp(r'[a-z](?:niz|nuz)\b').hasMatch(folded);

int? _amount(String raw) {
  final digits = RegExp(r'\d{1,3}').firstMatch(raw);
  if (digits != null) return int.parse(digits.group(0)!);
  return _words[_fold(raw).trim().replaceAll(RegExp(r'\s+'), ' ')];
}

/// Every act [folded] names.
Set<String> _acts(String folded) => {
  for (final (word, act) in _actWords)
    if (folded.contains(word)) act,
};

const _actWords = [
  ('istinaf', 'kanunYolu'),
  ('temyiz', 'kanunYolu'),
  ('kanun yolu', 'kanunYolu'),
  ('itiraz', 'itiraz'),
  ('cevap', 'cevap'),
  ('savunma', 'cevap'),
  ('iddia ve', 'cevap'),
  ('avans', 'odeme'),
  ('ode', 'odeme'),
  ('yatir', 'odeme'),
  ('delil', 'delil'),
  ('tanik', 'delil'),
  ('beyan', 'beyan'),
];

/// What [folded] says is to be done, by the act's word nearest to the time
/// at [from]–[to] in it: "gider avansını … iki haftalık kesin süre içinde
/// yatırması, …, ayrıca cevap dilekçesi" is a payment, not an answer.
String _act(String folded, int from, int to) {
  const words = _actWords;
  String? best;
  var bestGap = 1 << 30;
  for (final (word, act) in words) {
    for (
      var at = folded.indexOf(word);
      at >= 0;
      at = folded.indexOf(word, at + 1)
    ) {
      // "delil avansı" is a payment, not evidence.
      if (word == 'delil' && folded.startsWith(' avans', at + word.length)) {
        continue;
      }
      // Before the time, how far its word ends from it; after, how far it
      // begins; a word after is taken over one as far before ("on gün
      // içinde itiraz etmeniz").
      final gap = at + word.length <= from
          ? (from - (at + word.length)) * 2 + 1
          : at >= to
          ? (at - to) * 2
          : 0;
      if (gap < bestGap) {
        bestGap = gap;
        best = act;
      }
    }
  }
  return best ?? 'genel';
}
