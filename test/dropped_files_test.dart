import 'dart:io';

import 'package:evrak_convert/ui/widgets/drop_zone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('what is dropped to be sent: files, and a folder’s files within', () {
    final dir = Directory.systemTemp.createTempSync('folio_drop_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final one = File('${dir.path}/Dilekçe.udf')..writeAsStringSync('d');
    final folder = Directory('${dir.path}/Dosya')..createSync();
    File('${folder.path}/Ek 1.pdf').writeAsStringSync('e');
    Directory('${folder.path}/Alt').createSync();
    File('${folder.path}/Alt/Ek 2.pdf').writeAsStringSync('e');
    File('${folder.path}/.gizli').writeAsStringSync('g');
    final got = droppedFiles([one.path, folder.path, '${dir.path}/yok.pdf']);
    expect(got.map((p) => p.split(Platform.pathSeparator).last).toSet(), {
      'Dilekçe.udf',
      'Ek 1.pdf',
      'Ek 2.pdf',
    });
    expect(droppedFiles([folder.path], limit: 1), hasLength(1));
  });
}
