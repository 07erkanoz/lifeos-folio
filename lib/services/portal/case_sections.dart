import 'portal_channel.dart';

/// The parts of a case read on their own, each owned by a channel
/// (docs/uyap-hedef-harita.md §3, §7): its particulars, parties and
/// documents by either; its money, an icra file's account and debtors by
/// the web alone.
enum CaseSection {
  particulars,
  parties,
  documents,
  money,
  account,
  debtors;

  /// Whether only the web portal gives it.
  bool get webOnly => this == money || this == account || this == debtors;
}

/// What reading a section came to (§11.2). Only [failed] is not done: an
/// answer without what was asked for is [failed], never [empty].
enum SectionResult {
  /// Read, with something in it.
  read,

  /// Read, and there is none.
  empty,

  /// Not shown for this case (no permission, not this kind of case).
  notShown,

  /// Asked for and did not come.
  failed;

  bool get done => this != failed;
}

/// One section's result of one reading. [partial]: read but not whole, as
/// UYAP Mobil's last twenty documents where the full list did not come.
class SectionOutcome {
  const SectionOutcome(this.section, this.result, {this.partial = false});
  final CaseSection section;
  final SectionResult result;
  final bool partial;

  @override
  String toString() =>
      '${section.name}:${result.name}${partial ? ' (kısmi)' : ''}';
}

/// A section as a channel last read it.
class SectionState {
  const SectionState({
    required this.section,
    required this.channel,
    required this.result,
    required this.partial,
    required this.succeeded,
    required this.tried,
    required this.tries,
  });
  final CaseSection section;
  final PortalChannel channel;
  final SectionResult result;
  final bool partial;

  /// The last time it was read done; null when never.
  final DateTime? succeeded;
  final DateTime tried;

  /// Tries failed since the last success.
  final int tries;

  /// Read whole at some time.
  bool get complete => succeeded != null && !partial;
}
