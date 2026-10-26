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
class RelayServer {
  RelayServer._(this._server, this.limits);

  final HttpServer _server;
  final RelayLimits limits;
  final _rooms = <String, _Room>{};
  final _perAddress = <String, int>{};
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
  }) async {
    final server = await HttpServer.bind(address, port);
    server.idleTimeout = const Duration(seconds: 30);
    final relay = RelayServer._(server, limits);
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

  Future<void> close() async {
    _report?.cancel();
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
    final address = _address(request);
    if (!_roomName.hasMatch(name) ||
        (role != 'paylasan' && role != 'katilan')) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    if (_sockets >= limits.sockets ||
        (_perAddress[address] ?? 0) >= limits.perAddress) {
      request.response.statusCode = HttpStatus.tooManyRequests;
      await request.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(request);
    ws.pingInterval = limits.ping;
    _sockets++;
    _perAddress[address] = (_perAddress[address] ?? 0) + 1;
    unawaited(
      ws.done.whenComplete(() {
        _sockets--;
        final n = (_perAddress[address] ?? 1) - 1;
        if (n <= 0) {
          _perAddress.remove(address);
        } else {
          _perAddress[address] = n;
        }
      }),
    );
    if (role == 'paylasan') {
      if (_rooms.containsKey(name) || _rooms.length >= limits.rooms) {
        await ws.close(4409, 'oda var');
        return;
      }
      final room = _Room(this, name, ws);
      _rooms[name] = room;
      _opened++;
      room.listen(ws, sharer: true);
      return;
    }
    final room = _rooms[name];
    if (room == null) {
      await ws.close(4404, 'oda yok');
      return;
    }
    if (room.used) {
      await ws.close(4410, 'oda dolu');
      return;
    }
    room.join(ws);
    _joined++;
  }

  void _gone(_Room room) {
    if (identical(_rooms[room.name], room)) _rooms.remove(room.name);
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
  });

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
  _Room(this.relay, this.name, this.sharer) {
    _waiting = Timer(relay.limits.waiting, () {
      if (joiner == null) end(4408);
    });
    _lifetime = Timer(relay.limits.lifetime, () => end(4408));
  }

  final RelayServer relay;
  final String name;
  final WebSocket sharer;
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

  void join(WebSocket ws) {
    used = true;
    joiner = ws;
    _waiting?.cancel();
    listen(ws, sharer: false);
    _touch();
    sharer.add(jsonEncode({'t': 'katilan'}));
  }

  void listen(WebSocket ws, {required bool sharer}) {
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
