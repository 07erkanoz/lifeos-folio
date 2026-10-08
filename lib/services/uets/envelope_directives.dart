import '../legal/deadlines/sure_katalogu.dart';

/// A time the envelope of a notice gives the one it is sent to: "rapora
/// karşı itirazlarınızı tebliğden itibaren iki hafta içinde …". Read by
/// rule from the envelope's text, never by a model; a sentence is taken
/// only when it gives an amount, a unit and "içinde", and speaks to its
/// reader or of the notice's service.
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

  const EnvelopeDirective({
    required this.quote,
    required this.amount,
    required this.unit,
    required this.fromService,
    required this.act,
    this.startsFrom,
    this.party,
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

const _words = {
  'bir': 1,
  'iki': 2,
  'üç': 3,
  'dört': 4,
  'beş': 5,
  'altı': 6,
  'yedi': 7,
  'sekiz': 8,
  'dokuz': 9,
  'on': 10,
  'on beş': 15,
  'onbeş': 15,
  'yirmi': 20,
  'otuz': 30,
  'kırk beş': 45,
  'altmış': 60,
  'doksan': 90,
};

final _number =
    '(?:\\(?\\d{1,3}\\)?|${(_words.keys.toList()..sort((a, b) => b.length.compareTo(a.length))).join('|')})';

/// "iki (2) hafta içinde", "(30) gün içinde", "15 (onbeş) gün içerisinde",
/// "3 iş günü zarfında".
final _span = RegExp(
  '(?<![\\p{L}\\d])($_number)(?:\\s*\\(\\s*(?:\\d{1,3}|[\\p{L} ]{2,12})\\s*\\))?\\s+'
  '(iş\\s+günü|gün|hafta|ay|yıl)\\s+(?:içinde|içerisinde|zarfında)',
  caseSensitive: false,
  unicode: true,
);

/// The envelope's directives, in its order; the same time for the same act
/// once.
List<EnvelopeDirective> envelopeDirectives(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final out = <EnvelopeDirective>[];
  final seen = <String>{};
  for (final sentence in flat.split(
    RegExp(r'(?<=[.!?;])\s+(?=[A-ZÇĞİÖŞÜ0-9("“])'),
  )) {
    // A law quoted in the letter ("… kazadan sonraki 3 iş günü içinde …
    // bildirimde bulunur.") is not a directive to its reader.
    final own = sentence
        .replaceAll(RegExp(r'"[^"]*"'), ' ')
        .replaceAll(RegExp(r'“[^”]*”'), ' ');
    for (final m in _span.allMatches(own)) {
      // Each time read by its own clause, not by the whole sentence: a
      // service, an act or a past omission in another clause ("…
      // verilmediğinden ceza verildi; tebliğden itibaren 30 gün içinde
      // itiraz hakkınız vardır") says nothing of this time.
      final from = own.lastIndexOf(RegExp(r'[;:]'), m.start);
      final to = own.indexOf(RegExp(r'[;:]'), m.end);
      final clause = _lower(
        own.substring(from < 0 ? 0 : from + 1, to < 0 ? own.length : to),
      );
      if (!_speaksToReader(clause) && !clause.contains('tebli')) continue;
      if (RegExp(
        r'yapılmadığından|verilmediğinden|bildirilmediğinden|verilmemesi nedeniyle',
      ).hasMatch(clause)) {
        continue;
      }
      final before = _lower(own.substring(0, m.start));
      // "kazadan sonraki 3 iş günü içinde": another event's time.
      if (RegExp(r'sonraki\s*$').hasMatch(before.trimRight())) continue;
      final amount = _amount(m.group(1)!);
      if (amount == null || amount <= 0) continue;
      final unit = switch (_lower(m.group(2)!)
          .replaceAll(RegExp(r'\s+'), ' ')) {
        'iş günü' => SureBirimi.isGunu,
        'gün' => SureBirimi.gun,
        'hafta' => SureBirimi.hafta,
        'ay' => SureBirimi.ay,
        _ => SureBirimi.yil,
      };
      final act = _act(clause);
      final startsFrom = _startsFrom(clause);
      final party = _speaksToReader(clause) ? null : _party(clause);
      final key = '$amount|${unit.name}|$act|$startsFrom|$party';
      if (!seen.add(key)) continue;
      out.add(
        EnvelopeDirective(
          quote: sentence.length > 400
              ? '${sentence.substring(0, 400)}…'
              : sentence,
          amount: amount,
          unit: unit,
          fromService: _fromService.hasMatch(clause),
          act: act,
          startsFrom: startsFrom,
          party: party,
        ),
      );
    }
  }
  return out;
}

/// "tebliğinden itibaren", "tebliğ tarihinden itibaren", "tebellüğden
/// itibaren", "tebliğden başlayarak": the time runs from the service. A
/// bare "ihtar ve tebliğ olunur" is the serving, not a start.
final _fromService = RegExp(
  r'(tebli|tebellü)\p{L}*\s+(tarihinden\s+)?(itibaren|başla)',
  unicode: true,
);

/// "tefhimden itibaren", "kararın tebliğinden" is the service; "karar
/// tarihinden itibaren", "ilandan itibaren", "öğrenmeden itibaren" are not.
String? _startsFrom(String lower) {
  final m = RegExp(
    r'(tefhim|karar\s+tarihi|ilan|öğrenme)\p{L}*\s+(?:tarihinden\s+)?'
    r'(?:itibaren|başla)',
    unicode: true,
  ).firstMatch(lower);
  if (m == null) return null;
  final w = m.group(1)!;
  if (w.startsWith('tefhim')) return 'tefhim';
  if (w.startsWith('karar')) return 'karar';
  if (w.startsWith('ilan')) return 'ilan';
  return 'ogrenme';
}

/// The party a clause gives its duty to: "davalı tarafa", "davacıya",
/// "borçlu vekiline". Two parties named, or none: null.
String? _party(String lower) {
  final found = <String>{
    for (final m in RegExp(
      r'(davacı|davalı|alacaklı|borçlu)'
      r'(?:\s+(?:tarafa|vekiline|vekillerine)|ya|ye|lara|lere)\b',
      unicode: true,
    ).allMatches(lower))
      switch (m.group(1)!) {
        'davacı' => 'davaci',
        'davalı' => 'davali',
        'alacaklı' => 'alacakli',
        _ => 'borclu',
      },
  };
  return found.length == 1 ? found.single : null;
}

bool _speaksToReader(String lower) =>
    lower.contains('hakkınız') ||
    RegExp(
      r'\p{L}(nız|niz|nuz|nüz|ınız|iniz|unuz|ünüz)\b',
      unicode: true,
    ).hasMatch(lower);

int? _amount(String raw) {
  final digits = RegExp(r'\d{1,3}').firstMatch(raw);
  if (digits != null) return int.parse(digits.group(0)!);
  return _words[_lower(raw).trim().replaceAll(RegExp(r'\s+'), ' ')];
}

String _act(String lower) {
  if (lower.contains('istinaf') ||
      lower.contains('temyiz') ||
      lower.contains('kanun yolu')) {
    return 'kanunYolu';
  }
  if (lower.contains('itiraz')) return 'itiraz';
  if (lower.contains('cevap') ||
      lower.contains('savunma') ||
      lower.contains('iddia ve')) {
    return 'cevap';
  }
  if (lower.contains('öde') || lower.contains('yatır')) return 'odeme';
  if (lower.contains('delil') || lower.contains('tanık')) return 'delil';
  if (lower.contains('beyan')) return 'beyan';
  return 'genel';
}

String _lower(String s) =>
    s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
