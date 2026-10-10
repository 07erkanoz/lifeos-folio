/// What a suggestion is made of: a phrase a lawyer writes again and again,
/// and the rules for finding such phrases in a document and matching them
/// against what is being typed.
library;

/// [text] with Turkish letters and their plain look-alikes made the same,
/// and lower case: "İcra" and "icra", "Şikâyet" and "sikayet" match. Dart's
/// own toLowerCase puts a combining dot on a capital İ, so it is not used
/// for those letters.
String foldPhrase(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    out.write(_folded[char] ?? char.toLowerCase());
  }
  return out.toString();
}

const _folded = {
  'ı': 'i',
  'İ': 'i',
  'I': 'i',
  'ş': 's',
  'Ş': 's',
  'ğ': 'g',
  'Ğ': 'g',
  'ü': 'u',
  'Ü': 'u',
  'ö': 'o',
  'Ö': 'o',
  'ç': 'c',
  'Ç': 'c',
  'â': 'a',
  'Â': 'a',
  'î': 'i',
  'Î': 'i',
  'û': 'u',
  'Û': 'u',
};

final _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _word = RegExp(r"[\p{L}\p{N}][\p{L}\p{N}.\-/’']*", unicode: true);

/// Where a clause ends: a sentence mark, a colon or semicolon, a comma, a
/// bracket, or a line. A suggestion never runs across one. A full stop is
/// handled apart, in [clausesOf].
final _clauseEnd = RegExp(r'[;:!?,()\[\]\n\r\t•]');

/// Words after which a full stop abbreviates rather than ends a sentence.
const _abbreviations = {
  'm',
  'md',
  'av',
  'no',
  'vb',
  'vs',
  'bkz',
  'sn',
  'dr',
  'prof',
  'doç',
  'yrd',
  'doc',
  'st',
  'mah',
  'cad',
  'sok',
  'sk',
  'apt',
  'blv',
  'tc',
  't',
  'c',
  'e',
  'k',
  's',
  'hmk',
  'tmk',
  'tbk',
  'ttk',
  'iik',
  'tck',
  'cmk',
};

/// [text] cut into clauses. A full stop ends one only where it ends a
/// sentence: not after a number ("1. Asliye Hukuk"), nor after an
/// abbreviation ("m. 166", "Av.").
List<String> clausesOf(String text) {
  final out = <String>[];
  for (final part in text.split(_clauseEnd)) {
    var start = 0;
    for (var i = 0; i < part.length; i++) {
      if (part[i] != '.') continue;
      final next = i + 1 < part.length ? part[i + 1] : ' ';
      if (next.trim().isNotEmpty) continue; // 1.5, www.x, T.C.
      final word = RegExp(r'(\S+)$').firstMatch(part.substring(start, i));
      final last = word?.group(1) ?? '';
      if (RegExp(r'^\d+$').hasMatch(last)) continue;
      if (_abbreviations.contains(foldPhrase(last))) continue;
      out.add(part.substring(start, i));
      start = i + 1;
    }
    out.add(part.substring(start));
  }
  return out;
}

/// The phrases in [text] worth remembering: clauses of 10–120 characters
/// with at least two words, as written, without personal data. One each,
/// however often the document repeats it; keyed by [foldPhrase].
Map<String, String> phrasesIn(String text) {
  final found = <String, String>{};
  for (final raw in clausesOf(text)) {
    final phrase = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (phrase.length < 10 || phrase.length > 120) continue;
    if (_word.allMatches(phrase).length < 2) continue;
    // Numbered items, stray page numbers and the like start elsewhere.
    if (!_startsWord.hasMatch(phrase)) continue;
    if (isPersonal(phrase)) continue;
    found.putIfAbsent(foldPhrase(phrase), () => phrase);
  }
  return found;
}

final _startsWord = RegExp(r'^\p{L}', unicode: true);

/// Whether [phrase] carries something about a person, a place or a case
/// that must never be offered back: an identity, tax or registry number,
/// an IBAN, a telephone number, an e-mail or web address, a street
/// address, a date, a case number, or a name written the way filings write
/// names ("Ahmet YILMAZ", "AHMET YILMAZ TC").
bool isPersonal(String phrase) {
  if (_personal.any((p) => p.hasMatch(phrase))) return true;
  for (final m in _name.allMatches(phrase)) {
    if (!_notSurname(m.group(1)!)) return true;
  }
  // A name all in capitals inside a sentence: "DENİZ YILMAZ
  // görevlendirilmiştir". A heading in capitals ("SONUÇ VE İSTEM",
  // "MANAVGAT 1. ASLİYE HUKUK MAHKEMESİNE") has no lower case at all.
  if (_lowerCase.hasMatch(phrase)) {
    for (final m in _capitals.allMatches(phrase)) {
      if (!_notSurname(m.group(1)!) && !_notSurname(m.group(2)!)) return true;
    }
  }
  // Numbers of four digits or more are years, registry and case numbers,
  // except a law's number: "7036 sayılı".
  for (final m in RegExp(r'\d{4,}').allMatches(phrase)) {
    final after = foldPhrase(phrase.substring(m.end)).trimLeft();
    if (!after.startsWith('sayili')) return true;
  }
  return false;
}

final _personal = [
  // Groups of digits in a row: telephone, identity and account numbers.
  RegExp(r'\d+[ .\-]\d+[ .\-]\d+'),
  RegExp(r'\bTR\s?\d{2}', caseSensitive: false),
  // E-mail and web addresses, and what is left of them after splitting.
  RegExp(r'[@#_]|https?:|www|\.(com|net|org|tr)\b', caseSensitive: false),
  // "T.C. kimlik", "TC", "TCKN", "vergi no", "sicil".
  RegExp(r'\b(T\.?C\.?|TCKN|VKN)\b'),
  RegExp(
    r'\b(kimlik|vergi|sicil|pasaport)\s*(no|numara)',
    caseSensitive: false,
  ),
  // Street addresses.
  RegExp(
    r'\b(mah|mahallesi|cad|caddesi|cd|sok|sokak|sokağı|sk|apt|apartmanı|'
    r'bulvarı|blv|bulvar|sitesi|daire|köyü|no)\b\.?',
    caseSensitive: false,
  ),
  // "Konyaaltı/ANTALYA", "Manavgat / ANTALYA".
  RegExp(r'\p{L}+\s*/\s*[A-ZÇĞİÖŞÜ]{3,}', unicode: true),
  // Dates and case numbers: 12.03.2024, 2023/456.
  RegExp(r'\d{1,2}[./]\d{1,2}[./]\d{2,4}'),
  RegExp(r'\d+\s*/\s*\d+'),
];

/// A name, then a word in capitals: how filings write "Ahmet YILMAZ".
final _name = RegExp(r'\b[A-ZÇĞİÖŞÜ][a-zçğıöşü]+\s+([A-ZÇĞİÖŞÜ]{2,})\b');

/// Two words in capitals in a row, each a whole word.
final _capitals = RegExp(
  r'(?<!\p{L})(\p{Lu}{2,})\s+(\p{Lu}{2,})(?!\p{L})',
  unicode: true,
);
final _lowerCase = RegExp(r'\p{Ll}', unicode: true);

/// Capitals that are not a surname: the codes' abbreviations and the words
/// a heading is written in ("Davalının TMK", "Sayın MAHKEMENİZE").
bool _notSurname(String word) {
  final folded = foldPhrase(word);
  return _codes.contains(folded) ||
      RegExp(r'^(mahkeme|hakim|baskan|savci|noter|icra|daire|vekil|dava)')
          .hasMatch(folded);
}

const _codes = {
  'tmk',
  'tbk',
  'ttk',
  'hmk',
  'iik',
  'tck',
  'cmk',
  'huak',
  'iyuk',
  'sgk',
  'kvkk',
  'ktk',
  'kmk',
  'aym',
  'ygk',
  'hgk',
  'cgk',
  'ibk',
  'bam',
  'udf',
  'uyap',
  'tl',
  'kdv',
  'abd',
  'ab',
  'ceza',

  'tc',
};

/// The words at the end of [before] that a suggestion can complete: from
/// the last clause mark or line, at most six words. Null while the caret is
/// not at the end of a word of at least two letters.
String? typedTail(String before) {
  if (before.isEmpty || !_letter.hasMatch(before[before.length - 1])) {
    return null;
  }
  final clauses = clausesOf(before);
  final clause = clauses.last;
  final words = _word.allMatches(clause).toList();
  if (words.isEmpty || words.last.end != clause.length) return null;
  if (words.last.group(0)!.length < 2) return null;
  final from = words.length > 6
      ? words[words.length - 6].start
      : words.first.start;
  return clause.substring(from);
}

/// The phrases a lawyer writes whether or not Folio has seen them yet:
/// forms of address, section headings, closings, and the names of the
/// courts and codes filings cite most.
const builtInPhrases = [
  // Hitaplar
  'Asliye Hukuk Mahkemesine',
  'Asliye Ticaret Mahkemesine',
  'Aile Mahkemesine',
  'İş Mahkemesine',
  'Sulh Hukuk Mahkemesine',
  'Tüketici Mahkemesine',
  'İcra Hukuk Mahkemesine',
  'İcra Dairesine',
  'Asliye Ceza Mahkemesine',
  'Ağır Ceza Mahkemesine',
  'Sulh Ceza Hâkimliğine',
  'İdare Mahkemesine',
  'Vergi Mahkemesine',
  'Cumhuriyet Başsavcılığına',
  'Bölge Adliye Mahkemesine',
  'Yargıtay Başkanlığına',
  'Danıştay Başkanlığına',
  'Anayasa Mahkemesi Başkanlığına',
  'Gönderilmek üzere',
  'Noterliğine',
  // Bölüm başlıkları
  'DAVACI',
  'DAVALI',
  'VEKİLİ',
  'KONU',
  'AÇIKLAMALAR',
  'HUKUKİ NEDENLER',
  'HUKUKİ DELİLLER',
  'DELİLLER',
  'SONUÇ VE İSTEM',
  'İHTAR EDEN',
  'MUHATAP',
  'ŞÜPHELİ',
  'MÜŞTEKİ',
  'SANIK',
  'KATILAN',
  'ALACAKLI',
  'BORÇLU',
  'İTİRAZ EDEN',
  'DAVA DEĞERİ',
  'TEBLİĞ TARİHİ',
  'KARAR TARİHİ',
  'İSTİNAF EDEN',
  'TEMYİZ EDEN',
  'KARŞI TARAF',
  'EKLER',
  // Kapanışlar ve sık cümleler
  'Saygılarımla arz ederim',
  'Saygılarımla arz ve talep ederim',
  'Gereğini saygılarımla arz ederim',
  'Gereğinin yapılmasını saygılarımla arz ve talep ederim',
  'Yukarıda açıklanan nedenlerle',
  'Yukarıda arz ve izah edilen nedenlerle',
  'Sayın Mahkemenizce resen gözetilecek nedenlerle',
  'Davanın kabulüne karar verilmesini',
  'Davanın reddine karar verilmesini',
  'Yargılama giderleri ile vekâlet ücretinin karşı tarafa yükletilmesine',
  'Yargılama giderleri ile vekâlet ücretinin davalı tarafa yükletilmesine',
  'İhtiyati tedbir kararı verilmesini',
  'İhtiyati haciz kararı verilmesini',
  'Bilirkişi incelemesi yapılmasını',
  'Tanık beyanları',
  'Her türlü yasal delil',
  'Yemin dâhil her türlü yasal delil',
  'Vekâletname sureti',
  'Duruşma günü verilmesini',
  'Mazeretimin kabulü ile duruşmanın ertelenmesini',
  'Kararın kaldırılmasına karar verilmesini',
  'Kararın bozulmasına karar verilmesini',
  'Yürütmenin durdurulmasına karar verilmesini',
  'İstinaf kanun yolu açık olmak üzere',
  'Temyiz kanun yolu açık olmak üzere',
  'Gerekçeli kararın tebliğinden itibaren',
  'Müvekkil adına',
  'Müvekkilimiz',
  // Kanunlar
  'Türk Medeni Kanunu',
  'Türk Borçlar Kanunu',
  'Türk Ticaret Kanunu',
  'Hukuk Muhakemeleri Kanunu',
  'İcra ve İflas Kanunu',
  'Türk Ceza Kanunu',
  'Ceza Muhakemesi Kanunu',
  'İdari Yargılama Usulü Kanunu',
  'İş Kanunu',
  'Tüketicinin Korunması Hakkında Kanun',
  'Avukatlık Kanunu',
  'Kat Mülkiyeti Kanunu',
  'Tapu Kanunu',
  'Karayolları Trafik Kanunu',
  'Kişisel Verilerin Korunması Kanunu',
  'Arabuluculuk Kanunu',
  'Hukuk Uyuşmazlıklarında Arabuluculuk Kanunu',
  'Harçlar Kanunu',
  'Anayasa',
  'Yargıtay İçtihadı Birleştirme Büyük Genel Kurulu',
  'Yargıtay Hukuk Genel Kurulu',
];
