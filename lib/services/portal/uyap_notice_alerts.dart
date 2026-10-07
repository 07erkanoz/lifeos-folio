import 'dart:convert';

import 'portal_database.dart';
import 'uyap_notice.dart';

/// Which new UYAP notifications pop up on the desktop: all kinds at
/// first; the lawyer may turn it off, or leave out kinds.
class UyapNoticeAlerts {
  final bool on;
  final Set<UyapNoticeKind> quiet;

  const UyapNoticeAlerts({this.on = true, this.quiet = const {}});

  bool tells(UyapNotice n) => on && !quiet.contains(n.kind);

  static const _key = 'uyap_notice_alerts';

  static UyapNoticeAlerts of(PortalDatabase db) {
    try {
      final json = jsonDecode(db.meta(_key) ?? '{}');
      if (json is! Map) return const UyapNoticeAlerts();
      return UyapNoticeAlerts(
        on: json['acik'] != false,
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
      'sessiz': [for (final k in quiet) k.name],
    }),
  );
}
