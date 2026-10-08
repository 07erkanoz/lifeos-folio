import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Two Folios talking over a socket: one JSON object a line. A line longer
/// than [maxLine] ends the talk; nothing a peer says is trusted to be small.
class OfficeLink {
  OfficeLink(this._socket) {
    // The bytes since the last line's end are counted as they come: a line
    // that never ends must not grow until the memory is gone.
    var since = 0;
    _lines = _socket
        .map<List<int>>((chunk) {
          final end = chunk.lastIndexOf(10);
          since = end < 0 ? since + chunk.length : chunk.length - end - 1;
          if (since > maxLine) throw const FormatException('line too long');
          return chunk;
        })
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _line,
          onError: (Object _) => close(),
          onDone: close,
          cancelOnError: true,
        );
  }

  // A person's agenda, packed, comes in one line; a crowd of silent talks
  // is let in no more than 32 at a time (see OfficeNetwork).
  static const maxLine = 1024 * 1024;

  final Socket _socket;

  /// Where the other end is, as this end sees it.
  String? get remoteHost {
    try {
      return _socket.remoteAddress.address;
    } catch (_) {
      return null;
    }
  }

  late final StreamSubscription<String> _lines;
  // Broadcast so that the one who reads the first line can hand the rest
  // to whoever answers it; nothing is said between the two.
  final _messages = StreamController<Map<String, Object?>>.broadcast();
  bool _closed = false;

  /// What the other side says, in order; done when the talk ends.
  Stream<Map<String, Object?>> get messages => _messages.stream;

  bool get closed => _closed;

  static Future<OfficeLink> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 8),
  }) async => OfficeLink(await Socket.connect(host, port, timeout: timeout));

  void _line(String line) {
    try {
      final message = jsonDecode(line);
      if (message is Map<String, Object?>) {
        _messages.add(message);
        return;
      }
    } catch (_) {}
    close();
  }

  void send(Map<String, Object?> message) {
    if (_closed) return;
    try {
      _socket.write('${jsonEncode(message)}\n');
    } catch (_) {
      close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _lines.cancel();
    try {
      await _socket.flush();
    } catch (_) {}
    _socket.destroy();
    await _messages.close();
  }
}
