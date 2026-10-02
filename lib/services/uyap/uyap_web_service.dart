import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:path/path.dart' as p;

import '../signing/signed_data.dart';
import '../udf/signature_parser.dart';
import 'tray_recovery.dart';
import 'uyap_case_data.dart';

export 'uyap_case_data.dart';

/// A session for the Avukat Portal. Login signatures are made by the official
/// Adalet E-İmza tray; the UDF signature is a separate operation.
class UyapWebService {
  UyapWebService._() : _portal = _avukatPortal;

  /// For a stand-in that answers without UYAP: screenshots and dialog tests,
  /// and a local server standing in for [portal].
  @visibleForTesting
  UyapWebService.forTesting({Uri? portal}) : _portal = portal ?? _avukatPortal;

  static UyapWebService _instance = UyapWebService._();
  static UyapWebService get instance => _instance;
  @visibleForTesting
  static set instance(UyapWebService service) => _instance = service;
  static final _avukatPortal = Uri.https('avukat.uyap.gov.tr');
  final Uri _portal;
  Uri _at(String path, [Map<String, String>? query]) =>
      _portal.replace(path: path, queryParameters: query);
  String get _origin => _portal.origin;
  static const _tray = 'http://127.0.0.1:5975/api/v1/signature';
  static String _id(Object? value) =>
      (value?.toString() ?? '').replaceAll('"', '').replaceAll("'", '').trim();
  static bool _sameCaseNumber(String value, int year, int number) {
    final match = RegExp(r'(\d{4})\s*/\s*(\d+)').firstMatch(value);
    return match != null &&
        int.tryParse(match.group(1)!) == year &&
        int.tryParse(match.group(2)!) == number;
  }

  /// Case-, dotted-I- and diacritic-insensitive text key. UYAP writes the
  /// same words both ways ("Kaydi" / "Kaydı").
  static String fold(String value) {
    const plain = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u'};
    final lower = value
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase()
        .replaceAll('\u0307', '');
    return lower
        .split('')
        .map((c) => plain[c] ?? c)
        .join()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  final _cookies = <String, String>{};
  final _sent = <UyapSendReceipt>[];
  String _tckn = '';
  HttpClient? _client;
  Future<void> _queue = Future.value();
  Completer<void>? _loginCancel;

  bool get _hasCookie => (_cookies['JSESSIONID'] ?? '').isNotEmpty;

  /// Whether a login has been completed and its session not seen to end.
  bool get connected => _hasCookie && session.value != null;

  /// Who is logged in, how, and since when; null when no one is. Listened
  /// to by everything that shows the connection, so that a session UYAP
  /// ends is seen to end everywhere at once.
  final session = ValueNotifier<UyapSession?>(null);

  /// Documents sent (or possibly sent) in this app run, newest first. Kept in
  /// memory only and independent of the web session, so a sent document stays
  /// tracked across a reconnect.
  List<UyapSendReceipt> get sent => List.unmodifiable(_sent.reversed);

  void track(UyapSendReceipt receipt) => _sent.add(receipt);

  void disconnect() {
    _cookies.clear();
    _tckn = '';
    _resetTransport();
    session.value = null;
  }

  /// Drops a possibly half-open connection but keeps the session cookies, so
  /// the outcome of an uncertain send can still be checked without a new login.
  void _resetTransport() {
    _client?.close(force: true);
    _client = null;
  }

  void cancelConnect() {
    final cancel = _loginCancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    disconnect();
  }

  Future<T> _loginWait<T>(
    Future<T> work,
    Completer<void> cancel,
    Duration limit,
    String stage,
  ) async {
    try {
      return await Future.any<T>([
        work,
        cancel.future.then<T>((_) => throw StateError('Giriş iptal edildi.')),
      ]).timeout(limit);
    } on TimeoutException {
      disconnect();
      throw StateError(
        '$stage yanıt vermedi. Adalet E-İmza uygulamasını yeniden başlatıp tekrar deneyin.',
      );
    }
  }

  HttpClient get _http =>
      _client ??= (HttpClient()
        ..connectionTimeout = const Duration(seconds: 25));

  Future<T> _serial<T>(Future<T> Function() operation) async {
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }

  void _putCookies(HttpClientRequest request) {
    if (_cookies.isNotEmpty) {
      request.headers.set(
        'Cookie',
        _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      );
    }
  }

  void _takeCookies(HttpClientResponse response) {
    for (final cookie in response.cookies) {
      _cookies[cookie.name] = cookie.value;
    }
  }

  Future<String> _body(
    HttpClientResponse response, {
    Duration timeout = const Duration(seconds: 30),
  }) => response.transform(utf8.decoder).join().timeout(timeout);

  /// The same fixed 123-byte login challenge observed in the old project.
  static final Uint8List loginContent = Uint8List.fromList(
    utf8.encode(
      'Adalet Bakanlığı Bilgi İşlem Genel Müdürlüğü tarafından geliştirilen '
      'uygulamaya e-imza giriş yapmak istiyorum.',
    ),
  );

  Future<String> connect(
    String pin, {
    void Function(String stage)? onProgress,
  }) => _serial(() async {
    if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      throw UnsupportedError('UYAP web bağlantısı masaüstünde kullanılabilir.');
    }
    disconnect();
    final cancel = Completer<void>();
    _loginCancel = cancel;
    try {
      onProgress?.call('Adalet E-İmza güvenli oturumu hazırlanıyor');
      await _loginWait(
        TrayRecovery.prepare(),
        cancel,
        const Duration(seconds: 90),
        'Adalet E-İmza hazırlığı',
      );
      onProgress?.call('Kart ve sertifika okunuyor');
      final certificates = await _loginWait(
        _http.getUrl(Uri.parse('$_tray/getCertificates')),
        cancel,
        const Duration(seconds: 25),
        'Sertifika sorgusu',
      );
      certificates.headers.set('Accept', 'application/json');
      final certResponse = await _loginWait(
        certificates.close(),
        cancel,
        const Duration(seconds: 30),
        'Sertifika sorgusu',
      );
      if (certResponse.statusCode != 200) {
        throw StateError('Adalet E-İmza uygulamasına ulaşılamadı.');
      }
      final certJson = jsonDecode(
        await _loginWait(
          _body(certResponse),
          cancel,
          const Duration(seconds: 30),
          'Sertifika yanıtı',
        ),
      );
      Map? selectedCertificate;
      Map? fallbackCertificate;
      if (certJson is Map && certJson['data'] is List) {
        for (final terminal in certJson['data'] as List) {
          if (terminal is! Map || terminal['certificates'] is! List) continue;
          for (final certificate in terminal['certificates'] as List) {
            if (certificate is Map &&
                certificate['certificateId'] is String &&
                (certificate['certificateId'] as String).isNotEmpty) {
              fallbackCertificate ??= certificate;
              if (certificate['valid'] == true) {
                selectedCertificate = certificate;
                break;
              }
            }
          }
          if (selectedCertificate != null) break;
        }
      }
      final certificate = selectedCertificate ?? fallbackCertificate;
      final certificateId = certificate?['certificateId']?.toString() ?? '';
      if (certificateId.isEmpty) {
        throw StateError('İmza sertifikası bulunamadı.');
      }
      final tc = certificate?['subjectSerial']?.toString().trim() ?? '';
      _tckn = RegExp(r'^\d{11}$').hasMatch(tc) ? tc : '';

      onProgress?.call('Giriş imzası Adalet E-İmza ile oluşturuluyor');
      final sign = await _loginWait(
        _http.postUrl(Uri.parse('$_tray/sign')),
        cancel,
        const Duration(seconds: 25),
        'İmza bağlantısı',
      );
      sign.headers.contentType = ContentType.json;
      sign.headers.set('Accept', 'application/json');
      sign.add(
        utf8.encode(
          jsonEncode({
            'certificateId': certificateId,
            'password': pin,
            'content': base64Encode(loginContent),
          }),
        ),
      );
      final signResponse = await _loginWait(
        sign.close(),
        cancel,
        const Duration(seconds: 90),
        'Adalet E-İmza imza isteği',
      );
      if (signResponse.statusCode != 200) {
        throw StateError('Tray imzası alınamadı.');
      }
      final signed = jsonDecode(
        await _loginWait(
          _body(signResponse, timeout: const Duration(seconds: 90)),
          cancel,
          const Duration(seconds: 90),
          'İmza yanıtı',
        ),
      );
      if (signed is! Map ||
          signed['metadata'] is! Map ||
          signed['metadata']['STATUS'] != 'SUCCESS' ||
          signed['data'] is! Map) {
        final message = signed is Map && signed['metadata'] is Map
            ? signed['metadata']['MESSAGE']?.toString() ?? ''
            : '';
        throw StateError(
          message.isEmpty
              ? 'Adalet E-İmza giriş imzasını reddetti.'
              : 'Adalet E-İmza: $message',
        );
      }
      final signature = signed['data']['signedData']?.toString() ?? '';
      final txId = signed['data']['txId']?.toString() ?? '';
      if (signature.isEmpty || txId.isEmpty) {
        throw StateError('Tray yanıtı eksik.');
      }

      onProgress?.call('UYAP web oturumu açılıyor');
      try {
        final root = await _loginWait(
          _http.getUrl(_at('/giris')),
          cancel,
          const Duration(seconds: 30),
          'UYAP giriş sayfası',
        );
        root.headers.set('Accept', 'text/html,application/xhtml+xml,*/*');
        final rootResponse = await _loginWait(
          root.close(),
          cancel,
          const Duration(seconds: 30),
          'UYAP giriş sayfası',
        );
        _takeCookies(rootResponse);
        await rootResponse.drain<void>();
      } catch (_) {
        // The web1 step can establish its own session cookie.
        if (cancel.isCompleted) throw StateError('Giriş iptal edildi.');
      }

      final web = await _loginWait(
        _http.getUrl(_at('/web1.uyap', {'signature': signature, 'txId': txId})),
        cancel,
        const Duration(seconds: 30),
        'UYAP imza doğrulaması',
      );
      web.followRedirects = false;
      web.headers.set('Accept', 'application/json, text/plain, */*');
      web.headers.set('Cache-Control', 'no-cache');
      web.headers.set('Referer', '$_origin/giris');
      _putCookies(web);
      final webResponse = await _loginWait(
        web.close(),
        cancel,
        const Duration(seconds: 30),
        'UYAP imza doğrulaması',
      );
      _takeCookies(webResponse);
      final webBody = await _loginWait(
        _body(webResponse),
        cancel,
        const Duration(seconds: 30),
        'UYAP imza doğrulaması',
      );
      if (webResponse.statusCode != 200 ||
          (jsonDecode(webBody) as Map?)?['success'] != true) {
        throw StateError('UYAP giriş imzasını doğrulamadı.');
      }

      final login = await _loginWait(
        _http.postUrl(_at('/login.uyap')),
        cancel,
        const Duration(seconds: 30),
        'UYAP oturumu',
      );
      login.followRedirects = false;
      login.headers.contentType = ContentType.json;
      login.headers.set('Accept', 'application/json, text/plain, */*');
      login.headers.set('Referer', '$_origin/giris');
      _putCookies(login);
      login.add(utf8.encode('{}'));
      final loginResponse = await _loginWait(
        login.close(),
        cancel,
        const Duration(seconds: 30),
        'UYAP oturumu',
      );
      _takeCookies(loginResponse);
      await loginResponse.drain<void>();
      if (loginResponse.statusCode < 200 ||
          loginResponse.statusCode >= 300 ||
          !_hasCookie) {
        throw StateError('UYAP web oturumu açılamadı.');
      }

      onProgress?.call('Oturum ve kullanıcı bilgileri doğrulanıyor');
      final user = await _loginWait(
        _post('/kullanici_bilgileri.uyap', {}),
        cancel,
        const Duration(seconds: 35),
        'Kullanıcı doğrulaması',
      );
      if (user is! Map ||
          user['fmty'] == 'error' ||
          (user['adi']?.toString().trim().isEmpty ?? true)) {
        throw StateError('UYAP web oturumu doğrulanamadı.');
      }
      final name = '${user['adi']} ${user['soyadi'] ?? user['soyad'] ?? ''}'
          .trim();
      session.value = UyapSession(
        user: name,
        since: DateTime.now(),
        route: UyapLoginRoute.tray,
      );
      return name;
    } catch (_) {
      disconnect();
      rethrow;
    } finally {
      if (identical(_loginCancel, cancel)) _loginCancel = null;
    }
  });

  /// Where e-Devlet sends the lawyer back, with the code UYAP logs in by.
  static const edevletReturn = 'https://avukat.uyap.gov.tr/login.uyap';
  static const _edevletClient = '27e1dfc0-8536-11e4-b4a9-0800200c9a66';

  /// Opens a portal session and asks it for the state e-Devlet is to be
  /// given: the first half of a login through e-Devlet, by mobile signature
  /// or e-signature there. The page to show is in what comes back; the code
  /// it ends with goes to [finishEdevlet].
  Future<EdevletLogin> beginEdevlet(EdevletMethod method) => _serial(() async {
    if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      throw UnsupportedError('UYAP web bağlantısı masaüstünde kullanılabilir.');
    }
    disconnect();
    try {
      final start = await _http
          .getUrl(
            _at('/portal_baslangic.uyap', {
              'param': 'user',
              'value': 'a',
              'login_type': method.portal,
            }),
          )
          .timeout(const Duration(seconds: 30));
      start.headers.set('Accept', 'text/html,application/xhtml+xml,*/*');
      final started = await start.close().timeout(const Duration(seconds: 30));
      _takeCookies(started);
      await started.drain<void>();
      if (!_hasCookie) throw StateError('UYAP giriş için oturum açmadı.');
      final info = await _getJson('/kullanici_bilgileri.uyap', {
        'edevleturlparams': 'y',
      });
      // The portal's own number, 0 with a mobile signature: a state of 0 is
      // a state, not a missing one.
      final random = info is Map ? info['random'] : null;
      final state = '${random ?? ''}';
      if (!RegExp(r'^\d{1,32}$').hasMatch(state)) {
        throw StateError('UYAP giriş anahtarı vermedi.');
      }
      return EdevletLogin(
        method: method,
        state: state,
        page: Uri.https(
          'giris.turkiye.gov.tr',
          '/OAuth2AuthorizationServer/AuthorizationController',
          {
            'response_type': 'code',
            'scope': 'Kimlik-Dogrula',
            'redirect_uri': edevletReturn,
            'client_id': _edevletClient,
            'state': state,
            'loginTypeIndex': method.edevlet,
          },
        ),
      );
    } catch (_) {
      disconnect();
      rethrow;
    }
  });

  /// Completes [login] with the [code] e-Devlet returned: it goes to UYAP
  /// with the very session [beginEdevlet] opened, which the state is bound
  /// to. Only the level UYAP then reports says the login took.
  Future<String> finishEdevlet(EdevletLogin login, String code) =>
      _serial(() async {
        try {
          if (!_hasCookie) {
            throw StateError('UYAP oturumu kayboldu; yeniden deneyin.');
          }
          final request = await _http
              .getUrl(_at('/login.uyap', {'code': code, 'state': login.state}))
              .timeout(const Duration(seconds: 30));
          request.followRedirects = false;
          request.headers.set('Accept', 'text/html,application/json,*/*');
          request.headers.set('Referer', 'https://giris.turkiye.gov.tr/');
          _putCookies(request);
          final response = await request.close().timeout(
            const Duration(seconds: 30),
          );
          _takeCookies(response);
          await response.drain<void>();
          if (await _level() < 1) {
            throw StateError(
              'e-Devlet onayı UYAP’ta oturum açmadı. Yeniden deneyin.',
            );
          }
          var name = '';
          try {
            final user = await _post('/kullanici_bilgileri.uyap', {});
            if (user is Map) {
              name =
                  '${user['adi'] ?? ''} '
                          '${user['soyadi'] ?? user['soyad'] ?? ''}'
                      .trim();
            }
          } catch (_) {
            // The name is for showing; the level has already said yes.
          }
          if (name.isEmpty) name = 'UYAP kullanıcısı';
          session.value = UyapSession(
            user: name,
            since: DateTime.now(),
            route: login.method == EdevletMethod.mobile
                ? UyapLoginRoute.mobile
                : UyapLoginRoute.eSignature,
          );
          return name;
        } catch (_) {
          disconnect();
          rethrow;
        }
      });

  /// Whether the session is still alive, asked of UYAP. One that is not is
  /// let go of here, and everything showing it hears so.
  Future<bool> check() => _serial(() async {
    if (!_hasCookie || session.value == null) return false;
    try {
      if (await _level() >= 1) return true;
    } on SocketException {
      // Unreachable is not ended: the session may well still be there.
      return true;
    } on TimeoutException {
      return true;
    } catch (_) {
      // Answered, and not with a session.
    }
    disconnect();
    return false;
  });

  Future<int> _level() async {
    final info = await _getJson('/kullanici_bilgileri.uyap', {
      'edevleturlparams': 'y',
    });
    return info is Map ? int.tryParse('${info['level'] ?? ''}') ?? 0 : 0;
  }

  /// A GET the portal answers in JSON (as text/json).
  Future<dynamic> _getJson(String path, Map<String, String> query) async {
    final request = await _http
        .getUrl(_at(path, query))
        .timeout(const Duration(seconds: 30));
    request.followRedirects = false;
    request.headers.set('Accept', 'application/json, text/plain, */*');
    request.headers.set('Referer', '$_origin/');
    _putCookies(request);
    final response = await request.close().timeout(const Duration(seconds: 30));
    _takeCookies(response);
    final data = await _body(response);
    if (response.statusCode != 200 || data.trimLeft().startsWith('<')) {
      throw StateError('UYAP beklenmeyen bir yanıt verdi.');
    }
    return data.trim().isEmpty || data.trim() == 'null'
        ? null
        : jsonDecode(data);
  }

  Future<dynamic> _post(String path, Map<String, Object?> body) async {
    if (!_hasCookie) throw StateError('UYAP web oturumu açık değil.');
    final request = await _http.postUrl(_at(path));
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.headers.set('Accept', 'application/json, text/plain, */*');
    request.headers.set('Referer', '$_origin/giris');
    _putCookies(request);
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close().timeout(const Duration(seconds: 30));
    _takeCookies(response);
    final data = await _body(response);
    if (response.statusCode == 302 ||
        response.statusCode == 401 ||
        data.trimLeft().startsWith('<')) {
      disconnect();
      throw StateError('UYAP oturumu sona erdi. Yeniden bağlanın.');
    }
    if (response.statusCode != 200) {
      throw StateError('UYAP isteği başarısız (HTTP ${response.statusCode}).');
    }
    final parsed = jsonDecode(data);
    if (parsed is Map &&
        (parsed.containsKey('errorCode') || parsed['fmty'] == 'error')) {
      throw StateError(
        'UYAP isteği reddetti: ${parsed['error'] ?? parsed['message'] ?? parsed['errorCode']}',
      );
    }
    return parsed;
  }

  Future<List<UyapOption>> courtTypes(String jurisdiction) => _serial(() async {
    final data = await _post('/yargiBirimleriSorgula_brd.ajx', {
      'yargiTuru': jurisdiction,
    });
    return [
      for (final item in data is List ? data : const [])
        if (item is Map)
          UyapOption(
            item['tablo']?.toString() ?? '',
            item['kod']?.toString() ?? '',
          ),
    ].where((e) => e.id.isNotEmpty).toList();
  });

  Future<List<UyapOption>> courts(
    String jurisdiction,
    String courtType, {
    bool closed = false,
  }) => _serial(() async {
    final data = await _post('/avukat_mahkemeleri_sorgula.ajx', {
      'yargiTuru': jurisdiction,
      'yargiBirimi': courtType,
      'dosyaKapaliMi': closed,
    });
    return [
      for (final item in data is List ? data : const [])
        if (item is Map)
          UyapOption(_id(item['birimId']), item['birimAdi']?.toString() ?? ''),
    ].where((e) => e.id.isNotEmpty).toList();
  });

  Future<List<UyapCase>> cases({
    required String jurisdiction,
    required String courtType,
    required UyapOption court,
    int? year,
    int? number,
    bool closed = false,
    int pageNumber = 1,
  }) => _serial(() async {
    final filters = <String, Object?>{
      'dosyaDurumKod': closed ? 1 : 0,
      'pageSize': 500,
      'pageNumber': pageNumber,
      'birimTuru2': courtType,
      'birimTuru3': jurisdiction,
      'birimId': court.id,
    };
    if (year != null) filters['dosyaYil'] = year;
    if (number != null) filters['dosyaSira'] = number;
    final data = await _post('/search_phrase_detayli.ajx', filters);
    final rows = data is List && data.isNotEmpty && data.first is List
        ? data.first as List
        : const [];
    return [
          for (final row in rows)
            if (row is Map && (row['dosyaId']?.toString() ?? '').isNotEmpty)
              UyapCase(
                _id(row['dosyaId']),
                row['dosyaNo']?.toString() ?? '',
                _id(row['birimId'] ?? court.id),
                row['birimAdi']?.toString() ?? court.label,
                listing: UyapCaseListing.fromJson(row),
              ),
        ]
        .where(
          (e) =>
              (year == null ||
                  number == null ||
                  _sameCaseNumber(e.number, year, number)) &&
              e.courtId == court.id,
        )
        .toList();
  });

  Future<List<UyapDocumentType>> documentTypes(UyapCase target) =>
      _serial(() async {
        final data = await _post('/dosya_gonderilecek_evrak_listesi_brd.ajx', {
          'dosyaId': target.id,
        });
        final flat = <dynamic>[];
        if (data is List) {
          for (final item in data) {
            if (item is List) {
              flat.addAll(item);
            } else {
              flat.add(item);
            }
          }
        }
        return [
          for (final item in flat)
            if (item is Map && (item['turKodu'] ?? item['tur']) != null)
              UyapDocumentType.fromMap(item),
        ].toList();
      });

  Future<List<UyapParty>> parties(UyapCase target) => _serial(() async {
    final data = await _post('/dosya_taraf_bilgileri_brd.ajx', {
      'dosyaId': target.id,
    });
    if (data is! List || data.any((e) => e is! Map)) {
      throw const FormatException('UYAP taraf bilgileri okunamadı.');
    }
    final parties = [for (final row in data) UyapParty.fromMap(row as Map)];
    if (parties.isEmpty || parties.any((e) => e.name.isEmpty)) {
      throw StateError('Hedef dosyanın taraf bilgileri doğrulanamadı.');
    }
    return parties;
  });

  /// Read-only portal "İşlemlerim" query. The in-memory web session is reused
  /// until UYAP expires it; neither PIN nor cookies are persisted to disk.
  Future<List<UyapOperation>> operations({
    required DateTime from,
    required DateTime to,
  }) => _serial(() async {
    String date(DateTime value) => '${value.day}.${value.month}.${value.year}';
    final filters = <String, Object?>{
      'islemTuru': null,
      'isEmirNo': null,
      'baslangicTarihi': date(from),
      'bitisTarihi': date(to),
    };
    if (_tckn.isNotEmpty) filters['tcKimlikNo'] = _tckn;
    final data = await _post('/uyap_islem_sorgula.ajx', filters);
    if (data is! List || data.any((e) => e is! Map)) {
      throw const FormatException(
        'UYAP işlem sorgusu beklenmeyen yanıt döndürdü.',
      );
    }
    return [for (final row in data) UyapOperation.fromMap(row as Map)];
  });

  /// Bytes of an operation's document (PDF, UDF or TIFF). The handles come
  /// from the same "İşlemlerim" response and expire after a while; UYAP then
  /// answers with a JSON error instead of the document.
  Future<Uint8List> documentBytes(UyapOperation operation) => _serial(() async {
    if (!connected) throw StateError('UYAP web oturumu açık değil.');
    if (operation.documentId.isEmpty || operation.caseId.isEmpty) {
      throw StateError('Bu işlem kaydında evrak bilgisi yok.');
    }
    return _viewDocument(operation.documentId, operation.caseId);
  });

  /// What UYAP lets be seen of [target], and what kind of case it is.
  /// An answer that cannot be read lets everything be asked for.
  Future<UyapCasePermissions> permissions(UyapCase target) => _serial(() async {
    try {
      return UyapCasePermissions.fromJson(
        await _post('/dosya_islem_turleri_sorgula_brd.ajx', {
          'dosyaId': target.id,
        }),
      );
    } on FormatException {
      return const UyapCasePermissions(null, null);
    }
  });

  /// The fees, collections and payments out of [target]. Asked with the
  /// kind of case: the portal will not answer without it.
  Future<UyapCaseMoney> caseMoney(UyapCase target, int typeCode) =>
      _serial(() async {
        return UyapCaseMoney.fromJson(
          await _post('/dosya_tahsilat_reddiyat_bilgileri_brd.ajx', {
            'dosyaId': target.id,
            'dosyaTurKod': typeCode,
          }),
        );
      });

  /// The particulars of [target]: its kind, where it stands, and the days
  /// set for a hearing, an inspection or a preliminary examination.
  Future<UyapCaseDetails> caseDetails(UyapCase target) => _serial(() async {
    final data = await _post('/dosyaAyrintiBilgileri_brd.ajx', {
      'dosyaId': target.id,
    });
    return UyapCaseDetails.fromJson(data);
  });

  /// Every document of [target] and of the cases tied to it, page by page,
  /// each with the key it keeps from one session to the next. A page that
  /// repeats, a count that changes on the way or a page that comes back
  /// empty stops it: half a list is never handed back as the whole.
  Future<UyapCaseDocuments> caseDocuments(
    UyapCase target, {
    void Function(int page, int pages)? onPage,
  }) => _serial(() async {
    final pages = <UyapDocumentPage>[];
    final seen = <String>{};
    var total = 1;
    for (var number = 1; number <= total; number++) {
      onPage?.call(number, total);
      final page = UyapDocumentPage.fromJson(
        await _post('/list_dosya_evraklar.ajx', {
          'dosyaId': target.id,
          'pageNumber': number,
        }),
      );
      final count = page.pages == 0 ? 1 : page.pages;
      if (number == 1) {
        total = count;
      } else if (count != total) {
        throw StateError('UYAP evrak sayfaları değişti; yeniden deneyin.');
      }
      if (page.grouped.isEmpty && (total > 1 || page.message.isNotEmpty)) {
        if (number == 1 && page.message.isNotEmpty) {
          return UyapCaseDocuments(const [], withheld: page.message);
        }
        throw StateError('UYAP evrak sayfası eksik geldi; yeniden deneyin.');
      }
      final ids = [
        for (final d in page.grouped) '${d.source}|${d.number}|${d.documentId}',
      ]..sort();
      if (!seen.add(ids.join(','))) {
        throw StateError('UYAP evrak sayfası tekrarlandı; yeniden deneyin.');
      }
      pages.add(page);
    }
    return UyapCaseDocuments(keyDocuments(pages));
  });

  /// The file of a document of a case as it was filed — the UDF, not the
  /// PDF the portal shows it as — fetched by this session's ids, as the
  /// portal's own "Evrak İndir" fetches it: by the id of the case opened,
  /// [caseId], and failing that by the case the document came from.
  Future<Uint8List> caseDocumentBytes(
    UyapCaseDocument document, {
    String? caseId,
  }) => _serial(() async {
    if (!connected) throw StateError('UYAP web oturumu açık değil.');
    if (document.documentId.isEmpty) {
      throw UyapStaleDocument(
        'Evrakı indirmek için dosyanın listesini yeniden çekin.',
      );
    }
    final cases = {?caseId, document.caseId}.where((c) => c.isNotEmpty);
    UyapStaleDocument? last;
    for (final id in cases) {
      try {
        return await _viewDocument(
          document.documentId,
          id,
          path: '/download_document_brd.uyap',
        );
      } on UyapStaleDocument catch (e) {
        last = e;
      }
    }
    throw last ??
        UyapStaleDocument(
          'Evrakı indirmek için dosyanın listesini yeniden çekin.',
        );
  });

  Future<Uint8List> _viewDocument(
    String documentId,
    String caseId, {
    String path = '/view_document_brd.uyap',
  }) async {
    final request = await _http.getUrl(
      _at(path, {'evrakId': documentId, 'dosyaId': caseId}),
    );
    request.followRedirects = false;
    request.headers.set(
      'Accept',
      'application/pdf, application/octet-stream, */*',
    );
    request.headers.set('Referer', '$_origin/giris');
    _putCookies(request);
    final response = await request.close().timeout(const Duration(seconds: 30));
    _takeCookies(response);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 60))) {
      bytes.add(chunk);
      if (bytes.length > 64 * 1024 * 1024) {
        throw StateError('UYAP evrakı 64 MB sınırını aşıyor.');
      }
    }
    final data = bytes.takeBytes();
    final head = utf8
        .decode(
          data.sublist(0, data.length < 512 ? data.length : 512),
          allowMalformed: true,
        )
        .trimLeft();
    if (response.statusCode == 302 ||
        response.statusCode == 401 ||
        head.startsWith('<')) {
      disconnect();
      throw StateError('UYAP oturumu sona erdi. Yeniden bağlanın.');
    }
    if (head.startsWith('{') || head.startsWith('[')) {
      Object? parsed;
      try {
        parsed = jsonDecode(utf8.decode(data, allowMalformed: true));
      } catch (_) {}
      final message = parsed is Map
          ? parsed['error'] ?? parsed['message'] ?? parsed['errorCode']
          : null;
      throw UyapStaleDocument(
        'UYAP evrakı vermedi${message == null ? '' : ': $message'}',
      );
    }
    // An empty answer is what a stale id gets.
    if (response.statusCode == 404 || data.isEmpty) {
      throw UyapStaleDocument('UYAP evrakı vermedi; liste yeniden çekilmeli.');
    }
    if (response.statusCode != 200) {
      throw StateError('UYAP evrakı vermedi (HTTP ${response.statusCode}).');
    }
    return data;
  }

  /// No automatic retry: a lost response may follow a successful submission.
  /// [onDispatched] runs just before the request leaves; an error after it
  /// means the outcome is unknown, an error before it means nothing was sent.
  Future<String?> send({
    required UyapCase target,
    required UyapDocumentType type,
    required List<UyapUpload> files,
    void Function()? onDispatched,
  }) => _serial(() async {
    if (!connected) throw StateError('UYAP web oturumu açık değil.');
    if (files.isEmpty) throw StateError('Gönderilecek evrak yok.');
    if (files.length - 1 > type.attachmentMax) {
      throw StateError('Ek evrak sayısı UYAP sınırını aşıyor.');
    }
    final counts = <String, int>{};
    var totalBytes = 0;
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final itemType = file.documentType ?? type;
      if (p.basename(file.name) != file.name ||
          file.name.contains('"') ||
          file.name.contains('\r') ||
          file.name.contains('\n')) {
        throw StateError('Geçersiz evrak dosya adı.');
      }
      if (file.bytes.isEmpty) throw StateError('${file.name} boş.');
      final extension = p.extension(file.name).toLowerCase();
      if (i == 0 && extension != '.udf') {
        throw StateError('Ana evrak imzalı UDF olmalı.');
      }
      if (extension == '.udf') validateSignedUdf(file.bytes);
      totalBytes += file.bytes.length;
      if (totalBytes > 64 * 1024 * 1024) {
        throw StateError('Gönderim toplamı 64 MB sınırını aşıyor.');
      }
      counts[itemType.code] = (counts[itemType.code] ?? 0) + 1;
      if (itemType.max > 0 && counts[itemType.code]! > itemType.max) {
        throw StateError(
          '${itemType.label} için UYAP evrak adedi sınırı aşıldı.',
        );
      }
      final accepted = itemType.acceptedExtensions;
      if (accepted.isNotEmpty && !accepted.contains(extension)) {
        throw StateError(
          '${file.name} seçilen evrak türü için desteklenmiyor.',
        );
      }
      items.add({
        'id': DateTime.now().millisecondsSinceEpoch + i,
        'tur': itemType.code,
        'turAciklama': itemType.label,
        'mandatory': itemType.mandatory,
        'file': <String, Object?>{},
        'path': 'C:/fakepath/${file.name}',
        'kullaniciEvrakAciklama': file.description,
        'parentId': -1,
        'isVekalet': false,
        'isVekaletBilgiFormu': false,
        'fileId': i + 1,
        'evrakTuruOptionDVO': itemType.toOptionJson(),
      });
    }
    final boundary =
        '----WebKitFormBoundary${DateTime.now().millisecondsSinceEpoch}';
    final bytes = BytesBuilder(copy: false);
    void part(String name, String value) {
      bytes.add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="$name"\r\n\r\n$value\r\n',
        ),
      );
    }

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      bytes.add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="file_${i + 1}"; '
          'filename="${file.name}"\r\n'
          'Content-Type: application/octet-stream\r\n\r\n',
        ),
      );
      bytes.add(file.bytes);
      bytes.add(utf8.encode('\r\n'));
    }
    part('items', jsonEncode(items));
    part('dosyaId', target.id);
    part('isDusurme', 'false');
    part('evrakTipi', type.operationType);
    part('dosyaNo', target.number);
    part('birimId', target.courtId);
    part('birimAdi', target.courtName);
    bytes.add(utf8.encode('--$boundary--\r\n'));
    final request = await _http.postUrl(_at('/evrakGonder_brd.ajx'));
    request.followRedirects = false;
    request.headers.set(
      'Content-Type',
      'multipart/form-data; boundary=$boundary',
    );
    request.headers.set('Accept', 'application/json, text/plain, */*');
    _putCookies(request);
    final payload = bytes.takeBytes();
    request.contentLength = payload.length;
    request.add(payload);
    late final HttpClientResponse response;
    late final String body;
    onDispatched?.call();
    try {
      response = await request.close().timeout(const Duration(seconds: 60));
      _takeCookies(response);
      body = await _body(response);
    } on TimeoutException {
      try {
        request.abort();
      } catch (_) {}
      _resetTransport();
      rethrow;
    } on SocketException {
      try {
        request.abort();
      } catch (_) {}
      _resetTransport();
      rethrow;
    }
    if (response.statusCode == 302 ||
        response.statusCode == 401 ||
        body.trimLeft().startsWith('<')) {
      disconnect();
      throw StateError(
        'UYAP oturumu sona erdi; gönderim sonucunu portalda kontrol edin.',
      );
    }
    if (response.statusCode != 200) {
      throw StateError(
        'UYAP gönderim yanıtı HTTP ${response.statusCode}. '
        'Tekrar denemeden önce dosyanın evraklarını kontrol edin.',
      );
    }
    final data = jsonDecode(body);
    final result = data is Map
        ? data
        : data is List && data.isNotEmpty && data.first is Map
        ? data.first as Map
        : null;
    if (result == null ||
        !(result['type'] == 'success' ||
            result['success'] == true ||
            result['sonuc'] == true ||
            (result['evrakId']?.toString().isNotEmpty ?? false))) {
      throw StateError(
        'UYAP gönderimi doğrulamadı: '
        '${result?['mesaj'] ?? result?['message'] ?? 'Sonucu portalda kontrol edin.'}',
      );
    }
    return result['evrakId']?.toString();
  });

  static void validateSignedUdf(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final content = archive.findFile('content.xml');
    final signature = archive.findFile('sign.sgn');
    if (content == null ||
        signature == null ||
        UdfSignatureParser.parse(signature.content)
            .where((e) => !e.counterSignature && e.issue == null)
            .isEmpty ||
        !SignedData.covers(
          Uint8List.fromList(signature.content),
          content.content,
        ) ||
        !UdfSignatureParser.verifyDocument(
          signature.content,
          content.content,
        )) {
      throw StateError(
        'UDF imzası eksik, değişmiş veya kriptografik olarak doğrulanamadı.',
      );
    }
  }
}

/// UYAP refused a document handle, typically because it has expired. A fresh
/// "İşlemlerim" query issues new handles.
class UyapStaleDocument extends StateError {
  UyapStaleDocument(super.message);
}

class UyapOption {
  const UyapOption(this.id, this.label);
  final String id;
  final String label;
}

class UyapCase {
  const UyapCase(
    this.id,
    this.number,
    this.courtId,
    this.courtName, {
    this.listing,
  });
  final String id;
  final String number;
  final String courtId;
  final String courtName;

  /// What the list it was found in says of it besides.
  final UyapCaseListing? listing;

  ({int year, int sequence})? get parsedNumber {
    final match = RegExp(r'(\d{4})\s*/\s*(\d+)').firstMatch(number);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final sequence = int.tryParse(match.group(2)!);
    return year == null || sequence == null
        ? null
        : (year: year, sequence: sequence);
  }

  bool sameCase(UyapCase other) {
    final a = parsedNumber;
    final b = other.parsedNumber;
    return courtId == other.courtId &&
        (a == null || b == null ? number == other.number : a == b);
  }
}

/// A document handed to UYAP. [confirmed] is false when the request left but
/// no success response came back: it may or may not have been registered.
class UyapSendReceipt {
  const UyapSendReceipt({
    required this.target,
    required this.documentName,
    required this.documentType,
    required this.startedAt,
    required this.confirmed,
  });
  final UyapCase target;
  final String documentName;
  final String documentType;
  final DateTime startedAt;
  final bool confirmed;

  /// Pairs each receipt with its "İşlemlerim" record. `evrakId` cannot be used:
  /// UYAP issues it anew in every response. A record belongs to a receipt when
  /// it is for the same case (number + court), was created within minutes of
  /// the send, and preferably names the same document type. Each record is
  /// claimed once, oldest send first, so two sends to one case stay apart.
  static Map<UyapSendReceipt, UyapOperation> match(
    List<UyapSendReceipt> receipts,
    List<UyapOperation> operations,
  ) {
    final result = <UyapSendReceipt, UyapOperation>{};
    final claimed = <UyapOperation>{};
    final ordered = [...receipts]
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    for (final receipt in ordered) {
      final type = UyapWebService.fold(receipt.documentType);
      bool typed(UyapOperation op) =>
          type.isNotEmpty && UyapWebService.fold(op.name).contains(type);
      Duration gap(UyapOperation op) =>
          op.time!.difference(receipt.startedAt).abs();
      final candidates =
          operations.where((op) {
            final time = op.time;
            return !claimed.contains(op) &&
                time != null &&
                !time.isBefore(receipt.startedAt.subtract(matchBefore)) &&
                !time.isAfter(receipt.startedAt.add(matchAfter)) &&
                op.isFor(receipt.target);
          }).toList()..sort((a, b) {
            final byType = (typed(a) ? 0 : 1) - (typed(b) ? 0 : 1);
            return byType != 0 ? byType : gap(a).compareTo(gap(b));
          });
      if (candidates.isNotEmpty) {
        result[receipt] = candidates.first;
        claimed.add(candidates.first);
      }
    }
    return result;
  }

  /// Clock skew between this computer and UYAP, and the time a send can take.
  static const matchBefore = Duration(minutes: 5);
  static const matchAfter = Duration(minutes: 10);
}

class UyapParty {
  const UyapParty(this.name, this.role, this.lawyer, this.kind);
  final String name;
  final String role;
  final String lawyer;
  final String kind;

  factory UyapParty.fromMap(Map data) => UyapParty(
    (data['adi'] ?? '').toString().trim(),
    (data['rol'] ?? '').toString().trim(),
    (data['vekil'] ?? '').toString().trim(),
    (data['kisiKurum'] ?? '').toString().trim(),
  );

  String get identity => '$role|$name|$lawyer|$kind';
}

class UyapOperation {
  const UyapOperation({
    required this.orderNumber,
    required this.date,
    required this.court,
    required this.caseNumber,
    required this.caseId,
    required this.name,
    required this.status,
    required this.owner,
    required this.documentId,
    required this.globalDocumentId,
    required this.documentNumber,
    required this.documentDate,
    required this.documentType,
  });
  final String orderNumber;
  final String date;
  final String court;
  final String caseNumber;
  final String caseId;
  final String name;
  final String status;
  final String owner;
  final String documentId;
  final String globalDocumentId;
  final String documentNumber;
  final String documentDate;
  final String documentType;

  factory UyapOperation.fromMap(Map data) => UyapOperation(
    orderNumber: (data['isEmirNo'] ?? '').toString(),
    date: (data['isEmirTarihi'] ?? '').toString(),
    court: (data['birimAdi'] ?? '').toString(),
    caseNumber: (data['dosyaNo'] ?? '').toString(),
    caseId: UyapWebService._id(data['dosyaId']),
    name: (data['name'] ?? '').toString(),
    status: (data['isinDurumu'] ?? '').toString(),
    owner: (data['isinSahibi'] ?? '').toString(),
    documentId: UyapWebService._id(data['evrakId']),
    globalDocumentId: UyapWebService._id(data['ggEvrakId']),
    documentNumber: (data['birimEvrakNo'] ?? data['evrakNo'] ?? '').toString(),
    documentDate: (data['birimEvrakTarihi'] ?? '').toString(),
    documentType: (data['evrakTuru'] ?? '').toString(),
  );

  bool get pending {
    final value = UyapWebService.fold(status);
    return value.contains('devam') ||
        value.contains('bekle') ||
        value.contains('islemde');
  }

  bool get completed => UyapWebService.fold(status).contains('tamamlan');

  /// `isEmirTarihi`, measured as "2026-06-15 14:44:55.0"; "15.6.2026 14:44"
  /// is accepted as well. Null when UYAP sends neither.
  DateTime? get time {
    final iso = DateTime.tryParse(date.trim());
    if (iso != null) return iso;
    final m = RegExp(
      r'^(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
    ).firstMatch(date.trim());
    if (m == null) return null;
    int at(int i) => int.parse(m.group(i) ?? '0');
    return DateTime(at(3), at(2), at(1), at(4), at(5), at(6));
  }

  /// Same case by number and court name; `dosyaId` differs in every response.
  bool isFor(UyapCase target) {
    final parts = target.parsedNumber;
    return parts != null &&
        UyapWebService._sameCaseNumber(
          caseNumber,
          parts.year,
          parts.sequence,
        ) &&
        UyapWebService.fold(court) == UyapWebService.fold(target.courtName);
  }
}

class UyapDocumentType {
  const UyapDocumentType(
    this.code,
    this.label,
    this.operationType,
    this.mandatory,
    this.max,
    this.attachmentMax,
    this.acceptedExtensions,
  );
  final String code;
  final String label;
  final String operationType;
  final bool mandatory;
  final int max;
  final int attachmentMax;
  final Set<String> acceptedExtensions;

  factory UyapDocumentType.fromMap(Map data) => UyapDocumentType(
    (data['turKodu'] ?? data['tur']).toString(),
    (data['aciklama'] ?? data['label'] ?? '').toString(),
    (data['islemTipi'] ?? '1').toString(),
    data['mandatory'] == true,
    data['max'] is int ? data['max'] as int : 1,
    data['ekEvrakMax'] is int ? data['ekEvrakMax'] as int : 0,
    {
      for (final value
          in data['acceptTypeList'] is List
              ? data['acceptTypeList'] as List
              : const ['.udf'])
        value.toString().toLowerCase(),
    },
  );

  Map<String, Object?> toOptionJson() => {
    'tur': code,
    'label': label,
    'mandatory': mandatory,
    'max': max,
    'ekEvrakMax': attachmentMax,
    'sablonTurKodu': '',
    'acceptTypeList': acceptedExtensions.toList(),
  };
}

class UyapUpload {
  const UyapUpload(
    this.name,
    this.bytes, {
    this.description = '',
    this.documentType,
  });
  final String name;
  final Uint8List bytes;
  final String description;
  final UyapDocumentType? documentType;
}

/// How a UYAP session was opened.
enum UyapLoginRoute {
  /// With the card, through the Adalet E-İmza application on this computer.
  tray,

  /// Through e-Devlet, by mobile signature.
  mobile,

  /// Through e-Devlet, by e-signature.
  eSignature,
}

/// Who is logged into UYAP, how, and since when.
class UyapSession {
  const UyapSession({
    required this.user,
    required this.since,
    required this.route,
  });

  /// Measured: a portal session answered at 164 and 174 minutes and was
  /// gone at 175. Asking does not lengthen it, and only a new signature
  /// renews it, so this is the time it is shown to have, no more.
  static const lifetime = Duration(hours: 2, minutes: 55);

  final String user;
  final DateTime since;
  final UyapLoginRoute route;

  DateTime get expires => since.add(lifetime);

  Duration remaining([DateTime? now]) {
    final left = expires.difference(now ?? DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

/// How to log in through e-Devlet: what the portal and e-Devlet call it.
enum EdevletMethod {
  mobile('m', '2'),
  eSignature('t', '3');

  const EdevletMethod(this.portal, this.edevlet);

  /// `login_type` for the portal.
  final String portal;

  /// `loginTypeIndex` for e-Devlet: which of its methods opens first.
  final String edevlet;
}

/// A login through e-Devlet half way: the page to show, and the state the
/// portal bound to its session.
class EdevletLogin {
  const EdevletLogin({
    required this.method,
    required this.state,
    required this.page,
  });
  final EdevletMethod method;
  final String state;
  final Uri page;
}

/// The documents of a case: all of them, or none and why, when UYAP
/// withholds them ("Cumhuriyet savcısının onayı sonrası…").
class UyapCaseDocuments {
  const UyapCaseDocuments(this.documents, {this.withheld});
  final List<UyapCaseDocument> documents;
  final String? withheld;
}
