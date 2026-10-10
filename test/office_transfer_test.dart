import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:evrak_convert/services/office/office_chat.dart';
import 'package:evrak_convert/services/office/office_identity.dart';
import 'package:evrak_convert/services/office/office_known.dart';
import 'package:evrak_convert/services/office/office_ledger.dart';
import 'package:evrak_convert/services/office/office_link.dart';
import 'package:evrak_convert/services/office/office_inbox.dart';
import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/services/office/office_pairing.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/sync/own_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:evrak_convert/services/office/office_peer.dart';
import 'package:evrak_convert/services/office/office_task.dart';
import 'package:evrak_convert/services/office/office_transfer.dart';
import 'package:evrak_convert/services/office/task_package.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:evrak_convert/services/uyap/uyap_case_panel_controller.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
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
      packages: TaskPackages(
        file: () async => File('${dir.path}/$device/p.json'),
      ),
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
    for (var i = 0; i < 1500 && !done(); i++) {
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

  test(
    'cut after the first of two files: the first is not written twice',
    () async {
      final one = file('Bir.pdf', 90 * 1024, seed: 3);
      final two = file('İki.pdf', 120 * 1024, seed: 4);
      final id = OfficeTransfer.newId();
      final inbox = Directory('${dir.path}/mert-pc/gelen');
      final parts = Directory('${inbox.path}/.folio-parca')
        ..createSync(recursive: true);
      // The first came whole before the cut, the second half.
      final came = File('${inbox.path}/Bir.pdf')
        ..writeAsBytesSync(one.readAsBytesSync());
      File('${parts.path}/$id-0.done').writeAsStringSync(
        jsonEncode({
          'yol': came.path,
          'boyut': 90 * 1024,
          'sha': await OfficeTransfer.sha256Of(one),
        }),
      );
      File('${parts.path}/$id-1.part')
          .writeAsBytesSync(two.readAsBytesSync().sublist(0, 60 * 1024));
      final t = (await a.send(b.self!, [one.path, two.path], id: id))!;
      await until(() => b.incomingOffer.value != null);
      final offer = b.incomingOffer.value!;
      await b.acceptOffer(offer);
      await until(() => offer.state == TransferState.done);
      await until(() => t.state == TransferState.done);
      expect(offer.saved.length, 2);
      expect(File('${inbox.path}/Bir (2).pdf').existsSync(), isFalse);
      expect(File(offer.saved.last).readAsBytesSync(), two.readAsBytesSync());
    },
  );

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
      // An approval made up on the trainee's side, in the giver's name, is
      // not taken: it is not the giver's signature.
      await b.tasks.add(
        b.tasks.all.single,
        TaskEvent.create(
          TaskEventKind.approved,
          a.self!.deviceId,
          'Av. Deniz Kaya',
        ),
      );
      await b.act(
        b.tasks.all.single,
        TaskEventKind.message,
        text: 'Bakar mısınız?',
      );
      await until(
        () => theirs().timeline.any((e) => e.text == 'Bakar mısınız?'),
      );
      expect(theirs().stage, TaskStage.review);
      // It undid only the trainee's own copy.
      b.tasks.all.single.events.removeWhere(
        (e) => e.kind == TaskEventKind.approved,
      );
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
        b.tasks.all.single.timeline.where((e) => e.isTalk).map((e) => e.text),
        ['Taslak hazır.', 'Bakar mısınız?'],
      );
    },
  );

  test('what is said while a phone is away reaches it when it comes back, '
      'its files too, not only once it answers', () async {
    b.seenForTesting(a.self!);
    await a.foundOffice('Kaya Hukuk Bürosu');
    await a.admit(b.self!.deviceId, OfficeRole.trainee);
    await until(() => b.ledger.members.length == 2);
    // Heard once, and brought up to date then.
    a.foundForTesting(b.self!);
    final talk = (await a.privateChat(b.self!.deviceId))!;
    await a.post(talk, text: 'Günaydın');
    await until(() => b.chats.of(talk.id)?.messages.length == 1);
    // Its bringing up to date done.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    // The phone sleeps: what is said meanwhile waits.
    a.lostForTesting(b.self!.deviceId);
    final photo = file('Tutanak.jpg', 40 * 1024);
    await a.post(
      a.chats.of(talk.id)!,
      text: 'Tutanak ekte',
      files: [photo.path],
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(b.chats.of(talk.id)!.messages, hasLength(1));
    // Back on the network: it comes, the photograph with it.
    a.foundForTesting(b.self!);
    await until(() => b.chats.of(talk.id)!.messages.length == 2);
    final got = b.chats.of(talk.id)!.messages.last;
    expect(got.text, 'Tutanak ekte');
    await until(() => b.chats.fileOf(got.id, 'Tutanak.jpg') != null);
    expect(
      File(b.chats.fileOf(got.id, 'Tutanak.jpg')!).readAsBytesSync(),
      photo.readAsBytesSync(),
    );
    await until(() => a.chats.pending.isEmpty);
  });

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
    // "Gönder" on a document: the same talk, the members listed.
    expect(
      a.sendTargets.map((t) => (t.name, t.member)),
      containsAll([('Av. Selin Aksoy', true)]),
    );
    expect(
      File(b.chats.fileOf(got.id, 'Ara Karar.pdf')!).readAsBytesSync(),
      doc.readAsBytesSync(),
    );
    expect(b.chats.fileOf(got.id, 'Ara Karar.pdf'), contains('Mesajlar'));
    await until(() => a.chats.pending.isEmpty);
    // The writer corrects their words, then takes them back: so for all.
    final sent = a.chats.of(mine.id)!.ordered.single;
    expect(
      await a.correct(mine, sent, text: 'Şuna bakar mısın, acil?'),
      isNull,
    );
    await until(
      () =>
          b.chats.of(mine.id)!.ordered.single.text == 'Şuna bakar mısın, acil?',
    );
    expect(b.chats.of(mine.id)!.edited(sent.id), isTrue);
    expect(b.chats.unread(b.chats.of(mine.id)!, b.me), 1);
    // No one corrects another's words.
    expect(
      await b.correct(b.chats.of(mine.id)!, sent, text: 'başka'),
      isNotNull,
    );
    expect(await a.correct(mine, sent, delete: true), isNull);
    await until(() => b.chats.of(mine.id)!.ordered.single.deleted);
    expect(b.chats.of(mine.id)!.ordered.single.attachments, isEmpty);
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
    // Nor a private talk of two set up by a third with themself in it.
    final trap = Chat(
      id: Chat.privateId(a.self!.deviceId, c.self!.deviceId),
      kind: ChatKind.private,
      by: b.self!.deviceId,
      members: {
        a.self!.deviceId: 'Av. Deniz Kaya',
        b.self!.deviceId: 'Mert',
        c.self!.deviceId: 'Selin',
      },
    );
    expect(
      await a.chats.merge(
        trap,
        from: b.self!.deviceId,
        mayBroadcast: a.ledger.isManager,
        me: a.self!.deviceId,
      ),
      isFalse,
    );
    // Nor under a private talk's id as a group.
    final groupTrap = Chat(
      id: Chat.privateId(a.self!.deviceId, c.self!.deviceId),
      kind: ChatKind.group,
      by: b.self!.deviceId,
      members: {a.self!.deviceId: 'Av. Deniz Kaya', b.self!.deviceId: 'Mert'},
    );
    expect(
      await a.chats.merge(
        groupTrap,
        from: b.self!.deviceId,
        mayBroadcast: a.ledger.isManager,
        me: a.self!.deviceId,
      ),
      isFalse,
    );
    // One taken off the office hears no more of a talk it was in.
    expect(await a.removeMember(c.self!.deviceId), isNull);
    await a.post(a.chats.of(group.id)!, text: 'Yalnız ikimiz biliyoruz.');
    await until(() => (b.chats.of(group.id)?.messages.length ?? 0) == 2);
    await c.post(c.chats.of(group.id)!, text: 'Ben hâlâ buradayım');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(
      c.chats.of(group.id)!.messages.map((m) => m.text),
      isNot(contains('Yalnız ikimiz biliyoruz.')),
    );
    expect(
      a.chats.of(group.id)!.messages.map((m) => m.text),
      isNot(contains('Ben hâlâ buradayım')),
    );
  });

  test(
    'a task’s case goes with its details and documents, for one without UYAP',
    () async {
      b.seenForTesting(a.self!);
      await a.foundOffice('Kaya Hukuk Bürosu');
      await a.admit(b.self!.deviceId, OfficeRole.lawyer);
      await until(() => b.ledger.members.length == 2);
      const court = 'Antalya 3. Asliye Hukuk Mahkemesi';
      final store = UyapCaseStore(
        directory: Directory('${dir.path}/uyap'),
        settings: UyapSettings(
          directory: Directory('${dir.path}/uyap'),
          home: '${dir.path}/ev',
        ),
      );
      UyapCaseDocument doc(String key, String type) => UyapCaseDocument(
        key: key,
        documentId: key,
        caseId: '1',
        type: type,
        number: key,
        approved: '01.10.2026 10:00',
        sender: 'Mahkeme',
        description: '',
      );
      var record = await store.keep(
        target: const UyapCase('1', '2024/318', '', court),
        details: const UyapCaseDetails(
          kind: 'Alacak (İtirazın İptali)',
          status: 'Açık',
        ),
        parties: const [
          UyapParty('AYŞE KARACA', 'Davacı', 'Av. Deniz Kaya', 'Kişi'),
        ],
        documents: UyapCaseDocuments([
          doc('a', 'Ara Karar'),
          doc('b', 'Bilirkişi Raporu'),
        ]),
      );
      final bytes = utf8.encode('%PDF-1.4 ara karar');
      (record, _) = await store.save(
        record,
        record.documents.first,
        Uint8List.fromList(bytes),
      );
      const c = TaskCase(
        caseKey: 'k1',
        number: '2024/318',
        court: court,
        docKeys: ['a', 'b'],
      );
      final pack = await TaskPackage.pack(
        c,
        store: store,
        controller: UyapCasePanelController(
          web: UyapWebService.forTesting(),
          mobile: UyapMobileApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
          store: store,
        ),
        temp: () async => Directory('${dir.path}/tmp'),
      );
      // UYAP not connected: the one not here is said, not sent.
      expect(pack.missing, ['Bilirkişi Raporu']);
      expect(pack.paths, hasLength(2));
      await a.giveTask(
        title: 'İncele',
        to: [b.self!.deviceId],
        cases: const [c],
        packed: {'k1': pack},
      );
      await until(() => b.tasks.all.isNotEmpty);
      final t = b.tasks.all.single;
      await until(() => b.receivedCase(t, 'k1') != null);
      final got = b.receivedCase(t, 'k1')!;
      expect(got.number, '2024/318');
      expect(got.particulars['kind'], 'Alacak (İtirazın İptali)');
      expect(got.parties.single['ad'], 'AYŞE KARACA');
      expect(File(got.documents.single).readAsBytesSync(), bytes);
      // The giver's paths go nowhere.
      expect(got.details['dosyalar'], isEmpty);
      await until(() => a.packages.pending.isEmpty);
      // In Gelenler too, by the task's title.
      final inbox = OfficeInbox(
        network: b,
        file: () async => File('${dir.path}/gelenler-b.json'),
      );
      await inbox.start();
      await until(() => inbox.items.isNotEmpty);
      expect(inbox.items.single.task, 'İncele');
    },
  );

  test(
    'one person’s devices share a key once and then know each other unasked',
    () async {
      final laptop = await folio('Av. Erkan Öz', 'dizustu');
      final phone = await folio('Av. Erkan Öz', 'telefon');
      final tablet = await folio('Av. Erkan Öz', 'tablet');
      Future<void> meet(OfficeNetwork x, OfficeNetwork y) async {
        x.seenForTesting(y.self!);
        y.seenForTesting(x.self!);
        final asking = x.pair(y.self!)!;
        await until(
          () => y.incoming.value?.code != null && asking.code != null,
        );
        // The same name: "Bu cihaz da benim" comes ticked.
        expect(asking.mine, isTrue);
        y.incoming.value!.confirm();
        asking.confirm();
        await until(() => x.self!.userId == y.self!.userId);
      }

      await meet(laptop, phone);
      await meet(laptop, tablet);
      expect(tablet.self!.userId, phone.self!.userId);
      // The phone and the tablet never met by a code.
      expect(phone.isKnown(tablet.self!.deviceId), isFalse);
      phone.seenForTesting(tablet.self!);
      tablet.seenForTesting(phone.self!);
      // "Gönder" on a document lists it as an own device.
      final to = phone.sendTargets.singleWhere(
        (x) => x.deviceId == tablet.self!.deviceId,
      );
      expect((to.member, to.online, to.name), (false, true, 'Kendi cihazım'));
      expect(await phone.sendTo(to, [file('Not.txt', 2000).path]), isNull);
      // Taken unasked: it is the same person's.
      await until(
        () => tablet.transfers.any((x) => x.state == TransferState.done),
      );
      expect(tablet.incomingOffer.value, isNull);
      // Told where it went: it came on its own, to the inbox.
      expect(tablet.arrived.value?.saved.single, endsWith('Not.txt'));
      // In Gelenler: new, opened, new again, and off with its file.
      final inbox = OfficeInbox(
        network: tablet,
        file: () async => File('${dir.path}/gelenler.json'),
      );
      await inbox.start();
      await until(() => inbox.items.isNotEmpty);
      final came = inbox.items.single;
      expect(came.names, ['Not.txt']);
      expect(inbox.unread, 1);
      expect(inbox.searchable, isFalse);
      await inbox.markRead(came);
      expect(inbox.unread, 0);
      await inbox.markUnread(came);
      expect(inbox.unread, 1);
      await inbox.remove(came);
      expect(File(came.paths.single).existsSync(), isFalse);
      await inbox.reload();
      expect(inbox.items, isEmpty);
      // Known to each other now, as their own.
      await until(
        () =>
            phone.isKnown(tablet.self!.deviceId) &&
            tablet.isKnown(phone.self!.deviceId),
      );
    },
  );

  test(
    'a phone reads the computer’s QR: known, as one’s own, unasked',
    () async {
      final pc = await folio('Av. Erkan Öz', 'masaustu');
      final phone = await folio('Erkan', 'telefon');
      final invite = (await pc.inviteByQr(at: ['127.0.0.1']))!;
      // A QR with another secret is turned away, and the real one still holds.
      final forged = QrInvite.parse(invite.text)!;
      final fake = QrInvite(
        hosts: forged.hosts,
        port: forged.port,
        deviceId: forged.deviceId,
        secret: List.filled(32, 1),
      );
      final bad = (await phone.pairByQr(fake))!;
      await until(() => bad.finished);
      expect(bad.state, PairingState.failed);
      expect(pc.isKnown(phone.self!.deviceId), isFalse);
      final read = QrInvite.parse(invite.text)!;
      final pairing = (await phone.pairByQr(read))!;
      await until(() => pairing.state == PairingState.done);
      await until(() => pc.self!.userId == phone.self!.userId);
      expect(pc.isKnown(phone.self!.deviceId), isTrue);
      expect(pc.incoming.value, isNull);
      expect(pc.qrPairing.value?.state, PairingState.done);
      // Used once.
      final again = (await folio('Başka', 'tablet')).pairByQr(read);
      final second = (await again)!;
      await until(() => second.finished);
      expect(second.state, PairingState.failed);
    },
  );

  test('one person’s devices keep their agenda alike, by proof only', () async {
    final laptop = await folio('Av. Erkan Öz', 'dizustu2');
    final phone = await folio('Av. Erkan Öz', 'telefon2');
    laptop.seenForTesting(phone.self!);
    phone.seenForTesting(laptop.self!);
    final asking = laptop.pair(phone.self!)!;
    await until(
      () => phone.incoming.value?.code != null && asking.code != null,
    );
    phone.incoming.value!.confirm();
    asking.confirm();
    await until(() => laptop.self!.userId == phone.self!.userId);
    final pcDb = PortalDatabase.memory(), phoneDb = PortalDatabase.memory();
    addTearDown(pcDb.dispose);
    addTearDown(phoneDb.dispose);
    for (final (net, db) in [(laptop, pcDb), (phone, phoneDb)]) {
      net.ownParts['ajanda'] = OwnPart(
        export: () async => db.agendaExport(),
        merge: (theirs) async => db.agendaMerge(theirs),
      );
    }
    pcDb.saveAgenda(
      AgendaItem(
        id: 'n1',
        kind: 'note',
        title: 'Bilirkişi raporuna itiraz',
        updated: DateTime(2026, 10, 8, 9),
      ),
    );
    laptop.seenForTesting(phone.self!);
    phone.seenForTesting(laptop.self!);
    await laptop.syncOwn();
    expect(
      [for (final i in phoneDb.agenda()) i.title],
      ['Bilirkişi raporuna itiraz'],
    );
    expect(laptop.synced.containsKey(phone.self!.deviceId), isTrue);
    phoneDb.removeAgenda('n1');
    await phone.syncOwn();
    expect(pcDb.agenda(), isEmpty);
    // A colleague's device, known by a code, gets none of it.
    final other = await folio('Av. Selin Aksoy', 'selin2');
    final asked = laptop.pair(other.self!)!;
    other.seenForTesting(laptop.self!);
    laptop.seenForTesting(other.self!);
    await until(() => other.incoming.value?.code != null && asked.code != null);
    asked.mine = false;
    other.incoming.value!.mine = false;
    other.incoming.value!.confirm();
    asked.confirm();
    await until(() => laptop.isKnown(other.self!.deviceId));
    final otherDb = PortalDatabase.memory();
    addTearDown(otherDb.dispose);
    other.ownParts['ajanda'] = OwnPart(
      export: () async => otherDb.agendaExport(),
      merge: (theirs) async => otherDb.agendaMerge(theirs),
    );
    pcDb.saveAgenda(
      AgendaItem(
        id: 'n2',
        kind: 'note',
        title: 'Gizli',
        updated: DateTime(2026),
      ),
    );
    // Even announced as the same person, it is not taken for theirs.
    final o = other.self!;
    laptop.seenForTesting(
      OfficePeer(
        deviceId: o.deviceId,
        userId: laptop.self!.userId,
        name: o.name,
        device: o.device,
        platform: o.platform,
        host: o.host,
        port: o.port,
      ),
    );
    expect(laptop.ownOnline.map((p) => p.deviceId), contains(o.deviceId));
    await laptop.syncOwn();
    expect(otherDb.agenda(), isEmpty);
    expect(laptop.synced.containsKey(o.deviceId), isFalse);
  });

  test(
    'a session is shared with one’s own device, and renewed for both',
    () async {
      final pc = await folio('Av. Erkan Öz', 'dizustu3');
      final phone = await folio('Av. Erkan Öz', 'telefon3');
      pc.seenForTesting(phone.self!);
      phone.seenForTesting(pc.self!);
      final asking = pc.pair(phone.self!)!;
      await until(
        () => phone.incoming.value?.code != null && asking.code != null,
      );
      phone.incoming.value!.confirm();
      asking.confirm();
      await until(() => pc.self!.userId == phone.self!.userId);
      pc.seenForTesting(phone.self!);
      phone.seenForTesting(pc.self!);
      final pcHas = _Sessions({
        'mobil': {'access': 'a1', 'refresh': 'r1'},
      });
      final phoneHas = _Sessions({});
      final dir2 = Directory.systemTemp.createTempSync('folio_own_');
      addTearDown(() => dir2.deleteSync(recursive: true));
      OwnSync own(OfficeNetwork net, _Sessions s, String name, bool isPhone) =>
          OwnSync(
            network: net,
            database: () async => PortalDatabase.memory(),
            file: () async => File('${dir2.path}/$name.json'),
            sessions: s,
            phone: isPhone,
          );
      final onPc = own(pc, pcHas, 'pc', false);
      final onPhone = own(phone, phoneHas, 'tel', true);
      await onPc.start();
      await onPhone.start();
      await phone.syncOwn();
      // Each knows what the other holds, and the computer's tokens came.
      expect(onPhone.held[pc.self!.deviceId], {'mobil'});
      expect(phoneHas.alike.last, {'access': 'a1', 'refresh': 'r1'});
      // "Bu cihazda da aç" on the phone: open there, still open here.
      expect(await onPhone.take(pc.self!.deviceId, 'mobil'), isNull);
      expect(phoneHas.sessionOf('mobil'), {'access': 'a1', 'refresh': 'r1'});
      expect(pcHas.holds('mobil'), isTrue);
      // The phone renews through the computer: one refresh token, one
      // spender; the computer only renews for itself.
      expect(phoneHas.renewer, isNotNull);
      expect(pcHas.renewer, isNull);
      pcHas.fresh = {'access': 'a2', 'refresh': 'r2'};
      expect(await phoneHas.renewer!(), {'access': 'a2', 'refresh': 'r2'});
      // "Öbür cihazla paylaş": shared the other way, kept here too.
      phoneHas.kept['uets'] = {'token': 't'};
      expect(await onPhone.give(pc.self!.deviceId, 'uets'), isNull);
      expect(pcHas.holds('uets') && phoneHas.holds('uets'), isTrue);
      // Nothing to share: said so.
      expect(await onPc.take(phone.self!.deviceId, 'web'), isNotNull);
    },
  );

  test('a person’s tasks and talks are on all their devices', () async {
    final boss = await folio('Av. Selin Aksoy', 'selin4');
    final laptop = await folio('Av. Erkan Öz', 'dizustu4');
    final phone = await folio('Av. Erkan Öz', 'telefon4');
    void see(OfficeNetwork x, OfficeNetwork y) {
      x.seenForTesting(y.self!);
      y.seenForTesting(x.self!);
    }

    Future<void> meet(
      OfficeNetwork x,
      OfficeNetwork y, {
      bool mine = false,
    }) async {
      see(x, y);
      final asking = x.pair(y.self!)!;
      await until(() => y.incoming.value?.code != null && asking.code != null);
      asking.mine = mine;
      y.incoming.value!.mine = mine;
      y.incoming.value!.confirm();
      asking.confirm();
      await until(
        () => x.isKnown(y.self!.deviceId) && y.isKnown(x.self!.deviceId),
      );
    }

    await meet(boss, laptop);
    await boss.foundOffice('Aksoy Hukuk');
    await boss.admit(laptop.self!.deviceId, OfficeRole.lawyer);
    await until(() => laptop.ledger.members.length == 2);
    await meet(laptop, phone, mine: true);
    await until(() => laptop.self!.userId == phone.self!.userId);
    see(laptop, phone);
    see(boss, phone);
    for (final net in [laptop, phone]) {
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);
      net.ownParts['ajanda'] = OwnPart(
        export: () async => db.agendaExport(),
        merge: (theirs) async => db.agendaMerge(theirs),
      );
    }
    // Met by proof, the phone is taken in as the same person.
    await laptop.syncOwn();
    await until(() => boss.ledger.member(phone.self!.deviceId) != null);
    await until(() => phone.ledger.member(phone.self!.deviceId) != null);
    final person = laptop.self!.deviceId;
    expect(phone.me, person);
    expect(boss.ledger.people.map((m) => m.name), [
      'Av. Selin Aksoy',
      'Av. Erkan Öz',
    ]);
    // A task given to the person comes to the phone too.
    expect(
      await boss.giveTask(title: 'Keşif notlarını yaz', to: [person]),
      isNull,
    );
    await until(
      () => phone.tasks.all.isNotEmpty && laptop.tasks.all.isNotEmpty,
    );
    await phone.act(phone.tasks.all.single, TaskEventKind.accepted);
    await until(
      () => boss.tasks.all.single.events.any(
        (e) => e.kind == TaskEventKind.accepted && e.by == person,
      ),
    );
    // A private talk with the person: the same talk on both devices.
    final talk = (await boss.privateChat(person))!;
    await boss.post(talk, text: 'Yarın 10:00 uygun mu?');
    await until(() => phone.chats.of(talk.id)?.messages.isNotEmpty ?? false);
    await until(() => laptop.chats.of(talk.id)?.messages.isNotEmpty ?? false);
    await phone.post(phone.chats.of(talk.id)!, text: 'Uygun.');
    await until(
      () => boss.chats.of(talk.id)!.messages.any((m) => m.text == 'Uygun.'),
    );
    expect(
      boss.chats.of(talk.id)!.messages.firstWhere((m) => m.text == 'Uygun.').by,
      person,
    );
  });
}

class _Sessions implements SessionHolder {
  _Sessions(this.kept);
  final Map<String, Map<String, Object?>> kept;
  final _told = <VoidCallback>[];

  /// What the other device's tokens were, as they came.
  final alike = <Object?>[];
  Map<String, Object?>? fresh;
  Future<Map<String, Object?>?> Function()? renewer;

  @override
  bool holds(String kind) => kept.containsKey(kind);
  @override
  Map<String, Object?>? sessionOf(String kind) => kept[kind];
  @override
  Future<bool> takeSession(String kind, Object? data) async {
    if (data is! Map) return false;
    kept[kind] = data.cast<String, Object?>();
    for (final t in _told) {
      t();
    }
    return true;
  }

  @override
  void listen(VoidCallback changed) => _told.add(changed);
  @override
  Future<Map<String, Object?>?> freshMobile() async => fresh ?? kept['mobil'];
  @override
  bool keepMobileAlike(Object? theirs) {
    if (theirs != null) alike.add(theirs);
    return false;
  }

  @override
  void renewMobileThrough(Future<Map<String, Object?>?> Function()? ask) =>
      renewer = ask;
  @override
  void listenMobileTokens(VoidCallback changed) {}
}
