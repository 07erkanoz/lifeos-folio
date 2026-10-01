import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/document_model.dart';
import '../../models/evrak_file.dart';
import '../docx/docx_bridge.dart';

import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

import '../pdf/pdf_service.dart';
import '../pdf/pdf_native_reader.dart';
import '../tiff/tiff_service.dart';
import '../doc/doc_reader.dart';
import '../rtf/rtf_reader.dart';
import '../rtf/rtf_writer.dart';
import '../udf/udf_reader.dart';
import '../udf/udf_writer.dart';
import '../preview/structured_reader.dart';

class ConverterResult {
  final bool success;
  final String? outputPath;
  final Uint8List? outputBytes;
  final String? errorMessage;

  const ConverterResult({
    required this.success,
    this.outputPath,
    this.outputBytes,
    this.errorMessage,
  });
}

class ConverterService {
  /// Opens a document from disk without first copying a potentially large PDF
  /// into the UI isolate. PDFium reads text and styling together on a worker;
  /// cached viewer text is only used if the original file is no longer present.
  static Future<DocModel?> extractFileDocModel(
    String path,
    EvrakFormat format, {
    String? extractedPdfText,
  }) async {
    if (format == EvrakFormat.pdf) {
      return _extractPdfFileModel(path, extractedPdfText);
    }
    return extractDocModel(await File(path).readAsBytes(), format);
  }

  /// Bir evrak dosyasını hedef formata dönüştürür.
  static Future<ConverterResult> convertFile({
    required String sourcePath,
    required EvrakFormat targetFormat,
    String? targetDirectory,
    String? customFileName,
  }) async {
    try {
      final file = File(sourcePath);
      if (!await file.exists()) {
        return const ConverterResult(
          success: false,
          errorMessage: 'Kaynak dosya bulunamadı.',
        );
      }
      final bytes = await file.readAsBytes();
      final baseName = p.basename(
        customFileName ?? p.basenameWithoutExtension(sourcePath),
      );

      final resultBytes = await convertBytes(
        bytes: bytes,
        sourceFormat: EvrakFormat.fromExtension(
          sourcePath.split('.').last.toLowerCase(),
        ),
        targetFormat: targetFormat,
        title: baseName,
      );

      if (resultBytes == null || resultBytes.isEmpty) {
        return const ConverterResult(
          success: false,
          errorMessage: 'Dönüştürme başarısız oldu.',
        );
      }

      final outDir = targetDirectory ?? file.parent.path;
      await Directory(outDir).create(recursive: true);
      final stem = p.join(outDir, '${baseName}_donusturuldu');
      var outPath = '$stem.${targetFormat.defaultExtension}';
      var suffix = 1;
      while (await FileSystemEntity.type(outPath) !=
          FileSystemEntityType.notFound) {
        outPath = '${stem}_${suffix++}.${targetFormat.defaultExtension}';
      }
      final outFile = File(outPath);
      await outFile.writeAsBytes(resultBytes, flush: true);

      return ConverterResult(
        success: true,
        outputPath: outPath,
        outputBytes: resultBytes,
      );
    } catch (e) {
      return ConverterResult(success: false, errorMessage: e.toString());
    }
  }

  /// Byte dizisi üzerinden format dönüşümü yapar.
  static Future<Uint8List?> convertBytes({
    required Uint8List bytes,
    required EvrakFormat sourceFormat,
    required EvrakFormat targetFormat,
    String? title,
  }) async {
    if (!sourceFormat.availableConversions.contains(targetFormat)) {
      throw UnsupportedError(
        '${sourceFormat.label} → ${targetFormat.label} dönüşümü desteklenmiyor.',
      );
    }
    if (sourceFormat == EvrakFormat.image &&
        [EvrakFormat.image, EvrakFormat.tif].contains(targetFormat)) {
      return compute(_convertImage, (bytes: bytes, target: targetFormat));
    }
    // 1. Özel Hızlı Yol: TIF -> PDF
    if (sourceFormat == EvrakFormat.tif && targetFormat == EvrakFormat.pdf) {
      return await TiffService.tiffToPdf(bytes);
    }

    // 2. Kaynak Dokümanı DocModel'e Çözümle
    DocModel? model = await extractDocModel(bytes, sourceFormat);

    if (model == null) throw const FormatException('Kaynak belge okunamadı.');

    // 3. Hedef Formata Serileştir
    switch (targetFormat) {
      case EvrakFormat.pdf:
        return await PdfService.modelToPdfBytes(model, title: title);

      case EvrakFormat.udf:
        return Uint8List.fromList(UdfWriter.writeBytes(model));

      case EvrakFormat.docx:
        return await DocxBridge.writeBytes(model);

      case EvrakFormat.rtf:
        return Uint8List.fromList(RtfWriter.writeBytes(model));

      case EvrakFormat.text:
        return Uint8List.fromList(utf8.encode(model.toPlainText()));

      default:
        return null;
    }
  }

  static Uint8List _convertImage(
    ({Uint8List bytes, EvrakFormat target}) request,
  ) {
    final image = img.decodeImage(request.bytes);
    if (image == null) throw const FormatException('Görsel okunamadı.');
    if (image.numFrames > 1) {
      throw const FormatException(
        'Çok kareli görseller için PDF seçin; PNG/TIFF yazıcısı bu kareleri koruyamaz.',
      );
    }
    if (image.isHdrFormat && request.target == EvrakFormat.tif) {
      throw const FormatException(
        'Yüksek bit derinlikli görsel TIFF yazıcısında korunamıyor.',
      );
    }
    if (request.target == EvrakFormat.tif) {
      return Uint8List.fromList(img.encodeTiff(image));
    }
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Herhangi bir formattan DocModel çıkarır.
  static Future<DocModel?> extractDocModel(
    Uint8List bytes,
    EvrakFormat format,
  ) async {
    switch (format) {
      case EvrakFormat.odt:
      case EvrakFormat.html:
      case EvrakFormat.markdown:
        return compute(StructuredReader.read, (bytes: bytes, format: format));
      case EvrakFormat.udf:
        return compute(UdfReader.readBytes, bytes);
      case EvrakFormat.rtf:
        return compute(RtfReader.readBytes, bytes);
      case EvrakFormat.doc:
        // Some programs save RTF under a .doc name; the bytes decide.
        return RtfReader.looksLikeRtf(bytes)
            ? compute(RtfReader.readBytes, bytes)
            : compute(DocReader.readBytes, bytes);

      case EvrakFormat.docx:
        return await DocxBridge.readBytes(bytes);

      case EvrakFormat.image:
        final image = img.decodeImage(bytes);
        if (image == null) throw const FormatException('Görsel okunamadı.');
        return DocModel(
          blocks: [
            for (final frame in image.frames)
              DocBlock(
                type: DocBlockType.image,
                plainText: '',
                imageBase64: base64Encode(img.encodePng(frame)),
                imageMime: 'image/png',
              ),
          ],
        );
      case EvrakFormat.pdf:
        // Text extraction, reflow and model construction all stay outside the
        // UI isolate. Long court filings otherwise pause the window after the
        // extraction itself has already completed.
        return PdfNativeReader.read(bytes);

      case EvrakFormat.text:
        final text = utf8.decode(bytes, allowMalformed: true);
        return _textToDocModel(text);

      default:
        return null;
    }
  }

  static Future<DocModel> _extractPdfFileModel(
    String path,
    String? text,
  ) async {
    Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException {
      // The viewer can still hold text after the file was moved or deleted.
      if (text != null && text.trim().isNotEmpty) {
        return compute(_pdfTextToModelIsolate, text);
      }
      rethrow;
    }
    return PdfNativeReader.read(bytes);
  }

  static DocModel _pdfTextToModelIsolate(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.trim().isEmpty) throw const PdfWithoutText();
    // Keep one text operation rather than manufacturing thousands of styled
    // blocks. Quill still treats the embedded newlines as paragraphs, while
    // opening a long filing stays cheap and the extracted text stays exact.
    return DocModel(
      blocks: [
        DocBlock(plainText: normalized.replaceFirst(RegExp(r'\n+$'), '')),
      ],
    );
  }

  static DocModel _textToDocModel(String text) {
    final lines = text.split('\n');
    final blocks = <DocBlock>[];

    for (final line in lines) {
      final val = line.trim();
      if (val.isEmpty) {
        blocks.add(DocBlock(plainText: ''));
      } else if (PdfService.isHeading(val)) {
        blocks.add(
          DocBlock(
            plainText: val,
            alignment: DocAlignment.center,
            spans: [DocSpan(startOffset: 0, length: val.length, bold: true)],
          ),
        );
      } else {
        blocks.add(
          DocBlock(
            plainText: val,
            alignment: DocAlignment.justify,
            lineSpacing: 1.25,
          ),
        );
      }
    }

    if (blocks.isEmpty) blocks.add(DocBlock(plainText: ''));
    return DocModel(blocks: blocks);
  }
}
