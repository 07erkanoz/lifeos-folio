import 'dart:isolate';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/evrak_file.dart';
import '../search/library_controller.dart';
import 'ocr_service.dart';
import '../pdf/pdf_pages.dart';

/// Text OCR can offer for the document on screen.
///
/// Two ways in. A document in the archive already has its text indexed, so it
/// appears instantly. A document opened from the desktop is not in the archive
/// at all — Folio is a viewer as much as an archive — and for that the reader
/// asks for it and waits. Reading on demand does not touch the index: nothing
/// is added to the archive just because it was looked at.
class PreviewOcr extends ChangeNotifier {
  final LibraryController? library;
  PreviewOcr({this.library});

  String? _text;
  bool _running = false;
  bool _attempted = false;
  bool _supported = false;
  String? _error;
  String? _path;

  /// Swiping through a folder of photographs replaces this viewer faster than
  /// the archive can answer, so an answer can arrive after it is gone.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String? get text => _text;
  bool get running => _running;
  String? get error => _error;

  /// Whether reading this document on demand is worth offering: the format can
  /// carry text in a picture, the tool is present, and there is no text yet.
  bool get canRun => _supported && !_running && _text == null;

  /// True once a run finished and found nothing, so the button can say so
  /// instead of looking like it did nothing.
  bool get foundNothing => _attempted && _text == null && !_running;

  /// Call when the viewer opens a document. Indexed text, if any, appears
  /// without work; otherwise the reader is offered a button.
  Future<void> attach(String? path, EvrakFormat format) async {
    if (path == _path) return;
    _path = path;
    _text = null;
    _error = null;
    _attempted = false;
    _running = false;
    _supported = false;
    _notify();
    if (path == null) return;

    final indexed = await library?.ocrText(path);
    if (_path != path) return;
    if (indexed != null) {
      _text = indexed;
      _notify();
      return;
    }
    // A normal indexed PDF already carries searchable/selectable text. OCR is
    // neither useful nor offered for it; only a scan should reach that path.
    final nativePdfText = format == EvrakFormat.pdf
        ? await library?.nativePdfText(path)
        : null;
    if (_path != path) return;
    if (nativePdfText != null) {
      _notify();
      return;
    }
    // Only offer what OCR can actually take on.
    _supported =
        (format.isVisual || format == EvrakFormat.pdf) &&
        format != EvrakFormat.svg &&
        await OcrService.available;
    if (_path == path) _notify();
  }

  /// Read the document now, with the accurate model: this is one document the
  /// reader asked for and is waiting on, so the seconds the archive pass cannot
  /// afford are well spent here. The work runs off the UI isolate — rasterising
  /// a page and converting it costs enough to drop frames.
  Future<void> run(EvrakFormat format) async {
    final path = _path;
    if (path == null || _running) return;
    _running = true;
    _error = null;
    _notify();
    try {
      final read = await recognizeNow(path, format);
      if (_path != path) return;
      _text = read;
    } catch (e) {
      if (_path != path) return;
      _error = 'Metin okunamadı: $e';
    } finally {
      if (_path == path) {
        _running = false;
        _attempted = true;
        _notify();
      }
    }
  }
}

/// Reads [path] by OCR now, with the accurate model, for a reader who asked
/// and is waiting. The work runs off the UI isolate — rasterising a page and
/// converting it costs enough to drop frames — and the pages are drawn by
/// the isolate that owns PDFium. [pdfPages] lifts the page limit of a PDF.
Future<String?> recognizeNow(
  String path,
  EvrakFormat format, {
  int? pdfPages,
}) => compute(_recognize, (
  path: path,
  format: format,
  pdfium: PdfPagesHost.start(),
  pdfPages: pdfPages,
));

Future<String?> _recognize(
  ({String path, EvrakFormat format, SendPort pdfium, int? pdfPages}) request,
) {
  PdfPages.host = request.pdfium;
  return OcrService.recognize(
    request.path,
    request.format,
    thorough: true,
    pdfPages: request.pdfPages,
  );
}
