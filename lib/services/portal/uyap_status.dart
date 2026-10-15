import '../uyap/uyap_case_store.dart';
import 'case_sections.dart';
import 'observed.dart';
import 'portal_channel.dart';
import 'portal_database.dart';
import 'portal_sync.dart';

/// A section of a case that would not be read: tried, failed, not yet
/// read done since.
typedef FailedSection = ({
  String number,
  String court,
  CaseSection section,
  PortalChannel channel,
  int tries,
});

/// What Folio holds of UYAP, as the lawyer is shown it to follow the
/// readings (Dava Dosyalarım's "UYAP durumu"): when the portfolio's list
/// was last read whole, a reading of it left unfinished, how many of the
/// open cases were read one by one and with what, those never read, and
/// the sections that would not come. All of it from what is kept: nothing
/// is asked of UYAP.
class UyapStatus {
  const UyapStatus({
    required this.listWhole,
    required this.listTried,
    required this.listStarted,
    required this.open,
    required this.read,
    required this.withParties,
    required this.withDocuments,
    required this.withMoney,
    required this.unread,
    required this.documentsMissing,
    required this.documentsMissingWebOnly,
    required this.webMissing,
    required this.failed,
  });

  /// When the whole portfolio's list last came whole; null when never.
  final DateTime? listWhole;

  /// When a reading of the list last came in part, if after [listWhole].
  final DateTime? listTried;

  /// Readings of the list begun and never ended, by channel: Folio closed
  /// or the reading stopped in the middle of them (or one runs now).
  final Map<PortalChannel, DateTime> listStarted;

  /// The open cases, and those of them read one by one.
  final int open, read;

  /// Of the [read]: with their parties, their documents' list, their money.
  final int withParties, withDocuments, withMoney;

  /// The open cases never read one by one, by key.
  final Set<String> unread;

  /// The open cases whose documents' list never came, by key: never read,
  /// or read for their parties alone (a fill stopped after its first
  /// stage). Not those read and found to have none.
  final Set<String> documentsMissing;

  /// Of the [documentsMissing]: the Court of Cassation's and the
  /// prosecutors', which UYAP Mobil does not read
  /// (docs/uyap-hedef-harita.md §11.6).
  final int documentsMissingWebOnly;

  /// The open cases whose money the web never brought, by key: those never
  /// read, and those read without it (on UYAP Mobil, or by an earlier
  /// Folio's reading cut short). Not those the web said it does not show.
  final Set<String> webMissing;

  /// The sections that would not be read, the most tried first.
  final List<FailedSection> failed;
}

/// [UyapStatus] read from [database] and [store].
Future<UyapStatus> readUyapStatus({
  PortalDatabase? database,
  UyapCaseStore? store,
}) async {
  final db = database ?? await PortalDatabase.shared();
  final records = {
    for (final (record, _) in await (store ?? UyapCaseStore.instance).cases(
      counted: false,
    ))
      caseKey(record.number, record.court): record,
  };
  DateTime? at(String key) => DateTime.tryParse(db.meta(key) ?? '');
  final whole = at('portfolio_at');
  final tried = at('portfolio_try_at');
  final archived = db.revokedShares();
  final open = [
    for (final c in db.cases().values)
      if (!archived.contains(c.key) && !isClosedStatus(c.status?.value)) c,
  ];
  var read = 0, parties = 0, documents = 0, money = 0, webOnly = 0;
  final unread = <String>{};
  final documentsMissing = <String>{};
  final webMissing = <String>{};
  final failed = <FailedSection>[];
  for (final c in open) {
    final record = records[c.key];
    final sections = db.sections(c.key);
    // Read done on the web, as there is none or it is not shown: the web
    // has nothing more to give of it.
    final moneyDone = sections.any(
      (s) =>
          s.section == CaseSection.money &&
          s.channel == PortalChannel.uyapWeb &&
          s.result.done &&
          s.succeeded != null,
    );
    if (record?.money == null && !moneyDone) webMissing.add(c.key);
    final documentsDone = sections.any(
      (s) =>
          s.section == CaseSection.documents &&
          s.result.done &&
          s.succeeded != null,
    );
    if ((record?.documents.isEmpty ?? true) && !documentsDone) {
      documentsMissing.add(c.key);
      if (!PortalSync.mobileReads(c)) webOnly++;
    }
    if (record == null) {
      unread.add(c.key);
    } else {
      read++;
      if (record.parties.isNotEmpty) parties++;
      if (record.documents.isNotEmpty) documents++;
      if (record.money != null) money++;
    }
    for (final s in sections) {
      if (s.result == SectionResult.failed && s.tries > 0) {
        failed.add((
          number: c.number,
          court: c.court,
          section: s.section,
          channel: s.channel,
          tries: s.tries,
        ));
      }
    }
  }
  failed.sort((a, b) => b.tries.compareTo(a.tries));
  return UyapStatus(
    listWhole: whole,
    listTried: tried != null && (whole == null || tried.isAfter(whole))
        ? tried
        : null,
    listStarted: {
      for (final channel in [PortalChannel.uyapMobile, PortalChannel.uyapWeb])
        channel: ?at(PortalSync.listStartedKey(channel)),
    },
    open: open.length,
    read: read,
    withParties: parties,
    withDocuments: documents,
    withMoney: money,
    unread: unread,
    documentsMissing: documentsMissing,
    documentsMissingWebOnly: webOnly,
    webMissing: webMissing,
    failed: failed,
  );
}
