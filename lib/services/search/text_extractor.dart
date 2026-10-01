import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/document_model.dart';
import '../../models/evrak_file.dart';
import '../docx/docx_bridge.dart';
import '../spreadsheet/xlsx_workbook.dart';
import '../preview/structured_reader.dart';
import '../ocr/ocr_service.dart';
import '../pdf/pdf_pages.dart';
import '../doc/doc_reader.dart';
import '../rtf/rtf_reader.dart';
import '../udf/udf_reader.dart';

class IndexTextExtractor {
  static const maxFileBytes = 64 * 1024 * 1024;
  static const maxTextCharacters = 32 * 1024 * 1024;

  static Future<Map<String, Object?>> extract(
    String path, {
    bool ocr = false,
  }) async {
    try {
      final file = File(path);
      final format = EvrakFormat.fromExtension(path.split('.').last);
      if (format.isVisual) {
        if (ocr && await file.length() <= maxFileBytes) {
          final read = await OcrService.recognize(path, format);
          if (read != null && read.isNotEmpty) {
            return {
              'text': read,
              'state': 'ready',
              'ocr': true,
              'note': 'Metin görselden okundu (OCR); tanıma hataları olabilir.',
            };
          }
        }
        return {
          'text': '',
          'state': 'image',
          'note': ocr
              ? 'Görselde okunabilir yazı bulunamadı. Dosya adı aranabilir.'
              : 'Görselin dosya adı aranabilir. Görselden metin okuma (OCR) uygulanmadı.',
        };
      }
      if (await file.length() > maxFileBytes) {
        return {
          'text': '',
          // This is an intentional resource limit, not a damaged document.
          // Keep it in the "name only" count instead of alarming the user as
          // an extraction failure on every status screen.
          'state': 'too_large',
          'note': '64 MB üzerindeki dosyalarda yalnız dosya adı aranabilir.',
        };
      }
      final bytes = await file.readAsBytes();
      String text;
      int? pdfPageCount;
      switch (format) {
        case EvrakFormat.spreadsheet:
          text = XlsxWorkbook.read(bytes).text();
        case EvrakFormat.udf:
          final model = UdfReader.readBytes(bytes);
          if (model == null) throw const FormatException('UDF okunamadı.');
          text = _modelText(model);
        case EvrakFormat.docx:
          final model = await DocxBridge.readBytes(bytes);
          if (model == null) throw const FormatException('DOCX okunamadı.');
          text = _modelText(model);
        case EvrakFormat.rtf:
          final model = RtfReader.readBytes(bytes);
          if (model == null) throw const FormatException('RTF okunamadı.');
          text = _modelText(model);
        case EvrakFormat.doc:
          final model = RtfReader.looksLikeRtf(bytes)
              ? RtfReader.readBytes(bytes)
              : DocReader.readBytes(bytes);
          if (model == null) throw const FormatException('DOC okunamadı.');
          text = _modelText(model);
        case EvrakFormat.odt:
        case EvrakFormat.html:
        case EvrakFormat.markdown:
          text = _modelText(
            StructuredReader.read((bytes: bytes, format: format)),
          );
        case EvrakFormat.pdf:
          final read = await _pdfiumText(path);
          if (read == null) throw StateError('PDFium yüklenemedi.');
          (text, pdfPageCount) = read;
        case EvrakFormat.text:
        case EvrakFormat.data:
          text = decodeText(bytes);
        default:
          return {
            'text': '',
            'state': 'image',
            'note': 'Yalnız dosya adı aranabilir.',
          };
      }
      text = text.replaceAll('\u0000', '').trim();
      // A PDF with no text layer is a scan. This is the case OCR exists for, so
      // try it before recording the document as unsearchable.
      if (text.isEmpty && ocr && format == EvrakFormat.pdf) {
        final read = await OcrService.recognize(path, format);
        if (read != null && read.isNotEmpty) {
          final limited = (pdfPageCount ?? 0) > OcrService.maxPages;
          return {
            'text': read.length > maxTextCharacters
                ? read.substring(0, maxTextCharacters)
                : read,
            'state': limited ? 'partial' : 'ready',
            'ocr': true,
            'note': limited
                ? 'İlk ${OcrService.maxPages} sayfa OCR ile okundu; kalan '
                      'sayfalar kaynak PDF\'de korunur.'
                : 'Metin taranmış sayfalardan okundu (OCR); tanıma '
                      'hataları olabilir.',
          };
        }
      }
      final truncated = text.length > maxTextCharacters;
      return {
        'text': truncated ? text.substring(0, maxTextCharacters) : text,
        'state': truncated
            ? 'partial'
            : text.isEmpty
            ? 'no_text'
            : 'ready',
        'note': truncated
            ? 'İlk 32 milyon karakter indekslendi; kalan içerik kaynak belgede korunur.'
            : text.isEmpty
            ? (ocr
                  ? 'Taranmış sayfalarda okunabilir yazı bulunamadı.'
                  : 'Okunabilir metin bulunamadı. Taranmış belgeler için OCR gerekir.')
            : null,
      };
    } catch (error) {
      return {'text': '', 'state': 'error', 'note': _errorNote(error)};
    }
  }

  /// A PDF's text through PDFium, a page at a time, read by the isolate that
  /// owns PDFium (see [PdfPages]). Null only when PDFium cannot be loaded at
  /// all; a document it cannot open is an error like any other, not a reason
  /// to try another reader.
  ///
  /// Syncfusion, which read PDFs before, held a 637-page, 20 MB indictment
  /// in memory to the tune of more than 6 GB within half a minute — 26 GB
  /// before the kernel stopped it — and the indexing isolate did that in the
  /// background until its time ran out. PDFium read the same file in 1.7 s
  /// at 184 MB. It reads better too: of 311 PDFs with a text layer in the
  /// archive, Syncfusion wrote glyph names in place of Turkish letters in 93
  /// ("oldugbreveu" for "olduğu", "boscedillaanma" for "boşanma"), words no
  /// search can find, and PDFium in none.
  static Future<(String, int)?> _pdfiumText(String path) =>
      PdfPages.text(path, maxTextCharacters);

  /// Files kept online-only by OneDrive or a similar provider fail with a cloud
  /// error code instead of a missing file. Name the cause so the archive does
  /// not read as a damaged document.
  static String _errorNote(Object error) {
    if (error is FileSystemException && Platform.isWindows) {
      // ERROR_CLOUD_FILE_* occupy 362-395; 362 is PROVIDER_NOT_RUNNING, which
      // is what an unhydrated OneDrive placeholder reports.
      final code = error.osError?.errorCode ?? 0;
      if (code >= 362 && code <= 395) {
        return 'Dosya çevrimdışı saklanıyor; içeriği okunamadı. '
            'Cihaza indirdikten sonra Ayarlar → İndeks durumu → Yeniden tara.';
      }
    }
    return 'İçerik okunamadı: $error';
  }

  static String _modelText(DocModel model) => [
    model.toPlainText(),
    for (final region in model.pageRegions.values)
      DocModel(blocks: region).toPlainText(),
  ].where((s) => s.isNotEmpty).join('\n');

  static String decodeText(Uint8List bytes) {
    if (bytes.length >= 2 &&
        ((bytes[0] == 255 && bytes[1] == 254) ||
            (bytes[0] == 254 && bytes[1] == 255))) {
      final little = bytes[0] == 255;
      if (bytes.length.isOdd) {
        throw const FormatException('Eksik UTF-16 metni.');
      }
      final data = ByteData.sublistView(bytes);
      return String.fromCharCodes([
        for (var i = 2; i < bytes.length; i += 2)
          data.getUint16(i, little ? Endian.little : Endian.big),
      ]);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      const replacements = {
        0xd0: 0x011e,
        0xdd: 0x0130,
        0xde: 0x015e,
        0xf0: 0x011f,
        0xfd: 0x0131,
        0xfe: 0x015f,
      };
      return String.fromCharCodes(bytes.map((b) => replacements[b] ?? b));
    }
  }
}
