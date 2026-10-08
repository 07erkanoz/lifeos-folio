import 'dart:convert';

/// Why a deadline is as it is, in a code the screens can tell apart and a
/// sentence for the lawyer.
class DeadlineReason {
  final String code;
  final String text;
  const DeadlineReason(this.code, this.text);

  Map<String, Object?> toJson() => {'kod': code, 'metin': text};

  static DeadlineReason fromJson(Object? json) {
    final m = json is Map ? json : const {};
    return DeadlineReason('${m['kod'] ?? ''}', '${m['metin'] ?? ''}');
  }
}

/// What the engine made of a notice: one rule's deadline, never certain by
/// itself. The lawyer's own decisions on it are a [DeadlineUser], kept
/// apart, so that a new reckoning never overwrites them.
class DeadlineRecord {
  /// `uets:<notice>:r:<ruleId>` (a rule with two regimes adds its own id).
  final String id;
  final String noticeId;
  final String? caseKey;
  final String ruleId;
  final String title;
  final String law;

  /// 'teblig', 'ogrenme', 'tefhim', 'karar' or 'ilan'.
  final String startEvent;

  /// 'yyyy-mm-dd' Turkish days; null where no date was made.
  final String? startDay;
  final String? rawDay;
  final String? dueDay;

  /// The engine's state: 'aday' (a date to be confirmed), 'olayBekleniyor'
  /// (the event it starts from is not known), 'desteklenmiyor' (a regime
  /// this version does not reckon) or 'eski' (no longer made).
  final String state;

  /// 'olasiBizim', 'olasiKarsi' or 'belirsiz'.
  final String ownership;
  final List<DeadlineReason> reasons;

  /// What the kind of document was told by: {'kaynak': 'ek'|'konu',
  /// 'ad': the document's name, 'parca': its id}. No document text.
  final Map<String, Object?> evidence;
  final int engine;
  final int calendar;

  /// SHA-256 of what the reckoning was made from (see the notice
  /// deadlines' inputs): the same inputs, the same record.
  final String inputs;
  final DateTime updated;

  const DeadlineRecord({
    required this.id,
    required this.noticeId,
    required this.caseKey,
    required this.ruleId,
    required this.title,
    required this.law,
    required this.startEvent,
    required this.startDay,
    required this.rawDay,
    required this.dueDay,
    required this.state,
    required this.ownership,
    required this.reasons,
    required this.evidence,
    required this.engine,
    required this.calendar,
    required this.inputs,
    required this.updated,
  });

  DeadlineRecord withState(
    String state, {
    List<DeadlineReason>? reasons,
    DateTime? updated,
  }) => DeadlineRecord(
    id: id,
    noticeId: noticeId,
    caseKey: caseKey,
    ruleId: ruleId,
    title: title,
    law: law,
    startEvent: startEvent,
    startDay: startDay,
    rawDay: rawDay,
    dueDay: dueDay,
    state: state,
    ownership: ownership,
    reasons: reasons ?? this.reasons,
    evidence: evidence,
    engine: engine,
    calendar: calendar,
    inputs: inputs,
    updated: updated ?? this.updated,
  );

  String get reasonsJson => jsonEncode([for (final r in reasons) r.toJson()]);
  String get evidenceJson => jsonEncode(evidence);
}

/// The lawyer's decisions on a [DeadlineRecord].
class DeadlineUser {
  final String deadlineId;
  final bool done;

  /// The lawyer's own last day ('yyyy-mm-dd'), shown instead of the
  /// engine's, which stays beside it.
  final String? manualDay;
  final String? titleOverride;
  final String? bodyOverride;

  /// The inputs the lawyer confirmed; the deadline is confirmed while the
  /// record's inputs are still these.
  final String? confirmedInputs;
  final DateTime? confirmedAt;

  /// Taken off the agenda by the lawyer; still shown on its notice.
  final bool dismissed;

  const DeadlineUser({
    required this.deadlineId,
    this.done = false,
    this.manualDay,
    this.titleOverride,
    this.bodyOverride,
    this.confirmedInputs,
    this.confirmedAt,
    this.dismissed = false,
  });

  DeadlineUser copyWith({
    bool? done,
    String? manualDay,
    bool clearManualDay = false,
    String? titleOverride,
    String? bodyOverride,
    String? confirmedInputs,
    DateTime? confirmedAt,
    bool clearConfirmation = false,
    bool? dismissed,
  }) => DeadlineUser(
    deadlineId: deadlineId,
    done: done ?? this.done,
    manualDay: clearManualDay ? null : manualDay ?? this.manualDay,
    titleOverride: titleOverride ?? this.titleOverride,
    bodyOverride: bodyOverride ?? this.bodyOverride,
    confirmedInputs: clearConfirmation
        ? null
        : confirmedInputs ?? this.confirmedInputs,
    confirmedAt: clearConfirmation ? null : confirmedAt ?? this.confirmedAt,
    dismissed: dismissed ?? this.dismissed,
  );
}

/// A record and the lawyer's decisions on it, read together.
class KeptDeadline {
  final DeadlineRecord record;
  final DeadlineUser? user;
  const KeptDeadline(this.record, this.user);

  /// Confirmed by the lawyer on the very inputs it now has, and with a day.
  bool get confirmed =>
      record.state == 'aday' &&
      record.dueDay != null &&
      user?.confirmedInputs != null &&
      user!.confirmedInputs == record.inputs;

  /// Confirmed once, on inputs it no longer has (a document, the case,
  /// the engine or the calendar changed), and still made with a day: it
  /// stays followed while the lawyer looks at it again. A change never
  /// takes a deadline the lawyer followed off the agenda quietly.
  bool get reconfirm =>
      !confirmed &&
      record.state == 'aday' &&
      record.dueDay != null &&
      user?.confirmedInputs != null;

  /// The day the lawyer goes by: their own, else the engine's.
  String? get day => user?.manualDay ?? record.dueDay;

  /// On the agenda, counted and alarmed: confirmed, to be confirmed again,
  /// or given a day by the lawyer; never one the lawyer took off.
  bool get onAgenda =>
      !(user?.dismissed ?? false) &&
      (confirmed || reconfirm || user?.manualDay != null);

  /// The lawyer has decided on it: confirmed, given a day, done, or taken
  /// off. Until then an old agenda row it was carried over from stays on
  /// the agenda, so that no alarm the lawyer had goes quietly.
  bool get decided =>
      confirmed ||
      user?.manualDay != null ||
      (user?.done ?? false) ||
      (user?.dismissed ?? false);

  /// To be looked at: everything not on the agenda and not taken off,
  /// including what is no longer made, until the lawyer decides; and what
  /// is to be confirmed again.
  bool get toReview =>
      (!onAgenda || reconfirm) &&
      !(user?.dismissed ?? false) &&
      !(user?.done ?? false);

  /// Not put before the lawyer at [now]: its last day more than a week
  /// gone; or, its last day not known, its notice served more than forty
  /// days ago (a box read whole brings years of notices; Banaozel keeps to
  /// forty days too). A long time limit whose last day is still to come is
  /// shown however long ago it was served: ninety days from a notice two
  /// months old are not gone. It stays on its notice's page; one the lawyer
  /// confirmed stays on the agenda.
  bool expired(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final d = day;
    if (d != null) {
      return DateTime.parse(d)
          .isBefore(DateTime(today.year, today.month, today.day - 7));
    }
    final start = record.startDay;
    return start != null &&
        DateTime.parse(start)
            .isBefore(DateTime(today.year, today.month, today.day - 40));
  }
}

/// A notice's package as kept on this computer (see
/// `PortalDatabase.saveEnvelope`).
class NoticeEnvelope {
  final String noticeId;
  final String state;
  final String? folder;
  final String? packagePath;
  final String? envelopePath;

  /// The envelope's text layer; the lawyer's matter, kept only here.
  final String? envelopeText;
  final List<({String name, String path})> attachments;
  final DateTime? fetchedAt;
  final String? error;

  const NoticeEnvelope({
    required this.noticeId,
    required this.state,
    this.folder,
    this.packagePath,
    this.envelopePath,
    this.envelopeText,
    this.attachments = const [],
    this.fetchedAt,
    this.error,
  });
}
