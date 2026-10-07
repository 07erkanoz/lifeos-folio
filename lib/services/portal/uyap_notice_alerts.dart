import 'dart:convert';

import '../platform/system_notices.dart';
import 'portal_database.dart';
import 'uyap_notice.dart';

/// Which new UYAP notifications pop up on the desktop: all kinds at
/// first; the lawyer may turn it off, or leave out kinds.
class UyapNoticeAlerts {
  final bool on;
  final Set<UyapNoticeKind> quiet;

  /// Whether a phone looks for them with Folio closed, too.
  final bool background;

  const UyapNoticeAlerts({
    this.on = true,
    this.quiet = const {},
    this.background = true,
  });

  UyapNoticeAlerts copyWith({
    bool? on,
    Set<UyapNoticeKind>? quiet,
    bool? background,
  }) => UyapNoticeAlerts(
    on: on ?? this.on,
    quiet: quiet ?? this.quiet,
    background: background ?? this.background,
  );

  bool tells(UyapNotice n) => on && !quiet.contains(n.kind);

  static const _key = 'uyap_notice_alerts';

  static UyapNoticeAlerts of(PortalDatabase db) {
    try {
      final json = jsonDecode(db.meta(_key) ?? '{}');
      if (json is! Map) return const UyapNoticeAlerts();
      return UyapNoticeAlerts(
        on: json['acik'] != false,
        background: json['arkaplan'] != false,
        quiet: {
          for (final name in (json['sessiz'] as List?) ?? const [])
            for (final k in UyapNoticeKind.values)
              if (k.name == name) k,
        },
      );
    } catch (_) {
      return const UyapNoticeAlerts();
    }
  }

  void save(PortalDatabase db) => db.setMeta(
    _key,
    jsonEncode({
      'acik': on,
      'arkaplan': background,
      'sessiz': [for (final k in quiet) k.name],
    }),
  );
}

/// [notices] told on the computer's or phone's own notifications, as the
/// lawyer chose: each with its case, or one word for many at once.
/// [ask]: whether leave may be asked for here (not from the background).
Future<void> tellUyapNotices(
  PortalDatabase db,
  List<UyapNotice> notices, {
  bool ask = true,
}) async {
  final alerts = UyapNoticeAlerts.of(db);
  final told = [
    for (final n in notices)
      if (alerts.tells(n)) n,
  ];
  if (told.isEmpty) return;
  final cases = db.cases();
  String line(UyapNotice n) => switch (cases[n.caseKey]) {
    null => n.body.length > 140 ? '${n.body.substring(0, 140)}…' : n.body,
    final c => '${c.number} · ${c.court}',
  };
  if (told.length > 3) {
    await SystemNotices.instance.show(
      id: 1,
      title: '${told.length} yeni UYAP bildirimi',
      body: told.take(4).map((n) => n.title).join(', '),
      payload: 'notices:',
      ask: ask,
    );
    return;
  }
  for (final n in told) {
    await SystemNotices.instance.show(
      id: n.signature.hashCode & 0x7fffffff,
      title: n.title.isEmpty ? 'UYAP bildirimi' : n.title,
      body: line(n),
      payload: 'notice:${n.signature}',
      ask: ask,
    );
  }
}
