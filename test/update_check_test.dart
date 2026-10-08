import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:evrak_convert/services/update/update_check.dart';
import 'package:evrak_convert/services/update/update_manifest.dart';
import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A key made for these tests only; Folio's real one signs nothing here.
final seed = List<int>.generate(32, (i) => i * 7 + 3);

Future<List<int>> publicKey() async =>
    (await (await Ed25519().newKeyPairFromSeed(seed)).extractPublicKey()).bytes;

Map<String, dynamic> body({
  int build = 5,
  String platform = 'linux-x64',
  String url =
      'https://lifeos.com.tr/downloads/LifeOS-Folio-1.2.0-linux-x64.tar.gz',
}) => {
  'schema': 1,
  'product': 'folio',
  'channel': 'stable',
  'platform': platform,
  'version': '1.2.0',
  'build': build,
  'url': url,
  'sha256': 'a' * 64,
  'size': 123456,
  'notes': {'tr': 'Güncelleme bildirimi.', 'en': 'Update notice.'},
  'published': '2026-09-29T15:00:00Z',
};

Future<String> signed(Map<String, dynamic> b) async =>
    jsonEncode(await UpdateManifest.sign(b, seed));

void main() {
  test('canonical JSON sorts keys at every level, whatever the order', () {
    expect(
      UpdateManifest.canonical({
        'b': 1,
        'a': {'y': true, 'x': 'ş'},
      }),
      '{"a":{"x":"ş","y":true},"b":1}',
    );
  });

  test('a signed manifest is read back', () async {
    final m = await UpdateManifest.verify(
      await signed(body()),
      platform: 'linux-x64',
      key: await publicKey(),
    );
    expect(m.version, '1.2.0');
    expect(m.build, 5);
    expect(m.notes['tr'], 'Güncelleme bildirimi.');
  });

  test('a manifest changed after signing is refused', () async {
    final json = jsonDecode(await signed(body())) as Map<String, dynamic>;
    json['url'] = 'https://lifeos.com.tr/downloads/baska.tar.gz';
    await expectLater(
      UpdateManifest.verify(
        jsonEncode(json),
        platform: 'linux-x64',
        key: await publicKey(),
      ),
      throwsFormatException,
    );
  });

  test(
    'an unsigned manifest, or one signed by another key, is refused',
    () async {
      await expectLater(
        UpdateManifest.verify(
          jsonEncode(body()),
          platform: 'linux-x64',
          key: await publicKey(),
        ),
        throwsFormatException,
      );
      // Folio's real public key did not sign this.
      await expectLater(
        UpdateManifest.verify(await signed(body()), platform: 'linux-x64'),
        throwsFormatException,
      );
    },
  );

  test('another platform\'s manifest or a file elsewhere is refused', () async {
    final key = await publicKey();
    await expectLater(
      UpdateManifest.verify(
        await signed(body(platform: 'windows-x64')),
        platform: 'linux-x64',
        key: key,
      ),
      throwsFormatException,
    );
    for (final url in [
      'http://lifeos.com.tr/downloads/folio.tar.gz',
      'https://example.com/downloads/folio.tar.gz',
      'https://lifeos.com.tr/baska/folio.tar.gz',
    ]) {
      await expectLater(
        UpdateManifest.verify(
          await signed(body(url: url)),
          platform: 'linux-x64',
          key: key,
        ),
        throwsFormatException,
        reason: url,
      );
    }
  });

  _bannerTest();

  group('the check', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('folio-update-'));
    tearDown(() => dir.deleteSync(recursive: true));

    UpdateCheck check(String? manifest, {int installed = 4}) => UpdateCheck(
      fetch: (_) async => manifest,
      currentBuild: () async => installed,
      settings: () async => File('${dir.path}/update.json'),
      platform: 'linux-x64',
      key: seedKey,
    );

    test('offers a newer build, not the same or an older one', () async {
      seedKey = await publicKey();
      final manifest = await signed(body(build: 5));
      expect((await check(manifest, installed: 4).check())?.build, 5);
      expect(await check(manifest, installed: 5).check(), isNull);
      expect(await check(manifest, installed: 6).check(), isNull);
    });

    test('a release put off is offered again at the next check', () async {
      seedKey = await publicKey();
      final first = check(await signed(body(build: 5)));
      expect(await first.check(), isNotNull);
      first.later();
      expect(first.available.value, isNull);
      expect(first.ready.value?.build, 5);
      expect((await check(await signed(body(build: 5))).check())?.build, 5);
    });

    test('nothing published, or nothing readable, is quiet', () async {
      seedKey = await publicKey();
      expect(await check(null).check(), isNull);
      expect(await check('<html>').check(), isNull);
    });
  });
}

void _bannerTest() {
  testWidgets('a newer release shows across the top until put off', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-update-ui-'),
    ))!;
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    final theme = ThemeController(
      settingsPath: '${dir.path}/appearance.json',
      mode: ThemeMode.light,
    );
    await tester.runAsync(library.initialize);
    await tester.pumpWidget(
      EvrakConvertApp(library: library, appearance: theme),
    );
    await tester.pump();
    final manifest = UpdateManifest(
      platform: 'linux-x64',
      version: '1.2.0',
      build: 5,
      url: Uri.parse('https://lifeos.com.tr/downloads/folio.tar.gz'),
      sha256: 'a' * 64,
      size: 1,
      notes: const {'tr': 'Güncelleme bildirimi eklendi.'},
      published: DateTime(2026, 9, 29),
    );
    UpdateCheck.instance.ready.value = manifest;
    UpdateCheck.instance.available.value = manifest;
    await tester.pumpAndSettle();
    // A card at the window's foot, not a strip across its top.
    expect(find.byKey(const ValueKey('update-card')), findsOneWidget);
    expect(find.text('LifeOS Folio 1.2.0 hazır'), findsOneWidget);
    expect(find.text('Güncelleme bildirimi eklendi.'), findsOneWidget);
    await tester.tap(find.text('Sonra'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('update-card')), findsNothing);
    // Still there, at the top of the settings.
    expect(UpdateCheck.instance.ready.value, manifest);
    UpdateCheck.instance.ready.value = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      library.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await dir.delete(recursive: true);
    });
    theme.dispose();
  });
}

List<int>? seedKey;
