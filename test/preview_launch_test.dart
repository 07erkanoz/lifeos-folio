import 'dart:io';

import 'package:evrak_convert/main.dart';
import 'package:flutter_test/flutter_test.dart';

// A document opened from outside is shown in a preview window of its own,
// so that two can be read side by side; anything else asked of Folio is
// its own window's.
void main() {
  late Directory dir;
  late String pdf, word;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('folio-launch-');
    pdf = (File('${dir.path}/karar.pdf')..writeAsStringSync('%PDF')).path;
    word = (File('${dir.path}/dilekçe.docx')..writeAsStringSync('PK')).path;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('files alone, one or several, each get a window', () {
    expect(previewLaunch([pdf]), [pdf]);
    expect(previewLaunch([pdf, word]), [pdf, word]);
    expect(previewLaunch(['--', pdf]), [pdf]);
  });

  test('to be edited, a folder, an invitation, the agenda, a flag, a file '
      'not there or not a document: Folio\'s own window', () {
    expect(previewLaunch(const []), isEmpty);
    expect(previewLaunch(['--edit', '--', pdf]), isEmpty);
    expect(previewLaunch([dir.path]), isEmpty);
    expect(previewLaunch([pdf, dir.path]), isEmpty);
    expect(previewLaunch(['lifeos-folio://katil/K7Q4MP2XD']), isEmpty);
    expect(previewLaunch(['--ajanda']), isEmpty);
    expect(previewLaunch(['--quick-search']), isEmpty);
    expect(previewLaunch(['--minimized', pdf]), isEmpty);
    expect(previewLaunch(['${dir.path}/yok.pdf']), isEmpty);
    final other = (File(
      '${dir.path}/program.exe',
    )..writeAsStringSync('x')).path;
    expect(previewLaunch([other]), isEmpty);
  });
}
