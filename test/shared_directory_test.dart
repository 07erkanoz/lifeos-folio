import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:evrak_convert/services/platform/app_directories.dart';

/// What LifeOS Editör kept in a folder of its own comes over to Folio's.
void main() {
  test('cases, ties, settings and voice models come over; a case kept in '
      'both keeps the newer copy; nothing is fetched twice', () async {
    final root = await Directory.systemTemp.createTemp('folio-ortak-');
    addTearDown(() => root.delete(recursive: true));
    final editor = Directory('${root.path}/com.erkanoz.lifeos_editor');
    final folio = Directory('${root.path}/com.erkanoz.evrak_convert');
    Future<File> write(Directory d, String path, String text) async =>
        (await File('${d.path}/$path').create(recursive: true))
          ..writeAsStringSync(text);

    await write(folio, 'uyap/dosyalar/ortak.json', 'folio eski');
    await write(folio, 'uyap/baglar.json', jsonEncode({'a': 1}));
    await write(folio, 'uyap.json', 'folio ayarı');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await write(editor, 'uyap/dosyalar/ortak.json', 'editör yeni');
    await write(editor, 'uyap/dosyalar/konya.json', 'konya');
    await write(editor, 'uyap/baglar.json', jsonEncode({'b': 2}));
    await write(editor, 'uyap.json', 'editör ayarı');
    await write(editor, 'ses/okuma-supertonic3-1/voice.bin', 'ses');

    await bringOverEditorData(editor, folio);

    String read(String path) => File('${folio.path}/$path').readAsStringSync();
    expect(read('uyap/dosyalar/ortak.json'), 'editör yeni');
    expect(read('uyap/dosyalar/konya.json'), 'konya');
    expect(jsonDecode(read('uyap/baglar.json')), {'a': 1, 'b': 2});
    // Folio's own settings stand; the editor's had no say over them.
    expect(read('uyap.json'), 'folio ayarı');
    expect(read('ses/okuma-supertonic3-1/voice.bin'), 'ses');
    expect(Directory('${editor.path}/uyap/dosyalar').listSync(), isEmpty);
  });

  test('the Mac keeps the folder of the old name where there is one: '
      'its records name their files by full path', () async {
    final root = await Directory.systemTemp.createTemp('folio-mac-');
    addTearDown(() => root.delete(recursive: true));
    final now = Directory('${root.path}/com.lifeos.folio')..createSync();
    expect((await macDataFolder(now)).path, now.path);
    final old = Directory('${root.path}/com.erkanoz.evrakConvert')
      ..createSync();
    expect((await macDataFolder(now)).path, old.path);
  });

  test('on Windows the data stays in the folder it was first kept in, '
      'whatever company the executable names', () async {
    final roaming = await Directory.systemTemp.createTemp('folio-roaming-');
    addTearDown(() => roaming.delete(recursive: true));
    // What path_provider gives 1.6.7 and later: <company>\\<product>.
    final current = Directory(p.join(roaming.path, 'LifeOS', 'LifeOS Folio'));

    // First installed since 1.6.7: its own folder under LifeOS.
    final fresh = await windowsDataFolder(current);
    expect(fresh.path, p.join(roaming.path, 'LifeOS', 'LifeOS Evrakçı'));
    expect(fresh.existsSync(), isTrue);

    // Kept by 1.6.6 or before under com.erkanoz: that one, even beside a
    // folder 1.6.7 made when it did not find it.
    final before = await Directory(
      p.join(roaming.path, 'com.erkanoz', 'LifeOS Evrakçı'),
    ).create(recursive: true);
    expect((await windowsDataFolder(current)).path, before.path);
  });
}
