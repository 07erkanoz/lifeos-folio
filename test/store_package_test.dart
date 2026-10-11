import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:evrak_convert/services/platform/app_directories.dart';
import 'package:evrak_convert/services/platform/store_package.dart';
import 'package:evrak_convert/services/update/update_check.dart';
import 'package:evrak_convert/services/update/update_installer.dart';
import 'package:evrak_convert/services/update/update_manifest.dart';

void main() {
  tearDown(() => debugRunsFromStorePackage = null);

  test('only Windows has Store packages', () {
    if (!Platform.isWindows) expect(runsFromStorePackage, isFalse);
  });

  test('a Store package neither looks for nor installs updates', () {
    debugRunsFromStorePackage = true;
    expect(UpdateCheck.platformName, isNull);
    expect(UpdateInstaller.canInstall, isFalse);
  });

  test('a Store package refuses to download or install an update before '
      'touching a file, the network or a process', () async {
    debugRunsFromStorePackage = true;
    final manifest = UpdateManifest(
      platform: 'windows-x64',
      version: '9.9.9',
      build: 999,
      url: Uri.parse('https://lifeos.com.tr/downloads/x.exe'),
      sha256: '00',
      size: 1,
      notes: const {},
      published: DateTime(2026),
    );
    await expectLater(UpdateInstaller.download(manifest), throwsStateError);
    await expectLater(
      UpdateInstaller.install(File('yok.exe'), restart: () async {}),
      throwsStateError,
    );
  });

  test('a Store package keeps its data in the user folder, outside AppData '
      'and OneDrive', () {
    final folder = storeDataFolder(r'C:\Users\avukat');
    expect(folder, p.windows.join(r'C:\Users\avukat', 'LifeOS Folio'));
    expect(folder.toLowerCase(), isNot(contains('appdata')));
    expect(folder.toLowerCase(), isNot(contains('onedrive')));
  });
}
