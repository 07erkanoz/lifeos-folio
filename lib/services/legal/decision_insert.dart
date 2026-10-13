import 'case_law.dart';
import 'rich_text.dart' show fullCourtName;

/// A decision written into a petition as the filing cites one
/// (GELISTIRME.md §5): the court in the genitive, the date, the numbers;
/// with the passage chosen in quotes, or alone as "bu yöndedir".
///
/// No model is asked: everything here comes from the official bank.
class DecisionInsert {
  const DecisionInsert._();

  /// Set by the editor while one is open: where "Dilekçeye ekle" writes.
  /// [quote] is the passage chosen in the decision (empty: none);
  /// [beforeConclusion] puts it before the petition's SONUÇ heading.
  static void Function(
    Decision decision, {
    String quote,
    bool beforeConclusion,
  })?
  target;

  /// [name] with its genitive ending, as a proper name takes it: after an
  /// apostrophe, with the vowel its last vowel calls for and an n before it
  /// when the name ends in a vowel. "Dairesi'nin", "Kurulu'nun",
  /// "Mahkemesi'nin", "Yargıtay'ın".
  static String genitive(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;
    const vowels = 'aeıioöuüAEIİOÖUÜ';
    final last = trimmed
        .split('')
        .lastWhere(vowels.contains, orElse: () => 'e');
    // Turkish's own pairs: Dart's toLowerCase takes I for i.
    final harmony = switch (last) {
      'a' || 'ı' || 'A' || 'I' => 'ı',
      'e' || 'i' || 'E' || 'İ' => 'i',
      'o' || 'u' || 'O' || 'U' => 'u',
      _ => 'ü',
    };
    final end = trimmed[trimmed.length - 1];
    return vowels.contains(end)
        ? "$trimmed'n${harmony}n"
        : "$trimmed'${harmony}n";
  }

  /// The decision's particulars as the sentence opens: "Yargıtay 9. Hukuk
  /// Dairesi'nin 12.03.2024 tarihli, 2023/1234 E. ve 2024/567 K. sayılı".
  static String particulars(Decision d) {
    final court = fullCourtName(d.court).trim();
    final numbers = d.karar.trim().isEmpty
        ? '${d.esas} sayılı'
        : '${d.esas} E. ve ${d.karar} K. sayılı';
    return [
      if (court.isNotEmpty) genitive(court),
      if (d.date.trim().isNotEmpty) '${d.date.trim()} tarihli,',
      numbers,
    ].join(' ');
  }

  /// The runs to write, each bold or italic: the particulars bold, the
  /// passage in quotes and italic. [same] for one written right after
  /// another: "Aynı yönde, ".
  static List<({String text, bool bold, bool italic})> runs(
    Decision d, {
    String quote = '',
    bool same = false,
  }) {
    final passage = quote.trim().replaceAll(RegExp(r'\s+'), ' ');
    final lead = same ? 'Aynı yönde, ' : '';
    if (passage.isEmpty) {
      return [
        if (lead.isNotEmpty) (text: lead, bold: false, italic: false),
        (text: '${particulars(d)} kararı', bold: true, italic: false),
        (text: ' da bu yöndedir.', bold: false, italic: false),
      ];
    }
    return [
      if (lead.isNotEmpty) (text: lead, bold: false, italic: false),
      (text: '${particulars(d)} kararında;', bold: true, italic: false),
      (text: ' ', bold: false, italic: false),
      (text: '“$passage”', bold: false, italic: true),
      (text: ' şeklinde hüküm kurulmuştur.', bold: false, italic: false),
    ];
  }

  static final _conclusion = RegExp(
    r'^\s*(SONUÇ\s+VE\s+İSTEM|SONUÇ\s+VE\s+TALEP|NETİCE\s+VE\s+TALEP|'
    r'TALEP\s+SONUCU|SONUÇ\s+VE\s+İSTEMLER|NETİCE-İ\s+TALEP)\b',
    multiLine: true,
  );

  /// Where the petition's conclusion heading begins in [plain], the start
  /// of its line; null when it has none.
  static int? conclusionAt(String plain) =>
      _conclusion.firstMatch(plain)?.start;
}
