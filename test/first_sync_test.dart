import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/sync/own_sync.dart';
import 'package:evrak_convert/services/sync/settings_sync.dart';
import 'package:evrak_convert/ui/sync/first_sync.dart';

void main() {
  group('settings kept alike', () {
    late Directory dir;
    late SettingsSync sync;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('folio-settings-sync-');
      sync = SettingsSync(folder: () async => dir);
      SettingsSync.receiveOnly = false;
    });
    tearDown(() {
      SettingsSync.receiveOnly = false;
      dir.deleteSync(recursive: true);
    });

    File file(String name) => File('${dir.path}/$name');

    Map<String, Object?> theirs(String name, String json, DateTime at) => {
      name: {'at': at.toUtc().toIso8601String(), 'json': json},
    };

    test('the newer copy is kept, written with its time so that it is not '
        'sent back as new', () async {
      final old = DateTime(2026, 10, 1, 9);
      file('kaliplar.json')
        ..writeAsStringSync('[]')
        ..setLastModifiedSync(old);
      final at = DateTime(2026, 10, 12, 18);
      expect(
        await sync.merge(
          theirs('kaliplar.json', '[{"ad":"vekalet"}]', at),
          SettingsSync.settings,
        ),
        isTrue,
      );
      expect(file('kaliplar.json').readAsStringSync(), '[{"ad":"vekalet"}]');
      final out = await sync.export(SettingsSync.settings);
      expect(
        DateTime.parse('${(out['kaliplar.json'] as Map)['at']}'),
        at.toUtc(),
      );
      // The same again: nothing to write.
      expect(
        await sync.merge(
          theirs('kaliplar.json', '[{"ad":"vekalet"}]', at),
          SettingsSync.settings,
        ),
        isFalse,
      );
    });

    test('an older copy, a broken one and a file not of the part are left '
        'alone', () async {
      file('hukuk.json')
        ..writeAsStringSync('{"maddeler":true}')
        ..setLastModifiedSync(DateTime(2026, 10, 12));
      expect(
        await sync.merge({
          ...theirs('hukuk.json', '{"maddeler":false}', DateTime(2026, 9, 1)),
          ...theirs('editor.json', '{bozuk', DateTime(2026, 10, 13)),
          ...theirs('kilit.json', '{"pin":"1"}', DateTime(2026, 10, 13)),
        }, SettingsSync.settings),
        isFalse,
      );
      expect(file('hukuk.json').readAsStringSync(), '{"maddeler":true}');
      expect(file('editor.json').existsSync(), isFalse);
      expect(file('kilit.json').existsSync(), isFalse);
    });

    test('a device being set up gives nothing and takes what its computer '
        'has, though its own defaults are newer', () async {
      file('kaliplar.json')
        ..writeAsStringSync('[]')
        ..setLastModifiedSync(DateTime.now());
      SettingsSync.receiveOnly = true;
      expect(await sync.export(SettingsSync.settings), isEmpty);
      expect(
        await sync.merge(
          theirs('kaliplar.json', '[{"ad":"ihtarname"}]', DateTime(2025, 1, 1)),
          SettingsSync.settings,
        ),
        isTrue,
      );
      expect(file('kaliplar.json').readAsStringSync(), '[{"ad":"ihtarname"}]');
    });
  });

  testWidgets('the first sync shows each part as it comes, then Hazır', (
    tester,
  ) async {
    final events = StreamController<({String part, bool done})>.broadcast();
    addTearDown(events.close);
    final run = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FirstSyncDialog(events: events.stream, run: () => run.future),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Bilgisayarınızdan alınıyor'), findsOneWidget);
    expect(SettingsSync.receiveOnly, isTrue);
    events.add((part: OwnSync.profilePart, done: false));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    events.add((part: OwnSync.profilePart, done: true));
    events.add((part: OwnSync.agenda, done: true));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('first-sync-profil-done')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('first-sync-ajanda-done')),
      findsOneWidget,
    );
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('first-sync-progress')),
    );
    expect(bar.value, closeTo(2 / FirstSyncDialog.parts.length, .001));
    final done = tester.widget<FilledButton>(
      find.byKey(const ValueKey('first-sync-done')),
    );
    expect(done.onPressed, isNull);
    run.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Hazır'), findsOneWidget);
    expect(SettingsSync.receiveOnly, isFalse);
    // What the computer did not send is said, not waited for.
    expect(find.text('yok'), findsNWidgets(FirstSyncDialog.parts.length - 2));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('first-sync-done')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('nothing came: the computer was not reached, and it can be '
      'tried again', (tester) async {
    var runs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FirstSyncDialog(
            events: const Stream.empty(),
            run: () async => runs++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Bilgisayara ulaşılamadı'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('first-sync-retry')));
    await tester.pump();
    await tester.pump();
    expect(runs, 2);
  });

  testWidgets('once alike, the computer\'s documents are offered with their '
      'count and size, and asked for on a press', (tester) async {
    var asked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FirstSyncDialog(
            events: Stream.value((part: OwnSync.uyapData, done: true)),
            run: () async {},
            documents: () async => (count: 214, bytes: 350 << 20),
            takeDocuments: () async {
              asked++;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining('indirilmiş 214 evrak var (350 MB)'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('first-sync-take-documents')));
    await tester.pump();
    await tester.pump();
    expect(asked, 1);
    expect(find.textContaining('Evraklar geliyor'), findsOneWidget);
  });
}
