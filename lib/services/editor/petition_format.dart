/// "Biçimlendir" (GELISTIRME.md §7): a petition's lines set the way a
/// filing is set, by rules a lawyer would apply by hand. Only what each
/// line is decides what it gets; the words are not changed but for the
/// spaces between a label and its colon, which become a tab.
library;

/// What a line of a petition is.
enum PetitionLine {
  /// "ANTALYA 3. ASLİYE HUKUK MAHKEMESİ'NE": centred, bold.
  court,

  /// "AÇIKLAMALAR", "SONUÇ VE İSTEM": bold.
  heading,

  /// "DAVACI     : Ayşe Karaca": the colons in one column.
  label,

  /// "1- …", "2) …": the rows after the first under its text.
  numbered,

  /// The text of the petition: justified, its first row set in.
  body,

  /// "Davacı Vekili", "Av. Deniz Kaya" at the end: to the right.
  signature,

  /// Empty, or nothing a rule is sure of: left as it is.
  other,
}

/// What a line gets.
class LineFormat {
  const LineFormat(
    this.kind, {
    this.text,
    this.align,
    this.bold = false,
    this.left,
    this.first,
    this.hanging,
    this.tabs,
  });

  final PetitionLine kind;

  /// The line's new words; null leaves them.
  final String? text;

  /// "center", "right", "justify", "left"; null leaves it.
  final String? align;
  final bool bold;

  /// Indents in points, and the tab set (UDF's "points:kind"); null leaves
  /// each as it was.
  final double? left, first, hanging;
  final String? tabs;
}

class PetitionFormat {
  const PetitionFormat._();

  /// 1.25 cm, the first row's step in a body paragraph.
  static const bodyIndent = 1.25 * 72 / 2.54;

  /// Room between the longest label and the colons' column.
  static const labelGap = 8.0;

  static const _letters = 'A-ZÇĞİÖŞÜÂÎÛ';

  static final _court = RegExp(
    "(MAHKEMES[İI]|MÜDÜRLÜĞÜ|BAŞKANLIĞI|H[AÂ]K[İI]MLİĞİ|SAVCILIĞI|"
    "DAİRESİ|KURULU)[’']?(NE|NA|E|A)\\s*\$",
  );

  static final _label = RegExp(
    '^\\s*([$_letters][${_letters}0-9 ./()-]{0,28}?[$_letters.)])'
    '\\s*:\\s*(\\S.*)\$',
  );

  static final _numbered = RegExp(r'^\s*(\d{1,2}\s*[-.)])\s+\S');

  static final _signature = RegExp(
    r'^\s*(Av\.|Avukat\b|(Davacı|Davalı|Alacaklı|Borçlu|Müşteki|Şüpheli|Sanık|Katılan|Başvurucu|İtiraz Eden)(\s+\S+){0,2}\s+Vekili\b|Vekili\b)',
    caseSensitive: false,
  );

  static const _headings = {
    'AÇIKLAMALAR',
    'AÇIKLAMA',
    'HUKUKİ NEDENLER',
    'HUKUKİ SEBEPLER',
    'HUKUKİ DELİLLER',
    'DELİLLER',
    'SONUÇ VE İSTEM',
    'SONUÇ VE TALEP',
    'NETİCE VE TALEP',
    'TALEP SONUCU',
    'OLAYLAR',
    'İTİRAZLARIMIZ',
    'EKLER',
  };

  static bool _upper(String s) =>
      s.isNotEmpty &&
      s == s.toUpperCase() &&
      RegExp('[$_letters]').hasMatch(s) &&
      !RegExp('[a-zçğıöşü]').hasMatch(s);

  /// What each of [lines] is. [measure] gives a text's width in points in
  /// the petition's font: the labels' column is set by the widest label.
  static List<LineFormat> plan(
    List<String> lines, {
    required double Function(String text) measure,
  }) {
    final kinds = List.filled(lines.length, PetitionLine.other);
    final seen = <int>[];
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.isEmpty) continue;
      seen.add(i);
      final words = t.split(RegExp(r'\s+')).length;
      if (seen.length <= 4 && _upper(t) && _court.hasMatch(t)) {
        kinds[i] = PetitionLine.court;
      } else if (_label.hasMatch(t) &&
          _upper(_label.firstMatch(t)![1]!) &&
          t.length < 200) {
        kinds[i] = PetitionLine.label;
      } else if (_headings.contains(t.replaceAll(RegExp(r'[\s:]+$'), '')) ||
          (_upper(t) && words <= 5 && t.length <= 40 && !t.contains(':'))) {
        kinds[i] = PetitionLine.heading;
      } else if (_numbered.hasMatch(t)) {
        kinds[i] = PetitionLine.numbered;
      } else if (RegExp('[a-zçğıöşü]').hasMatch(t) && t.length > 60) {
        kinds[i] = PetitionLine.body;
      }
    }
    // The signature: short lines at the end that name the signer.
    for (final i in seen.reversed.take(6)) {
      final t = lines[i].trim();
      if (t.length > 60) break;
      if (_signature.hasMatch(t)) kinds[i] = PetitionLine.signature;
    }

    // One column for the labels: the widest label and its gap.
    final labels = [
      for (var i = 0; i < lines.length; i++)
        if (kinds[i] == PetitionLine.label)
          _label.firstMatch(lines[i].trim())![1]!.trim(),
    ];
    final stop = labels.isEmpty
        ? 0.0
        : (labels.map(measure).reduce((a, b) => a > b ? a : b) + labelGap)
              .ceilToDouble();
    final valueAt = stop + measure(': ');

    return [
      for (var i = 0; i < lines.length; i++)
        switch (kinds[i]) {
          PetitionLine.court => const LineFormat(
            PetitionLine.court,
            align: 'center',
            bold: true,
            left: 0,
            first: 0,
            hanging: 0,
          ),
          PetitionLine.heading => const LineFormat(
            PetitionLine.heading,
            bold: true,
          ),
          PetitionLine.label => () {
            final m = _label.firstMatch(lines[i].trim())!;
            return LineFormat(
              PetitionLine.label,
              text: '${m[1]!.trim()}\t: ${m[2]!.trim()}',
              align: 'left',
              left: 0,
              first: 0,
              // A value running onto a second row starts under the first.
              hanging: valueAt,
              tabs: '${stop.toStringAsFixed(1)}:0',
            );
          }(),
          PetitionLine.numbered => LineFormat(
            PetitionLine.numbered,
            align: 'justify',
            left: 0,
            first: 0,
            hanging: measure(
              '${_numbered.firstMatch(lines[i].trim())![1]!.trim()} ',
            ).ceilToDouble(),
          ),
          PetitionLine.body => const LineFormat(
            PetitionLine.body,
            align: 'justify',
            left: 0,
            first: bodyIndent,
            hanging: 0,
          ),
          PetitionLine.signature => const LineFormat(
            PetitionLine.signature,
            align: 'right',
            first: 0,
            hanging: 0,
          ),
          PetitionLine.other => const LineFormat(PetitionLine.other),
        },
    ];
  }
}
