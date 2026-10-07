import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:evrak_convert/services/office/office_chat.dart';
import 'package:evrak_convert/services/office/office_identity.dart';
import 'package:evrak_convert/services/office/office_known.dart';
import 'package:evrak_convert/services/office/office_ledger.dart';
import 'package:evrak_convert/services/office/office_link.dart';
import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/services/office/office_peer.dart';
import 'package:evrak_convert/services/office/office_task.dart';
import 'package:evrak_convert/services/office/office_transfer.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
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

/// Two known Folios on loopback sending files to each other, encrypted.
void main() {
  late Directory dir;
  late OfficeNetwork a, b;

  Future<OfficeNetwork> folio(String name, String device) async {
    final net = OfficeNetwork(
      settings: () async => File('${dir.path}/$device/buro.json'),
      known: KnownDevices(file: () async => File('${dir.path}/$device/k.json')),
      ledger: OfficeLedger(
        file: () async => File('${dir.path}/$device/d.json'),
      ),
      tasks: OfficeTasks(file: () async => File('${dir.path}/$device/g.json')),
      chats: OfficeChats(file: () async => File('${dir.path}/$device/m.json')),
    );
    Directory('${dir.path}/$device/gelen').createSync(recursive: true);
    net.inbox = () async => Directory('${dir.path}/$device/gelen');
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

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  File file(String name, int size, {int seed = 1}) {
    final r = Random(seed);
    return File('${dir.path}/$name')
      ..writeAsBytesSync([for (var i = 0; i < size; i++) r.nextInt(256)]);
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('folio_send_');
    a = await folio('Av. Deniz Kaya', 'deniz-pc');
    b = await folio('Av. Mert Yıldız', 'mert-pc');
    final asking = a.pair(b.self!)!;
    await until(() => b.incoming.value?.code != null);
    b.incoming.value!.confirm();
    asking.confirm();
    await until(
      () => a.isKnown(b.self!.deviceId) && b.isKnown(a.self!.deviceId),
    );
    a.seenForTesting(b.self!);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('files go in pieces, sealed, and come whole', () async {
    // Larger than the window of pieces, and an empty one.
    final big = file('Bilirkişi Raporu.pdf', 900 * 1024);
    final small = file('not.txt', 0);
    final t = (await a.send(b.self!, [
      big.path,
      small.path,
    ], note: 'bakar mısın'))!;
    await until(() => b.incomingOffer.value != null);
    final offer = b.incomingOffer.value!;
    expect(offer.note, 'bakar mısın');
    expect(offer.files.map((f) => f.name), ['Bilirkişi Raporu.pdf', 'not.txt']);
    expect(offer.peer.name, 'Av. Deniz Kaya');
    await b.acceptOffer(offer);
    await until(() => t.state == TransferState.done);
    await until(() => offer.state == TransferState.done);
    expect(offer.saved, hasLength(2));
    expect(File(offer.saved.first).readAsBytesSync(), big.readAsBytesSync());
    expect(t.moved, t.total);
    // Recorded on both sides.
    await until(
      () => File('${dir.path}/mert-pc/buro_aktarimlar.json').existsSync(),
    );
    final log = jsonDecode(
      File('${dir.path}/mert-pc/buro_aktarimlar.json').readAsStringSync(),
    ) as List;
    expect((log.first as Map)['durum'], 'done');
  });

  test('declined, nothing is written', () async {
    final t = (await a.send(b.self!, [file('x.udf', 1000).path]))!;
    await until(() => b.incomingOffer.value != null);
    await b.incomingOffer.value!.decline();
    await until(() => t.state == TransferState.declined);
    expect(Directory('${dir.path}/mert-pc/gelen').listSync(), isEmpty);
  });

  test('cut off, it goes on from where it was', () async {
    final big = file('Dosya.pdf', 300 * 1024, seed: 7);
    final id = OfficeTransfer.newId();
    // What came before the line was cut.
    final parts = Directory('${dir.path}/mert-pc/gelen/.folio-parca')
      ..createSync(recursive: true);
    File('${parts.path}/$id-0.part')
        .writeAsBytesSync(big.readAsBytesSync().sublist(0, 200 * 1024));
    final t = (await a.send(b.self!, [big.path], id: id))!;
    await until(() => b.incomingOffer.value != null);
    final offer = b.incomingOffer.value!;
    await b.acceptOffer(offer);
    await until(() => offer.state == TransferState.done);
    await until(() => t.state == TransferState.done);
    expect(File(offer.saved.single).readAsBytesSync(), big.readAsBytesSync());
    // Only the rest was sent.
    expect(t.moved, t.total);
  });

  test('a device not known cannot even open a talk', () async {
    final stranger = await OfficeIdentity.load(store: _Store());
    final link = await OfficeLink.connect('127.0.0.1', b.self!.port);
    link.send({
      't': 'hello',
      'id': stranger.deviceId,
      'eph': base64Encode(List.filled(32, 1)),
      'sig': base64Encode(List.filled(64, 0)),
    });
    await until(() => link.closed);
    expect(b.incomingOffer.value, isNull);
  });

  test('a file whose name holds a folder is put under its name alone', () {
    final f = TransferFile.fromJson({'n': '../../.bashrc', 's': 3, 'h': 'x'})!;
    expect(f.name, '.bashrc');
    expect(TransferFile.fromJson({'n': '..', 's': 3, 'h': 'x'}), isNull);
  });

  test('members an office took in talk to each other unpaired', () async {
    final c = await folio('Av. Selin Aksoy', 'selin-pc');
    final asking = a.pair(c.self!)!;
    await until(() => c.incoming.value?.code != null);
    c.incoming.value!.confirm();
    asking.confirm();
    await until(() => a.isKnown(c.self!.deviceId));
    a.seenForTesting(c.self!);
    expect(await a.foundOffice('Kaya Hukuk Bürosu'), isNull);
    expect(await a.admit(b.self!.deviceId, OfficeRole.trainee), isNull);
    expect(await a.admit(c.self!.deviceId, OfficeRole.lawyer), isNull);
    // The ledger went to both.
    await until(
      () => b.ledger.members.length == 3 && c.ledger.members.length == 3,
    );
    expect(b.ledger.officeName, 'Kaya Hukuk Bürosu');
    expect(c.ledger.member(b.self!.deviceId)!.role, OfficeRole.trainee);
    // A trainee cannot change roles.
    expect(await b.setRole(b.self!.deviceId, OfficeRole.manager), isNotNull);
    // B and C never met by a code, yet a file goes between them.
    b.seenForTesting(c.self!);
    final t = (await b.send(c.self!, [file('Tanık listesi.udf', 5000).path]))!;
    await until(() => c.incomingOffer.value != null);
    await c.acceptOffer(c.incomingOffer.value!);
    await until(() => t.state == TransferState.done);
  });

  test(
    'a task goes from the giver to the trainee and back, stage by stage',
    () async {
      b.seenForTesting(a.self!);
      await a.foundOffice('Kaya Hukuk Bürosu');
      await a.admit(b.self!.deviceId, OfficeRole.trainee);
      await until(() => b.ledger.members.length == 2);
      // A trainee gives no task.
      expect(b.mayGive(a.self!.deviceId), isFalse);
      final item = TaskItem.create(
        'İtiraz dilekçesini hazırla',
        assignee: b.self!.deviceId,
      );
      final given = await a.giveTask(
        title: 'Bilirkişi raporuna itiraz',
        to: [b.self!.deviceId],
        due: DateTime.now().add(const Duration(days: 2)),
        cases: [
          TaskCase(
            caseKey: 'k1',
            number: '2024/318',
            court: 'Antalya 3. Asliye Hukuk',
            items: [item],
          ),
        ],
      );
      expect(given, isNull);
      await until(() => b.tasks.all.isNotEmpty);
      final mine = b.tasks.all.single;
      expect(mine.supervisor, 'Av. Deniz Kaya');
      expect(mine.daysLeft(DateTime.now()), 2);
      OfficeTask theirs() => a.tasks.all.single;
      await b.act(mine, TaskEventKind.accepted);
      await b.act(mine, TaskEventKind.itemDone, itemId: item.id);
      await until(
        () => theirs().percent == 100 && theirs().stage == TaskStage.running,
      );
      await b.act(mine, TaskEventKind.message, text: 'Taslak hazır.');
      await b.act(mine, TaskEventKind.delivered, text: 'Dilekçe imzaya hazır.');
      await until(() => theirs().stage == TaskStage.review);
      // Sent back needs a reason; then it is running again.
      expect(await a.act(theirs(), TaskEventKind.returned), isNotNull);
      await a.act(
        theirs(),
        TaskEventKind.returned,
        text: 'Faiz başlangıcını düzelt.',
      );
      await until(() => b.tasks.all.single.stage == TaskStage.running);
      await b.act(
        b.tasks.all.single,
        TaskEventKind.delivered,
        text: 'Düzelttim.',
      );
      await until(() => theirs().stage == TaskStage.review);
      // Only the giver approves.
      expect(
        await b.act(b.tasks.all.single, TaskEventKind.approved),
        isNotNull,
      );
      await a.act(theirs(), TaskEventKind.approved);
      await until(() => b.tasks.all.single.stage == TaskStage.done);
      expect(
        b.tasks.all.single.timeline.where((e) => e.isTalk).single.text,
        'Taslak hazır.',
      );
    },
  );

  test('private, group and broadcast talk, with a file, sealed', () async {
    final c = await folio('Av. Selin Aksoy', 'selin-pc');
    final asking = a.pair(c.self!)!;
    await until(() => c.incoming.value?.code != null);
    c.incoming.value!.confirm();
    asking.confirm();
    await until(() => a.isKnown(c.self!.deviceId));
    for (final n in [a, b, c]) {
      for (final o in [a, b, c]) {
        if (n != o) n.seenForTesting(o.self!);
      }
    }
    await a.foundOffice('Kaya Hukuk Bürosu');
    await a.admit(b.self!.deviceId, OfficeRole.trainee);
    await a.admit(c.self!.deviceId, OfficeRole.lawyer);
    await until(
      () => b.ledger.members.length == 3 && c.ledger.members.length == 3,
    );
    // Private, with a file.
    final mine = (await a.privateChat(b.self!.deviceId))!;
    final doc = file('Ara Karar.pdf', 70 * 1024);
    expect(
      await a.post(mine, text: 'Şuna bakar mısın?', files: [doc.path]),
      isNull,
    );
    await until(() => b.chats.of(mine.id)?.messages.isNotEmpty ?? false);
    final got = b.chats.of(mine.id)!.messages.single;
    expect(got.text, 'Şuna bakar mısın?');
    expect(got.attachments.single.name, 'Ara Karar.pdf');
    await until(() => b.chats.fileOf(got.id, 'Ara Karar.pdf') != null);
    expect(
      File(b.chats.fileOf(got.id, 'Ara Karar.pdf')!).readAsBytesSync(),
      doc.readAsBytesSync(),
    );
    expect(b.chats.fileOf(got.id, 'Ara Karar.pdf'), contains('Mesajlar'));
    await until(() => a.chats.pending.isEmpty);
    // A group: what one writes reaches the others.
    final group = (await a.groupChat('Duruşma ekibi', [
      b.self!.deviceId,
      c.self!.deviceId,
    ]))!;
    await until(() => c.chats.of(group.id) != null);
    await c.post(c.chats.of(group.id)!, text: 'Yarın 09:00 adliyedeyim.');
    await until(() => (b.chats.of(group.id)?.messages.length ?? 0) == 1);
    // The managers' word to all; a trainee writes nothing in it.
    final word = (await a.broadcastChat())!;
    await a.post(word, text: 'Cuma günü büro kapalı.');
    await until(() => c.chats.of(word.id)?.messages.isNotEmpty ?? false);
    await until(() => b.chats.of(word.id)?.messages.isNotEmpty ?? false);
    expect(
      await b.post(b.chats.of(word.id)!, text: 'Ben de duyurayım'),
      isNotNull,
    );
    // Nor is one made up in a trainee's name taken in.
    final forged = Chat.fromJson(word.toJson())!
      ..messages.add(
        ChatMessage(
          id: 'x',
          by: b.self!.deviceId,
          byName: 'Mert',
          at: DateTime.now(),
          text: 'sahte',
        ),
      );
    expect(
      await c.chats.merge(
        forged,
        from: b.self!.deviceId,
        mayBroadcast: c.ledger.isManager,
      ),
      isFalse,
    );
  });
}
