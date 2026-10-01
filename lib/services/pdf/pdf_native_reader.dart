import 'dart:ffi';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as native;
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../../models/document_model.dart';
import 'pdfium_setup.dart';

/// A PDF with no text to take: scanned, or with its letters saved as
/// shapes — what "Microsoft Print to PDF" makes of a page UYAP's editor
/// prints. It looks like text on screen, since PDFium draws the shapes, but
/// holds no characters. Only reading its pages as pictures (OCR) gets text.
class PdfWithoutText extends FormatException {
  const PdfWithoutText()
    : super(
        'PDF metin katmanı içermiyor; metne dönüştürmek için OCR gerekiyor.',
      );
}

/// Text and formatting come from the same PDFium character indices. Matching
/// strings from two PDF engines loses whole styled lines on legacy encodings.
abstract final class PdfNativeReader {
  static Future<DocModel> read(Uint8List bytes) async {
    if (!await PdfiumSetup.ensure()) throw StateError('PDFium yüklenemedi.');
    final document = await PdfDocument.openData(bytes);
    try {
      final module = Pdfrx.pdfiumModulePath;
      final address = await document.useNativeDocumentHandle(
        (address) => address,
      );
      // Read on pdfrx's own PDFium isolate, not on one of ours. PDFium calls
      // back into Dart — to read a document over 1 MB, which pdfrx opens
      // through a read callback, and to map fonts a PDF does not embed — and
      // those callbacks belong to that isolate. Called from any other, the
      // VM aborts the whole process ("Cannot invoke native callback from a
      // different isolate"): converting or editing any PDF over 1 MB closed
      // the app. The worker also queues this behind its other PDFium work,
      // which PDFium, not being thread-safe, needs.
      final model = await PdfrxEntryFunctions.instance.compute(_extract, (
        address: address,
        module: module,
      ));
      if (model == null) throw const PdfWithoutText();
      return model;
    } finally {
      await document.dispose();
    }
  }

  /// Null when the PDF has no text layer. Thrown here, the exception would
  /// cross back from the worker isolate without its type.
  static DocModel? _extract(({int address, String? module}) request) {
    final api = native.getPdfium(modulePath: request.module);
    final document = Pointer<native.fpdf_document_t__>.fromAddress(
      request.address,
    );
    final blocks = <DocBlock>[];
    final name = calloc<Uint8>(1024);
    final flags = calloc<Int>();
    final colors = calloc<UnsignedInt>(4);
    final box = calloc<Double>(4);
    DocPageProperties? properties;
    try {
      for (
        var pageIndex = 0;
        pageIndex < api.FPDF_GetPageCount(document);
        pageIndex++
      ) {
        final page = api.FPDF_LoadPage(document, pageIndex);
        if (page == nullptr) continue;
        final textPage = api.FPDFText_LoadPage(page);
        try {
          if (textPage == nullptr) continue;
          final width = api.FPDF_GetPageWidth(page);
          final height = api.FPDF_GetPageHeight(page);
          final lines = <_Line>[];
          var line = _Line();
          void flush() {
            if (line.text.toString().trim().isNotEmpty) lines.add(line);
            line = _Line();
          }

          for (var i = 0; i < api.FPDFText_CountChars(textPage); i++) {
            final code = api.FPDFText_GetUnicode(textPage, i);
            if (code == 13 || code == 10) {
              flush();
              continue;
            }
            if (code == 0) continue;
            final character = String.fromCharCode(code);
            if (character.trim().isEmpty) {
              line.add(character, line.lastFace);
              continue;
            }
            final hasBox =
                api.FPDFText_GetCharBox(
                  textPage,
                  i,
                  box,
                  box + 1,
                  box + 2,
                  box + 3,
                ) !=
                0;
            final size = api.FPDFText_GetFontSize(textPage, i);
            flags.value = 0;
            final length = api.FPDFText_GetFontInfo(
              textPage,
              i,
              name.cast(),
              1024,
              flags,
            );
            final rawName = length > 0 && length <= 1024
                ? name.cast<Utf8>().toDartString()
                : 'Times New Roman';
            final family = _family(rawName);
            final hasColor =
                api.FPDFText_GetFillColor(
                  textPage,
                  i,
                  colors,
                  colors + 1,
                  colors + 2,
                  colors + 3,
                ) !=
                0;
            final color = hasColor
                ? '#${[colors[0], colors[1], colors[2]].map((c) => c.clamp(0, 255).toRadixString(16).padLeft(2, '0')).join()}'
                : null;
            final face = (
              family: family,
              size: size > 0 ? size : 12.0,
              bold:
                  api.FPDFText_GetFontWeight(textPage, i) >= 600 ||
                  rawName.toLowerCase().contains('bold') ||
                  flags.value & 0x40000 != 0,
              italic:
                  flags.value & 64 != 0 ||
                  RegExp(
                    'italic|oblique',
                    caseSensitive: false,
                  ).hasMatch(rawName),
              color: color,
            );
            if (hasBox) {
              // PDFium reports x-left/right and y-bottom/top in page space.
              if (line.right.isFinite && box[0] - line.right > size * 1.5) {
                line.add('\t', face);
                line.tabs.add(box[0]);
              }
              line.left = math.min(line.left, box[0]);
              line.right = math.max(line.right, box[1]);
              line.top = math.min(line.top, height - box[3]);
              line.bottom = math.max(line.bottom, height - box[2]);
            }
            line.add(character, face);
          }
          flush();
          if (lines.isEmpty) continue;
          final positioned = lines
              .where((l) => l.left.isFinite && l.right.isFinite)
              .toList();
          final left = positioned.isEmpty
              ? 42.525
              : positioned.map((l) => l.left).reduce(math.min);
          final right = positioned.isEmpty
              ? width - 42.525
              : positioned.map((l) => l.right).reduce(math.max);
          properties ??= DocPageProperties(
            marginLeft: left.clamp(0, width / 3),
            marginRight: (width - right).clamp(0, width / 3),
            landscape: width > height,
          );
          for (var i = 0; i < lines.length; i++) {
            final current = lines[i];
            final positioned = current.left.isFinite && current.right.isFinite;
            final indent = positioned
                ? math.max(0.0, current.left - left)
                : 0.0;
            final remaining = positioned ? right - current.right : 0.0;
            final centered =
                indent > 12 && remaining > 12 && (indent - remaining).abs() < 8;
            final alignedRight =
                !centered && indent > 12 && remaining.abs() < 5;
            final next = i + 1 < lines.length ? lines[i + 1] : null;
            final gap =
                next != null && next.top.isFinite && current.bottom.isFinite
                ? math.max(0.0, next.top - current.bottom - 3)
                : 0.0;
            blocks.add(
              DocBlock(
                plainText: current.text.toString(),
                spans: current.finish(),
                alignment: centered
                    ? DocAlignment.center
                    : alignedRight
                    ? DocAlignment.right
                    : DocAlignment.left,
                leftIndent: centered || alignedRight ? 0 : indent,
                spacingAfter: gap.clamp(0, 72),
                tabSet: current.tabs.isEmpty
                    ? null
                    : current.tabs
                          .map((x) => '${x - current.left}:0')
                          .join(','),
              ),
            );
          }
        } finally {
          if (textPage != nullptr) api.FPDFText_ClosePage(textPage);
          api.FPDF_ClosePage(page);
        }
      }
    } finally {
      calloc.free(name);
      calloc.free(flags);
      calloc.free(colors);
      calloc.free(box);
    }
    if (blocks.isEmpty) return null;
    return DocModel(
      blocks: blocks,
      pageProperties: properties ?? const DocPageProperties(),
    );
  }

  static String _family(String name) {
    final clean = name
        .replaceFirst(RegExp(r'^[A-Z]{6}\+'), '')
        .replaceFirst(
          RegExp(
            r'[-,](BoldItalic|BoldOblique|Bold|Italic|Oblique|Regular|Roman)(MT)?$',
            caseSensitive: false,
          ),
          '',
        );
    return switch (clean.toLowerCase().replaceAll(' ', '')) {
      'timesnewromanpsmt' ||
      'timesnewromanps' ||
      'timesnewroman' ||
      'times' => 'Times New Roman',
      'arialmt' || 'arial' => 'Arial',
      'couriernewpsmt' || 'couriernewps' || 'couriernew' => 'Courier New',
      'liberationserif' => 'Liberation Serif',
      'liberationsans' => 'Liberation Sans',
      'liberationmono' => 'Liberation Mono',
      _ => clean,
    };
  }
}

typedef _Face = ({
  String family,
  double size,
  bool bold,
  bool italic,
  String? color,
});

class _Line {
  final text = StringBuffer();
  final spans = <DocSpan>[];
  final tabs = <double>[];
  double left = double.infinity, top = double.infinity;
  double right = double.negativeInfinity, bottom = double.negativeInfinity;
  _Face? lastFace;
  int start = 0;
  void add(String value, _Face? face) {
    if (face != lastFace) {
      _flush();
      lastFace = face;
      start = text.length;
    }
    text.write(value);
  }

  void _flush() {
    final face = lastFace;
    if (face == null || text.length == start) return;
    spans.add(
      DocSpan(
        startOffset: start,
        length: text.length - start,
        fontFamily: face.family,
        fontSize: face.size,
        bold: face.bold,
        italic: face.italic,
        color: face.color,
      ),
    );
  }

  List<DocSpan> finish() {
    _flush();
    return spans;
  }
}
