import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../models/evrak_file.dart';
import '../pdf/pdf_pages.dart';
import '../pdf/pdfium_setup.dart';
import '../platform/native_tools.dart';
import 'grey_resize.dart';

/// Reads text out of scanned documents so they can be searched. One in five
/// documents in a typical archive has no text layer at all, and OCR is the only
/// thing that makes those findable.
///
/// Turkish text survives the round trip on both desktops: the bundled Windows
/// binary carries an activeCodePage=UTF-8 manifest so paths like
/// "Müvekkil Özlem" reach it intact, and Tesseract's own output is decoded as
/// UTF-8 rather than byte-per-character.
///
/// Everything runs locally: pages are rasterized with the PDFium already shipped
/// for previews and piped to Tesseract over stdin as TIFF, which Leptonica
/// reads from memory on every platform, so no fragment of a document is ever
/// written to a temporary file (see [toGrayTiff]).
class OcrService {
  /// Beyond this a scan is almost always a bulk archive rather than a document
  /// someone searches for a phrase in; OCRing all of it would cost minutes.
  static const maxPages = 20;

  /// 200 dpi reads body text reliably while keeping a page near 4 MB. Measured
  /// against a notarised document: 300 dpi scored slightly *worse* on phrases
  /// that must survive intact, so the usual "more dpi is better" advice does not
  /// hold for this material.
  ///
  /// The model is tessdata_fast rather than tessdata_best for the same kind of
  /// reason: best cuts junk fragments by about a third but takes 6.1 s a page
  /// against 3.4 s, which turns a 40-minute pass over an archive into 70.
  static const renderDpi = 200;

  static const _pageTimeout = Duration(seconds: 45);

  /// Above this many pages the accurate model stops being a good trade even for
  /// a document someone asked for. Measured on this archive: a page costs 3.3 s
  /// quick against 9.6 s accurate, so a twelve-page filing is the difference
  /// between forty seconds and two minutes of waiting. Scanned filings here run
  /// to seventy pages, where the accurate model would mean a twelve-minute wait
  /// for a reader watching a spinner.
  static const thoroughPageLimit = 4;

  /// Shortest side an image must have before OCR is worth starting. An archive
  /// folder can easily pick up an icon theme — thousands of assets, none of
  /// which can hold a word — and each would otherwise cost a process launch to
  /// read nothing.
  ///
  /// Measured against a real archive: the largest icon in a bundled GTK theme
  /// was 108 px on its short side, and the smallest genuine document image —
  /// a screenshot — was 270 px. Every WhatsApp photo of a document sat between
  /// 720 and 1868 px. The floor is set nearer the icons than the documents on
  /// purpose: wasting a process on an icon costs a second, missing a document
  /// makes it unsearchable and the user is never told.
  static const minSide = 150;

  /// Above this a file is a real image, not interface furniture, so the
  /// dimension check is skipped rather than reading the whole thing.
  static const _sizeCheckCeiling = 1024 * 1024;

  /// The quick model, used when reading a whole archive.
  static const language = 'tur';

  /// The accurate one, used when a reader asked for this document and is
  /// waiting. Measured on a notarised page: it keeps every phrase that must
  /// survive intact where the quick model loses one, at 6.0 s a page against
  /// 3.4 s. Fine for one document, not for hundreds.
  static const thoroughLanguage = 'tur_best';

  static bool? _available;
  static String? _binary;
  static String? _tessdata;
  static bool _hasThorough = false;

  /// Whether OCR can run at all. Cached: the answer cannot change while the
  /// app is open, and the check walks PATH.
  static Future<bool> get available async {
    if (_available != null) return _available!;
    _binary = await NativeTools.optional('tesseract');
    _tessdata = null;
    if (_binary != null) {
      // The bundled layout is tools/bin/tesseract next to tools/tessdata. Use
      // the model that shipped with the binary rather than whatever the host
      // happens to have installed, so recognition does not vary by machine.
      final beside = p.join(p.dirname(p.dirname(_binary!)), 'tessdata');
      if (await File(p.join(beside, '$language.traineddata')).exists()) {
        _tessdata = beside;
        _hasThorough = await File(
          p.join(beside, '$thoroughLanguage.traineddata'),
        ).exists();
      }
    }
    return _available = _binary != null;
  }

  static void resetForTest() {
    _available = null;
    _binary = null;
    _tessdata = null;
    _hasThorough = false;
  }

  /// Whether the accurate model shipped alongside. A system Tesseract will not
  /// have it, and the quick one is then used for everything.
  static Future<bool> get thoroughAvailable async {
    await available;
    return _hasThorough;
  }

  /// Text for [path], or null when OCR is unavailable or produced nothing.
  /// Images are handed to Tesseract directly — Leptonica decodes JPEG, PNG and
  /// TIFF itself — while PDFs are rendered page by page.
  /// [thorough] picks the accurate model. Use it when one document was asked
  /// for; leave it off when walking an archive, where the extra seconds a page
  /// turn into an extra half hour. A long scan overrides it either way: see
  /// [thoroughPageLimit].
  ///
  /// A PDF is read up to [maxPages] pages, or [pdfPages] when given: the
  /// archive pass keeps to the first, a reader who asked to edit a document
  /// needs all of it.
  static Future<String?> recognize(
    String path,
    EvrakFormat format, {
    bool thorough = false,
    int? pdfPages,
  }) async {
    if (!await available) return null;
    try {
      if (format.isVisual) {
        if (!await _worthReading(path, format)) return null;
        // A scanned filing is routinely one TIFF holding dozens of pages, and
        // Tesseract reads every one of them from a single invocation. Both the
        // model and the time budget have to be chosen for the whole document,
        // not for one page of it.
        final pages = format == EvrakFormat.tif
            ? await tiffPages(File(path))
            : 1;
        final language = _language(thorough && pages <= thoroughPageLimit);
        if (pages == 1) return await _image(path, language);
        final text = await _run(
          language,
          imagePath: path,
          budget: budgetFor(pages),
        );
        return text.trim().isEmpty ? null : text.trim();
      }
      if (format != EvrakFormat.pdf) return null;
      // The PDF path already reads a page at a time and stops at [maxPages],
      // so the accurate model stays affordable there.
      return await _pdf(path, _language(thorough), pdfPages ?? maxPages);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _language(bool thorough) =>
      thorough && _hasThorough ? thoroughLanguage : language;

  /// How long one Tesseract invocation may take. [_pageTimeout] is a budget for
  /// a single page, which is what the PDF path hands it; a multi-page image is
  /// one invocation covering every page, so it needs the sum. Capped at
  /// [maxPages] worth so a damaged directory chain claiming thousands of pages
  /// cannot leave a process running for a day.
  static Duration budgetFor(int pages) =>
      _pageTimeout * (pages < maxPages ? (pages < 1 ? 1 : pages) : maxPages);

  /// Pages in a TIFF, counted by walking the image directory chain instead of
  /// decoding. A scanned filing runs to tens of megabytes and seventy pages,
  /// and OCR only needs the count to size its budget, so reading a few bytes
  /// per page beats pulling the whole file through a decoder.
  static Future<int> tiffPages(File file) async {
    RandomAccessFile? handle;
    try {
      final length = await file.length();
      handle = await file.open();
      final header = await handle.read(8);
      if (header.length < 8) return 1;
      final little = header[0] == 0x49 && header[1] == 0x49;
      if (!little && !(header[0] == 0x4D && header[1] == 0x4D)) return 1;
      final endian = little ? Endian.little : Endian.big;
      final head = ByteData.sublistView(header);
      // 42 is TIFF. BigTIFF (43) lays its offsets out differently; reporting a
      // single page there only means the budget is the old one, not a failure.
      if (head.getUint16(2, endian) != 42) return 1;
      var offset = head.getUint32(4, endian);
      var pages = 0;
      while (offset > 0 && offset + 2 <= length && pages <= maxPages) {
        await handle.setPosition(offset);
        final count = await handle.read(2);
        if (count.length < 2) break;
        final entries = ByteData.sublistView(count).getUint16(0, endian);
        final next = offset + 2 + entries * 12;
        if (next + 4 > length) break;
        await handle.setPosition(next);
        final link = await handle.read(4);
        if (link.length < 4) break;
        offset = ByteData.sublistView(link).getUint32(0, endian);
        pages++;
      }
      return pages < 1 ? 1 : pages;
    } catch (_) {
      return 1;
    } finally {
      await handle?.close();
    }
  }

  /// Whether starting Tesseract on this image can pay off. Cheap on purpose:
  /// a folder of interface assets must not cost a process launch per file.
  static Future<bool> _worthReading(String path, EvrakFormat format) async {
    // Leptonica decodes JPEG, PNG, TIFF and friends, but not SVG. Handing one
    // over just spawns a process that fails.
    if (format == EvrakFormat.svg) return false;
    try {
      final file = File(path);
      if (await file.length() >= _sizeCheckCeiling) return true;
      final bytes = await file.readAsBytes();
      // Header only: startDecode reports the size without decoding pixels.
      final info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info == null) return true; // Unknown format; let Tesseract judge.
      return info.width >= minSide && info.height >= minSide;
    } catch (_) {
      return true;
    }
  }

  /// Tesseract's word-by-word output with confidences, asked for by its
  /// variables rather than the `tsv` config file: the tessdata shipped with
  /// Folio holds the models only, and without the file Tesseract says
  /// "Can't open tsv" and writes plain text, which read as no words at all.
  @visibleForTesting
  static const tsv = [
    '-c',
    'tessedit_create_tsv=1',
    '-c',
    'tessedit_create_txt=0',
  ];

  /// A single picture: a photographed page, a screenshot, a one-page scan.
  /// Read as it is first; read badly, it is enlarged so its capitals come
  /// near 30 px and read again with Sauvola, and the better reading kept.
  ///
  /// Measured on 30 real pictures (20 document photos and scans, 10
  /// screenshots): 2075 confident words read as they are, 2609 this way, and
  /// none fewer on any picture. Screenshots gain most: their interface text is
  /// 9 to 11 px, and one went from 144 confident words to 352.
  static Future<String?> _image(String path, String language) async {
    var page = OcrPageRead.fromTsv(
      await _run(language, imagePath: path, options: tsv),
    );
    if (page.unsure) {
      final enlarged = await _scaledGray(path, page.enlargement(0.5, 2.5));
      if (enlarged != null) {
        final second = OcrPageRead.fromTsv(
          await _run(
            language,
            input: enlarged,
            // A picture has no page to measure a resolution against; 300 is
            // what the measurement above used for the enlarged copy.
            options: const [
              '--dpi',
              '300',
              '-c',
              'thresholding_method=2',
              ...tsv,
            ],
          ),
        );
        if (second.good > page.good) page = second;
      }
    }
    return page.text.isEmpty ? null : page.text;
  }

  /// Largest enlarged picture, in pixels: past this a phone photo scaled
  /// up would need hundreds of megabytes to hold.
  static const _maxEnlargedPixels = 40000000;

  /// [path] in grey, scaled by [scale], as an uncompressed TIFF; null when
  /// the picture cannot be decoded here.
  static Future<Uint8List?> _scaledGray(String path, double scale) async {
    final decoded = img.decodeImage(await File(path).readAsBytes());
    if (decoded == null) return null;
    var factor = scale;
    final area = decoded.width * decoded.height * factor * factor;
    if (area > _maxEnlargedPixels) {
      factor *= math.sqrt(_maxEnlargedPixels / area);
    }
    final luma = Uint8List(decoded.width * decoded.height);
    var i = 0;
    // Normalised, so a 16-bit or palette PNG comes out as the same greys.
    for (final pixel in decoded) {
      luma[i++] = (pixel.luminanceNormalized * 255).round().clamp(0, 255);
    }
    if (factor == 1) return grayTiff(luma, decoded.width, decoded.height);
    final width = (decoded.width * factor).round();
    final height = (decoded.height * factor).round();
    return grayTiff(
      resizeGrey(luma, decoded.width, decoded.height, width, height),
      width,
      height,
    );
  }

  static Future<String?> _pdf(String path, String language, int limit) async {
    // Pages are drawn by the isolate that owns PDFium (see [PdfPages]); this
    // one may be the indexer's, which must not load PDFium itself.
    final document = await PdfPages.open(path);
    try {
      final buffer = StringBuffer();
      final sizes = document.sizes;
      final count = sizes.length < limit ? sizes.length : limit;
      for (var i = 0; i < count; i++) {
        final (pageWidth, pageHeight) = sizes[i];
        Future<OcrPageRead?> read(int dpi, List<String> options) async {
          final width = (pageWidth * dpi / 72).round();
          final height = (pageHeight * dpi / 72).round();
          if (width <= 0 || height <= 0) return null;
          final rendered = await document.render(i, width, height);
          if (rendered == null) return null;
          final image = toGrayTiff(
            rendered.bgra,
            rendered.width,
            rendered.height,
          );
          return OcrPageRead.fromTsv(
            await _run(
              language,
              input: image,
              options: ['--dpi', '$dpi', ...options, ...tsv],
            ),
          );
        }

        var page = await read(renderDpi, const []);
        if (page == null) continue;
        // A page read badly is read once more the way Tesseract's own
        // guidance asks for: drawn so its capitals are about 30 px tall, and
        // binarised by Sauvola, which copes with the uneven background the
        // default Otsu does not. The better reading is kept, so this never
        // makes a page worse; see [OcrPageRead.retryDpi].
        final retry = page.retryDpi(renderDpi);
        if (retry != null) {
          final second = await read(retry, const [
            '-c',
            'thresholding_method=2',
          ]);
          if (second != null && second.good > page.good) page = second;
        }
        if (page.text.isNotEmpty) buffer.writeln(page.text);
      }
      final text = buffer.toString().trim();
      return text.isEmpty ? null : text;
    } finally {
      await document.close();
    }
  }

  /// An uncompressed 8-bit grayscale TIFF. Tesseract works on luminance
  /// anyway, so converting here sends a third of the bytes of RGB and skips
  /// any image encoder: the header is written by hand.
  ///
  /// TIFF rather than the simpler PGM because of how Leptonica reads from
  /// memory. A PNM goes through fopenReadFromMemory, which on Windows — where
  /// MinGW has no fmemopen — writes the page to a file in %TEMP% and reads it
  /// back: every page of a client's scan passed through the disk and past the
  /// virus scanner. A TIFF is read through Leptonica's own memory stream
  /// (TIFFClientOpen) on every platform. No resolution is written; the page's
  /// DPI is passed to Tesseract with `--dpi` instead, which it otherwise has to
  /// guess from the text, and which its binarisation windows are sized by.
  ///
  /// PDFium hands back BGRA, not RGBA: reading it the other way round swaps the
  /// red and blue weights and shifts the luminance of anything coloured, such
  /// as a notary's blue stamp over black text.
  static Uint8List toGrayTiff(Uint8List bgra, int width, int height) {
    final luma = Uint8List(width * height);
    var w = 0;
    for (var i = 0; i + 3 < bgra.length && w < luma.length; i += 4) {
      // Rec. 601 luma, integer arithmetic: keeps antialiased glyph edges that a
      // plain channel average would smear.
      luma[w++] = (bgra[i + 2] * 77 + bgra[i + 1] * 150 + bgra[i] * 29) >> 8;
    }
    return grayTiff(luma, width, height);
  }

  /// [luma], one byte a pixel, as an uncompressed 8-bit grey TIFF.
  static Uint8List grayTiff(Uint8List luma, int width, int height) {
    const entries = 9;
    const pixelsAt = 8 + 2 + entries * 12 + 4;
    final out = Uint8List(pixelsAt + width * height);
    final header = ByteData.sublistView(out);
    // "II", 42, first directory right after the header.
    header
      ..setUint8(0, 0x49)
      ..setUint8(1, 0x49)
      ..setUint16(2, 42, Endian.little)
      ..setUint32(4, 8, Endian.little)
      ..setUint16(8, entries, Endian.little);
    var at = 10;
    void entry(int tag, int type, int value) {
      header
        ..setUint16(at, tag, Endian.little)
        ..setUint16(at + 2, type, Endian.little)
        ..setUint32(at + 4, 1, Endian.little);
      // SHORT values sit in the first two bytes of the value field.
      if (type == 3) {
        header.setUint16(at + 8, value, Endian.little);
      } else {
        header.setUint32(at + 8, value, Endian.little);
      }
      at += 12;
    }

    const short = 3, long = 4;
    // In ascending tag order, as TIFF requires.
    entry(256, long, width); // ImageWidth
    entry(257, long, height); // ImageLength
    entry(258, short, 8); // BitsPerSample
    entry(259, short, 1); // Compression: none
    entry(262, short, 1); // PhotometricInterpretation: black is zero
    entry(273, long, pixelsAt); // StripOffsets
    entry(277, short, 1); // SamplesPerPixel
    entry(278, long, height); // RowsPerStrip: the whole page in one strip
    entry(279, long, width * height); // StripByteCounts
    header.setUint32(at, 0, Endian.little); // no further directory
    out.setRange(pixelsAt, pixelsAt + luma.length, luma);
    return out;
  }

  static Future<String> _run(
    String language, {
    String? imagePath,
    Uint8List? input,
    Duration budget = _pageTimeout,
    List<String> options = const [],
  }) async {
    final process = await Process.start(
      _binary!,
      [imagePath ?? '-', '-', '-l', language, '--psm', '3', ...options],
      // Only set when a model shipped beside the binary; a system Tesseract is
      // left to find its own, which is what a user who installed it expects.
      environment: _tessdata == null ? null : {'TESSDATA_PREFIX': _tessdata!},
    );
    final stdoutFuture = process.stdout.fold<List<int>>(
      <int>[],
      (a, b) => a..addAll(b),
    );
    // Draining stderr matters: Tesseract is chatty about page layout and a full
    // pipe buffer would deadlock the process.
    final stderrFuture = process.stderr.drain<void>();
    if (input != null) {
      process.stdin.add(input);
    }
    unawaited(process.stdin.close().catchError((Object _) {}));
    try {
      final bytes = await stdoutFuture.timeout(budget);
      await stderrFuture;
      await process.exitCode.timeout(budget);
      // Tesseract writes UTF-8. Reading it byte-per-character would turn every
      // Turkish letter into mojibake — 'İ' is two bytes and would arrive as 'Ä°'
      // — which then goes into the search index that way.
      return utf8.decode(bytes, allowMalformed: true);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      rethrow;
    }
  }

  /// Test hook, kept where the OCR tests look for it: see
  /// [PdfiumSetup.pathOverride].
  static String? get pdfiumPathOverride => PdfiumSetup.pathOverride;
  static set pdfiumPathOverride(String? path) =>
      PdfiumSetup.pathOverride = path;
}

/// One page as Tesseract read it, from its TSV output: the text, and how sure
/// Tesseract was of it.
///
/// Measured on 30 scanned pages without a text layer (29 September 2026), the
/// numbers below pick the pages worth a second reading: 8 of the 30, of which
/// none came out worse and a small-print traffic report went from 21 words
/// read with confidence to 152. Applied to every page instead, the same
/// second reading lost words on three.
@visibleForTesting
class OcrPageRead {
  const OcrPageRead({
    required this.text,
    required this.good,
    required this.confidence,
    required this.wordHeight,
    required this.words,
  });

  final String text;

  /// Words read with at least 85% confidence, three letters or more: the
  /// measure the choices here were made by.
  final int good;

  /// Mean confidence over every word, 0–100.
  final double confidence;

  /// Median height of the confidently read words' boxes, in pixels; 0 when
  /// there were none.
  final double wordHeight;
  final int words;

  /// Below this mean confidence a page is read again.
  static const confident = 85.0;

  /// Word boxes shorter than this (at the render DPI) are small print, which
  /// Tesseract reads best enlarged.
  static const smallPrint = 18.0;

  /// A word box is about 1.35 times a capital's height; Tesseract reads best
  /// with capitals near 30 px.
  static const targetWordHeight = 30 * 1.35;

  /// The DPI to read this page again at, or null when once was enough. A page
  /// with no words at all is blank, not badly read.
  int? retryDpi(int dpi) {
    if (!unsure) return null;
    // Kept to 150–400: past 400 an A4 page is over 60 MB to draw, and the
    // small-print page above read best at 300.
    return (dpi * enlargement(0, double.infinity)).round().clamp(150, 400);
  }

  /// Whether the page is worth a second reading: read with little confidence,
  /// or in small print. A page with no words at all is blank, not badly read.
  bool get unsure =>
      words > 0 &&
      (confidence < confident || (wordHeight > 0 && wordHeight < smallPrint));

  /// How much to enlarge the page for its words to reach [targetWordHeight],
  /// kept between [min] and [max]; 1 when no word was read confidently.
  double enlargement(double min, double max) =>
      wordHeight == 0 ? 1 : (targetWordHeight / wordHeight).clamp(min, max);

  factory OcrPageRead.fromTsv(String tsv) {
    final text = StringBuffer();
    final heights = <int>[];
    var good = 0, words = 0;
    var total = 0.0;
    String? paragraph, line;
    for (final row in const LineSplitter().convert(tsv).skip(1)) {
      final cells = row.split('\t');
      if (cells.length < 12 || cells[0] != '5') continue;
      final word = cells.sublist(11).join('\t').trim();
      final conf = double.tryParse(cells[10]) ?? -1;
      if (word.isEmpty || conf < 0) continue;
      final here = '${cells[2]}/${cells[3]}';
      final at = '$here/${cells[4]}';
      if (line == null) {
        text.write(word);
      } else if (at != line) {
        // Tesseract's own text output: a line a row, a paragraph apart.
        text.write(here == paragraph ? '\n' : '\n\n');
        text.write(word);
      } else {
        text.write(' $word');
      }
      paragraph = here;
      line = at;
      words++;
      total += conf;
      if (conf >= 85 &&
          word.runes.length >= 3 &&
          word.runes.any(
            (r) =>
                String.fromCharCode(r).toLowerCase() !=
                String.fromCharCode(r).toUpperCase(),
          )) {
        good++;
        heights.add(int.tryParse(cells[9]) ?? 0);
      }
    }
    heights.sort();
    return OcrPageRead(
      text: text.toString().trim(),
      good: good,
      confidence: words == 0 ? 0 : total / words,
      wordHeight: heights.isEmpty ? 0 : heights[heights.length ~/ 2].toDouble(),
      words: words,
    );
  }
}
