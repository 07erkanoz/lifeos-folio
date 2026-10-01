import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/library/file_library.dart';
import 'package:evrak_convert/services/optimize/optimizer_service.dart';
import 'package:evrak_convert/services/platform/native_tools.dart';
import 'package:evrak_convert/services/preview/structured_reader.dart';
import 'package:evrak_convert/services/preview/svg_source.dart';
import 'package:evrak_convert/services/convert/converter_service.dart';

import 'support/pdf_readback.dart';
import 'support/styled_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('folder scan filters supported files, recurses optionally and skips symlinks', () async {
    final dir = await Directory.systemTemp.createTemp('lifeos-folder-');
    try {
      await Directory('${dir.path}/sub').create();
      for (final name in [
        'A.PDF',
        'picture.webp',
        'notes.md',
        'run.exe',
        'old.doc',
        'sub/body.odt',
        'sub/grid.csv',
      ]) {
        await File('${dir.path}/$name').writeAsString('fixture');
      }
      if (!Platform.isWindows) {
        await Link('${dir.path}/sub/loop').create(dir.path);
      }
      final recursive = await FileLibrary.collect([
        dir.path,
        '${dir.path}/A.PDF',
      ]);
      // Word 97 documents count now; programs still do not.
      expect(recursive.paths.length, 6);
      expect(recursive.paths.where((p) => p.endsWith('A.PDF')).length, 1);
      expect(recursive.paths.where((p) => p.endsWith('.doc')).length, 1);
      expect(recursive.paths.any((p) => p.endsWith('.exe')), isFalse);
      final shallow = await FileLibrary.collect([dir.path], recursive: false);
      expect(shallow.paths.length, 4);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('document and image conversion paths are distinct', () async {
    final image = Uint8List.fromList(
      img.encodePng(img.Image(width: 8, height: 8)),
    );
    await expectLater(
      ConverterService.convertBytes(
        bytes: image,
        sourceFormat: EvrakFormat.image,
        targetFormat: EvrakFormat.udf,
      ),
      throwsUnsupportedError,
    );
    final tiff = await ConverterService.convertBytes(
      bytes: image,
      sourceFormat: EvrakFormat.image,
      targetFormat: EvrakFormat.tif,
    );
    expect(img.decodeTiff(tiff!)!.width, 8);
    final file = EvrakFile(
      path: '/a.png',
      name: 'a.png',
      format: EvrakFormat.image,
      sizeInBytes: 1,
    );
    expect(file.conversionTargets.contains(EvrakFormat.image), isFalse);
    expect(EvrakFormat.data.availableConversions, isEmpty);
    expect(EvrakFormat.svg.availableConversions, isEmpty);
  });
  test('animated image cannot silently become one PNG', () async {
    final image = img.Image(width: 4, height: 4)
      ..addFrame(img.Image(width: 4, height: 4));
    final gif = Uint8List.fromList(img.encodeGif(image));
    await expectLater(
      ConverterService.convertBytes(
        bytes: gif,
        sourceFormat: EvrakFormat.image,
        targetFormat: EvrakFormat.image,
      ),
      throwsFormatException,
    );
    await expectLater(
      ConverterService.convertBytes(
        bytes: gif,
        sourceFormat: EvrakFormat.image,
        targetFormat: EvrakFormat.tif,
      ),
      throwsFormatException,
    );
  });
  test(
    'HTML/Markdown show content and ignore executable or remote resources',
    () {
      final html = StructuredReader.read((
        bytes: Uint8List.fromList(
          utf8.encode(
            '<h1>Başlık</h1><p>Türkçe <b>kalın</b></p><script>gizli()</script><iframe src="https://example.org"></iframe>',
          ),
        ),
        format: EvrakFormat.html,
      ));
      expect(html.toPlainText(), contains('Türkçe kalın'));
      expect(html.toPlainText(), isNot(contains('gizli')));
      final markdown = StructuredReader.read((
        bytes: Uint8List.fromList(utf8.encode('# Başlık\n\n**Güçlü** içerik')),
        format: EvrakFormat.markdown,
      ));
      expect(markdown.toPlainText(), contains('Güçlü içerik'));
      expect(markdown.blocks.last.spans.any((s) => s.bold), isTrue);
    },
  );
  test('ODT reads paragraphs and style inheritance from its archive', () {
    const xml =
        '''<office:document-content xmlns:office="urn:o" xmlns:text="urn:t" xmlns:style="urn:s" xmlns:fo="urn:f"><office:automatic-styles><style:style style:name="p1"><style:text-properties fo:font-weight="bold" fo:font-family="Arial" fo:font-size="13pt"/></style:style></office:automatic-styles><office:body><office:text><text:p text:style-name="p1">İşlem<text:s text:c="2"/>metni</text:p></office:text></office:body></office:document-content>''';
    final content = utf8.encode(xml);
    final bytes = Uint8List.fromList(
      ZipEncoder().encode(
        Archive()..addFile(ArchiveFile('content.xml', content.length, content)),
      ),
    );
    final model = StructuredReader.read((
      bytes: bytes,
      format: EvrakFormat.odt,
    ));
    expect(model.toPlainText(), 'İşlem  metni');
    expect(model.blocks.single.spans.first.fontFamily, 'Arial');
    expect(model.blocks.single.spans.first.bold, isTrue);
  });
  test('SVG blocks external resources, accepts local geometry', () async {
    final dir = await Directory.systemTemp.createTemp('lifeos-svg-');
    try {
      final file = File('${dir.path}/icon.svg');
      await file.writeAsString(
        '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>',
      );
      expect(await SvgSource.load(file.path), contains('rect'));
      await file.writeAsString(
        '<svg xmlns="http://www.w3.org/2000/svg"><defs><linearGradient id="g"/></defs><rect style="fill:url(&quot;#g&quot;)" width="10" height="10"/></svg>',
      );
      expect(await SvgSource.load(file.path), contains('linearGradient'));
      await file.writeAsString(
        '<svg xmlns="http://www.w3.org/2000/svg"><image href="https://example.org/a.png"/></svg>',
      );
      await expectLater(SvgSource.load(file.path), throwsFormatException);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'PNG lossless reduction preserves dimensions and every decoded byte',
    () async {
      final dir = await Directory.systemTemp.createTemp('lifeos-png-');
      try {
        final source = img.Image(width: 512, height: 768, numChannels: 4);
        img.fill(source, color: img.ColorRgba8(30, 60, 120, 128));
        final original = Uint8List.fromList(img.encodePng(source, level: 0));
        final file = File('${dir.path}/image.png');
        await file.writeAsBytes(original);
        final result = await OptimizerService.optimize(file.path);
        expect(result.reduced, isTrue);
        final decoded = img.decodePng(
          await File(result.outputPath!).readAsBytes(),
        )!;
        expect(decoded.width, source.width);
        expect(decoded.height, source.height);
        expect(decoded.getBytes(), orderedEquals(source.getBytes()));
        expect(await file.readAsBytes(), original);
        final repeated = await OptimizerService.optimize(file.path);
        expect(repeated.outputPath, isNot(result.outputPath));
        final again = await OptimizerService.optimize(result.outputPath!);
        expect(again.reduced, isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('corrupted PNG never produces a success result', () {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 4, height: 4)),
    );
    bytes[20] ^= 1;
    expect(() => OptimizerService.recompressPng(bytes), throwsFormatException);
  });
  test(
    'lossless TIFF reduction retains all pages, sample bytes and source',
    () async {
      if (!await _available('tiffcp', ['-h'])) return;
      final dir = await Directory.systemTemp.createTemp('lifeos-tiff-');
      try {
        final source = img.Image(width: 128, height: 256, numChannels: 3);
        img.fill(source, color: img.ColorRgb8(120, 30, 45));
        source.addFrame(img.Image(width: 128, height: 256, numChannels: 3));
        await File('${dir.path}/first.tiff')
            .writeAsBytes(img.encodeTiff(source.frames[0]));
        await File('${dir.path}/second.tiff')
            .writeAsBytes(img.encodeTiff(source.frames[1]));
        final file = File('${dir.path}/scan.tiff');
        final joined = await Process.run('tiffcp', [
          '-c',
          'none',
          '${dir.path}/first.tiff',
          '${dir.path}/second.tiff',
          file.path,
        ]);
        expect(joined.exitCode, 0);
        final input = await file.readAsBytes();
        final result = await OptimizerService.optimize(file.path);
        expect(result.reduced, isTrue);
        final decoded = img.decodeTiff(
          await File(result.outputPath!).readAsBytes(),
        )!;
        final before = img.decodeTiff(input)!;
        expect(before.numFrames, 2);
        expect(decoded.numFrames, before.numFrames);
        for (var i = 0; i < before.numFrames; i++) {
          expect(
            decoded.frames[i].getBytes(),
            orderedEquals(before.frames[i].getBytes()),
          );
        }
        expect(await file.readAsBytes(), input);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('PDF reduction preserves page size, text and source bytes', () async {
    if (!await _available('qpdf', ['--version'])) return;
    final dir = await Directory.systemTemp.createTemp('lifeos-pdf-');
    try {
      final pdf = pw.Document(compress: false);
      pdf.addPage(
        pw.Page(
          build: (_) => pw.Column(
            children: [
              for (var i = 0; i < 50; i++)
                pw.Text('Lossless document sample $i'),
            ],
          ),
        ),
      );
      final graphic = img.Image(width: 128, height: 256, numChannels: 3);
      img.fill(graphic, color: img.ColorRgb8(20, 90, 180));
      img.fillRect(
        graphic,
        x1: 20,
        y1: 20,
        x2: 90,
        y2: 140,
        color: img.ColorRgb8(200, 80, 30),
      );
      pdf.addPage(
        pw.Page(
          build: (_) => pw.Image(
            pw.MemoryImage(Uint8List.fromList(img.encodeJpg(graphic))),
          ),
        ),
      );
      final input = await pdf.save();
      final file = File('${dir.path}/document.pdf');
      await file.writeAsBytes(input);
      final result = await OptimizerService.optimize(file.path);
      expect(result.reduced, isTrue);
      final before = await PdfReadback.of(input);
      final after = await PdfReadback.of(
        await File(result.outputPath!).readAsBytes(),
      );
      expect(after.pageCount, before.pageCount);
      expect(after.pageSizes, before.pageSizes);
      expect(after.text, before.text);
      if (await _available('pdftoppm', ['-v'])) {
        for (final entry in {
          'before': file.path,
          'after': result.outputPath!,
        }.entries) {
          final rendered = await Process.run('pdftoppm', [
            '-f',
            '2',
            '-l',
            '2',
            '-singlefile',
            '-scale-to',
            '400',
            '-png',
            entry.value,
            '${dir.path}/${entry.key}',
          ]);
          expect(rendered.exitCode, 0);
        }
        final a = img.decodePng(
          await File('${dir.path}/before.png').readAsBytes(),
        )!;
        final b = img.decodePng(
          await File('${dir.path}/after.png').readAsBytes(),
        )!;
        expect(a.getBytes(), orderedEquals(b.getBytes()));
      }
      expect(await file.readAsBytes(), input);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'JPEG entropy optimization preserves decoded pixels and source',
    () async {
      if (!await _available('jpegtran', ['-version'])) return;
      final dir = await Directory.systemTemp.createTemp('lifeos-jpeg-');
      try {
        final image = img.Image(width: 256, height: 512, numChannels: 3);
        img.fill(image, color: img.ColorRgb8(40, 120, 180));
        final input = Uint8List.fromList(img.encodeJpg(image, quality: 90));
        final file = File('${dir.path}/photo.jpg');
        await file.writeAsBytes(input);
        final result = await OptimizerService.optimize(file.path);
        expect(result.reduced, isTrue);
        final before = img.decodeJpg(input)!;
        final after = img.decodeJpg(
          await File(result.outputPath!).readAsBytes(),
        )!;
        expect(after.getBytes(), orderedEquals(before.getBytes()));
        expect(await file.readAsBytes(), input);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'a scanned page\'s JPEG shrinks inside the PDF with every pixel kept',
    () async {
      if (!await _available('qpdf', ['--version']) ||
          !await _available('jpegtran', ['-version'])) {
        return;
      }
      final dir = await Directory.systemTemp.createTemp('lifeos-scan-');
      try {
        // A page-sized picture with detail, encoded the way scanners do:
        // baseline JPEG with the standard Huffman tables.
        final scan = img.Image(width: 620, height: 877, numChannels: 3);
        for (var y = 0; y < scan.height; y++) {
          for (var x = 0; x < scan.width; x++) {
            final ink = (x ~/ 7 + y ~/ 11) % 5 == 0 && y % 23 < 14;
            scan.setPixelRgb(
              x,
              y,
              ink ? 30 : 235 - (x + y) % 17,
              ink ? 30 : 232 - (x * 3 + y) % 13,
              ink ? 40 : 225,
            );
          }
        }
        final jpeg = Uint8List.fromList(img.encodeJpg(scan, quality: 85));
        final pdf = pw.Document();
        pdf.addPage(
          pw.Page(
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(pw.MemoryImage(jpeg), fit: pw.BoxFit.fill),
          ),
        );
        final input = await pdf.save();
        final file = File('${dir.path}/tarama.pdf');
        await file.writeAsBytes(input);
        final result = await OptimizerService.optimize(file.path);
        expect(result.reduced, isTrue);

        Uint8List dct(Uint8List bytes) {
          final text = latin1.decode(bytes);
          final m = RegExp(
            r'/DCTDecode[^>]*?/Length (\d+)[^>]*>>\s*stream\r?\n',
          ).firstMatch(text);
          final n = RegExp(
            r'/Length (\d+)[^>]*?/DCTDecode[^>]*>>\s*stream\r?\n',
          ).firstMatch(text);
          final hit = m ?? n!;
          return bytes.sublist(hit.end, hit.end + int.parse(hit[1]!));
        }

        final before = dct(input),
            after = dct(await File(result.outputPath!).readAsBytes());
        expect(after.length, lessThan(before.length));
        // The image package decodes progressive JPEG with its own rounding,
        // so it cannot compare the two directly (libjpeg, PDFium, poppler and
        // Ghostscript all decode them identically). Taking the result back to
        // baseline, again losslessly, shows the DCT coefficients are the ones
        // the scan had: its pixels then match through the same decoder.
        await File('${dir.path}/after.jpg').writeAsBytes(after);
        final baseline = await Process.run(
          await NativeTools.executable('jpegtran'),
          ['-outfile', '${dir.path}/baseline.jpg', '${dir.path}/after.jpg'],
        );
        expect(baseline.exitCode, 0);
        expect(
          img
              .decodeJpg(await File('${dir.path}/baseline.jpg').readAsBytes())!
              .getBytes(),
          orderedEquals(img.decodeJpg(before)!.getBytes()),
        );
        expect(await file.readAsBytes(), input);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('PDF signature fields prevent lossless rewrite', () async {
    if (!await _available('qpdf', ['--version'])) return;
    final dir = await Directory.systemTemp.createTemp('lifeos-signed-');
    try {
      final file = File('${dir.path}/signed.pdf');
      await file.writeAsBytes(signatureFieldPdf());
      await expectLater(
        OptimizerService.optimize(file.path),
        throwsFormatException,
      );
      expect(await dir.list().length, 1);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

Future<bool> _available(String command, List<String> args) async {
  try {
    await Process.run(command, args);
    return true;
  } on ProcessException {
    return false;
  }
}
