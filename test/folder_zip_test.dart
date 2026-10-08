import 'dart:io';

import 'package:archive/archive.dart';
import 'package:evrak_convert/services/platform/folder_zip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a folder is packed whole, its subfolders with it', () async {
    final root = Directory.systemTemp.createTempSync('folio_klasor_');
    addTearDown(() => root.deleteSync(recursive: true));
    final folder = Directory('${root.path}/Karaca dosyası')..createSync();
    File('${folder.path}/dilekce.udf').writeAsStringSync('a');
    File('${folder.path}/Ekler/rapor.pdf')
      ..createSync(recursive: true)
      ..writeAsStringSync('b');
    final zip = await zipFolder(folder.path);
    expect(zip, endsWith('Karaca dosyası.zip'));
    final names = [
      for (final f in ZipDecoder().decodeBytes(File(zip).readAsBytesSync()))
        if (f.isFile) f.name,
    ]..sort();
    expect(names, ['Ekler/rapor.pdf', 'dilekce.udf']);
    // Come to another device, it opens as the folder it was.
    final there = await unzipFolder(zip);
    expect(File('$there/Ekler/rapor.pdf').readAsStringSync(), 'b');
  });
}
