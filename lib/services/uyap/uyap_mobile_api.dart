import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;

/// The UYAP mobile API (mobilws.uyap.gov.tr), Folio's second UYAP channel
/// beside the web portal (UYGULAMAPLANI §9.2, §9.3). Its own e-Devlet login,
/// its own tokens: a session lasts a week and renews itself, but answers
/// with less than the web, and knows nothing of the Court of Cassation's
/// or the prosecutors' cases. Nothing here starts or touches a web login.
class UyapMobileApi {
  UyapMobileApi._() : _base = Uri.parse(_services);

  @visibleForTesting
  UyapMobileApi.forTesting(Uri base) : _base = base;

  static UyapMobileApi _instance = UyapMobileApi._();
  static UyapMobileApi get instance => _instance;
  @visibleForTesting
  static set instance(UyapMobileApi api) => _instance = api;

  static const _services = 'https://mobilws.uyap.gov.tr/portaldmz/services/';

  /// Where e-Devlet sends the lawyer back with the code for this API: not
  /// the web portal's return, whose code is useless here.
  static final edevletReturn = Uri.parse(
    'https://mobilws.uyap.gov.tr/portaldmz/avukat.html',
  );

  /// UYAP's own client for its mobile application.
  static const _clientId = '27e1dfc0-8536-11e4-b4a9-0800200c9a66';

  /// The e-Devlet page that logs into this API, with a [state] of this
  /// login's own, checked when the lawyer comes back.
  static Uri loginPage(String state) => Uri.https(
    'giris.turkiye.gov.tr',
    '/OAuth2AuthorizationServer/AuthorizationController',
    {
      'response_type': 'code',
      'scope': 'Kimlik-Dogrula;Ad-Soyad',
      'redirect_uri': edevletReturn.toString(),
      'client_id': _clientId,
      'state': state,
    },
  );

  static String newState() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(10)).join();
  }

  /// Whether [url] is this API's return, exactly: scheme, host and path.
  /// A code meant for any other page is never exchanged.
  static bool isReturn(Uri url) =>
      url.scheme == edevletReturn.scheme &&
      url.host == edevletReturn.host &&
      url.path == edevletReturn.path;

  final Uri _base;
  HttpClient? _client;
  HttpClient get _http => _client ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 30);

  MobileTokens? _tokens;
  int _generation = 0;
  Future<void>? _refreshing;

  /// Who is logged in and until when; null when no one is.
  final session = ValueNotifier<MobileSession?>(null);

  bool get connected =>
      _tokens != null && _tokens!.refreshExpires.isAfter(DateTime.now());

  MobileTokens? get tokens => _tokens;

  /// Told whenever the tokens change, null when the session ends: where
  /// they are kept between runs (`SecretStore`).
  void Function(MobileTokens? tokens)? onTokens;

  void _setTokens(MobileTokens? tokens) {
    _tokens = tokens;
    onTokens?.call(tokens);
  }

  /// Exchanges e-Devlet's [code] for this API's tokens and reads who the
  /// lawyer is. A login started later replaces this one; nothing it does
  /// reaches the web portal.
  Future<MobileSession> login(String code) async {
    final generation = ++_generation;
    final data = await _send('POST', 'auth/edevlet', {
      'code': code,
      // The three are required, or UYAP fails with a NullPointerException.
      'model': 'windows_desktop',
      'serial': 'LifeOS_Folio',
      'type': '2',
    }, authorized: false);
    final tokens = MobileTokens.fromLogin(data, DateTime.now());
    if (generation != _generation) {
      throw StateError('Daha yeni bir giriş başladı.');
    }
    _setTokens(tokens);
    return _identify();
  }

  /// A session kept from before, its refresh token not yet expired.
  Future<MobileSession?> restore(MobileTokens tokens) async {
    if (!tokens.refreshExpires.isAfter(DateTime.now())) return null;
    _generation++;
    _tokens = tokens;
    try {
      return await _identify();
    } catch (_) {
      _setTokens(null);
      return null;
    }
  }

  Future<MobileSession> _identify() async {
    final user = await _get('mobile/avukat/user');
    final map = user is Map ? user : const {};
    String field(String key) => '${map[key] ?? ''}'.trim();
    final name = [
      field('adi'),
      field('soyadi'),
    ].where((s) => s.isNotEmpty).join(' ');
    final s = MobileSession(
      user: name.isEmpty ? 'UYAP Mobil' : name,
      since: DateTime.now(),
      expires: _tokens!.refreshExpires,
      bar: field('baroAdi'),
    );
    session.value = s;
    return s;
  }

  Future<void> logout() async {
    final had = _tokens != null;
    try {
      if (had) await _send('DELETE', 'mobile/ortak/logout', null);
    } catch (_) {
      // Ended here whatever UYAP answers.
    } finally {
      _generation++;
      _setTokens(null);
      session.value = null;
    }
  }

  /// Renews the access token once, however many requests wait for it; a
  /// login that happened meanwhile wins over the renewal's answer.
  Future<void> _refresh() => _refreshing ??= () async {
    final had = _tokens;
    final generation = _generation;
    try {
      if (had == null) throw StateError('UYAP Mobil oturumu açık değil.');
      final data = await _send('POST', 'auth/refresh', {
        'refreshToken': had.refresh,
      }, authorized: false);
      if (generation != _generation || !identical(_tokens, had)) return;
      _setTokens(had.renewed(data, DateTime.now()));
    } on _HttpError {
      if (generation == _generation) {
        _setTokens(null);
        session.value = null;
      }
      throw StateError('UYAP Mobil oturumu sona erdi. Yeniden bağlanın.');
    } finally {
      _refreshing = null;
    }
  }();

  Future<dynamic> _get(String path) => _authorized('GET', path, null);
  Future<dynamic> _post(String path, Map<String, Object?> body) =>
      _authorized('POST', path, body);

  /// A request with the access token, renewed first when about to expire,
  /// and once more when UYAP refuses it.
  Future<dynamic> _authorized(
    String method,
    String path,
    Map<String, Object?>? body,
  ) async {
    if (_tokens == null) throw StateError('UYAP Mobil oturumu açık değil.');
    if (_tokens!.accessExpires.isBefore(
      DateTime.now().add(const Duration(seconds: 30)),
    )) {
      await _refresh();
    }
    try {
      return await _send(method, path, body);
    } on _Refused {
      await _refresh();
      return _send(method, path, body);
    }
  }

  Future<dynamic> _send(
    String method,
    String path,
    Map<String, Object?>? body, {
    bool authorized = true,
  }) async {
    final request = await _http
        .openUrl(method, _base.resolve(path))
        .timeout(const Duration(seconds: 15));
    request.headers.set('Accept', 'application/json');
    if (authorized) {
      request.headers.set('Authorization', 'Bearer ${_tokens?.access ?? ''}');
    }
    if (body != null) {
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 45));
    if (authorized &&
        (response.statusCode == 401 || response.statusCode == 403)) {
      throw const _Refused();
    }
    if (response.statusCode != 200) {
      throw _HttpError(response.statusCode, _message(text));
    }
    if (text.trim().isEmpty) return null;
    final data = jsonDecode(text);
    if (data is Map && data['status'] != null && '${data['status']}' != '200') {
      if (authorized && '${data['status']}' == '403') throw const _Refused();
      throw StateError('UYAP Mobil: ${_message(text)}');
    }
    return data;
  }

  static String _message(String text) {
    try {
      final data = jsonDecode(text);
      if (data is Map) {
        return '${data['message'] ?? data['title'] ?? data['errorCode'] ?? 'beklenmeyen yanıt'}';
      }
    } catch (_) {}
    return 'beklenmeyen yanıt';
  }

  // Endpoints (UYGULAMAPLANI §9.3).

  /// The kinds of unit of jurisdiction [type] (0 ceza, 1 hukuk, 2 icra,
  /// 6 idari, 12 BAM ceza and so on).
  Future<List<Map<String, Object?>>> unitTypes(int type) async =>
      _list(await _get('mobile/ortak/yargibirimleri/$type'), 'yargiBirimleri');

  /// The courts where the lawyer has a case of [unitKind] (`tablo` of
  /// [unitTypes]), open or [closed]. Their ids are the mobile API's own.
  Future<List<Map<String, Object?>>> courts(
    int type,
    String unitKind, {
    required bool closed,
  }) async => _list(
    await _post('mobile/avukat/mahkeme', {
      'birimTuru2': unitKind,
      'birimTuru3': type,
      'dosyaKapaliMi': closed,
    }),
    'birimListesi',
    fallback: 'mahkemeList',
  );

  /// The lawyer's cases at [court], page by page until a page is short or
  /// brings nothing new; at most twenty pages.
  Future<List<Map<String, Object?>>> cases(
    int type,
    String unitKind,
    String court, {
    required bool closed,
  }) async {
    final out = <Map<String, Object?>>[];
    final seen = <String>{};
    for (var page = 1; page <= 20; page++) {
      final rows = _list(
        await _post('mobile/avukat/dosya', {
          'birimTuru2': unitKind,
          'birimTuru3': type,
          'dosyaKapaliMi': closed,
          'mahkeme': court,
          'pageCount': page,
          'pageSize': 100,
          'dosyaYil': '',
          'dosyaSira': '',
        }),
        'dosyaList',
      );
      final fresh = rows.where((r) => seen.add('${r['dosyaId']}')).toList();
      out.addAll(fresh);
      if (rows.length < 100 || fresh.isEmpty) break;
    }
    return out;
  }

  /// The case [year]/[sequence] at [court], as `dosya` lists it filtered:
  /// one request, not the court's whole list. Its ids are this session's.
  Future<List<Map<String, Object?>>> findCase(
    int type,
    String unitKind,
    String court, {
    required String year,
    required String sequence,
    required bool closed,
  }) async => _list(
    await _post('mobile/avukat/dosya', {
      'birimTuru2': unitKind,
      'birimTuru3': type,
      'dosyaKapaliMi': closed,
      'mahkeme': court,
      'pageCount': 1,
      'pageSize': 100,
      'dosyaYil': year,
      'dosyaSira': sequence,
    }),
    'dosyaList',
  );

  /// A case's documents: `son20Evrak` and `tumEvraklar`, as UYAP gives them.
  Future<Map<String, Object?>> caseDocuments(String caseId) async {
    final data = await _get('mobile/avukat/dosya/${_id(caseId)}/1');
    return data is Map ? Map<String, Object?>.from(data) : const {};
  }

  Future<List<Map<String, Object?>>> parties(
    String caseId, {
    String? caseType,
  }) async => _list(
    await _post('mobile/avukat/taraflar', {
      'dosyaId': _id(caseId),
      if (caseType != null && caseType.isNotEmpty) 'dosyaTurKod': caseType,
    }),
    'tarafList',
  );

  /// A document's bytes. Both ids must come from this session; UYAP
  /// sometimes answers 500 for a moment, so it is asked twice more.
  Future<Uint8List> documentBytes(String documentId, String caseId) async {
    Object? last;
    for (final wait in const [
      Duration.zero,
      Duration(milliseconds: 800),
      Duration(milliseconds: 1800),
    ]) {
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      try {
        final data = await _get(
          'mobile/ortak/evrakV2/${_id(documentId)}/${_id(caseId)}',
        );
        final dvo = data is Map ? data['evrakContentDVO'] : null;
        final content = dvo is Map ? '${dvo['content'] ?? ''}' : '';
        if (content.isEmpty) throw StateError('Evrak içeriği boş geldi.');
        return base64Decode(content);
      } on _HttpError catch (e) {
        if (e.status != 500) rethrow;
        last = e;
      }
    }
    throw StateError('Evrak indirilemedi: $last');
  }

  /// The hearings from [from] to [to], both days included; UYAP takes at
  /// most thirty days at once, which `syncHearings` keeps to.
  Future<List<Map<String, Object?>>> hearingRows(
    DateTime from,
    DateTime to,
  ) async {
    String day(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return _list(
      await _get('mobile/avukat/durusmalarim/${day(from)}/${day(to)}'),
      'listDurusmalar',
    );
  }

  Future<List<Map<String, Object?>>> danistayChambers() async =>
      _list(await _get('mobile/avukat/danistaydaireleri'), 'danistayDairesi');

  Future<List<Map<String, Object?>>> danistayCases(String chamber) async =>
      _list(
        await _post('mobile/avukat/danistaydosyasorgula', {
          'danistayDairesi': chamber,
        }),
        'dosyaList',
      );

  /// Ids go as they are, only their quotes and spaces trimmed.
  static String _id(String id) => id.replaceAll('"', '').trim();

  static List<Map<String, Object?>> _list(
    Object? data,
    String key, {
    String? fallback,
  }) {
    final raw = data is List
        ? data
        : data is Map
        ? (data[key] ?? (fallback == null ? null : data[fallback]))
        : null;
    return [
      if (raw is List)
        for (final row in raw)
          if (row is Map) Map<String, Object?>.from(row),
    ];
  }
}

/// The two tokens and when each expires.
class MobileTokens {
  final String access;
  final String refresh;
  final DateTime accessExpires;

  /// A week from the login; renewing the access token does not extend it.
  final DateTime refreshExpires;

  const MobileTokens({
    required this.access,
    required this.refresh,
    required this.accessExpires,
    required this.refreshExpires,
  });

  factory MobileTokens.fromLogin(Object? data, DateTime now) {
    final map = data is Map ? data : const {};
    final access = '${map['accessToken'] ?? ''}';
    final refresh = '${map['refreshToken'] ?? ''}';
    if (access.isEmpty || refresh.isEmpty) {
      throw StateError('UYAP Mobil girişi token vermedi.');
    }
    return MobileTokens(
      access: access,
      refresh: refresh,
      accessExpires: _expiry(access, map['accessTokenLifetime'], 3300, now),
      refreshExpires: _expiry(
        refresh,
        map['refreshTokenLifetime'],
        604800,
        now,
        cap: const Duration(days: 7),
      ),
    );
  }

  MobileTokens renewed(Object? data, DateTime now) {
    final map = data is Map ? data : const {};
    final next = '${map['accessToken'] ?? ''}';
    if (next.isEmpty) throw StateError('UYAP Mobil yenilemesi token vermedi.');
    final nextRefresh = '${map['refreshToken'] ?? ''}';
    return MobileTokens(
      access: next,
      // Kept unless a new one comes: it may be single-use.
      refresh: nextRefresh.isEmpty ? refresh : nextRefresh,
      accessExpires: _expiry(next, map['accessTokenLifetime'], 3300, now),
      refreshExpires: refreshExpires,
    );
  }

  /// The JWT's own `exp` when it has one, else the lifetime UYAP gave, else
  /// [fallback] seconds; never longer than [cap].
  static DateTime _expiry(
    String token,
    Object? lifetime,
    int fallback,
    DateTime now, {
    Duration? cap,
  }) {
    DateTime? fromJwt;
    final parts = token.split('.');
    if (parts.length == 3) {
      try {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        if (payload is Map && payload['exp'] is num) {
          fromJwt = DateTime.fromMillisecondsSinceEpoch(
            (payload['exp'] as num).toInt() * 1000,
          );
        }
      } catch (_) {}
    }
    final seconds = lifetime is num
        ? lifetime.toInt()
        : int.tryParse('$lifetime');
    var at = fromJwt ?? now.add(Duration(seconds: seconds ?? fallback));
    if (cap != null && at.isAfter(now.add(cap))) at = now.add(cap);
    return at;
  }

  Map<String, Object?> toJson() => {
    'access': access,
    'refresh': refresh,
    'accessExpires': accessExpires.toIso8601String(),
    'refreshExpires': refreshExpires.toIso8601String(),
  };

  static MobileTokens? fromJson(Object? json) {
    if (json is! Map) return null;
    final a = DateTime.tryParse('${json['accessExpires']}');
    final r = DateTime.tryParse('${json['refreshExpires']}');
    if (a == null || r == null) return null;
    return MobileTokens(
      access: '${json['access']}',
      refresh: '${json['refresh']}',
      accessExpires: a,
      refreshExpires: r,
    );
  }
}

class MobileSession {
  final String user;
  final DateTime since;
  final DateTime expires;
  final String bar;
  const MobileSession({
    required this.user,
    required this.since,
    required this.expires,
    this.bar = '',
  });
}

class _Refused implements Exception {
  const _Refused();
}

class _HttpError implements Exception {
  final int status;
  final String message;
  const _HttpError(this.status, this.message);
  @override
  String toString() => 'HTTP $status: $message';
}
