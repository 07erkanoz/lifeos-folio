import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/platform/save_name.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a name typed without its extension is given the chosen kind\'s; '
      'with another kind\'s it is saved as that kind', () {
    expect(
      savedNameAndFormat('/belgeler/cevap', EvrakFormat.udf),
      (path: '/belgeler/cevap.udf', format: EvrakFormat.udf),
    );
    expect(
      savedNameAndFormat('/belgeler/cevap.', EvrakFormat.docx),
      (path: '/belgeler/cevap.docx', format: EvrakFormat.docx),
    );
    expect(
      savedNameAndFormat('/belgeler/cevap.DOCX', EvrakFormat.udf),
      (path: '/belgeler/cevap.DOCX', format: EvrakFormat.docx),
    );
    expect(
      savedNameAndFormat('/belgeler/cevap.pdf', EvrakFormat.udf),
      (path: '/belgeler/cevap.pdf', format: EvrakFormat.pdf),
    );
    // A dot inside a name is no extension the editor writes.
    expect(
      savedNameAndFormat('/belgeler/2026.10 cevap', EvrakFormat.udf),
      (path: '/belgeler/2026.10 cevap.udf', format: EvrakFormat.udf),
    );
  });

  test('a text or workbook name without its extension is given it', () {
    expect(withExtension('/a/notlar', 'txt'), '/a/notlar.txt');
    expect(withExtension('/a/notlar.md', 'txt'), '/a/notlar.md');
    expect(withExtension('/a/tablo.', 'xlsx'), '/a/tablo.xlsx');
    expect(withExtension('/a/tablo', ''), '/a/tablo');
  });
}
