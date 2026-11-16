import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/platform/editor_window.dart';
import 'package:flutter_test/flutter_test.dart';

// LifeOS Editör writes formatted documents only; the rest is edited in
// Folio's own window. A Markdown file sent to it opened as a blank page.
void main() {
  test('the standalone editor takes formatted documents, Folio the rest', () {
    for (final ext in ['.udf', '.docx', '.rtf', '.odt', '.txt']) {
      expect(
        opensInStandaloneEditor(EvrakFormat.fromExtension(ext)),
        isTrue,
        reason: ext,
      );
    }
    for (final ext in ['.md', '.markdown', '.html', '.json', '.xlsx']) {
      expect(
        opensInStandaloneEditor(EvrakFormat.fromExtension(ext)),
        isFalse,
        reason: ext,
      );
    }
  });

  test('handed to Folio from LifeOS Editör, Folio\'s own program starts, '
      'not the editor again', () {
    expect(
      EditorWindow.folioExecutable('/opt/folio/lifeos_editor'),
      '/opt/folio/lifeos_folio',
    );
    expect(
      EditorWindow.folioExecutable('/opt/folio/lifeos_folio'),
      '/opt/folio/lifeos_folio',
    );
  });
}
