import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class TiffRaster {
  final int width, height;
  final Uint8List rgba;
  const TiffRaster(this.width, this.height, this.rgba);
}

class _Request {
  final int page;
  final done = Completer<TiffRaster>();
  _Request(this.page);
}

/// Owns one decoder in one worker, so the file/header is read only once.
class TiffPreviewSession {
  final _messages = ReceivePort();
  final _errors = ReceivePort();
  final _exits = ReceivePort();
  final _ready = Completer<void>();
  final _pending = <int, _Request>{};
  final _queue = <_Request>[];
  Isolate? _worker;
  SendPort? _commands;
  _Request? _active;
  bool _closed = false;
  int pageCount = 0;
  int decodedPages = 0;
  TiffPreviewSession._();

  static Future<TiffPreviewSession> open(String path) async {
    final session = TiffPreviewSession._();
    session._ready.future.ignore();
    session._messages.listen(session._receive);
    session._errors.listen(
      (error) => session._fail(StateError('TIFF çözücüsü: $error')),
    );
    session._exits.listen((_) {
      if (!session._closed) session._fail(StateError('TIFF çözücüsü kapandı.'));
    });
    try {
      session._worker = await Isolate.spawn(
        _decodeWorker,
        (path, session._messages.sendPort),
        onError: session._errors.sendPort,
        onExit: session._exits.sendPort,
      );
      await session._ready.future;
      return session;
    } catch (_) {
      session.close();
      rethrow;
    }
  }

  void _receive(dynamic raw) {
    if (_closed) return;
    final message = raw as List;
    if (message[0] == 'ready') {
      _commands = message[1] as SendPort;
      pageCount = message[2] as int;
      _ready.complete();
      return;
    }
    if (message[0] == 'fatal') {
      _fail(StateError(message[1] as String));
      return;
    }
    final request = _active;
    if (request == null) return;
    _pending.remove(request.page);
    _active = null;
    if (message[0] == 'page') {
      decodedPages++;
      request.done.complete(
        TiffRaster(
          message[1] as int,
          message[2] as int,
          (message[3] as TransferableTypedData).materialize().asUint8List(),
        ),
      );
    } else {
      request.done.completeError(StateError(message[1] as String));
    }
    _drain();
  }

  Future<TiffRaster> page(int page, {bool priority = true}) {
    if (_closed) return Future.error(StateError('TIFF kapatıldı.'));
    if (page < 0 || page >= pageCount) {
      return Future.error(RangeError.range(page, 0, pageCount - 1));
    }
    if (priority) {
      for (final stale
          in _queue.where((r) => (r.page - page).abs() > 1).toList()) {
        _queue.remove(stale);
        _pending.remove(stale.page);
        stale.done.completeError(StateError('Sayfa isteği değişti.'));
      }
    }
    final request = _pending.putIfAbsent(page, () {
      final request = _Request(page);
      _queue.add(request);
      return request;
    });
    if (priority && _queue.remove(request)) _queue.insert(0, request);
    _drain();
    return request.done.future;
  }

  void promote(int page) {
    final request = _pending[page];
    if (request != null && _queue.remove(request)) _queue.insert(0, request);
    _drain();
  }

  void _drain() {
    if (_closed || _active != null || _queue.isEmpty) return;
    _active = _queue.removeAt(0);
    _commands!.send(_active!.page);
  }

  void _fail(Object error) {
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final request in _pending.values) {
      if (!request.done.isCompleted) request.done.completeError(error);
    }
    _pending.clear();
    _queue.clear();
    _active = null;
    close();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final request in _pending.values) {
      if (!request.done.isCompleted) {
        request.done.completeError(StateError('TIFF kapatıldı.'));
      }
    }
    _pending.clear();
    _queue.clear();
    _worker?.kill(priority: Isolate.immediate);
    _messages.close();
    _errors.close();
    _exits.close();
  }
}

void _decodeWorker((String, SendPort) request) async {
  final (path, output) = request;
  try {
    final decoder = img.TiffDecoder();
    final info = decoder.startDecode(await File(path).readAsBytes());
    if (info == null || decoder.numFrames() == 0) {
      throw const FormatException('TIFF sayfaları okunamadı.');
    }
    final commands = ReceivePort();
    output.send(['ready', commands.sendPort, decoder.numFrames()]);
    await for (final index in commands) {
      try {
        var frame = decoder.decodeFrame(index as int);
        if (frame == null) throw const FormatException('Sayfa okunamadı.');
        final longest = frame.width > frame.height ? frame.width : frame.height;
        if (longest > 2000) {
          frame = img.copyResize(
            frame,
            width: (frame.width * 2000 / longest).round().clamp(1, 2000),
            height: (frame.height * 2000 / longest).round().clamp(1, 2000),
            interpolation: img.Interpolation.average,
          );
        }
        if (frame.format != img.Format.uint8) {
          frame = frame.convert(format: img.Format.uint8);
        }
        output.send([
          'page',
          frame.width,
          frame.height,
          TransferableTypedData.fromList([
            frame.getBytes(order: img.ChannelOrder.rgba),
          ]),
        ]);
      } catch (e) {
        output.send(['error', 'TIFF sayfası açılamadı: $e']);
      }
    }
  } catch (e) {
    output.send(['fatal', 'TIFF açılamadı: $e']);
  }
}
