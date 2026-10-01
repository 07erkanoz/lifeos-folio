import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/convert/converter_service.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UDF & Converter Motoru Testleri', () {
    test('viewer PDF text stays exact without opening the PDF again', () async {
      const extracted =
          'ANKARA 1. ASLİYE HUKUK MAHKEMESİ\n  sütun aralığı\n\nDava metni';
      final model = await ConverterService.extractFileDocModel(
        '/var/olmayan-bir-dosya.pdf',
        EvrakFormat.pdf,
        extractedPdfText: extracted,
      );
      expect(model, isNotNull);
      expect(model!.blocks, hasLength(1));
      expect(model.blocks.single.plainText, extracted);
      expect(model.toPlainText(), contains('Dava metni'));
    });

    test('UDF DocModel yazma ve okuma round-trip testi', () {
      final model = DocModel(
        blocks: [
          DocBlock(
            plainText: 'ANKARA 1. ASLİYE HUKUK MAHKEMESİ',
            alignment: DocAlignment.center,
            spans: [const DocSpan(startOffset: 0, length: 32, bold: true)],
          ),
          DocBlock(
            plainText: 'DAVACI: Ahmet Yılmaz',
            alignment: DocAlignment.left,
          ),
          DocBlock(
            plainText: 'Dava dilekçesinin özetidir. Haklı davamızın kabulünü talep ederiz.',
            alignment: DocAlignment.justify,
          ),
        ],
      );

      final bytes = UdfWriter.writeBytes(model);
      expect(bytes, isNotEmpty);

      final parsed = UdfReader.readBytes(bytes);
      expect(parsed, isNotNull);
      expect(parsed!.blocks.length, greaterThanOrEqualTo(3));
      expect(
        parsed.toPlainText(),
        contains('ANKARA 1. ASLİYE HUKUK MAHKEMESİ'),
      );
      expect(parsed.toPlainText(), contains('Ahmet Yılmaz'));
    });

    test('UDF -> DOCX ve UDF -> PDF dönüştürme testi', () async {
      final model = DocModel(
        blocks: [
          DocBlock(plainText: 'BAŞLIK', alignment: DocAlignment.center),
          DocBlock(plainText: 'Paragraf içeriği burada yer almaktadır.'),
        ],
      );
      final udfBytes = Uint8List.fromList(UdfWriter.writeBytes(model));

      // UDF -> DOCX
      final docxBytes = await ConverterService.convertBytes(
        bytes: udfBytes,
        sourceFormat: EvrakFormat.udf,
        targetFormat: EvrakFormat.docx,
      );
      expect(docxBytes, isNotNull);
      expect(docxBytes!.length, greaterThan(0));

      // UDF -> PDF
      final pdfBytes = await ConverterService.convertBytes(
        bytes: udfBytes,
        sourceFormat: EvrakFormat.udf,
        targetFormat: EvrakFormat.pdf,
      );
      expect(pdfBytes, isNotNull);
      expect(pdfBytes!.length, greaterThan(0));
    });
  });
}
