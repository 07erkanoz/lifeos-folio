/// A light Turkish stem finder, so that matching survives inflection.
///
/// Not a morphological analyser and not trying to be: the whole job is to let
/// a search for "iş kazaları" find a decision that says "iş kazası", and
/// "tazminatın" find "tazminat". Turkish adds to the ends of words, so a
/// search that matches whole words only misses most of what it is looking
/// for.
///
/// It is deliberately cautious, because over-stripping costs precision:
///
///  * Only the common noun inflections come off — plural, possessive, case.
///    Verb endings and the suffixes that make new words (-lık, -cı, -sız,
///    -dı, -yor) are left alone, because taking those off changes what the
///    word means.
///  * Nothing is stripped that would leave a stem under four letters, so
///    short words keep their shape: "kanun" must not become "kan", and
///    "dava" and "kaza" must not be touched at all.
///  * A bare trailing vowel comes off only from a word of six letters or
///    more — "tazminatı" becomes "tazminat", while "kaza" is left whole.
///
/// What matters is not that the stem is the true root, but that every
/// inflection of one word lands on the same stem, so they match each other.
class TurkishStem {
  const TurkishStem._();

  // Longest first, so the fullest ending is the one taken off.
  static const _endings = <String>[
    'larından', 'lerinden', 'larının', 'lerinin', 'larında', 'lerinde',
    'larına', 'lerine', 'larını', 'lerini', 'larıyla', 'leriyle',
    'sından', 'sinden', 'sundan', 'sünden', 'sının', 'sinin', 'sunun',
    'sünün',
    'sında', 'sinde', 'sunda', 'sünde', 'sına', 'sine', 'suna', 'süne',
    'sını', 'sini', 'sunu', 'sünü',
    'ından', 'inden', 'undan', 'ünden', 'ının', 'inin', 'unun', 'ünün',
    'ında', 'inde', 'unda', 'ünde', 'ına', 'ine', 'una', 'üne',
    'ını', 'ini', 'unu', 'ünü',
    'ları', 'leri', 'lara', 'lere', 'larda', 'lerde', 'lardan', 'lerden',
    'ların', 'lerin',
    'nın', 'nin', 'dan', 'den', 'tan', 'ten', 'lar', 'ler',
    'yla', 'yle', 'sı', 'si', 'su', 'sü', 'da', 'de', 'la', 'le',
    'ya', 'ye', 'yı', 'yi', 'yu', 'yü', 'ın', 'in', 'un', 'ün',
    // 'ta' and 'te' are left out on purpose: they would eat a stem that
    // ends in t — "tazminata" would become "tazmina". The trailing-vowel
    // step below reaches "tazminat" correctly instead.
    //
    // 'nun', 'nün' and a bare 'nı/ni/nu/nü' are left out for the same
    // reason, against a stem ending in n: "kanunu" would become "kanu".
    // The two-letter 'un'/'ün' plus the trailing-vowel step reaches
    // "kanun". 'nın'/'nin' is kept, because there it joins a stem ending
    // in a vowel: "davanın" becomes "dava".
  ];

  static const _vowels = {'a', 'e', 'ı', 'i', 'o', 'ö', 'u', 'ü'};

  /// The word reduced to roughly its stem. The word must already be in
  /// Turkish lower case; see [lowerTr] in legal_terms.dart.
  static String of(String word) {
    var stem = word;
    // Twice, because a word can carry two of these at once: "kararlarında"
    // is plural and then case.
    for (var pass = 0; pass < 2; pass++) {
      var stripped = false;
      for (final ending in _endings) {
        if (stem.endsWith(ending) && stem.length - ending.length >= 4) {
          stem = stem.substring(0, stem.length - ending.length);
          stripped = true;
          break;
        }
      }
      if (!stripped) break;
    }
    if (stem.length >= 6 && _vowels.contains(stem[stem.length - 1])) {
      stem = stem.substring(0, stem.length - 1);
    }
    return stem;
  }
}
