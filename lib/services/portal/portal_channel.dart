/// The three portals Folio connects to, each with its own login and its own
/// session, and the rule for which of them does what (UYGULAMAPLANI §9.2).
///
/// One table, used by every layer: the sync, the downloads, the screens
/// and the sending ask it rather than keep a channel rule of their own,
/// which is how Banaozel came to have four that disagreed.
library;

enum PortalChannel {
  /// avukat.uyap.gov.tr: everything, for about three hours a session.
  uyapWeb,

  /// mobilws.uyap.gov.tr: less, but a session lasts a week.
  uyapMobile,

  /// UETS, the electronic notification system.
  uets,
}

/// The kinds of case UYAP keeps apart: the web alone has the Court of
/// Cassation's and the public prosecutors'.
enum CaseFamily { court, yargitay, prosecutor, danistay }

/// What is asked of UYAP.
enum UyapOp {
  /// The case list. Both channels fill it, and the results are merged.
  caseList,
  parties,
  details,
  proceedings,
  money,
  documentList,
  documentDownload,

  /// The hearings. Both channels are asked, and the results are merged.
  hearings,
  send,
  excuse,
  eHearing,
}

class ChannelRule {
  /// Asked first.
  final PortalChannel primary;

  /// Asked when [primary] is not connected or fails; never for a write.
  final PortalChannel? fallback;

  /// Every connected channel is asked and the answers merged.
  final bool merged;

  /// Changes something at UYAP: never retried, never sent elsewhere.
  final bool writes;

  const ChannelRule(
    this.primary, {
    this.fallback,
    this.merged = false,
    this.writes = false,
  });
}

abstract final class ChannelTable {
  static const _web = PortalChannel.uyapWeb;
  static const _mobile = PortalChannel.uyapMobile;

  /// The rule for [op] on a case of [family]. The web gives more than the
  /// mobile API, so where both can answer the web comes first and the
  /// mobile fills what it cannot reach; the Court of Cassation's and the
  /// prosecutors' cases are the web's alone.
  static ChannelRule rule(UyapOp op, [CaseFamily family = CaseFamily.court]) {
    final webOnly =
        family == CaseFamily.yargitay || family == CaseFamily.prosecutor;
    return switch (op) {
      UyapOp.caseList when webOnly => const ChannelRule(_web),
      UyapOp.caseList => const ChannelRule(
        _web,
        fallback: _mobile,
        merged: true,
      ),
      UyapOp.hearings => const ChannelRule(
        _web,
        fallback: _mobile,
        merged: true,
      ),
      UyapOp.proceedings || UyapOp.money => const ChannelRule(_web),
      UyapOp.send => const ChannelRule(_web, writes: true),
      UyapOp.excuse ||
      UyapOp.eHearing => const ChannelRule(_mobile, writes: true),
      _ when webOnly => const ChannelRule(_web),
      UyapOp.parties ||
      UyapOp.details ||
      UyapOp.documentList ||
      UyapOp.documentDownload => const ChannelRule(_web, fallback: _mobile),
    };
  }

  /// The channels to ask for [op], in order, among those [connected]. A
  /// merged operation asks all of them; a read asks its fallback after its
  /// primary; a write asks its primary alone. Empty: nothing connected can
  /// do it, and the screen offers the primary's connection card.
  static List<PortalChannel> channels(
    UyapOp op,
    Set<PortalChannel> connected, [
    CaseFamily family = CaseFamily.court,
  ]) {
    final r = rule(op, family);
    return [
      if (connected.contains(r.primary)) r.primary,
      if (!r.writes && r.fallback != null && connected.contains(r.fallback))
        r.fallback!,
    ];
  }
}
