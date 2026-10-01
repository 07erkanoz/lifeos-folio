import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'pdfium_setup.dart';

/// PDF text and page pictures for code that runs outside the interface
/// isolate: indexing, OCR.
///
/// PDFium belongs to one isolate. pdfrx installs its font mapper in PDFium,
/// which is one library for the whole process, as callbacks that only the
/// isolate that made them may call. A second isolate that starts pdfrx puts
/// its own callbacks in their place, and the next page the first one opens
/// with a font it does not embed aborts the process ("Cannot invoke native
/// callback from a different isolate"). Indexing a PDF, then previewing one,
/// closed the app. PDFium is not thread-safe either, and two pdfrx workers
/// use it from two threads.
///
/// So the interface isolate runs [PdfPagesHost], and every other isolate
/// that has been given its [host] asks it. Where no host is set, this
/// isolate is the one that owns PDFium and reads directly.
abstract final class PdfPages {
  /// The owner's port, in an isolate that must not load PDFium itself.
  static SendPort? host;

  /// The text of a PDF and its page count; null where PDFium cannot be
  /// loaded at all. Stops reading pages once [maxCharacters] is passed.
  static Future<(String, int)?> text(String path, int maxCharacters) async {
    final port = host;
    if (port == null) return _text(path, maxCharacters);
    final answer = await _ask(port, {
      'op': 'text',
      'path': path,
      'max': maxCharacters,
    });
    if (answer['unavailable'] == true) return null;
    return (answer['text'] as String, answer['pages'] as int);
  }

  /// A PDF opened for rendering page by page. Close it when done.
  static Future<PdfPageSource> open(String path) async {
    final port = host;
    if (port == null) {
      if (!await PdfiumSetup.ensure()) throw StateError('PDFium yüklenemedi.');
      return _LocalSource(await PdfDocument.openFile(path));
    }
    final answer = await _ask(port, {'op': 'open', 'path': path});
    return _RemoteSource(port, answer['id'] as int, [
      for (final size in answer['sizes'] as List)
        ((size as List)[0] as double, size[1] as double),
    ]);
  }

  static Future<Map> _ask(SendPort port, Map<String, Object?> request) async {
    final reply = ReceivePort();
    try {
      port.send({...request, 'reply': reply.sendPort});
      final answer = await reply.first as Map;
      if (answer['error'] case final String error) throw StateError(error);
      return answer;
    } finally {
      reply.close();
    }
  }

  static Future<(String, int)?> _text(String path, int maxCharacters) async {
    if (!await PdfiumSetup.ensure()) return null;
    final document = await PdfDocument.openFile(path);
    try {
      final out = StringBuffer();
      for (final page in document.pages) {
        final text = (await page.loadText())?.fullText ?? '';
        if (text.isNotEmpty) out.writeln(text);
        if (out.length > maxCharacters) break;
      }
      return (out.toString(), document.pages.length);
    } finally {
      await document.dispose();
    }
  }
}

/// A page drawn white-backed at a given pixel size, as BGRA.
typedef PdfPagePixels = ({Uint8List bgra, int width, int height});

abstract class PdfPageSource {
  /// Page sizes in points.
  List<(double, double)> get sizes;

  /// The whole page scaled to [width] × [height] pixels; null when PDFium
  /// could not draw it.
  Future<PdfPagePixels?> render(int page, int width, int height);

  Future<void> close();
}

Future<PdfPagePixels?> _render(
  PdfDocument document,
  int page,
  int width,
  int height,
) async {
  // fullWidth/fullHeight are what scale the page; width/height alone only
  // size the output buffer, so without them the page is drawn at its natural
  // 72 dpi into the corner of a large white canvas.
  final rendered = await document.pages[page].render(
    width: width,
    height: height,
    fullWidth: width.toDouble(),
    fullHeight: height.toDouble(),
    backgroundColor: 0xFFFFFFFF,
  );
  if (rendered == null) return null;
  // PDFium's buffer is plain malloc with no finalizer: copied out and freed
  // here, or it is never freed at all.
  try {
    return (
      bgra: Uint8List.fromList(rendered.pixels),
      width: rendered.width,
      height: rendered.height,
    );
  } finally {
    rendered.dispose();
  }
}

class _LocalSource implements PdfPageSource {
  _LocalSource(this._document);

  final PdfDocument _document;

  @override
  List<(double, double)> get sizes => [
    for (final page in _document.pages) (page.width, page.height),
  ];

  @override
  Future<PdfPagePixels?> render(int page, int width, int height) =>
      _render(_document, page, width, height);

  @override
  Future<void> close() => _document.dispose();
}

class _RemoteSource implements PdfPageSource {
  _RemoteSource(this._port, this._id, this.sizes);

  final SendPort _port;
  final int _id;

  @override
  final List<(double, double)> sizes;

  @override
  Future<PdfPagePixels?> render(int page, int width, int height) async {
    final answer = await PdfPages._ask(_port, {
      'op': 'render',
      'id': _id,
      'page': page,
      'width': width,
      'height': height,
    });
    final data = answer['bgra'];
    if (data is! TransferableTypedData) return null;
    return (
      bgra: data.materialize().asUint8List(),
      width: answer['width'] as int,
      height: answer['height'] as int,
    );
  }

  @override
  Future<void> close() async => _port.send({'op': 'close', 'id': _id});
}

/// Runs in the isolate that owns PDFium and answers [PdfPages] for the
/// others. pdfrx does the work on its own worker isolate, so this isolate
/// only passes messages on and the interface does not stall.
abstract final class PdfPagesHost {
  static SendPort? _port;
  static final _documents = <int, PdfDocument>{};
  static final _idle = <int, Timer>{};
  static var _next = 0;

  /// A document its reader stopped asking about — the isolate reading it
  /// was killed on a timeout — is closed after this long.
  static const _forgotten = Duration(minutes: 2);

  /// Starts answering, once, and returns the port to hand to other isolates.
  static SendPort start() {
    if (_port != null) return _port!;
    final receive = ReceivePort();
    receive.listen((message) => _handle(message as Map));
    return _port = receive.sendPort;
  }

  static Future<void> _handle(Map request) async {
    final reply = request['reply'] as SendPort?;
    try {
      switch (request['op']) {
        case 'text':
          final read = await PdfPages._text(
            request['path'] as String,
            request['max'] as int,
          );
          reply?.send(
            read == null
                ? {'unavailable': true}
                : {'text': read.$1, 'pages': read.$2},
          );
        case 'open':
          if (!await PdfiumSetup.ensure()) {
            throw StateError('PDFium yüklenemedi.');
          }
          final document = await PdfDocument.openFile(
            request['path'] as String,
          );
          final id = _next++;
          _documents[id] = document;
          _touch(id);
          reply?.send({
            'id': id,
            'sizes': [
              for (final page in document.pages) [page.width, page.height],
            ],
          });
        case 'render':
          final id = request['id'] as int;
          final document = _documents[id];
          if (document == null) throw StateError('Belge kapatılmış.');
          _touch(id);
          final pixels = await _render(
            document,
            request['page'] as int,
            request['width'] as int,
            request['height'] as int,
          );
          reply?.send(
            pixels == null
                ? {'bgra': null}
                : {
                    'bgra': TransferableTypedData.fromList([pixels.bgra]),
                    'width': pixels.width,
                    'height': pixels.height,
                  },
          );
        case 'close':
          await _close(request['id'] as int);
      }
    } catch (error) {
      reply?.send({'error': '$error'});
    }
  }

  static void _touch(int id) {
    _idle.remove(id)?.cancel();
    _idle[id] = Timer(_forgotten, () => _close(id));
  }

  static Future<void> _close(int id) async {
    _idle.remove(id)?.cancel();
    await _documents.remove(id)?.dispose();
  }
}
