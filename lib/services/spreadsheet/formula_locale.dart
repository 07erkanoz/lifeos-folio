/// Formulas as a Turkish Excel user types them, in the form a file keeps.
///
/// Excel stores every formula with English function names and commas between
/// arguments, and shows it in the language of its interface: someone used to
/// the Turkish one writes `=TOPLA(A1;A9)` for what the file calls
/// `=SUM(A1,A9)`. Both are accepted here and kept the way the file needs.
library;

const _functions = {
  'TOPLA': 'SUM',
  'ETOPLA': 'SUMIF',
  'ÇOKETOPLA': 'SUMIFS',
  'TOPLA.ÇARPIM': 'SUMPRODUCT',
  'ÇARPIM': 'PRODUCT',
  'ORTALAMA': 'AVERAGE',
  'EĞERORTALAMA': 'AVERAGEIF',
  'ORTANCA': 'MEDIAN',
  'MİN': 'MIN',
  'MAK': 'MAX',
  'BAĞ_DEĞ_SAY': 'COUNT',
  'BAĞ_DEĞ_DOLU_SAY': 'COUNTA',
  'BOŞLUKSAY': 'COUNTBLANK',
  'EĞERSAY': 'COUNTIF',
  'ÇOKEĞERSAY': 'COUNTIFS',
  'EĞER': 'IF',
  'ÇOKEĞER': 'IFS',
  'EĞERHATA': 'IFERROR',
  'VE': 'AND',
  'YADA': 'OR',
  'DEĞİL': 'NOT',
  'YUVARLA': 'ROUND',
  'YUKARIYUVARLA': 'ROUNDUP',
  'AŞAĞIYUVARLA': 'ROUNDDOWN',
  'TAMSAYI': 'INT',
  'MUTLAK': 'ABS',
  'KAREKÖK': 'SQRT',
  'KUVVET': 'POWER',
  'DÜŞEYARA': 'VLOOKUP',
  'YATAYARA': 'HLOOKUP',
  'İNDİS': 'INDEX',
  'KAÇINCI': 'MATCH',
  'BİRLEŞTİR': 'CONCATENATE',
  'SOLDAN': 'LEFT',
  'SAĞDAN': 'RIGHT',
  'PARÇAAL': 'MID',
  'UZUNLUK': 'LEN',
  'BÜYÜKHARF': 'UPPER',
  'KÜÇÜKHARF': 'LOWER',
  'KIRP': 'TRIM',
  'METNEÇEVİR': 'TEXT',
  'SAYIYAÇEVİR': 'VALUE',
  'BUGÜN': 'TODAY',
  'ŞİMDİ': 'NOW',
  'TARİH': 'DATE',
  'YIL': 'YEAR',
  'AY': 'MONTH',
  'GÜN': 'DAY',
  'HAFTANINGÜNÜ': 'WEEKDAY',
  'TAMİŞGÜNÜ': 'NETWORKDAYS',
  'SERİTARİH': 'EDATE',
  'SERİAY': 'EOMONTH',
  'KÖPRÜ': 'HYPERLINK',
};

final _name = RegExp(
  r'[A-Za-zÇĞİÖŞÜçğıöşü_][A-Za-zÇĞİÖŞÜçğıöşü0-9_.]*(?=\s*\()',
);

/// [formula] (with its leading `=`) with Turkish function names replaced by
/// Excel's own, and `;` between arguments turned into `,`. Text in quotes and
/// array constants in braces are left exactly as written.
String excelFormula(String formula) {
  final out = StringBuffer();
  var inString = false, turkish = false;
  var i = 0;
  while (i < formula.length) {
    final char = formula[i];
    if (char == '"') {
      inString = !inString;
      out.write(char);
      i++;
      continue;
    }
    if (inString) {
      out.write(char);
      i++;
      continue;
    }
    final match = _name.matchAsPrefix(formula, i);
    if (match != null) {
      final word = match.group(0)!;
      final english = _functions[_upper(word)];
      if (english != null) turkish = true;
      out.write(english ?? word);
      i += word.length;
      continue;
    }
    out.write(char);
    i++;
  }
  final text = out.toString();
  // English formulas use `;` only between the rows of an array constant, so
  // it is read as the Turkish argument separator only outside braces, and
  // only when the formula was written the Turkish way or has no commas.
  if (!turkish && text.contains(',')) return text;
  return _separators(text);
}

String _separators(String text) {
  final out = StringBuffer();
  var inString = false, braces = 0;
  for (final char in text.split('')) {
    if (char == '"') inString = !inString;
    if (!inString && char == '{') braces++;
    if (!inString && char == '}') braces--;
    out.write(!inString && braces == 0 && char == ';' ? ',' : char);
  }
  return out.toString();
}

/// Upper case the Turkish way: `i` becomes `İ`, not `I`.
String _upper(String word) =>
    word.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
