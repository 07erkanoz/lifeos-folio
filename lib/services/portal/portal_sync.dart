import 'dart:async';

import 'package:flutter/foundation.dart';

import '../security/secret_store.dart';
import '../uyap/uyap_mobile_api.dart';
import '../uyap/uyap_web_service.dart';
import 'hearing_sync.dart';
import 'observed.dart';
import 'portal_case.dart';
import 'portal_channel.dart';
import 'portal_database.dart';

/// One channel's sync, as the screens show it.
class ChannelSync {
  final bool running;
  final DateTime? finished;

  /// What could not be fetched, or null.
  final String? problem;
  const ChannelSync({this.running = false, this.finished, this.problem});
}

/// Runs each connected channel's sync when it connects, whether or not the
/// agenda is open, and never one channel's for another (UYGULAMAPLANI §3,
/// §9). A channel's sync touches only its own share: the web's hearings,
/// or the mobile API's hearings and cases; the database merges them.
class PortalSync extends ChangeNotifier {
  PortalSync({
    UyapWebService? web,
    UyapMobileApi? mobile,
    Future<PortalDatabase> Function()? database,
    SecretStore? secrets,
  }) : _secrets = secrets ?? SecretStore(),
       _web = web ?? UyapWebService.instance,
       _mobile = mobile ?? UyapMobileApi.instance,
       _database = database ?? PortalDatabase.shared;

  static PortalSync? _instance;
  static PortalSync get instance => _instance ??= PortalSync()..start();

  final UyapWebService _web;
  final UyapMobileApi _mobile;
  final Future<PortalDatabase> Function() _database;
  final SecretStore _secrets;

  static const _mobileSecret = 'uyap-mobile';
  final _state = <PortalChannel, ChannelSync>{};
  bool _started = false;

  ChannelSync state(PortalChannel channel) =>
      _state[channel] ?? const ChannelSync();

  UyapWebService get web => _web;
  UyapMobileApi get mobile => _mobile;

  void start() {
    if (_started) return;
    _started = true;
    _web.session.addListener(_webChanged);
    _mobile.session.addListener(_mobileChanged);
    // The mobile session lasts a week: kept sealed between runs, and taken
    // up again here. The web portal's three hours are not kept.
    _mobile.onTokens = (tokens) => unawaited(
      tokens == null
          ? _secrets.remove(_mobileSecret)
          : _secrets.write(_mobileSecret, tokens.toJson()),
    );
    unawaited(_restoreMobile());
  }

  Future<void> _restoreMobile() async {
    if (_mobile.connected) return;
    final kept = MobileTokens.fromJson(await _secrets.read(_mobileSecret));
    if (kept != null) await _mobile.restore(kept);
  }

  @override
  void dispose() {
    _web.session.removeListener(_webChanged);
    _mobile.session.removeListener(_mobileChanged);
    super.dispose();
  }

  void _webChanged() {
    notifyListeners();
    if (_web.connected) unawaited(syncWeb());
  }

  void _mobileChanged() {
    notifyListeners();
    if (_mobile.connected) unawaited(syncMobile());
  }

  Future<void> _run(
    PortalChannel channel,
    Future<String?> Function(PortalDatabase db) work,
  ) async {
    if (state(channel).running) return;
    _state[channel] = ChannelSync(
      running: true,
      finished: state(channel).finished,
    );
    notifyListeners();
    String? problem;
    try {
      problem = await work(await _database());
    } catch (e) {
      problem = '$e';
    }
    _state[channel] = ChannelSync(finished: DateTime.now(), problem: problem);
    notifyListeners();
  }

  /// The web portal's hearings.
  Future<void> syncWeb() => _run(PortalChannel.uyapWeb, (db) async {
    if (!_web.connected) return null;
    final result = await syncHearings(
      PortalChannel.uyapWeb,
      db,
      _web.hearingRows,
    );
    return result.complete ? null : 'Bazı tarihler alınamadı';
  });

  /// The mobile API's hearings, then its cases.
  Future<void> syncMobile() => _run(PortalChannel.uyapMobile, (db) async {
    if (!_mobile.connected) return null;
    final hearings = await syncHearings(
      PortalChannel.uyapMobile,
      db,
      _mobile.hearingRows,
    );
    final cases = await syncMobilePortfolio(_mobile, db);
    return hearings.complete && cases.complete
        ? null
        : 'Bazı kayıtlar alınamadı';
  });
}

class PortfolioResult {
  final int cases;
  final bool complete;
  const PortfolioResult(this.cases, this.complete);
}

/// The kinds of jurisdiction the mobile API lists cases for: ceza, hukuk,
/// icra and idari. The Court of Cassation's and the prosecutors' are the
/// web's alone (§9.2).
const mobileJurisdictions = [1, 0, 2, 6];

/// Every case the mobile API knows of the lawyer's, open and closed, merged
/// into [db]: the number, the court, the status and the kind, as partial
/// answers that fill what the web has not given and replace nothing it
/// has (§9.4). A court that fails makes the answer incomplete; the others
/// are still asked.
Future<PortfolioResult> syncMobilePortfolio(
  UyapMobileApi api,
  PortalDatabase db,
) async {
  final asked = DateTime.now().toUtc();
  const mobile = PortalChannel.uyapMobile;
  var complete = true;
  final found = <String, PortalCase>{};

  void add(Map<String, Object?> row, CaseFamily family) {
    final number = '${row['dosyaNo'] ?? ''}'.trim();
    final court = '${row['birimAdi'] ?? ''}'.trim();
    if (number.isEmpty || court.isEmpty) return;
    final closed = row['dosyaKapaliMi'] == true;
    final status = '${row['dosyaDurumAciklama'] ?? ''}'.trim();
    final details = {
      if ('${row['dosyaTurAciklama'] ?? ''}'.isNotEmpty)
        'tur': row['dosyaTurAciklama'],
      if ('${row['dosyaAcilisTarihi'] ?? ''}'.isNotEmpty)
        'acilis': row['dosyaAcilisTarihi'],
      if ('${row['dosyaKapanisTarihi'] ?? ''}'.isNotEmpty)
        'kapanis': row['dosyaKapanisTarihi'],
    };
    final one = PortalCase(
      key: caseKey(number, court),
      number: number,
      court: court,
      family: family,
      ids: {
        if ('${row['dosyaId'] ?? ''}'.isNotEmpty) mobile: '${row['dosyaId']}',
      },
      status: Observed(
        status.isNotEmpty ? status : (closed ? 'Kapalı' : 'Açık'),
        mobile,
        asked,
      ),
      details: details.isEmpty
          ? null
          : Observed(details, mobile, asked, complete: false),
    );
    found[one.key] = found[one.key]?.merge(one) ?? one;
  }

  for (final type in mobileJurisdictions) {
    List<Map<String, Object?>> units;
    try {
      units = await api.unitTypes(type);
    } catch (_) {
      complete = false;
      continue;
    }
    for (final unit in units) {
      final kind = '${unit['tablo'] ?? ''}'.trim();
      if (kind.isEmpty) continue;
      for (final closed in [false, true]) {
        try {
          for (final court in await api.courts(type, kind, closed: closed)) {
            final id = '${court['birimId'] ?? ''}'.trim();
            if (id.isEmpty) continue;
            try {
              for (final row in await api.cases(
                type,
                kind,
                id,
                closed: closed,
              )) {
                add(row, CaseFamily.court);
              }
            } catch (_) {
              complete = false;
            }
          }
        } catch (_) {
          complete = false;
        }
      }
    }
  }
  try {
    for (final chamber in await api.danistayChambers()) {
      final id = '${chamber['birimId'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      for (final row in await api.danistayCases(id)) {
        add(row, CaseFamily.danistay);
      }
    }
  } catch (_) {
    complete = false;
  }
  db.mergeCases(found.values);
  return PortfolioResult(found.length, complete);
}
