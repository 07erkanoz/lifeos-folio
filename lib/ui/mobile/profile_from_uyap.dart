import 'package:flutter/material.dart';

import '../../services/editor/lawyer_profile.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/uyap/uyap_mobile_api.dart';
import '../agenda/mobile_connect.dart';

/// "ERKAN ÖZ" as "Erkan Öz", with Turkish's dotted and dotless i.
String titleCaseTr(String text) => text
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) {
      final rest = w
          .substring(1)
          .replaceAll('I', 'ı')
          .replaceAll('İ', 'i')
          .toLowerCase();
      return '${w[0]}$rest';
    })
    .join(' ');

/// [current] with what UYAP Mobil knows of the lawyer: the name, the bar
/// and its register number, the TBB's, the TC number, a phone and an
/// e-mail. The default lawyer is filled in, or added when there is none;
/// what UYAP does not give stays as it was. UYAP Mobil is connected first
/// when it is not (e-Devlet); null when it is not, or gives no one.
Future<LawyerProfile?> profileFromUyap(
  BuildContext context,
  LawyerProfile current,
) async {
  PortalSync.begin();
  final api = UyapMobileApi.instance;
  if (!api.connected && !await connectUyapMobile(context, api: api)) {
    return null;
  }
  final s = api.session.value;
  if (s == null || s.user.isEmpty || s.user == 'UYAP Mobil') return null;
  return fillFromSession(current, s);
}

/// [current] filled from [s]; see [profileFromUyap].
LawyerProfile fillFromSession(LawyerProfile current, MobileSession s) {
  String pick(String fresh, String old) => fresh.trim().isEmpty ? old : fresh;
  final lawyers = [...current.lawyers];
  final at = lawyers.isEmpty
      ? -1
      : current.main >= 0 && current.main < lawyers.length
      ? current.main
      : 0;
  final old = at < 0 ? const Lawyer() : lawyers[at];
  final bar = s.bar.replaceFirst(
    RegExp(r'\s+barosu$', caseSensitive: false),
    '',
  );
  final filled = Lawyer(
    name: pick(titleCaseTr(s.user), old.name),
    bar: pick(bar.isEmpty ? '' : '${titleCaseTr(bar)} Barosu', old.bar),
    barNumber: pick(s.barNumber, old.barNumber),
    tbbNumber: pick(s.tbbNumber, old.tbbNumber),
    idNumber: pick(s.tckn, old.idNumber),
  );
  if (at < 0) {
    lawyers.add(filled);
  } else {
    lawyers[at] = filled;
  }
  return LawyerProfile(
    lawyers: lawyers,
    main: at < 0 ? 0 : current.main,
    address: current.address,
    phone: current.phone.trim().isEmpty && s.phones.isNotEmpty
        ? s.phones.first
        : current.phone,
    email: current.email.trim().isEmpty && s.emails.isNotEmpty
        ? s.emails.first
        : current.email,
    kep: current.kep,
  );
}
