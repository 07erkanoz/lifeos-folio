import 'dart:io';

import 'package:evrak_convert/services/platform/data_reset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const env = {
    'USERPROFILE': r'C:\Users\avukat',
    'APPDATA': r'C:\Users\avukat\AppData\Roaming',
    'LOCALAPPDATA': r'C:\Users\avukat\AppData\Local',
    'TEMP': r'C:\Users\avukat\AppData\Local\Temp',
  };
  bool safe(String path) =>
      DataReset.safeToClear(path, env: env, windows: true, phone: false);

  test('only Folio\'s own folders are cleared, never a place of the '
      'person\'s', () {
    expect(
      safe(r'C:\Users\avukat\AppData\Roaming\com.erkanoz\LifeOS Evrakçı'),
      isTrue,
    );
    expect(
      safe(r'C:\Users\avukat\AppData\Roaming\LifeOS\LifeOS Folio'),
      isTrue,
    );
    expect(safe(r'C:\Users\avukat\LifeOS Folio'), isTrue);
    expect(safe(r'C:\Users\avukat\AppData\Local\Temp\folio-edevlet'), isTrue);
    // The person's folders themselves, and what holds them.
    expect(safe(r'C:\Users\avukat'), isFalse);
    expect(safe(r'C:\Users\avukat\AppData\Roaming'), isFalse);
    expect(safe(r'C:\Users\avukat\AppData'), isFalse);
    expect(safe(r'C:\Users'), isFalse);
    expect(safe(r'C:\'), isFalse);
    // Deep enough, but not named for Folio.
    expect(safe(r'C:\Users\avukat\Documents\Dilekçeler'), isFalse);
    expect(safe(r'C:\Users\avukat\AppData\Roaming\Microsoft'), isFalse);
    expect(safe('relative/LifeOS Folio'), isFalse);
  });

  group('clearing', () {
    late Directory root;
    late File marker;
    late List<Directory> folders;
    var keychainCleared = 0;
    Object? keychainFails;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('folio-sifirla-');
      marker = File(p.join(root.path, 'isaret'));
      folders = [
        Directory(p.join(root.path, 'com.erkanoz', 'LifeOS Evrakçı')),
        Directory(p.join(root.path, 'LifeOS', 'LifeOS Folio')),
      ];
      for (final d in folders) {
        await File(p.join(d.path, 'portal', 'oturum.secret'))
            .create(recursive: true);
      }
      keychainCleared = 0;
      keychainFails = null;
      DataReset.marker = () => marker;
      DataReset.folders = () async => folders;
      DataReset.keychain = () async {
        if (keychainFails != null) throw keychainFails!;
        keychainCleared++;
      };
    });
    tearDown(() => root.delete(recursive: true));

    test('everything of Folio\'s goes, the keychain too, and the mark with '
        'it', () async {
      expect(await DataReset.clear(), isTrue);
      for (final d in folders) {
        expect(d.existsSync(), isFalse);
      }
      expect(keychainCleared, 1);
      expect(marker.existsSync(), isFalse);
    });

    test('what could not be cleared is cleared at the next start', () async {
      keychainFails = StateError('kilitli');
      expect(await DataReset.clear(), isFalse);
      expect(marker.existsSync(), isTrue, reason: 'left for the next start');
      keychainFails = null;
      await DataReset.finishPending();
      expect(marker.existsSync(), isFalse);
      expect(keychainCleared, 1);
    });

    test('the next start tries once and never again: what it makes since '
        'is not cleared at the start after', () async {
      keychainFails = StateError('anahtar zinciri yok');
      expect(await DataReset.clear(), isFalse);
      await DataReset.finishPending();
      expect(marker.existsSync(), isFalse, reason: 'tried once');
      // What Folio writes after that start stays at the next.
      await File('${folders.first.path}/yeni.json').create(recursive: true);
      await DataReset.finishPending();
      expect(File('${folders.first.path}/yeni.json').existsSync(), isTrue);
    });

    test('a start with nothing pending clears nothing', () async {
      await DataReset.finishPending();
      for (final d in folders) {
        expect(d.existsSync(), isTrue);
      }
    });
  });
}
