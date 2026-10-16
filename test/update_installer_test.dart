import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:evrak_convert/services/platform/app_directories.dart';
import 'package:evrak_convert/services/update/update_installer.dart';
import 'package:evrak_convert/services/update/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

  _mac();
}

// On a Mac the new .app comes out of the disk image, is held to its code
// signature and its developer, and is copied beside the old one; it takes
// the old one's place once Folio has quit. The system's commands are
// played here by a fake that keeps what it was asked.
void _mac() {
  group('Mac', () {
    late Directory root;
    late String app;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('folio-mac-');
      app = p.join(root.path, 'Applications', 'LifeOS Folio.app');
      await Directory(app).create(recursive: true);
    });
    tearDown(() => root.delete(recursive: true));

    final ok = ProcessResult(0, 0, '', '');
    ProcessResult team(String id) =>
        ProcessResult(0, 0, '', 'Identifier=com.erkanoz\nTeamIdentifier=$id\n');

    /// The commands asked, and a stand-in for each.
    ({
      List<List<String>> asked,
      Future<ProcessResult> Function(String, List<String>) run,
    })
    system({
      bool appInImage = true,
      bool signatureHolds = true,
      String newTeam = 'TEAM123456',
      String oldTeam = 'TEAM123456',
    }) {
      final asked = <List<String>>[];
      Future<ProcessResult> run(String command, List<String> args) async {
        asked.add([command, ...args]);
        if (command == 'hdiutil' && args.first == 'attach') {
          final mount = args[args.indexOf('-mountpoint') + 1];
          await Directory(mount).create(recursive: true);
          if (appInImage) {
            await Directory(p.join(mount, 'LifeOS Folio.app')).create();
          }
          return ok;
        }
        if (command == 'codesign' && args.first == '--verify') {
          return signatureHolds ? ok : ProcessResult(0, 3, '', 'invalid');
        }
        if (command == 'codesign' && args.first == '-dv') {
          return team(args.last == app ? oldTeam : newTeam);
        }
        if (command == 'ditto') {
          await Directory(args.last).create(recursive: true);
        }
        return ok;
      }

      return (asked: asked, run: run);
    }

    test('finds the .app around the program, and only that', () {
      expect(
        UpdateInstaller.macBundleOf(
          '/Applications/LifeOS Folio.app/Contents/MacOS/LifeOS Folio',
        ),
        '/Applications/LifeOS Folio.app',
      );
      expect(
        UpdateInstaller.macBundleOf('/Users/a/folio/build/lifeos_folio'),
        isNull,
      );
    });

    test('reads the developer from codesign, none when signed ad hoc', () {
      expect(
        UpdateInstaller.macTeamOf('Format=app\nTeamIdentifier=ABCDE12345\n'),
        'ABCDE12345',
      );
      expect(UpdateInstaller.macTeamOf('TeamIdentifier=not set\n'), isNull);
      expect(UpdateInstaller.macTeamOf(''), isNull);
    });

    test('replaces in place only where it may write, and not from the '
        'image or a translocated copy', () {
      expect(UpdateInstaller.macReplaceable(app), isTrue);
      expect(
        UpdateInstaller.macReplaceable(
          '/Volumes/LifeOS Folio/LifeOS Folio.app',
        ),
        isFalse,
      );
      expect(
        UpdateInstaller.macReplaceable(
          '/private/var/folders/x/T/AppTranslocation/1234/d/LifeOS Folio.app',
        ),
        isFalse,
      );
      expect(
        UpdateInstaller.macReplaceable(
          p.join(root.path, 'yok', 'LifeOS Folio.app'),
        ),
        isFalse,
      );
      expect(UpdateInstaller.macReplaceable(null), isFalse);
    });

    test('the new .app, checked, is copied beside the old one', () async {
      final s = system();
      final staged = await UpdateInstaller.stageMac(
        File('/tmp/LifeOS-Folio-1.7.1-macOS.dmg'),
        app,
        run: s.run,
      );
      expect(staged, p.join(p.dirname(app), '.LifeOS Folio.app.yeni'));
      expect(Directory(staged).existsSync(), isTrue);
      expect(s.asked.map((c) => '${c[0]} ${c[1]}'), [
        'hdiutil attach',
        'codesign --verify',
        'codesign -dv',
        'codesign -dv',
        'ditto ${s.asked[4][1]}',
        'hdiutil detach',
      ]);
      // From the image, not the old one.
      expect(s.asked[4][1], isNot(app));
      expect(p.basename(s.asked[4][1]), 'LifeOS Folio.app');
    });

    test('a broken signature, another developer or no app is refused, '
        'and the image let go of', () async {
      for (final s in [
        system(signatureHolds: false),
        system(newTeam: 'OTHER99999'),
        system(appInImage: false),
      ]) {
        await expectLater(
          UpdateInstaller.stageMac(File('/tmp/x.dmg'), app, run: s.run),
          throwsA(isA<StateError>()),
        );
        expect(s.asked.where((c) => c[0] == 'ditto'), isEmpty);
        expect(s.asked.last.take(2), ['hdiutil', 'detach']);
      }
      expect(
        Directory(p.join(p.dirname(app), '.LifeOS Folio.app.yeni'))
            .existsSync(),
        isFalse,
      );
    });

    test('an ad hoc Folio takes any validly signed one', () async {
      final s = system(oldTeam: 'not set', newTeam: 'TEAM123456');
      await UpdateInstaller.stageMac(File('/tmp/x.dmg'), app, run: s.run);
      expect(s.asked.where((c) => c[0] == 'ditto'), hasLength(1));
    });

    test(
      'the swap waits for Folio, puts the new one in place and opens it',
      () async {
        final bin = await Directory(p.join(root.path, 'bin')).create();
        final opened = p.join(root.path, 'opened');
        final open = File(p.join(bin.path, 'open'))
          ..writeAsStringSync('#!/bin/sh\necho "\$1" > "$opened"\n');
        await Process.run('chmod', ['+x', open.path]);
        File(p.join(app, 'eski')).writeAsStringSync('1.7.0');
        final staged = p.join(p.dirname(app), '.LifeOS Folio.app.yeni');
        Directory(staged).createSync();
        File(p.join(staged, 'yeni')).writeAsStringSync('1.7.1');
        // A Folio that quits a moment later.
        final folio = await Process.start('sleep', ['1']);
        final swap = await Process.run(
          '/bin/sh',
          [
            '-c',
            UpdateInstaller.macSwapScript,
            'folio-guncelleme',
            '${folio.pid}',
            app,
            staged,
          ],
          environment: {'PATH': '${bin.path}:${Platform.environment['PATH']}'},
        );
        expect(swap.exitCode, 0, reason: '${swap.stderr}');
        expect(File(p.join(app, 'yeni')).existsSync(), isTrue);
        expect(File(p.join(app, 'eski')).existsSync(), isFalse);
        expect(Directory(staged).existsSync(), isFalse);
        expect(
          Directory(p.dirname(app)).listSync().map((e) => p.basename(e.path)),
          ['LifeOS Folio.app'],
        );
        expect(File(opened).readAsStringSync().trim(), app);
      },
      skip: Platform.isWindows ? 'a POSIX sh is needed' : false,
    );
  });
}
