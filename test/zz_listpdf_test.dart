import 'dart:io';
import 'package:evrak_convert/services/pdf/pdf_service.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pdf', (tester) async {
    final model = UdfReader.readBytes(File('/tmp/claude-1000/list/listeler.udf').readAsBytesSync())!;
    final bytes = await tester.runAsync(() => PdfService.modelToPdfBytes(model));
    File('/tmp/claude-1000/list/listeler.pdf').writeAsBytesSync(bytes!);
  });
}
