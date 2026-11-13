import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:evrak_convert/services/live/live_remote.dart';
import 'package:evrak_convert/services/office/office_chat.dart';
import 'package:evrak_convert/services/office/office_identity.dart';
import 'package:evrak_convert/services/office/office_known.dart';
import 'package:evrak_convert/services/office/office_ledger.dart';
import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/services/office/office_peer.dart';
import 'package:evrak_convert/services/office/office_task.dart';
import 'package:evrak_convert/services/office/task_package.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/canli_relay/relay.dart';

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

// Senkron between the person's own devices on different networks: they
// meet in a room of the relay, prove themselves with their device keys as
// on the network, and are kept alike; the relay carries what it cannot
// open and stops at the person's quota.
void main() {
  late Directory dir;
  late RelayServer relay;
  final server = LiveRelay.server;

  setUp(() async {
    HttpOverrides.global = null;
    dir = Directory.systemTemp.createTempSync('folio_uzak_senkron_');
  });
  tearDown(() async {
    await relay.close();
    LiveRelay.server = server;
    dir.deleteSync(recursive: true);
  });

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 1500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  Future<OfficeNetwork> folio(String device) async {
    File f(String n) => File('${dir.path}/$device/$n');
    final net = OfficeNetwork(
      settings: () async => f('buro.json'),
      known: KnownDevices(file: () async => f('k.json')),
      ledger: OfficeLedger(file: () async => f('d.json')),
      tasks: OfficeTasks(file: () async => f('g.json')),
      chats: OfficeChats(file: () async => f('m.json')),
      packages: TaskPackages(file: () async => f('p.json')),
    );
    final identity = await OfficeIdentity.load(store: _Store());
    await net.listenForTesting(
      identity,
      OfficePeer(
        deviceId: identity.deviceId,
        userId: identity.userId,
        name: 'Av. Deniz Yılmaz',
        device: device,
        platform: OfficePlatform.linux,
      ),
    );
    return net;
  }

  /// A computer and a phone of one person, known to each other (as once
  /// on the office's network).
  Future<(OfficeNetwork, OfficeNetwork)> ownPair() async {
    final pc = await folio('bilgisayar'), phone = await folio('telefon');
    pc.seenForTesting(phone.self!);
    phone.seenForTesting(pc.self!);
    final asking = pc.pair(phone.self!)!;
    await until(
      () => phone.incoming.value?.code != null && asking.code != null,
    );
    phone.incoming.value!.confirm();
    asking.confirm();
    await until(() => pc.self!.userId == phone.self!.userId);
    return (pc, phone);
  }

  Future<String> roomOf(OfficeNetwork a, OfficeNetwork b) async {
    final pair = [a.self!.deviceId, b.self!.deviceId]..sort();
    return (await a.ownTag('oda|${pair[0]}|${pair[1]}'))!;
  }

  Future<RelayWire> meet(
    OfficeNetwork waiter,
    OfficeNetwork comer, {
    required String person,
    Completer<bool>? answered,
  }) async {
    final room = await roomOf(waiter, comer);
    final waiting = await RelayWire.connect(room, 'paylasan', person: person);
    final coming = await RelayWire.connect(room, 'katilan', person: person);
    expect((await waiting.next(const Duration(seconds: 5)))?['t'], 'katilan');
    unawaited(
      waiter.answerOwnOver(waiting, comer.self!.deviceId).then((ok) {
        answered?.complete(ok);
      }),
    );
    return coming;
  }

  test('two own devices on different networks are kept alike over the '
      'relay, proving themselves as on the network', () async {
    relay = await RelayServer.start();
    LiveRelay.server = Uri.parse('ws://127.0.0.1:${relay.port}');
    final (pc, phone) = await ownPair();
    final kept = <String, Object?>{};
    pc.ownParts['ajanda'] = OwnPart(
      export: () async => {'kimden': 'bilgisayar'},
      merge: (theirs) async {
        kept['bilgisayar'] = theirs;
        return true;
      },
    );
    phone.ownParts['ajanda'] = OwnPart(
      export: () async => {'kimden': 'telefon'},
      merge: (theirs) async {
        kept['telefon'] = theirs;
        return true;
      },
    );
    // The person's tags, made with their private key: alike on their own
    // devices, unlike anyone else's.
    final person = (await pc.ownTag('kota'))!;
    expect(person, await phone.ownTag('kota'));
    expect(person, hasLength(43));
    expect(await roomOf(pc, phone), await roomOf(phone, pc));
    final stranger = await folio('yabanci');
    expect(await stranger.ownTag('kota'), isNot(person));
    final answered = Completer<bool>();
    final coming = await meet(pc, phone, person: person, answered: answered);
    expect(await phone.syncOwnOver(coming, pc.self!.deviceId), isTrue);
    expect(await answered.future, isTrue);
    await until(() => kept['bilgisayar'] != null);
    expect(kept['telefon'], {'kimden': 'bilgisayar'});
    expect(kept['bilgisayar'], {'kimden': 'telefon'});
    expect(phone.synced.containsKey(pc.self!.deviceId), isTrue);
  });

  test('a device that is not the person\'s is not let in, though it '
      'finds the room', () async {
    relay = await RelayServer.start();
    LiveRelay.server = Uri.parse('ws://127.0.0.1:${relay.port}');
    final (pc, phone) = await ownPair();
    final stranger = await folio('yabanci');
    var given = false;
    pc.ownParts['ajanda'] = OwnPart(
      export: () async {
        given = true;
        return {'gizli': true};
      },
      merge: (_) async => false,
    );
    stranger.ownParts['ajanda'] = OwnPart(
      export: () async => const {},
      merge: (_) async => true,
    );
    final person = (await pc.ownTag('kota'))!;
    final room = await roomOf(pc, phone);
    final waiting = await RelayWire.connect(room, 'paylasan', person: person);
    final coming = await RelayWire.connect(room, 'katilan', person: person);
    await waiting.next(const Duration(seconds: 5));
    final answered = pc.answerOwnOver(waiting, phone.self!.deviceId);
    // Not the device the room is for: turned away, whatever it is.
    expect(await stranger.syncOwnOver(coming, pc.self!.deviceId), isFalse);
    expect(await answered, isFalse);
    expect(given, isFalse);
  });

  test('the person quota: past it the room is closed and the door '
      'says so', () async {
    relay = await RelayServer.start(limits: const RelayLimits(personDay: 3000));
    LiveRelay.server = Uri.parse('ws://127.0.0.1:${relay.port}');
    final (pc, phone) = await ownPair();
    for (final net in [pc, phone]) {
      net.ownParts['ajanda'] = OwnPart(
        // What does not pack small: random bytes.
        export: () async => {
          'veri': base64Encode(
            List.generate(20000, (_) => Random.secure().nextInt(256)),
          ),
        },
        merge: (_) async => true,
      );
    }
    final person = (await pc.ownTag('kota'))!;
    final coming = await meet(pc, phone, person: person);
    expect(await phone.syncOwnOver(coming, pc.self!.deviceId), isFalse);
    expect(coming.closeCode, 4429);
    // The next try is turned away at the door, as a quota (429).
    await expectLater(
      RelayWire.connect(await roomOf(pc, phone), 'paylasan', person: person),
      throwsA(predicate((e) => '$e'.contains('429'))),
    );
  });

  test('a word held for whoever listens next: one that takes the first '
      'and stops leaves the second', () async {
    relay = await RelayServer.start();
    LiveRelay.server = Uri.parse('ws://127.0.0.1:${relay.port}');
    final room = 'a' * 43;
    final waiting = await RelayWire.connect(room, 'paylasan');
    final coming = await RelayWire.connect(room, 'katilan');
    await waiting.next(const Duration(seconds: 5));
    coming
      ..send({'n': 1})
      ..send({'n': 2});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect((await waiting.messages.first)['n'], 1);
    expect((await waiting.messages.first)['n'], 2);
    await waiting.close();
    await coming.close();
  });

  test('an address\'s day counts in every room, live documents\' too; '
      'the relay full is told apart from a quota', () async {
    relay = await RelayServer.start(
      limits: const RelayLimits(addressDay: 1000, perAddress: 2),
    );
    LiveRelay.server = Uri.parse('ws://127.0.0.1:${relay.port}');
    final room = 'b' * 43;
    final waiting = await RelayWire.connect(room, 'paylasan');
    final coming = await RelayWire.connect(room, 'katilan');
    await waiting.next(const Duration(seconds: 5));
    // Two sockets from this address: a third is the relay full (503).
    await expectLater(
      RelayWire.connect('c' * 43, 'paylasan'),
      throwsA(predicate((e) => '$e'.contains('503'))),
    );
    coming.send({'veri': 'x' * 2000});
    await coming.done;
    expect(coming.closeCode, 4429);
    await waiting.close();
    await expectLater(
      RelayWire.connect('d' * 43, 'paylasan'),
      throwsA(predicate((e) => '$e'.contains('429'))),
    );
  });

  test('an address brings ten new tags a day; one seen this month is let '
      'in still', () async {
    relay = await RelayServer.start();
    LiveRelay.server = Uri.parse('ws://127.0.0.1:${relay.port}');
    String tag(int i) => '$i'.padLeft(43, 'k');
    final open = <RelayWire>[];
    for (var i = 0; i < 10; i++) {
      final w = await RelayWire.connect(tag(i) * 1, 'paylasan', person: tag(i));
      open.add(w);
      await w.close();
    }
    await expectLater(
      RelayWire.connect('e' * 43, 'paylasan', person: tag(10)),
      throwsA(predicate((e) => '$e'.contains('429'))),
    );
    final again = await RelayWire.connect('f' * 43, 'paylasan', person: tag(3));
    expect(again.closed, isFalse);
    await again.close();
  });
}
