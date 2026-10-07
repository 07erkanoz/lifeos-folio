import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;

import '../legal/deadlines/legal_day.dart';

/// UETS, the national electronic notification system (api.etebligat.gov.tr),
/// Folio's third channel (UYGULAMAPLANI §3, P05/P08). Its own login, by
/// mobile signature or by the card; its own token, which lasts about half
/// an hour and cannot be renewed. Nothing here touches UYAP.
class UetsApi {
  UetsApi._() : _base = Uri.parse(_api);

  @visibleForTesting
  UetsApi.forTesting(Uri base, {this.pollEvery = const Duration(seconds: 2)})
    : _base = base;

  static UetsApi _instance = UetsApi._();
  static UetsApi get instance => _instance;
  @visibleForTesting
  static set instance(UetsApi api) => _instance = api;

  static const _api = 'https://api.etebligat.gov.tr/v1/';

  final Uri _base;
  Duration pollEvery = const Duration(seconds: 2);
  HttpClient? _client;
  HttpClient get _http =>
      _client ??= HttpClient()..connectionTimeout = const Duration(seconds: 20);

  String? _token;
  DateTime? _expires;
  int _generation = 0;

  /// Who is logged in and until when; null when no one is.
  final session = ValueNotifier<UetsSession?>(null);

  bool get connected =>
      _token != null &&
      _expires != null &&
      _expires!.isAfter(DateTime.now().add(const Duration(seconds: 60)));

  /// The GSM number as UETS wants it: ten digits, no 0 or +90.
  static String gsm(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('90') && digits.length == 12) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('0') && digits.length == 11) {
      digits = digits.substring(1);
    }
    return digits;
  }

  /// Starts a mobile-signature login. The [MobileLogin.fingerprint] is shown
  /// to the lawyer, to be matched with the one on the phone.
  Future<MobileLogin> startMobile({
    required String tckn,
    required String phone,
    required MobileOperator operator,
  }) async {
    final data = await _send('POST', 'auth/_mobil_imza', {
      'tcn': tckn.trim(),
      'mobile': gsm(phone),
      'provider': operator.code,
    }, authorized: false);
    final map = data is Map ? data : const {};
    final id = '${map['transaction_id'] ?? ''}';
    if (id.isEmpty) throw StateError('UETS mobil imza işlemi başlatılamadı.');
    return MobileLogin(
      tckn: tckn.trim(),
      transaction: id,
      fingerprint: '${map['fingerprint'] ?? ''}',
      generation: ++_generation,
    );
  }

  /// Waits for the phone's approval, then opens the session; at most
  /// [timeout]. A newer login, or [cancel], ends the wait.
  Future<UetsSession> finishMobile(
    MobileLogin login, {
    Duration timeout = const Duration(minutes: 5),
    Future<void>? cancel,
  }) async {
    var cancelled = false;
    unawaited(cancel?.then((_) => cancelled = true));
    final deadline = DateTime.now().add(timeout);
    bool live() =>
        !cancelled &&
        login.generation == _generation &&
        DateTime.now().isBefore(deadline);
    // The phone's answer.
    while (true) {
      if (!live()) {
        throw StateError('UETS girişi iptal edildi ya da süre doldu.');
      }
      final status = await _sendRaw(
        'GET',
        'auth/_mobil_imza?tcn=${Uri.encodeQueryComponent(login.tckn)}'
            '&transaction_id=${Uri.encodeQueryComponent(login.transaction)}',
        null,
        authorized: false,
      );
      if (status.code == 401) {
        throw StateError('UETS: ${_message(status.body, 'imza onaylanmadı')}');
      }
      if (status.code == 200 && _pending(status.body)) {
        await Future<void>.delayed(pollEvery);
        continue;
      }
      if (status.code >= 400) {
        throw StateError('UETS: ${_message(status.body, 'beklenmeyen yanıt')}');
      }
      break;
    }
    // The session, which may still be pending for a moment.
    while (true) {
      if (!live()) {
        throw StateError('UETS girişi iptal edildi ya da süre doldu.');
      }
      final answer = await _sendRaw('POST', 'clients/_authentication', {
        'method': 'mobil_imza',
        'ext_id': login.tckn,
        'transaction_id': login.transaction,
      }, authorized: false);
      if (answer.code >= 400) {
        throw StateError('UETS: ${_message(answer.body, 'giriş reddedildi')}');
      }
      final data = _json(answer.body);
      if (data is Map && '${data['access_token'] ?? ''}'.isNotEmpty) {
        return _open(data, login.tckn);
      }
      await Future<void>.delayed(pollEvery);
    }
  }

  /// Takes up the session UETS gave: the token and when it ends.
  UetsSession _open(Map data, String tckn) {
    _token = '${data['access_token']}';
    final end = data['expire_time'];
    _expires = end is num
        ? DateTime.fromMillisecondsSinceEpoch(end.toInt() * 1000)
        : DateTime.now().add(const Duration(minutes: 25));
    final clients = data['clients'];
    final s = UetsSession(
      expires: _expires!,
      method: '${data['login_method'] ?? ''}',
      accounts: clients is List ? clients.length : 1,
      tckn: tckn.trim(),
    );
    session.value = s;
    return s;
  }

  /// The card login's steps (UYGULAMAPLANI P05): open a transaction for
  /// [tckn], and get what the card must sign.
  Future<CardChallenge> startCard(String tckn) async {
    final opened = await _send('POST', 'clients/_authentication', {
      'method': 'eimza',
      'ext_id': tckn,
    }, authorized: false);
    final id = opened is Map ? opened['transactionID'] : null;
    if (id == null) throw StateError('UETS e-imza işlemi başlatılamadı.');
    final data = await _send(
      'GET',
      'auth/_eimza?transactionID=$id&TC=${Uri.encodeQueryComponent(tckn)}',
      null,
      authorized: false,
    );
    final map = data is Map ? data : const {};
    final code = map['statusCode'];
    if (code != null && '$code' != '0') {
      throw StateError(
        'UETS: ${map['statusMessage'] ?? 'imza verisi alınamadı'}',
      );
    }
    return CardChallenge(
      tckn: tckn,
      transaction: '$id',
      data: base64Decode('${map['data'] ?? ''}'),
      uuid: '${map['transactionUUID'] ?? ''}',
      type: '${map['signatureType'] ?? 'C'}',
      displayText: '${map['displayText'] ?? ''}',
      generation: ++_generation,
    );
  }

  /// Hands UETS the card's CAdES [signature] of [challenge], then waits for
  /// the session.
  Future<UetsSession> finishCard(
    CardChallenge challenge,
    Uint8List signature, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final sent = await _send('POST', 'auth/_eimza', {
      'signature': base64Encode(signature),
      'identityNumber': challenge.tckn,
      'transactionUUID': challenge.uuid,
      'signatureType': challenge.type,
    }, authorized: false);
    if (sent is Map &&
        sent['statusCode'] != null &&
        '${sent['statusCode']}' != '0') {
      throw StateError('UETS: ${sent['statusMessage'] ?? 'imza reddedildi'}');
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline) &&
        challenge.generation == _generation) {
      final answer = await _sendRaw('POST', 'clients/_authentication', {
        'method': 'eimza',
        'ext_id': challenge.tckn,
        'transactionID':
            int.tryParse(challenge.transaction) ?? challenge.transaction,
      }, authorized: false);
      final data = _json(answer.body);
      if (data is Map && '${data['access_token'] ?? ''}'.isNotEmpty) {
        return _open(data, challenge.tckn);
      }
      final state = data is Map ? '${data['status'] ?? ''}'.toLowerCase() : '';
      if (answer.code >= 400 ||
          state.contains('error') ||
          state.contains('fail') ||
          state.contains('expire')) {
        throw StateError('UETS: ${_message(answer.body, 'giriş reddedildi')}');
      }
      await Future<void>.delayed(pollEvery);
    }
    throw StateError('UETS girişi zaman aşımına uğradı.');
  }

  void logout() {
    _generation++;
    _token = null;
    _expires = null;
    session.value = null;
  }

  /// The session as it may be kept between runs: the token and when it
  /// ends. UETS gives no refresh token, so a kept session lasts as long as
  /// its token (about twenty-five minutes). Kept only in this computer's
  /// keystore, and never with the TC number.
  Map<String, Object?>? exportSession() {
    final s = session.value;
    final token = _token;
    if (s == null || token == null || _expires == null) return null;
    return {
      'token': token,
      'expires': _expires!.toUtc().toIso8601String(),
      'method': s.method,
      'accounts': s.accounts,
    };
  }

  /// Takes up a kept session whose token has not ended, and asks UETS
  /// whether it still holds it, as Banaozel does: the inbox's first
  /// notice. Only a refusal (401) ends it; UETS out of reach keeps it.
  Future<bool> restoreSession(Map<String, Object?> kept) async {
    if (connected) return true;
    final token = '${kept['token'] ?? ''}';
    final expires = DateTime.tryParse('${kept['expires'] ?? ''}')?.toLocal();
    if (token.isEmpty ||
        expires == null ||
        !expires.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return false;
    }
    _token = token;
    _expires = expires;
    session.value = UetsSession(
      expires: expires,
      method: '${kept['method'] ?? ''}',
      accounts: kept['accounts'] is int ? kept['accounts'] as int : 1,
    );
    try {
      await messages(count: 1);
    } on SocketException {
      return true;
    } on TimeoutException {
      return true;
    } on UetsAccessDenied {
      // Alive, not allowed this: still a session.
      return true;
    } catch (_) {
      // A refusal (401) has logged out already; UETS's own error has not,
      // and says nothing of the session.
      return connected;
    }
    return connected;
  }

  // Mail.

  /// One page of a folder's messages, newest first: [count] from [start].
  Future<List<UetsMessage>> messages({
    int folder = 1,
    int count = 50,
    int start = 0,
    DateTime? since,
  }) async {
    final query = [
      'sort=inserttime',
      'folders_id=$folder',
      'count=$count',
      if (start > 0) 'start=$start',
      if (since != null) 'starttime=${since.millisecondsSinceEpoch ~/ 1000}',
    ].join('&');
    final data = await _send('GET', 'messages?$query', null);
    final rows = data is List
        ? data
        : data is Map
        ? (data['messages'] ?? data['data'] ?? data['items'] ?? data['value'])
        : null;
    return [
      if (rows is List)
        for (final row in rows)
          if (row is Map) UetsMessage.fromJson(Map<String, Object?>.from(row)),
    ];
  }

  /// Every message of [folder] since [since], page by page until a page is
  /// short or brings nothing new.
  Future<List<UetsMessage>> allMessages({
    int folder = 1,
    DateTime? since,
    int pageSize = 50,
    int maxPages = 40,
  }) async {
    final out = <UetsMessage>[];
    final seen = <String>{};
    for (var page = 0; page < maxPages; page++) {
      final rows = await messages(
        folder: folder,
        count: pageSize,
        start: page * pageSize,
        since: since,
      );
      final fresh = rows.where((m) => seen.add(m.id)).toList();
      out.addAll(fresh);
      if (rows.length < pageSize || fresh.isEmpty) break;
    }
    return out;
  }

  /// Every message of [folder] since [since] (all of them without it), and
  /// whether the list is whole: false when the pages ran out before the box
  /// did, or a page brought only what was already seen, so that a short
  /// list is never taken for the whole box.
  ///
  /// The box is read fifty at a time, as Banaozel's server does; a page
  /// shorter than asked is not taken for the end, since UETS may give
  /// fewer than asked: only an empty page ends the box. Pages are moved on
  /// by what came, not by what was asked.
  Future<({List<UetsMessage> messages, bool complete})> listing({
    int folder = 1,
    DateTime? since,
    int pageSize = 50,
    int maxPages = 400,
  }) async {
    final out = <UetsMessage>[];
    final seen = <String>{};
    var start = 0;
    for (var page = 0; page < maxPages; page++) {
      final rows = await messages(
        folder: folder,
        count: pageSize,
        start: start,
        since: since,
      );
      if (rows.isEmpty) return (messages: out, complete: true);
      final fresh = rows.where((m) => seen.add(m.id)).toList();
      out.addAll(fresh);
      // A page of nothing new: the box is not moving on (an offset UETS
      // does not honour); said, not taken for the end.
      if (fresh.isEmpty) return (messages: out, complete: false);
      start += rows.length;
    }
    return (messages: out, complete: false);
  }

  /// The folders the box has, as UETS numbers them, the bin and the
  /// evidence folder left out; the inbox and the archive when UETS will
  /// not say.
  Future<List<int>> noticeFolders() async {
    try {
      final ids = <int>{};
      for (final f in await folders()) {
        final id = int.tryParse('${f['id'] ?? f['folders_id'] ?? ''}');
        // The evidence folder keeps receipts of delivery, not notices.
        final name = [
          for (final k in const ['name', 'ad', 'folder_name', 'type'])
            '${f[k] ?? ''}',
        ].join(' ').toLowerCase();
        if (id == null ||
            id == uetsBinFolder ||
            name.contains('evidence') ||
            name.contains('delil')) {
          continue;
        }
        ids.add(id);
      }
      if (ids.isNotEmpty) return (ids..add(1)).toList()..sort();
    } catch (_) {}
    return const [1, uetsArchiveFolder];
  }

  Future<List<Map<String, Object?>>> folders() async {
    final data = await _send('GET', 'folders', null);
    return [
      if (data is List)
        for (final f in data)
          if (f is Map) Map<String, Object?>.from(f),
    ];
  }

  Future<Map<String, Object?>> message(String id) async {
    final data = await _send(
      'GET',
      'messages/${Uri.encodeComponent(id)}',
      null,
    );
    return data is Map ? Map<String, Object?>.from(data) : const {};
  }

  /// The message's attachments. Downloading one marks the message read at
  /// UETS; listing them is asked only when the lawyer opens it.
  Future<List<UetsPart>> parts(String id) async {
    final data = await _send(
      'GET',
      'messages/${Uri.encodeComponent(id)}/parts',
      null,
    );
    // Anything but a list of documents is not "no documents": it is asked
    // again later.
    if (data is! List || data.any((p) => p is! Map)) {
      throw StateError('UETS ek listesi beklenmeyen biçimde geldi.');
    }
    return [
      for (final p in data) UetsPart.fromJson(Map<String, Object?>.from(p)),
    ];
  }

  Future<Uint8List> partBytes(String id, String part) => _bytes(
    'messages/${Uri.encodeComponent(id)}/parts/${Uri.encodeComponent(part)}/_download',
  );

  /// The whole notification as UETS packs it (EYP): the cover letter and
  /// every attachment.
  Future<Uint8List> package(String id) =>
      _bytes('messages/${Uri.encodeComponent(id)}/_download');

  // Transport.

  /// What one download may bring: a package past it is refused while it
  /// comes, before it fills the memory.
  static const maxDownloadBytes = 200 * 1024 * 1024;

  Future<Uint8List> _bytes(String path) async {
    final request = await _request('GET', path, null, authorized: true);
    final response = await request.close().timeout(const Duration(seconds: 90));
    final bytes = BytesBuilder(copy: false);
    // A pause between chunks, and the whole, each have their limit: a
    // slow trickle does not hold the sync for hours.
    await response
        .timeout(const Duration(seconds: 60))
        .forEach((chunk) {
          bytes.add(chunk);
          if (bytes.length > maxDownloadBytes) {
            throw StateError('UETS: dosya çok büyük.');
          }
        })
        .timeout(const Duration(minutes: 10));
    if (response.statusCode == 429) {
      final after = int.tryParse(
        response.headers.value(HttpHeaders.retryAfterHeader) ?? '',
      );
      throw UetsBusy(Duration(seconds: after ?? 30));
    }
    if (response.statusCode != 200) {
      _refuse(
        response.statusCode,
        utf8.decode(bytes.toBytes(), allowMalformed: true),
      );
    }
    return bytes.toBytes();
  }

  Future<dynamic> _send(
    String method,
    String path,
    Map<String, Object?>? body, {
    bool authorized = true,
  }) async {
    final answer = await _sendRaw(method, path, body, authorized: authorized);
    if (answer.code != 200 && answer.code != 201) {
      _refuse(answer.code, answer.body);
    }
    return _json(answer.body);
  }

  Never _refuse(int code, String body) {
    // 401 (602): the session is over; 403 (603): alive, but not allowed.
    if (code == 401) {
      logout();
      throw StateError('UETS oturumu sona erdi. Yeniden bağlanın.');
    }
    if (code == 403 || code == 404) {
      throw UetsAccessDenied('UETS: ${_message(body, 'HTTP $code')}');
    }
    throw StateError('UETS: ${_message(body, 'HTTP $code')}');
  }

  Future<HttpClientRequest> _request(
    String method,
    String path,
    Map<String, Object?>? body, {
    required bool authorized,
  }) async {
    if (authorized && !connected) {
      throw StateError('UETS oturumu açık değil.');
    }
    final request = await _http
        .openUrl(method, _base.resolve(path))
        .timeout(const Duration(seconds: 20));
    request.headers.set('Accept', 'application/json');
    if (authorized) request.headers.set('Authorization', 'Bearer $_token');
    if (body != null) {
      request.headers.set('Content-Type', 'application/json; charset=UTF-8');
      request.add(utf8.encode(jsonEncode(body)));
    }
    return request;
  }

  Future<({int code, String body})> _sendRaw(
    String method,
    String path,
    Map<String, Object?>? body, {
    required bool authorized,
  }) async {
    final request = await _request(method, path, body, authorized: authorized);
    final response = await request.close().timeout(const Duration(seconds: 90));
    final text = await response.transform(utf8.decoder).join();
    return (code: response.statusCode, body: text);
  }

  static Object? _json(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static bool _pending(String body) {
    final data = _json(body);
    return data is Map && '${data['status']}'.toLowerCase() == 'pending';
  }

  static String _message(String body, String fallback) {
    final data = _json(body);
    if (data is Map && '${data['message'] ?? ''}'.isNotEmpty) {
      return '${data['message']}';
    }
    return fallback;
  }
}

enum MobileOperator {
  turkcell('turkcell', 'Turkcell'),
  vodafone('vodafone', 'Vodafone'),
  turkTelekom('turktelekom', 'Türk Telekom');

  const MobileOperator(this.code, this.label);
  final String code;
  final String label;
}

class MobileLogin {
  final String tckn;
  final String transaction;

  /// The string the lawyer matches with the one on the phone.
  final String fingerprint;
  final int generation;
  const MobileLogin({
    required this.tckn,
    required this.transaction,
    required this.fingerprint,
    required this.generation,
  });
}

class CardChallenge {
  final String tckn;
  final String transaction;

  /// What the card signs, as UETS gave it.
  final Uint8List data;
  final String uuid;

  /// "C": the data inside the signature; "S": beside it.
  final String type;

  /// Shown to the lawyer before signing.
  final String displayText;
  final int generation;
  const CardChallenge({
    required this.tckn,
    required this.transaction,
    required this.data,
    required this.uuid,
    required this.type,
    required this.displayText,
    required this.generation,
  });
}

class UetsSession {
  final DateTime expires;
  final String method;

  /// How many UETS accounts the login reaches (the lawyer's own, an
  /// office's).
  final int accounts;

  /// Whose box it is: the TC number the login was made with. Kept in
  /// memory only, for telling one box from another.
  final String tckn;
  const UetsSession({
    required this.expires,
    this.method = '',
    this.accounts = 1,
    this.tckn = '',
  });
}

/// One notification in the list.
class UetsMessage {
  final String id;
  final String subject;
  final String sender;

  /// When UETS put it in the box; the notification counts as served five
  /// days later (Tebligat Kanunu m.7/a).
  final DateTime? sent;

  /// When it was first opened, at UETS; null while unread.
  final DateTime? read;
  final String barcode;
  final String status;

  const UetsMessage({
    required this.id,
    required this.subject,
    this.sender = '',
    this.sent,
    this.read,
    this.barcode = '',
    this.status = '',
  });

  /// Five days on from the day [sent] fell on in Turkey, whatever zone
  /// this computer is set to.
  DateTime? get served =>
      sent == null ? null : turkeyDay(sent!).addDays(5).toLocal();

  factory UetsMessage.fromJson(Map<String, Object?> json) {
    DateTime? time(Object? v) {
      final n = v is num ? v.toInt() : int.tryParse('$v');
      return n == null || n <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(n * 1000);
    }

    final attributes = json['attributes'];
    return UetsMessage(
      id: '${json['id'] ?? json['messages_id'] ?? ''}',
      subject: '${json['subject'] ?? ''}'.trim(),
      sender: '${json['sender_name'] ?? json['sender'] ?? ''}'.trim(),
      sent: time(json['inserttime']),
      read: time(attributes is Map ? attributes['readtime'] : null),
      barcode: '${json['reference_id'] ?? ''}',
      status: '${json['status'] ?? ''}',
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'subject': subject,
    'sender_name': sender,
    'inserttime': sent == null ? null : sent!.millisecondsSinceEpoch ~/ 1000,
    'attributes': {
      'readtime': read == null ? 0 : read!.millisecondsSinceEpoch ~/ 1000,
    },
    'reference_id': barcode,
    'status': status,
  };
}

class UetsPart {
  final String id;
  final String name;
  final String mime;
  final bool signed;
  const UetsPart({
    required this.id,
    required this.name,
    this.mime = '',
    this.signed = false,
  });

  factory UetsPart.fromJson(Map<String, Object?> json) => UetsPart(
    id: '${json['Id'] ?? json['id'] ?? ''}',
    name: '${json['DosyaAdi'] ?? json['Ad'] ?? json['name'] ?? 'Ek'}',
    mime: '${json['MimeTuru'] ?? ''}',
    signed: json['ImzaliMi'] == true,
  );
}

/// UETS's folder of archived notices (1 is the inbox).
const uetsArchiveFolder = 4;

/// UETS's bin: what the lawyer threw away.
const uetsBinFolder = 5;

/// UETS answered, but would not give this: the session lives (a 403, or a
/// folder this box has not).
class UetsAccessDenied extends StateError {
  UetsAccessDenied(super.message);
}

/// UETS asked to be asked less often (429): wait [retryAfter] and ask
/// again.
class UetsBusy implements Exception {
  final Duration retryAfter;
  const UetsBusy(this.retryAfter);
  @override
  String toString() =>
      'UETS yoğun; ${retryAfter.inSeconds} sn sonra yeniden denenecek.';
}
