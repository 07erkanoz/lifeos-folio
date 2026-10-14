import 'dart:io';

import 'package:evrak_convert/services/office/office_chat.dart';
import 'package:evrak_convert/services/office/office_identity.dart';
import 'package:evrak_convert/services/office/office_known.dart';
import 'package:evrak_convert/services/office/office_ledger.dart';
import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/services/office/office_peer.dart';
import 'package:evrak_convert/services/office/office_task.dart';
import 'package:evrak_convert/services/office/task_package.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:evrak_convert/services/sync/hlc.dart';
import 'package:evrak_convert/services/sync/sync_caps.dart';
import 'package:evrak_convert/services/sync/sync_generation.dart';
import 'package:evrak_convert/services/sync/sync_migration.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends SecretStore {
  final kept = <String, Map<String, Object?>>{};
  @override
  Future<bool> write(String name, Map<String, Object?> value) async {
    kept[name] = value;
    return true;
  }

  @override
  Future<Map<String, Object?>?> read(String name) async => kept[name];
}

/// docs/senkron-plan.md §5 step 1: the clock, the generation, the
/// schema's migration and what two Folios say they can do.
void main() {
  group('the clock (R2)', () {
    test('a change made here comes after every change made or seen here, '
        'whatever the computer\'s clock does', () {
      var wall = DateTime.utc(2026, 10, 14, 9);
      final clock = HlcClock(source: 'a:0', now: () => wall);
      final first = clock.tick();
      // The same millisecond, again and again: the counter goes on.
      final second = clock.tick();
      expect(second > first, isTrue);
      expect(second.c, first.c + 1);
      // The clock put back an hour: still after.
      wall = DateTime.utc(2026, 10, 14, 8);
      final third = clock.tick();
      expect(third > second, isTrue);
      expect(third.l, second.l);
      // A device whose clock is a day ahead: seen here, and written after.
      final ahead = Hlc(
        DateTime.utc(2026, 10, 15, 9).millisecondsSinceEpoch,
        4,
        'b:0',
      );
      clock.receive(ahead);
      final fourth = clock.tick();
      expect(fourth > ahead, isTrue);
      expect(fourth.l, ahead.l);
      expect(fourth.c, 6, reason: 'its counter, one for the receiving');
      // Time catches up: the counter starts again.
      wall = DateTime.utc(2026, 10, 16);
      final fifth = clock.tick();
      expect(fifth.c, 0);
      expect(fifth > fourth, isTrue);
    });

    test(
      'receiving takes the larger time and the counter that goes with it',
      () {
        final wall = DateTime.utc(2026, 10, 14, 9);
        final ms = wall.millisecondsSinceEpoch;
        HlcClock at(int l, int c) =>
            HlcClock(source: 'a:0', l: l, c: c, now: () => wall);
        // Both at the same time: the larger counter, and one.
        final both = at(ms + 10, 3)..receive(Hlc(ms + 10, 7, 'b:0'));
        expect((both.last.l, both.last.c), (ms + 10, 8));
        // Only here: here's counter, and one.
        final here = at(ms + 10, 3)..receive(Hlc(ms + 5, 9, 'b:0'));
        expect((here.last.l, here.last.c), (ms + 10, 4));
        // Only there.
        final there = at(ms + 5, 3)..receive(Hlc(ms + 10, 2, 'b:0'));
        expect((there.last.l, there.last.c), (ms + 10, 3));
        // Neither: now, from nought.
        final now = at(ms - 10, 3)..receive(Hlc(ms - 5, 2, 'b:0'));
        expect((now.last.l, now.last.c), (ms, 0));
      },
    );

    test('kept, the clock begins where it was after a restart', () {
      var saved = (0, 0);
      final wall = DateTime.utc(2026, 10, 14, 9);
      final ms = wall.millisecondsSinceEpoch;
      final clock = HlcClock(
        source: 'a:0',
        now: () => wall,
        persist: (l, c) => saved = (l, c),
      )..receive(Hlc(ms + 60000, 2, 'b:0'));
      final made = clock.tick();
      expect(saved, (made.l, made.c));
      final again = HlcClock(
        source: 'a:0',
        l: saved.$1,
        c: saved.$2,
        now: () => wall,
      );
      expect(again.tick() > made, isTrue);
    });

    test('a counter past its width carries into the millisecond: written '
        'and read back in order', () {
      final wall = DateTime.utc(2026, 10, 14, 9);
      final ms = wall.millisecondsSinceEpoch;
      final clock = HlcClock(
        source: 'a:0',
        l: ms,
        c: Hlc.maxCounter,
        now: () => wall,
      );
      final next = clock.tick();
      expect((next.l, next.c), (ms + 1, 0));
      final seen = HlcClock(source: 'a:0', now: () => wall)
        ..receive(Hlc(ms, Hlc.maxCounter, 'b:0'));
      expect((seen.last.l, seen.last.c), (ms + 1, 0));
      expect(Hlc.tryParse('${Hlc(ms, Hlc.maxCounter, 'b:0')}'), isNotNull);
      expect('${Hlc(ms, Hlc.maxCounter, 'b')}'.compareTo('$next') < 0, isTrue);
    });

    test('versions are ordered by time, counter and device, and read back', () {
      const a = Hlc(5, 0, 'b:0'), b = Hlc(5, 1, 'a:0'), c = Hlc(5, 1, 'b:0');
      expect([c, a, b]..sort(), [a, b, c]);
      for (final v in [a, b, c, const Hlc(1760430000000, 12, 'x:3')]) {
        expect(Hlc.tryParse(v.toString()), v);
      }
      // As text in the same order.
      expect(
        ([c, a, b].map((v) => '$v').toList()..sort()),
        [a, b, c].map((v) => '$v').toList(),
      );
      expect(Hlc.tryParse('dün'), isNull);
    });
  });

  group('the old timestamps (R2.1)', () {
    test('a timestamp with no zone is Türkiye\'s time on every device', () {
      expect(
        Hlc.fromLegacy('2026-10-14T10:00:00.000'),
        Hlc(DateTime.utc(2026, 10, 14, 7).millisecondsSinceEpoch, 0, 'goc'),
      );
      // Its microseconds read too, as Folio wrote them.
      expect(
        Hlc.fromLegacy('2026-10-14T10:00:00.123456').l,
        DateTime.utc(2026, 10, 14, 7, 0, 0, 123).millisecondsSinceEpoch,
      );
    });

    test('one with its zone keeps its instant; a missing or broken one is '
        'older than any', () {
      expect(
        Hlc.fromLegacy('2026-10-14T10:00:00Z').l,
        DateTime.utc(2026, 10, 14, 10).millisecondsSinceEpoch,
      );
      expect(
        Hlc.fromLegacy('2026-10-14T10:00:00+01:00').l,
        DateTime.utc(2026, 10, 14, 9).millisecondsSinceEpoch,
      );
      expect(Hlc.fromLegacy(null), const Hlc(0, 0, 'goc'));
      expect(Hlc.fromLegacy('dün öğlen'), const Hlc(0, 0, 'goc'));
      expect(
        Hlc.fromLegacy('') < Hlc.fromLegacy('2020-01-01T00:00:00'),
        isTrue,
      );
    });

    test('two values of the same old time: the same one wins on every '
        'device, whichever came first', () {
      final v = Hlc.fromLegacy('2026-10-14T10:00:00');
      final a = {'tutar': 120, 'tur': 'tahsilat'};
      final b = {'tur': 'tahsilat', 'tutar': 130};
      final ab = Hlc.decide(v, a, v, b), ba = Hlc.decide(v, b, v, a);
      expect(ab, isNot(0));
      expect(ab.sign, -ba.sign);
      // Keys in another order are the same value.
      expect(Hlc.decide(v, {'a': 1, 'b': 2}, v, {'b': 2, 'a': 1}), 0);
      // A later version wins whatever its value.
      expect(Hlc.decide(const Hlc(9, 0, 'x:0'), a, v, b) > 0, isFalse);
      expect(Hlc.decide(Hlc(v.l + 1, 0, 'x:0'), a, v, b) > 0, isTrue);
    });
  });

  group('the generation (R2)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('folio_nesil_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a database put back from a backup taken while Folio ran writes '
        'after every version made before it', () async {
      final path = '${dir.path}/portal.sqlite';
      final outside = File('${dir.path}/senkron-nesil.json');
      var db = PortalDatabase.open(path);
      await SyncGeneration.count(db, outside);
      final wall = DateTime.utc(2026, 10, 14, 9);
      // The backup taken now; then a version made and sent.
      db.backupTo('${dir.path}/yedek.sqlite');
      final sent = SyncGeneration.clockFor(
        db,
        deviceId: 'a',
        now: () => wall,
      ).tick();
      db.dispose();
      File('${dir.path}/yedek.sqlite').copySync(path);
      db = PortalDatabase.open(path);
      await SyncGeneration.count(db, outside);
      // The same moment again: after the one sent, from the bound kept
      // beside the database.
      final after = SyncGeneration.clockFor(
        db,
        deviceId: 'a',
        now: () => wall,
      ).tick();
      expect(after > sent, isTrue);
      db.dispose();
    });

    test('a database behind an opening came back from a backup: a new '
        'generation; the same backup put back twice, another', () async {
      final path = '${dir.path}/portal.sqlite';
      final outside = File('${dir.path}/senkron-nesil.json');
      var db = PortalDatabase.open(path);
      expect((await SyncGeneration.count(db, outside)).generation, 0);
      db.backupTo('${dir.path}/yedek.sqlite');
      expect((await SyncGeneration.count(db, outside)).restored, isFalse);
      db.dispose();
      File('${dir.path}/yedek.sqlite').copySync(path);
      db = PortalDatabase.open(path);
      final back = await SyncGeneration.count(db, outside);
      expect((back.restored, back.generation), (true, 1));
      expect(SyncGeneration.sourceOf(db, 'a'), 'a:1');
      expect((await SyncGeneration.count(db, outside)).generation, 1);
      db.dispose();
      File('${dir.path}/yedek.sqlite').copySync(path);
      db = PortalDatabase.open(path);
      expect((await SyncGeneration.count(db, outside)).generation, 2);
      db.dispose();
    });

    test('the file lost with its copy: not known what came after, so a new '
        'generation with an epoch of its own; two such returns never write '
        'as the same source', () async {
      final path = '${dir.path}/portal.sqlite';
      final outside = File('${dir.path}/senkron-nesil.json');
      var db = PortalDatabase.open(path);
      await SyncGeneration.count(db, outside);
      db.backupTo('${dir.path}/yedek.sqlite');
      db.dispose();
      final sources = <String>{};
      for (var i = 0; i < 2; i++) {
        for (final f in dir.listSync()) {
          if (f.path.contains('senkron-nesil')) f.deleteSync();
        }
        File('${dir.path}/yedek.sqlite').copySync(path);
        db = PortalDatabase.open(path);
        final back = await SyncGeneration.count(db, outside);
        expect(back.restored, isTrue);
        sources.add(SyncGeneration.sourceOf(db, 'a'));
        db.dispose();
      }
      expect(sources, hasLength(2));
    });

    test(
      'a file written half, or not at all, is read from the copy kept of '
      'it; a database never opened, with no file, is generation nought',
      () async {
        final db = PortalDatabase.memory();
        addTearDown(db.dispose);
        final outside = File('${dir.path}/senkron-nesil.json');
        await SyncGeneration.count(db, outside);
        await SyncGeneration.count(db, outside);
        // Cut while written: the file is broken; the one before it stands.
        outside.writeAsStringSync('{"sayac": 9');
        final next = await SyncGeneration.count(db, outside);
        expect(next.restored, isFalse);
        expect(next.generation, 0);
        final fresh = PortalDatabase.memory();
        addTearDown(fresh.dispose);
        final none = File('${dir.path}/yok/senkron-nesil.json');
        final first = await SyncGeneration.count(fresh, none);
        expect((first.generation, first.restored), (0, false));
      },
    );

    test('the bound beside the database is moved on only past it: a minute '
        'of versions writes the file once', () async {
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);
      final outside = File('${dir.path}/senkron-nesil.json');
      await SyncGeneration.count(db, outside);
      var wall = DateTime.utc(2026, 10, 14, 9);
      final clock = SyncGeneration.clockFor(
        db,
        deviceId: 'a',
        outside: outside,
        now: () => wall,
      );
      clock.tick();
      final first = outside.lastModifiedSync();
      final written = outside.readAsStringSync();
      for (var i = 0; i < 50; i++) {
        wall = wall.add(const Duration(milliseconds: 100));
        clock.tick();
      }
      expect(outside.readAsStringSync(), written);
      expect(outside.lastModifiedSync(), first);
      wall = wall.add(const Duration(minutes: 2));
      clock.tick();
      expect(outside.readAsStringSync(), isNot(written));
    });
  });

  group('the migration (R0)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('folio_goc_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('each step once, in order, after a copy is put aside; run again it '
        'does nothing', () {
      final db = PortalDatabase.open('${dir.path}/portal.sqlite');
      addTearDown(db.dispose);
      db.setMeta('eski', 'var');
      final ran = <String>[];
      final steps = [
        SyncMigrationStep(3, 'iki', (db) => ran.add('iki')),
        SyncMigrationStep(2, 'bir', (db) => ran.add('bir')),
      ];
      final backups = Directory('${dir.path}/yedek');
      expect(SyncMigration.run(db, backups: backups, using: steps), isTrue);
      expect(ran, ['bir', 'iki']);
      expect(SyncMigration.schemaOf(db), 3);
      List<FileSystemEntity> sqlite() => [
        for (final f in backups.listSync())
          if (f.path.endsWith('.sqlite')) f,
      ];
      final copies = sqlite();
      expect(copies, hasLength(1));
      // The copy is the database as it was before.
      final copy = PortalDatabase.open(copies.single.path);
      addTearDown(copy.dispose);
      expect(copy.meta('eski'), 'var');
      expect(SyncMigration.schemaOf(copy), 0);
      // Again: nothing runs, no copy is made.
      expect(SyncMigration.run(db, backups: backups, using: steps), isFalse);
      expect(ran, ['bir', 'iki']);
      expect(sqlite(), hasLength(1));
    });

    test('a step that fails leaves the database as it was before it', () {
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);
      expect(
        () => SyncMigration.run(
          db,
          using: [
            SyncMigrationStep(2, 'yarim', (db) {
              db.setMeta('yarim', 'evet');
              throw StateError('kesildi');
            }),
          ],
        ),
        throwsStateError,
      );
      expect(db.meta('yarim'), isNull);
      expect(SyncMigration.schemaOf(db), 0);
      // Run again with the step mended: it completes.
      expect(
        SyncMigration.run(
          db,
          using: [
            SyncMigrationStep(2, 'tam', (db) => db.setMeta('yarim', 'hayir')),
          ],
        ),
        isTrue,
      );
      expect(db.meta('yarim'), 'hayir');
      expect(SyncMigration.schemaOf(db), 2);
    });

    test('with nothing to change, the schema is the base one, and no copy', () {
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);
      final backups = Directory('${dir.path}/yedek');
      expect(SyncMigration.run(db, backups: backups, using: const []), isFalse);
      expect(SyncMigration.schemaOf(db), SyncMigration.base);
      expect(backups.existsSync(), isFalse);
    });
  });

  group('what two Folios say they can do (R0, §4.1)', () {
    test('a part needs of the other only what its format uses here', () {
      final before = SyncCaps.active;
      addTearDown(() => SyncCaps.active = before);
      SyncCaps.active = const {};
      expect(SyncCaps.missing('ajanda', const {}), isEmpty);
      SyncCaps.active = {SyncCaps.hlc, SyncCaps.split};
      expect(SyncCaps.missing('ajanda', const {}), {SyncCaps.hlc});
      expect(SyncCaps.missing('ajanda', {SyncCaps.hlc}), isEmpty);
      // One lacking of several is enough to stop it.
      SyncCaps.active = {SyncCaps.hlc, SyncCaps.fieldVersions};
      expect(SyncCaps.missing('ajanda', {SyncCaps.hlc}), {
        SyncCaps.fieldVersions,
      });
      // A part not in the matrix needs nothing.
      expect(SyncCaps.missing('profil', const {}), isEmpty);
    });

    test('a Folio that says nothing is one from before capabilities', () {
      final old = SyncCaps.of(const {'t': 'senkron'});
      expect(old.protocol, 1);
      expect(old.caps, isEmpty);
      final now = SyncCaps.of(SyncCaps.said);
      expect(now.protocol, SyncCaps.protocol);
      expect(now.caps, SyncCaps.known);
    });

    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('folio_yetenek_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 1500 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(done(), isTrue);
    }

    Future<OfficeNetwork> folio(String name, String device) async {
      final net = OfficeNetwork(
        settings: () async => File('${dir.path}/$device/buro.json'),
        known: KnownDevices(
          file: () async => File('${dir.path}/$device/k.json'),
        ),
        ledger: OfficeLedger(
          file: () async => File('${dir.path}/$device/d.json'),
        ),
        tasks: OfficeTasks(
          file: () async => File('${dir.path}/$device/g.json'),
        ),
        chats: OfficeChats(
          file: () async => File('${dir.path}/$device/m.json'),
        ),
        packages: TaskPackages(
          file: () async => File('${dir.path}/$device/p.json'),
        ),
      );
      final identity = await OfficeIdentity.load(store: _Store());
      await net.listenForTesting(
        identity,
        OfficePeer(
          deviceId: identity.deviceId,
          userId: identity.userId,
          name: name,
          device: device,
          platform: OfficePlatform.linux,
        ),
      );
      return net;
    }

    test(
      'two own devices say what they can do; a part whose format needs '
      'what the other lacks is neither sent nor taken, the others go on',
      () async {
        final before = SyncCaps.active;
        addTearDown(() => SyncCaps.active = before);
        final laptop = await folio('Av. Deniz Yılmaz', 'dizustu');
        final phone = await folio('Av. Deniz Yılmaz', 'telefon');
        laptop.seenForTesting(phone.self!);
        phone.seenForTesting(laptop.self!);
        final asking = laptop.pair(phone.self!)!;
        await until(
          () => phone.incoming.value?.code != null && asking.code != null,
        );
        phone.incoming.value!.confirm();
        asking.confirm();
        await until(() => laptop.self!.userId == phone.self!.userId);
        final kept = <String, Map<String, Object?>>{
          'dizustu': {},
          'telefon': {},
        };
        for (final (net, name) in [(laptop, 'dizustu'), (phone, 'telefon')]) {
          for (final part in ['ajanda', 'profil']) {
            net.ownParts[part] = OwnPart(
              export: () async => {'kimden': name},
              merge: (theirs) async {
                kept[name]![part] = theirs;
                return true;
              },
            );
          }
        }
        laptop.seenForTesting(phone.self!);
        phone.seenForTesting(laptop.self!);
        // Both of this Folio, no format changed: all goes, and each knows
        // what the other can do.
        SyncCaps.active = const {};
        await laptop.syncOwn();
        expect(kept['telefon']!['ajanda'], {'kimden': 'dizustu'});
        expect(kept['dizustu']!['ajanda'], {'kimden': 'telefon'});
        expect(laptop.peerCaps[phone.self!.deviceId], SyncCaps.known);
        expect(phone.peerCaps[laptop.self!.deviceId], SyncCaps.known);
        // The agenda's format needing the clock, the phone a Folio from
        // before: the agenda neither goes nor comes, the profile does, and
        // why is told.
        kept['dizustu']!.clear();
        kept['telefon']!.clear();
        SyncCaps.active = {SyncCaps.hlc};
        phone.actsOldForTesting = true;
        for (var round = 0; round < 2; round++) {
          await laptop.syncOwn();
        }
        expect(kept['dizustu']!.containsKey('ajanda'), isFalse);
        expect(kept['telefon']!.containsKey('ajanda'), isFalse);
        expect(kept['dizustu']!['profil'], {'kimden': 'telefon'});
        expect(kept['telefon']!['profil'], {'kimden': 'dizustu'});
        expect(laptop.stoppedParts[phone.self!.deviceId], {
          'ajanda': {SyncCaps.hlc},
        });
        // The old Folio starting: it sends every part at once, the agenda
        // too; this one takes the profile, not the agenda, and sends back
        // no agenda.
        kept['dizustu']!.clear();
        kept['telefon']!.clear();
        await phone.syncOwn();
        expect(kept['dizustu']!.containsKey('ajanda'), isFalse);
        expect(kept['dizustu']!['profil'], {'kimden': 'telefon'});
        expect(kept['telefon']!.containsKey('ajanda'), isFalse);
        expect(kept['telefon']!['profil'], {'kimden': 'dizustu'});
        // Updated, it is kept alike again.
        phone.actsOldForTesting = false;
        await laptop.syncOwn();
        await laptop.syncOwn();
        expect(kept['telefon']!['ajanda'], {'kimden': 'dizustu'});
        expect(kept['dizustu']!['ajanda'], {'kimden': 'telefon'});
        expect(laptop.stoppedParts[phone.self!.deviceId], isEmpty);
      },
    );

    Future<List<OfficeNetwork>> ownDevices(int n) async {
      final first = await folio('Av. Deniz Yılmaz', 'cihaz0');
      final all = [first];
      for (var i = 1; i < n; i++) {
        final next = await folio('Av. Deniz Yılmaz', 'cihaz$i');
        first.seenForTesting(next.self!);
        next.seenForTesting(first.self!);
        final asking = first.pair(next.self!)!;
        await until(
          () => next.incoming.value?.code != null && asking.code != null,
        );
        next.incoming.value!.confirm();
        asking.confirm();
        await until(() => first.self!.userId == next.self!.userId);
        all.add(next);
      }
      // Each sees each, as the network would show them.
      for (final a in all) {
        for (final b in all) {
          if (!identical(a, b)) a.seenForTesting(b.self!);
        }
      }
      return all;
    }

    test('a load larger than a message goes in pieces, each asked for, and '
        'is taken whole', () async {
      final size = OfficeNetwork.pieceSize;
      addTearDown(() => OfficeNetwork.pieceSize = size);
      OfficeNetwork.pieceSize = 2000;
      final [laptop, phone] = await ownDevices(2);
      // Words that do not pack small: a load of some pieces.
      final big = [for (var i = 0; i < 400; i++) '${i * 7919 % 10007}-$i'];
      Object? came;
      laptop.ownParts['ajanda'] = OwnPart(
        export: () async => {'satirlar': big},
        merge: (_) async => false,
      );
      phone.ownParts['ajanda'] = OwnPart(
        export: () async => {'satirlar': const []},
        merge: (theirs) async {
          came = theirs;
          return true;
        },
      );
      await laptop.syncOwn();
      expect((came as Map?)?['satirlar'], big);
      expect(laptop.synced.containsKey(phone.self!.deviceId), isTrue);
      // And the other way, the answer in pieces.
      came = null;
      Object? back;
      laptop.ownParts['ajanda'] = OwnPart(
        export: () async => {'satirlar': const []},
        merge: (theirs) async {
          back = theirs;
          return true;
        },
      );
      phone.ownParts['ajanda'] = OwnPart(
        export: () async => {'satirlar': big},
        merge: (_) async => false,
      );
      await laptop.syncOwn();
      expect((back as Map?)?['satirlar'], big);
    });

    test('a load too large for one message is not sent to a Folio that cannot '
        'join pieces, and that is not taken for kept alike', () async {
      final size = OfficeNetwork.pieceSize;
      addTearDown(() => OfficeNetwork.pieceSize = size);
      OfficeNetwork.pieceSize = 2000;
      final [laptop, phone] = await ownDevices(2);
      phone.actsOldForTesting = true;
      final big = [for (var i = 0; i < 400; i++) '${i * 7919 % 10007}-$i'];
      Object? came;
      laptop.ownParts['profil'] = OwnPart(
        export: () async => {'satirlar': big},
        merge: (_) async => false,
      );
      phone.ownParts['profil'] = OwnPart(
        export: () async => {'satirlar': const []},
        merge: (theirs) async {
          came = theirs;
          return false;
        },
      );
      await laptop.syncOwn();
      expect(came, isNull);
      expect(laptop.synced.containsKey(phone.self!.deviceId), isFalse);
    });

    test('what one own device takes from another goes on to the third, '
        'without waiting for a change of its own (A→B→C)', () async {
      final [a, b, c] = await ownDevices(3);
      final kept = <OfficeNetwork, List<String>>{a: [], b: [], c: []};
      for (final net in [a, b, c]) {
        net.ownParts['ajanda'] = OwnPart(
          export: () async => {'satirlar': kept[net]},
          merge: (theirs) async {
            final rows = [
              for (final r in ((theirs as Map)['satirlar'] as List)) '$r',
            ];
            final next = {...kept[net]!, ...rows}.toList()..sort();
            if (next.length == kept[net]!.length) return false;
            kept[net] = next;
            return true;
          },
        );
      }
      // A does not reach C: only B is between them.
      a.lostForTesting(c.self!.deviceId);
      expect(a.ownOnline.map((p) => p.deviceId), [b.self!.deviceId]);
      kept[a] = ['itiraz'];
      await a.syncOwn();
      expect(kept[b], ['itiraz']);
      expect(kept[c], isEmpty, reason: 'not from A');
      // B tells C of itself, having taken something new.
      await until(() => kept[c]!.contains('itiraz'));
      // And it stops there: nothing new, nothing sent round.
      expect(kept[a], ['itiraz']);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
