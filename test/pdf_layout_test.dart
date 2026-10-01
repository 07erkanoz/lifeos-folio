import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';

import 'support/pdf_readback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('short centered/right paragraphs align against the page body, including headers and indents', () async {
    final bytes = await PdfService.modelToPdfBytes(
      DocModel(
        pageProperties: const DocPageProperties(
          marginLeft: 60,
          marginRight: 40,
        ),
        blocks: [
          DocBlock(
            plainText: 'CENTERED HEADING',
            alignment: DocAlignment.center,
          ),
          DocBlock(plainText: 'RIGHT', alignment: DocAlignment.right),
          DocBlock(
            plainText: 'INDENTED',
            alignment: DocAlignment.center,
            leftIndent: 40,
            rightIndent: 20,
          ),
        ],
        pageRegions: {
          'header': [
            DocBlock(plainText: 'HEADER', alignment: DocAlignment.center),
          ],
        },
      ),
    );
    final pdf = await PdfReadback.of(bytes);
    final width = pdf.pageSizes.first.$1;
    final bodyCenter = (60 + width - 40) / 2;
    double center(String text) {
      final (left, right) = pdf.horizontalExtent(text);
      return (left + right) / 2;
    }

    expect(center('CENTERED HEADING'), closeTo(bodyCenter, 1));
    expect(pdf.horizontalExtent('RIGHT').$2, closeTo(width - 40, 1));
    expect(center('INDENTED'), closeTo(bodyCenter + 10, 1));
    expect(center('HEADER'), closeTo(bodyCenter, 1));
  });
}
