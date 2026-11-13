import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The relay a live document shared with another office goes through
/// (canli.lifeos.com.tr): two Folios, each reaching it, are put in touch by
/// a room both name, and what one says goes to the other as it is. It is
/// sealed end to end by a key the two make with the invitation's code; the
/// relay never has the code, cannot open a word, and keeps nothing.
///
/// A room is opened by the one sharing (`rol=paylasan`) and taken by one
/// joining (`rol=katilan`), once: one invitation, one person. The sharer
/// is told `{"t":"katilan"}` when someone comes; everything else is the
/// two Folios' own. Either leaving ends it for both.
///
/// The same rooms put one person's own devices in touch when they are on
/// different networks (Senkron, `kisi=` named): then what a room carries
/// is counted, for a day and a month, against that `kisi` (a digest of the
/// person's key, which tells the relay no one's name) and against the
/// address it came from, and stopped past [RelayLimits]'s quotas. Nothing
/// carried is ever written anywhere: it goes from one socket to the other
/// in memory; only the counts are kept.
class RelayServer {
  RelayServer._(this._server, this.limits);

  final HttpServer _server;
  final RelayLimits limits;
  final _rooms = <String, _Room>{};
  final _perAddress = <String, int>{};

  /// Own devices' bytes carried: by person and by address, this day and
  /// this month; and the sockets a person has open.
  final _quota = _Quota();
  final _personSockets = <String, int>{};

  /// Where the counts are kept between runs; none in a test.
  File? _counts;
  Timer? _keep;
  int _sockets = 0;
  Timer? _report;

  /// Rooms opened, joined and closed since the last report: counts only,
  /// never a room's name nor an address (KVKK).
  int _opened = 0, _joined = 0;

  int get port => _server.port;
  int get rooms => _rooms.length;

  static Future<RelayServer> start({
    Object address = '127.0.0.1',
    int port = 0,
    RelayLimits limits = const RelayLimits(),
    Duration? report,
    File? counts,
  }) async {
    final server = await HttpServer.bind(address, port);
    server.idleTimeout = const Duration(seconds: 30);
    final relay = RelayServer._(server, limits);
    if (counts != null) {
      relay._counts = counts;
      if (await counts.exists()) {
        try {
          relay._quota.load(jsonDecode(await counts.readAsString()));
        } catch (e) {
          stderr.writeln('sayac okunamadi, sifirdan: $e');
        }
      }
      relay._keep = Timer.periodic(
        const Duration(minutes: 5),
        (_) => unawaited(relay._save()),
      );
    }
    server.listen(relay._request, onError: (Object _) {});
    if (report != null) {
      relay._report = Timer.periodic(report, (_) => relay._tell());
    }
    return relay;
  }

  void _tell() {
    stdout.writeln(
      'odalar=${_rooms.length} baglanti=$_sockets '
      'acilan=$_opened katilan=$_joined',
    );
    _opened = 0;
    _joined = 0;
  }

  /// The counts kept, one write after another (the timer's and the
  /// close's never at once): written beside, then put in place, so that a
  /// stop halfway leaves the last whole one.
  Future<void> _saving = Future.value();
  Future<void> _save() => _saving = _saving.then((_) => _write());

  Future<void> _write() async {
    final file = _counts;
    if (file == null) return;
    try {
      final next = File('${file.path}.yeni');
      await next.writeAsString(jsonEncode(_quota.toJson()), flush: true);
      await next.rename(file.path);
    } catch (e) {
      stderr.writeln('sayac yazilamadi: $e');
    }
  }

  /// Whether [person] (and [address]) may carry [size] bytes more, counted
  /// when so.
  bool _spend(String? person, String address, int size) =>
      _quota.spend(person, address, size, limits);

  Future<void> close() async {
    _report?.cancel();
    _keep?.cancel();
    await _save();
    for (final room in _rooms.values.toList()) {
      room.end(1001);
    }
    await _server.close(force: true);
  }

  static final _roomName = RegExp(r'^[A-Za-z0-9_-]{43}$');

  /// The address it came from: Caddy's word for it, else the socket's.
  static String _address(HttpRequest request) {
    final said = request.headers.value('x-real-ip')?.trim();
    if (said != null && said.isNotEmpty && said.length < 64) return said;
    return request.connectionInfo?.remoteAddress.address ?? '?';
  }

  Future<void> _request(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/saglik') {
        request.response
          ..headers.contentType = ContentType.text
          ..write('ok');
        await request.response.close();
        return;
      }
      final parts = request.uri.pathSegments;
      if (parts.length == 3 &&
          parts[0] == 'v1' &&
          parts[1] == 'oda' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        await _socket(request, parts[2]);
        return;
      }
      if (path == '/.well-known/assetlinks.json') {
        // Android opens this site's links in Folio itself, once it finds
        // Folio's signing certificate named here.
        request.response
          ..headers.contentType = ContentType.json
          ..write(assetLinks);
        await request.response.close();
        return;
      }
      if (path == '/' || path == '/katil') {
        request.response
          ..headers.contentType = ContentType.html
          ..headers.set('cache-control', 'no-store')
          ..headers.set('referrer-policy', 'no-referrer')
          ..headers.set('x-content-type-options', 'nosniff')
          ..write(joinPage);
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _socket(HttpRequest request, String name) async {
    final role = request.uri.queryParameters['rol'];
    final person = request.uri.queryParameters['kisi'];
    final address = _address(request);
    if (!_roomName.hasMatch(name) ||
        (role != 'paylasan' && role != 'katilan') ||
        (person != null && !_roomName.hasMatch(person))) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    // A quota used: 429, the person's own devices wait for tomorrow. The
    // relay full: 503, tried again in a while.
    if (!_quota.mayStart(person, address, limits)) {
      request.response.statusCode = HttpStatus.tooManyRequests;
      await request.response.close();
      return;
    }
    if (_sockets >= limits.sockets ||
        (_perAddress[address] ?? 0) >= limits.perAddress ||
        (person != null &&
            (_personSockets[person] ?? 0) >= limits.personSockets)) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    // The places taken before the socket is made: two at once must not
    // both find the last one free.
    _sockets++;
    _perAddress[address] = (_perAddress[address] ?? 0) + 1;
    if (person != null) {
      _personSockets[person] = (_personSockets[person] ?? 0) + 1;
    }
    void giveBack() {
      if (person != null) {
        final n = (_personSockets[person] ?? 1) - 1;
        if (n <= 0) {
          _personSockets.remove(person);
        } else {
          _personSockets[person] = n;
        }
      }
      _sockets--;
      final n = (_perAddress[address] ?? 1) - 1;
      if (n <= 0) {
        _perAddress.remove(address);
      } else {
        _perAddress[address] = n;
      }
    }

    final WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(request);
    } catch (_) {
      giveBack();
      return;
    }
    ws.pingInterval = limits.ping;
    unawaited(ws.done.whenComplete(giveBack));
    if (role == 'paylasan') {
      if (_rooms.containsKey(name) || _rooms.length >= limits.rooms) {
        await ws.close(4409, 'oda var');
        return;
      }
      final room = _Room(this, name, ws, person: person);
      _rooms[name] = room;
      _opened++;
      room.listen(ws, sharer: true, address: address);
      return;
    }
    final room = _rooms[name];
    if (room == null) {
      await ws.close(4404, 'oda yok');
      return;
    }
    if (room.used || room.person != person) {
      await ws.close(4410, 'oda dolu');
      return;
    }
    room.join(ws, address);
    _joined++;
  }

  void _gone(_Room room) {
    if (identical(_rooms[room.name], room)) _rooms.remove(room.name);
  }
}

/// Bytes carried, by day and month: by address for every room, by person
/// for the person's own devices; counts against digests and addresses
/// only, never what was carried.
///
/// A person's tag is the client's word: no one's tag can be proved without
/// accounts, and a proof would not stop one making new keys. So the
/// address's day is what holds the relay; the person's quota keeps a
/// person to a fair share. An address may bring [newPerAddress] new tags a
/// day; the tables are kept to [most] entries, the oldest let go of when
/// full, so that a flood of tags neither grows the relay's memory nor
/// shuts out anyone else.
class _Quota {
  static const most = 50000, newPerAddress = 10;
  String _day = '', _month = '';
  final _personDay = <String, int>{};
  final _personMonth = <String, int>{};
  final _addressDay = <String, int>{};
  final _addressNew = <String, int>{};

  static void _keep(Map<String, int> table, String key, int value) {
    if (!table.containsKey(key) && table.length >= most) {
      table.remove(table.keys.first);
    }
    table[key] = value;
  }

  void _roll() {
    final now = DateTime.now().toUtc();
    final day = now.toIso8601String().substring(0, 10);
    final month = day.substring(0, 7);
    if (day != _day) {
      _day = day;
      _personDay.clear();
      _addressDay.clear();
      _addressNew.clear();
    }
    if (month != _month) {
      _month = month;
      _personMonth.clear();
    }
  }

  /// Whether a socket may open: no quota of its used, and, for a tag not
  /// seen this month, the address not past its new tags of the day.
  bool mayStart(String? person, String address, RelayLimits l) {
    _roll();
    if ((_addressDay[address] ?? 0) >= l.addressDay) return false;
    if (person == null) return true;
    if ((_personDay[person] ?? 0) >= l.personDay ||
        (_personMonth[person] ?? 0) >= l.personMonth) {
      return false;
    }
    if (_personMonth.containsKey(person)) return true;
    final brought = _addressNew[address] ?? 0;
    if (brought >= newPerAddress) return false;
    _keep(_addressNew, address, brought + 1);
    _keep(_personMonth, person, 0);
    return true;
  }

  bool spend(String? person, String address, int size, RelayLimits l) {
    _roll();
    final from = (_addressDay[address] ?? 0) + size;
    final day = person == null ? 0 : (_personDay[person] ?? 0) + size;
    final month = person == null ? 0 : (_personMonth[person] ?? 0) + size;
    final over =
        from > l.addressDay ||
        (person != null && (day > l.personDay || month > l.personMonth));
    if (over) {
      // Used: whatever is asked of it after this is turned away too.
      if (from > l.addressDay) _keep(_addressDay, address, l.addressDay);
      if (person != null) {
        if (day > l.personDay) _keep(_personDay, person, l.personDay);
        if (month > l.personMonth) _keep(_personMonth, person, l.personMonth);
      }
      return false;
    }
    _keep(_addressDay, address, from);
    if (person != null) {
      _keep(_personDay, person, day);
      _keep(_personMonth, person, month);
    }
    return true;
  }

  Map<String, Object?> toJson() {
    _roll();
    return {
      'gun': _day,
      'ay': _month,
      'kisiGun': _personDay,
      'kisiAy': _personMonth,
      'adresGun': _addressDay,
    };
  }

  void load(Object? json) {
    if (json is! Map) return;
    _roll();
    void fill(Map<String, int> into, Object? from) {
      if (from is! Map) return;
      for (final e in from.entries) {
        if (into.length >= most) return;
        if (e.key is String && e.value is int) into[e.key as String] = e.value;
      }
    }

    if (json['gun'] == _day) {
      fill(_personDay, json['kisiGun']);
      fill(_addressDay, json['adresGun']);
    }
    if (json['ay'] == _month) fill(_personMonth, json['kisiAy']);
  }
}

/// How far the relay goes for anyone.
class RelayLimits {
  const RelayLimits({
    this.rooms = 2000,
    this.sockets = 4000,
    this.perAddress = 40,
    this.message = 1536 * 1024,
    this.bytes = 1024 * 1024 * 1024,
    this.waiting = const Duration(minutes: 15),
    this.idle = const Duration(minutes: 5),
    this.lifetime = const Duration(hours: 12),
    this.ping = const Duration(seconds: 20),
    this.personDay = 50 * 1024 * 1024,
    this.personMonth = 500 * 1024 * 1024,
    this.addressDay = 100 * 1024 * 1024,
    this.personSockets = 6,
  });

  /// One person's own devices: bytes a day and a month, and sockets open
  /// at once (three devices, each waiting for the other two at most); and
  /// the bytes a day from one address. Low: the relay carries a lawyer's
  /// agenda and records, and a few documents, not archives.
  final int personDay, personMonth, addressDay, personSockets;

  /// Rooms open at once, sockets at once, and from one address.
  final int rooms, sockets, perAddress;

  /// The most one message may be: a word's piece sealed and written out
  /// stays well under it.
  final int message;

  /// The most a room may carry, both ways.
  final int bytes;

  /// How long a room waits for the one it is for; how long it may go with
  /// nothing said (the two say they are there every few seconds); and how
  /// long it may last at all.
  final Duration waiting, idle, lifetime;

  final Duration ping;
}

class _Room {
  _Room(this.relay, this.name, this.sharer, {this.person}) {
    _waiting = Timer(relay.limits.waiting, () {
      if (joiner == null) end(4408);
    });
    _lifetime = Timer(relay.limits.lifetime, () => end(4408));
  }

  final RelayServer relay;
  final String name;
  final WebSocket sharer;

  /// The person whose own devices meet here, counted against; none for a
  /// live document's invitation.
  final String? person;
  WebSocket? joiner;
  bool used = false, _ended = false;
  int _carried = 0;
  Timer? _waiting, _lifetime, _idle;

  /// Said something, once both are there: waited for again.
  void _touch() {
    if (joiner == null) return;
    _idle?.cancel();
    _idle = Timer(relay.limits.idle, () => end(4408));
  }

  void join(WebSocket ws, String address) {
    used = true;
    joiner = ws;
    _waiting?.cancel();
    listen(ws, sharer: false, address: address);
    _touch();
    sharer.add(jsonEncode({'t': 'katilan'}));
  }

  /// What [ws] says, from [address]: counted against that address, the
  /// sender's, and the room's person.
  void listen(WebSocket ws, {required bool sharer, required String address}) {
    ws.listen(
      (data) {
        final size = data is String
            ? data.length
            : data is List<int>
            ? data.length
            : 0;
        if (size > relay.limits.message) return end(1009);
        _carried += size;
        if (_carried > relay.limits.bytes) return end(4413);
        // Past the address's quota (any room), or the person's (own
        // devices'): stopped.
        if (!relay._spend(person, address, size)) return end(4429);
        _touch();
        final to = sharer ? joiner : this.sharer;
        // The sharer has no one to say anything to before someone comes.
        if (to == null) return;
        try {
          to.add(data);
        } catch (_) {
          end(1011);
        }
      },
      onDone: () => end(1000),
      onError: (Object _) => end(1011),
      cancelOnError: true,
    );
  }

  void end(int code) {
    if (_ended) return;
    _ended = true;
    _waiting?.cancel();
    _lifetime?.cancel();
    _idle?.cancel();
    relay._gone(this);
    for (final ws in [sharer, joiner]) {
      if (ws == null) continue;
      unawaited(ws.close(code).catchError((Object _) {}));
    }
  }
}

/// Folio's Android package and its signing certificate (release key,
/// SHA-256), for App Links.
const assetLinks =
    '[{"relation":["delegate_permission/common.handle_all_urls"],'
    '"target":{"namespace":"android_app",'
    '"package_name":"com.erkanoz.evrak_convert",'
    '"sha256_cert_fingerprints":["E0:2B:92:1B:90:66:1D:84:BB:E3:D9:5B:13:89:'
    '37:1A:20:82:8E:5C:AC:BD:2A:76:F3:AA:86:44:73:9B:49:17"]}}]';

/// What an invitation's link opens in a browser: the code, read from the
/// link's fragment, which the browser never sends here, and where to type
/// it. Nothing is loaded from elsewhere and nothing is kept.
const joinPage = r'''<!doctype html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex">
<title>Canlı belgeye katıl · LifeOS Folio</title>
<style>
  :root { --ink:#1B2130; --muted:#5B6373; --line:#E3E7EE; --primary:#2B5EA8; --page:#F4F6F9; }
  @media (prefers-color-scheme: dark) { :root { --ink:#E7EAF0; --muted:#A3AAB8; --line:#2C3340; --primary:#8FB4EA; --page:#14181F; } }
  * { box-sizing:border-box; }
  body { margin:0; font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; color:var(--ink); background:var(--page); }
  main { max-width:520px; margin:0 auto; padding:40px 16px; }
  h1 { font-size:22px; margin:0 0 8px; }
  p { line-height:1.55; color:var(--muted); margin:0 0 14px; }
  .code { font:700 32px ui-monospace,Consolas,monospace; letter-spacing:4px; text-align:center; padding:18px; border:1.5px solid var(--primary); border-radius:14px; margin:18px 0; }
  ol { padding-left:20px; line-height:1.7; }
  a { color:var(--primary); }
  .ac { display:inline-block; font-weight:600; padding:10px 16px; border-radius:10px; background:var(--primary); color:#fff; text-decoration:none; margin-right:6px; }
  @media (prefers-color-scheme: dark) { .ac { color:#14181F; } }
  button { font:inherit; padding:10px 16px; border-radius:10px; border:1px solid var(--line); background:transparent; color:var(--ink); cursor:pointer; }
</style>
</head>
<body>
<main>
  <h1>Canlı belgeye davet edildiniz</h1>
  <p>Bir meslektaşınız sizinle LifeOS Folio’da bir belgeyi canlı paylaşıyor.</p>
  <div class="code" id="kod">—</div>
  <p style="text-align:center"><a id="ac" class="ac" href="#">Folio’da aç</a> <button id="kopyala" type="button">Kodu kopyala</button></p>
  <ol>
    <li><b>Folio’da aç</b>’a basın; Folio açılır ve kod hazır gelir.</li>
    <li>Olmazsa Folio’yu kendiniz açın; ana sayfada <b>Canlı belge</b>’ye basıp bu kodu yazın.</li>
    <li>Paylaşan onaylayınca belge açılır.</li>
  </ol>
  <p>Folio yüklü değilse <a href="https://lifeos.com.tr/">lifeos.com.tr</a> adresinden ücretsiz indirebilirsiniz.</p>
  <p>Belge iki Folio arasında şifreli gider; bu sunucu içeriğini göremez ve hiçbir şey saklamaz. Kod 15 dakika geçerlidir.</p>
</main>
<script>
  var raw = (location.hash || '').replace('#', '').toUpperCase().replace(/[^0-9A-Z]/g, '');
  var ok = /^[0-9A-HJKMNP-TV-Z]{9}$/.test(raw);
  var shown = ok ? raw.slice(0, 3) + '-' + raw.slice(3, 6) + '-' + raw.slice(6) : '—';
  document.getElementById('kod').textContent = shown;
  document.getElementById('kopyala').onclick = function () {
    if (ok && navigator.clipboard) navigator.clipboard.writeText(shown);
  };
  if (ok) document.getElementById('ac').href = 'lifeos-folio://katil/' + raw;
  if (!ok) {
    document.getElementById('kopyala').style.display = 'none';
    document.getElementById('ac').style.display = 'none';
  }
</script>
</body>
</html>
''';
