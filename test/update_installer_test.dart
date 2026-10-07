import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:evrak_convert/services/platform/app_directories.dart';
import 'package:evrak_convert/services/update/update_installer.dart';
import 'package:evrak_convert/services/update/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_path_provider.dart';

// A newer Folio is downloaded and held to its signed manifest: its size
// and SHA-256. A package that is not the one signed is never kept.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The binding answers every request with 400; this test has its own
  // server.
  setUpAll(() => HttpOverrides.global = null);
  late HttpServer server;
  late Directory root;
  var body = <int>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('folio-update-');
    useFakePathProvider(root);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      r.response.add(body);
      await r.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  UpdateManifest manifest(List<int> signed, {int? size}) => UpdateManifest(
    platform: 'linux-x64',
    version: '9.9.9',
    build: 999,
    url: Uri.parse(
      'http://127.0.0.1:${server.port}/downloads/LifeOS-Folio-9.9.9.tar.gz',
    ),
    sha256: sha256.convert(signed).toString(),
    size: size ?? signed.length,
    notes: const {'tr': 'Deneme'},
    published: DateTime(2026, 10, 7),
  );

  test(
    'the package signed is downloaded and kept, its progress told',
    () async {
      body = List.generate(300000, (i) => i % 251);
      final seen = <int>[];
      final file = await UpdateInstaller.download(
        manifest(body),
        progress: (done, _) => seen.add(done),
      );
      expect(await file.readAsBytes(), body);
      expect(file.path, endsWith('LifeOS-Folio-9.9.9.tar.gz'));
      expect(seen.last, body.length);
    },
  );

  test(
    'a package that is not the one signed is refused and not kept',
    () async {
      final signed = List.generate(1000, (i) => i % 7);
      body = [...signed]..[10] = 99;
      await expectLater(
        UpdateInstaller.download(manifest(signed)),
        throwsA(isA<StateError>()),
      );
      final left = Directory(
        '${(await folioSupportDirectory()).path}/guncelleme',
      );
      final files = left.existsSync() ? left.listSync() : const [];
      expect(files, isEmpty);
    },
  );

  test('a bigger answer than the manifest says is cut off', () async {
    final signed = List.generate(1000, (i) => i % 7);
    body = [...signed, ...signed];
    await expectLater(
      UpdateInstaller.download(manifest(signed)),
      throwsA(isA<StateError>()),
    );
  });
}
