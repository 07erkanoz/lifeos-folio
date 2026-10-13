import '../clients/client.dart';
import '../clients/client_accounts.dart';
import '../portal/portal_database.dart';
import '../uyap/uyap_web_service.dart';

/// What a line of an enforcement file's own account in Folio is.
enum LedgerKind {
  /// The debtor paid the lawyer outside the office: until the office
  /// records it, UYAP's debt is the more by it.
  external('haricen', 'Haricen tahsilat'),

  /// The creditor waived part or all of the claim.
  waiver('feragat', 'Feragat');

  const LedgerKind(this.code, this.label);
  final String code, label;

  static LedgerKind? of(Object? code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// A line of an enforcement file's own account in Folio (Folio hesabı):
/// a payment made outside the office or a claim waived, which UYAP does
/// not know of until the office records the lawyer's request. Till then
/// the debt Folio shows is UYAP's less it; once UYAP shows it, it is
/// official and no longer taken off twice.
class LedgerEntry {
  const LedgerEntry(this.record);

  final ClientRecord record;

  String get id => record.id;
  LedgerKind get kind =>
      LedgerKind.of(record.data['tur']) ?? LedgerKind.external;
  String get caseKey => record.text('dosya');

  /// Kuruş.
  int get amount => record.amount;
  DateTime get at => record.at;

  /// Who paid it: a debtor of the file, by name.
  String get debtor => record.text('borclu');
  String get way => record.text('odeme');
  String get note => record.text('aciklama');

  /// Whether it settled the whole debt (or waived the whole claim).
  bool get whole => record.data['tamami'] == true;

  /// When the office (icra müdürlüğü) was told of it, by the lawyer's
  /// word; null while it was not. A payment told and not yet shown by UYAP
  /// still counts against the debt Folio shows.
  DateTime? get reported => DateTime.tryParse(record.text('bildirildi'));
  bool get isReported => reported != null;

  /// What UYAP showed it as (a collection's receipt, or the lawyer's word
  /// "elle"); empty while UYAP does not show it.
  String get official => record.text('resmi');
  bool get isOfficial => official.isNotEmpty;

  /// UYAP's balance when it was written, in kuruş; null when not known.
  int? get uyapLeftThen => record.data['uyapBakiye'] is int
      ? record.data['uyapBakiye'] as int
      : null;
}

/// [caseKey]'s own account in Folio, the oldest first; none taken off.
List<LedgerEntry> ledgerOf(PortalDatabase db, String caseKey) => [
  for (final r in db.allClientRecords())
    if (!r.removed &&
        r.kind == ClientRecordKind.enforcement &&
        r.text('dosya') == caseKey)
      LedgerEntry(r),
]..sort((a, b) => a.at.compareTo(b.at));

/// The key a collection of UYAP's is known by.
String collectionKey(UyapMoneyItem c) => c.receipt.isNotEmpty
    ? 'makbuz:${c.receipt}'
    : 'tahsilat:${c.date}|${c.amount}';

/// Which of [entries] UYAP now shows, by their id: each payment made
/// outside matched to a collection of UYAP's of the same sum, made no
/// sooner than a few days before it, that no other entry took; one UYAP
/// calls "haricen" first. A waiver UYAP does not list: the lawyer says.
/// [parse] reads UYAP's day.
Map<String, String> officialMatches(
  List<LedgerEntry> entries,
  List<UyapMoneyItem> collections,
  DateTime? Function(String raw) parse,
) {
  final taken = {
    for (final e in entries)
      if (e.isOfficial) e.official,
  };
  final out = <String, String>{};
  bool outside(UyapMoneyItem c) =>
      UyapWebService.fold(c.kind).contains('haric');
  for (final e in entries) {
    if (e.isOfficial || e.kind != LedgerKind.external) continue;
    final fits = [
      for (final c in collections)
        if ((c.amount * 100).round() == e.amount &&
            !taken.contains(collectionKey(c)) &&
            !(parse(c.date)?.isBefore(e.at.subtract(const Duration(days: 3))) ??
                false))
          c,
    ]..sort((a, b) => (outside(b) ? 1 : 0) - (outside(a) ? 1 : 0));
    if (fits.isEmpty) continue;
    final key = collectionKey(fits.first);
    taken.add(key);
    out[e.id] = key;
  }
  return out;
}

/// The debt as Folio counts it: UYAP's balance less what was paid outside
/// or waived that UYAP does not show yet; null while UYAP's is not known.
double? folioLeft(double? uyapLeft, Iterable<LedgerEntry> entries) {
  if (uyapLeft == null) return null;
  final pending = entries
      .where((e) => !e.isOfficial)
      .fold<int>(0, (n, e) => n + e.amount);
  final left = uyapLeft - pending / 100;
  return left < 0 ? 0 : left;
}
