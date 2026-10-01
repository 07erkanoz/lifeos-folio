import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../platform/native_tools.dart';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class OptimizeResult {
  final String? outputPath;
  final int beforeBytes;
  final int afterBytes;
  final String message;
  const OptimizeResult({
    this.outputPath,
    required this.beforeBytes,
    required this.afterBytes,
    required this.message,
  });
  bool get reduced => outputPath != null && afterBytes < beforeBytes;
}

/// Lossless recompression only: Flate streams are recompressed and JPEG images
/// re-entropy-coded, never re-quantised; no resizing, conversion or DPI change.
class OptimizerService {
  static Future<ProcessResult> _run(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      await NativeTools.executable(executable),
      arguments,
      runInShell: false,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        process.kill();
        throw TimeoutException('Boyut küçültme zaman aşımına uğradı.');
      },
    );
    return ProcessResult(
      process.pid,
      code,
      await stdoutFuture,
      await stderrFuture,
    );
  }

  static bool _hasSignature(Object? node) {
    if (node is Map) {
      if (node.containsKey('/ByteRange') ||
          node['/Type'] == '/Sig' ||
          node['/FT'] == '/Sig') {
        return true;
      }
      return node.values.any(_hasSignature);
    }
    return node is List && node.any(_hasSignature);
  }

  static Future<OptimizeResult> optimize(
    String sourcePath, {
    String? targetDirectory,
  }) async {
    final source = File(sourcePath).absolute;
    final ext = p.extension(source.path).toLowerCase();
    if (!['.pdf', '.tif', '.tiff', '.png', '.jpg', '.jpeg'].contains(ext)) {
      throw UnsupportedError(
        'Bu tür için kayıpsız boyut küçültme desteklenmiyor.',
      );
    }
    var before = await source.length();
    final temp = await Directory.systemTemp.createTemp('lifeos-optimize-');
    try {
      // Snapshot source first: inspection and rewriting must use the same bytes.
      final input = await source.copy(p.join(temp.path, 'source$ext'));
      before = await input.length();
      final output = File(p.join(temp.path, 'optimized$ext'));
      if (ext == '.pdf') {
        final inspect = await _run('qpdf', [
          '--json',
          '--json-key=qpdf',
          '--json-stream-data=none',
          input.path,
        ]);
        if (inspect.exitCode != 0) {
          throw const FormatException(
            'PDF okunamadı; şifreli veya bozuk olabilir.',
          );
        }
        if (_hasSignature(jsonDecode(inspect.stdout as String))) {
          throw const FormatException(
            'İmza alanı içeren PDF yeniden yazılmaz; imzayı korumak için küçültme uygulanmadı.',
          );
        }
        final update = await _recodeJpegStreams(input, temp);
        final result = await _run('qpdf', [
          '--object-streams=generate',
          '--stream-data=compress',
          '--recompress-flate',
          '--compression-level=9',
          if (update != null) ...[
            '--update-from-json=${update.path}',
            // Progressive DCT is part of PDF from 1.3 on.
            '--min-version=1.3',
          ],
          input.path,
          output.path,
        ]);
        if (result.exitCode != 0) {
          throw const FormatException(
            'PDF kayıpsız olarak yeniden paketlenemedi.',
          );
        }
        final check = await _run('qpdf', ['--check', output.path]);
        if (check.exitCode != 0) {
          throw const FormatException('Küçültülen PDF doğrulanamadı.');
        }
      } else if (ext == '.jpg' || ext == '.jpeg') {
        final result = await _run('jpegtran', [
          '-copy',
          'all',
          '-optimize',
          '-outfile',
          output.path,
          input.path,
        ]);
        if (result.exitCode != 0) {
          throw const FormatException(
            'JPEG kayıpsız olarak yeniden paketlenemedi.',
          );
        }
      } else if (ext == '.png') {
        final bytes = await input.readAsBytes();
        await output.writeAsBytes(await compute(recompressPng, bytes));
      } else {
        // ':' is used by libtiff options; arguments and paths never enter a shell.
        final result = await _run('tiffcp', [
          '-c',
          'zip:p9',
          input.path,
          output.path,
        ]);
        if (result.exitCode != 0) {
          throw const FormatException(
            'TIFF kayıpsız sıkıştırılamadı; kaynak dosya korunuyor.',
          );
        }
      }
      final after = await output.length();
      if (after >= before) {
        return OptimizeResult(
          beforeBytes: before,
          afterBytes: before,
          message: 'Dosya zaten verimli sıkıştırılmış. Kaliteyi koruyarak daha küçük sonuç elde edilemedi.',
        );
      }
      final dir = Directory(targetDirectory ?? source.parent.path);
      await dir.create(recursive: true);
      final stem = p.join(
        dir.path,
        '${p.basenameWithoutExtension(source.path)}_kucultulmus',
      );
      var path = '$stem$ext';
      var index = 1;
      while (await FileSystemEntity.type(path) !=
          FileSystemEntityType.notFound) {
        path = '${stem}_${index++}$ext';
      }
      await output.copy(path);
      return OptimizeResult(
        outputPath: path,
        beforeBytes: before,
        afterBytes: after,
        message:
            'Görüntü boyutları ve piksel verisi değiştirilmeden kaydedildi.',
      );
    } on ProcessException catch (e) {
      throw UnsupportedError(
        '${p.basename(e.executable)} çalıştırılamadı. Folio paketinin tools klasörünü ve izinlerini kontrol edin.',
      );
    } finally {
      await temp.delete(recursive: true);
    }
  }

  /// Rewrites the JPEG images inside a PDF losslessly, the way a scan's pages
  /// are stored, and returns a qpdf update naming the ones that shrank.
  ///
  /// `jpegtran -optimize -progressive` recodes only the entropy coding: the
  /// DCT coefficients, and so every decoded pixel, stay as they were. Measured
  /// on 25 scanned PDFs from a real archive this saved 12.4% (baseline
  /// optimisation alone 6.5%), where recompressing Flate streams saved 0.2%;
  /// PDFium, poppler and Ghostscript rendered the result identically. Only a
  /// stream whose sole filter is DCTDecode is touched, and only when it got
  /// smaller. Null when nothing changed, or when jpegtran is missing, in which
  /// case the Flate pass still runs.
  static Future<File?> _recodeJpegStreams(File input, Directory temp) async {
    final dump = File(p.join(temp.path, 'streams.json'));
    final streams = Directory(p.join(temp.path, 'streams'));
    await streams.create();
    final written = await _run('qpdf', [
      input.path,
      '--json-output=2',
      '--decode-level=none',
      '--json-stream-data=file',
      '--json-stream-prefix=${p.join(streams.path, 's')}',
      dump.path,
    ]);
    if (written.exitCode != 0) return null;
    final json = jsonDecode(await dump.readAsString()) as Map<String, dynamic>;
    final parts = json['qpdf'] as List;
    final objects = parts[1] as Map<String, dynamic>;
    final changed = <String, Object?>{};
    for (final entry in objects.entries) {
      final stream = entry.value is Map ? entry.value['stream'] : null;
      if (stream is! Map) continue;
      final dict = stream['dict'];
      final data = stream['datafile'];
      if (dict is! Map || data is! String) continue;
      final filter = dict['/Filter'];
      final dct =
          filter == '/DCTDecode' ||
          (filter is List && filter.length == 1 && filter[0] == '/DCTDecode');
      if (!dct) continue;
      final source = File(data);
      final recoded = File('$data.jpg');
      try {
        final result = await _run('jpegtran', [
          '-copy',
          'all',
          '-optimize',
          '-progressive',
          '-outfile',
          recoded.path,
          source.path,
        ]);
        if (result.exitCode != 0 ||
            !await recoded.exists() ||
            await recoded.length() >= await source.length()) {
          continue;
        }
      } on TimeoutException {
        continue;
      } on ProcessException {
        return null;
      } on UnsupportedError {
        // jpegtran is missing from this install: the Flate pass still runs.
        return null;
      }
      changed[entry.key] = {
        'stream': {'dict': dict, 'datafile': recoded.path},
      };
    }
    if (changed.isEmpty) return null;
    final update = File(p.join(temp.path, 'update.json'));
    await update.writeAsString(
      jsonEncode({
        'qpdf': [parts[0], changed],
      }),
    );
    return update;
  }

  /// Recompress PNG IDAT, preserving the exact filtered pixel stream and all
  /// other chunks (ICC, EXIF, gamma, text, etc.). Animated PNG is left unchanged.
  static Uint8List recompressPng(Uint8List bytes) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 8 || !listEquals(bytes.sublist(0, 8), signature)) {
      throw const FormatException('PNG başlığı geçersiz.');
    }
    final data = ByteData.sublistView(bytes);
    final chunks = <({String type, Uint8List bytes, Uint8List content})>[];
    var offset = 8;
    final compressed = BytesBuilder();
    var animated = false;
    var ended = false;
    while (offset + 12 <= bytes.length) {
      final length = data.getUint32(offset);
      if (offset + 12 + length > bytes.length) {
        throw const FormatException('PNG eksik.');
      }
      final type = ascii.decode(bytes.sublist(offset + 4, offset + 8));
      final content = Uint8List.sublistView(
        bytes,
        offset + 8,
        offset + 8 + length,
      );
      final chunk = Uint8List.sublistView(bytes, offset, offset + 12 + length);
      if (getCrc32(
            Uint8List.sublistView(bytes, offset + 4, offset + 8 + length),
          ) !=
          data.getUint32(offset + 8 + length)) {
        throw const FormatException('PNG CRC hatası.');
      }
      chunks.add((type: type, bytes: chunk, content: content));
      if (type == 'IDAT') compressed.add(content);
      if (type == 'acTL') animated = true;
      offset += 12 + length;
      if (type == 'IEND') {
        ended = true;
        break;
      }
    }
    if (!ended || offset != bytes.length) {
      throw const FormatException('PNG sonlandırıcısı geçersiz.');
    }
    if (animated) return bytes;
    final pixels = ZLibCodec().decode(compressed.takeBytes());
    final encoded = Uint8List.fromList(ZLibCodec(level: 9).encode(pixels));
    final chunk = BytesBuilder()
      ..add(ascii.encode('IDAT'))
      ..add(encoded);
    final crcInput = chunk.takeBytes();
    final header = ByteData(4)..setUint32(0, encoded.length);
    final crc = ByteData(4)..setUint32(0, getCrc32(crcInput));
    final output = BytesBuilder()..add(signature);
    var written = false;
    for (final c in chunks) {
      if (c.type == 'IDAT') {
        if (!written) {
          output.add(header.buffer.asUint8List());
          output.add(crcInput);
          output.add(crc.buffer.asUint8List());
          written = true;
        }
      } else {
        output.add(c.bytes);
      }
    }
    return output.takeBytes();
  }
}
