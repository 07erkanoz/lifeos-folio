import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/live/live_share.dart';
import 'package:evrak_convert/services/office/office_channel.dart';
import 'package:evrak_convert/services/office/office_chat.dart';
import 'package:evrak_convert/services/office/office_identity.dart';
import 'package:evrak_convert/services/office/office_known.dart';
import 'package:evrak_convert/services/office/office_ledger.dart';
import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/services/office/office_pairing.dart';
import 'package:evrak_convert/services/office/office_peer.dart';
import 'package:evrak_convert/services/office/office_task.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show Attribute, ChangeSource, Document, QuillController, QuillEditor;
import 'package:flutter_quill/quill_delta.dart';
import 'package:evrak_convert/ui/live/live_document_page.dart';
import 'package:evrak_convert/ui/live/live_guest_dialogs.dart';
import 'package:evrak_convert/ui/live/live_share_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  final identities = <OfficeNetwork, OfficeIdentity>{};
  setUp(() => dir = Directory.systemTemp.createTempSync('folio_live_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<OfficeNetwork> folio(
    String device, {
    String name = 'Av. Deniz Yılmaz',
  }) async {
    final net = OfficeNetwork(
      settings: () async => File('${dir.path}/$device/buro.json'),
      known: KnownDevices(file: () async => File('${dir.path}/$device/k.json')),
      ledger: OfficeLedger(
        file: () async => File('${dir.path}/$device/d.json'),
      ),
      tasks: OfficeTasks(file: () async => File('${dir.path}/$device/g.json')),
      chats: OfficeChats(file: () async => File('${dir.path}/$device/m.json')),
    );
    final identity = await OfficeIdentity.load(store: _Store());
    identities[net] = identity;
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

  /// Two of one person's devices, paired; the second listening.
  Future<(OfficeNetwork, OfficeNetwork)> pair() async {
    final pc = await folio('masaustu'), tablet = await folio('tablet');
    pc.seenForTesting(tablet.self!);
    tablet.seenForTesting(pc.self!);
    final asking = pc.pair(tablet.self!)!;
    await until(
      () => tablet.incoming.value?.code != null && asking.code != null,
    );
    tablet.incoming.value!.confirm();
    asking.confirm();
    await until(() => pc.self!.userId == tablet.self!.userId);
    pc.seenForTesting(tablet.self!);
    tablet.seenForTesting(pc.self!);
    LiveShare.instance.listen(tablet);
    return (pc, tablet);
  }

  String text(Document d) => d.toPlainText();

  test('a document is shown live on one of the person\'s own devices: '
      'whole, then change by change, alike to the letter with the writer\'s, '
      'and let go of when the sharing ends', () async {
    final (pc, tablet) = await pair();
    // A picture's worth of Turkish letters: more than a line takes, sent
    // in pieces measured in bytes.
    final big = 'ğüşiöç' * (300 * 1024);
    final writer = Document.fromDelta(
      Delta()
        ..insert('Merhaba\n')
        ..insert(big)
        ..insert('\n'),
    );
    var blocks = <DocBlock>[];
    final host = LiveShareHost(
      title: 'Kira sözleşmesi',
      snapshot: () => (delta: writer.toDelta().toJson(), blocks: blocks),
      blockCount: () => blocks.length,
      network: pc,
    );
    expect(await host.invite(tablet.self!.deviceId, 'tablet'), isTrue);
    await until(() => LiveShare.instance.incoming.value.isNotEmpty);
    final session = LiveShare.instance.incoming.value.single;
    expect(session.title, 'Kira sözleşmesi');
    await until(() => session.ready);
    expect(host.peers.value.single.state, LivePeerState.watching);

    // Written on while no page shows it: the session keeps up anyway.
    final took = <int>[];
    final sent = <int, DateTime>{};
    var got = 0;
    session.changes.listen((_) {
      got++;
      final at = sent[got];
      if (at != null) took.add(DateTime.now().difference(at).inMicroseconds);
    });
    for (var i = 1; i <= 100; i++) {
      final change = Delta()
        ..retain(7)
        ..insert('$i');
      writer.compose(change, ChangeSource.local);
      sent[i] = DateTime.now();
      host.body(change);
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
    await until(() => got == 100);
    took.sort();
    // ignore: avoid_print
    print(
      'canlı değişiklik gecikmesi (aynı makine): ortanca '
      '${took[took.length ~/ 2]} µs, en kötü ${took.last} µs',
    );
    expect(text(session.document!), text(writer));

    // A table put in: its block goes with the whole, the embed with it.
    blocks = [
      DocBlock(
        type: DocBlockType.table,
        plainText: '',
        table: DocTable(
          rows: [
            DocTableRow(
              cells: [
                DocTableCell(blocks: [DocBlock(plainText: 'A')]),
              ],
            ),
          ],
        ),
      ),
    ];
    final embed = Delta()
      ..retain(7)
      ..insert({'doc-table': 0});
    writer.compose(embed, ChangeSource.local);
    host.body(embed);
    await until(() => session.blocks.length == 1);
    expect(session.document!.toDelta().toJson(), writer.toDelta().toJson());

    host.selection(3, 7);
    await until(() => session.selection == (base: 3, extent: 7));

    await host.close();
    await until(() => session.ended);
    expect(session.document, isNull);
    expect(session.blocks, isEmpty);
    expect(LiveShare.instance.incoming.value, isEmpty);
    // Closed is closed: nothing more goes from it.
    expect(await host.invite(tablet.self!.deviceId, 'tablet'), isFalse);
  });

  test('fed as the editor feeds it, from the document\'s own changes: '
      'joining while it is written, bursts of changes and a table put in '
      'leave the viewer\'s alike with the writer\'s', () async {
    final (pc, tablet) = await pair();
    final writer = Document.fromDelta(Delta()..insert('Dava dilekçesi\n'));
    var blocks = <DocBlock>[];
    final host = LiveShareHost(
      title: 'Dilekçe',
      snapshot: () =>
          (delta: writer.toDelta().toJson(), blocks: List.of(blocks)),
      blockCount: () => blocks.length,
      network: pc,
    );
    // As the editor listens: told of each change after it is made.
    writer.changes.listen((e) {
      if (e.source == ChangeSource.local) host.body(e.change);
    });
    void type(String t) => writer.compose(
      Delta()
        ..retain(writer.length - 1)
        ..insert(t),
      ChangeSource.local,
    );
    type(' A');
    final joining = host.invite(tablet.self!.deviceId, 'tablet');
    // Written on while the viewer joins, several changes in one go.
    for (var i = 0; i < 5; i++) {
      type(' $i');
    }
    expect(await joining, isTrue);
    await until(() => LiveShare.instance.incoming.value.isNotEmpty);
    final session = LiveShare.instance.incoming.value.single;
    await until(() => session.ready);
    for (var round = 0; round < 20; round++) {
      // A burst: the editor tells of them after all are made.
      type(' x$round');
      type('y');
      if (round == 10) {
        // A table put in: its block kept first, then the embed.
        blocks = [
          DocBlock(
            type: DocBlockType.table,
            plainText: '',
            table: DocTable(
              rows: [
                DocTableRow(
                  cells: [
                    DocTableCell(blocks: [DocBlock(plainText: 'T')]),
                  ],
                ),
              ],
            ),
          ),
        ];
        writer.compose(
          Delta()
            ..retain(writer.length - 1)
            ..insert({'doc-table': 0}),
          ChangeSource.local,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await until(
      () =>
          session.document != null &&
          jsonEncode(session.document!.toDelta().toJson()) ==
              jsonEncode(writer.toDelta().toJson()),
    );
    expect(session.blocks.length, 1);
    await host.close();
    await until(() => session.ended);
  });

  test(
    'an invitation withdrawn while it is being made shows nothing',
    () async {
      final (pc, tablet) = await pair();
      final host = LiveShareHost(
        title: 'Taslak',
        snapshot: () =>
            (delta: (Delta()..insert('gizli\n')).toJson(), blocks: []),
        blockCount: () => 0,
        network: pc,
      );
      final asked = host.invite(tablet.self!.deviceId, 'tablet');
      await host.remove(tablet.self!.deviceId);
      expect(await asked, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(LiveShare.instance.incoming.value.where((s) => s.ready), isEmpty);
      for (final s in LiveShare.instance.incoming.value.toList()) {
        await s.leave();
      }
    },
  );

  test(
    'only one of the person\'s own devices is shown it in this step',
    () async {
      final pc = await folio('masaustu'), colleague = await folio('meslektas');
      LiveShare.instance.listen(colleague);
      pc.seenForTesting(colleague.self!);
      colleague.seenForTesting(pc.self!);
      final host = LiveShareHost(
        title: 'Taslak',
        snapshot: () =>
            (delta: (Delta()..insert('gizli\n')).toJson(), blocks: []),
        blockCount: () => 0,
        network: pc,
      );
      // Not paired, not the person's: no channel is opened at all.
      expect(await host.invite(colleague.self!.deviceId, 'meslektaş'), isFalse);
      expect(LiveShare.instance.incoming.value, isEmpty);
    },
  );

  test('a colleague of the office is shown it when chosen; a device only '
      'paired, not the office\'s, is not even reached', () async {
    final deniz = await folio('deniz-pc', name: 'Av. Deniz Kaya');
    final mert = await folio('mert-pc', name: 'Av. Mert Yıldız');
    final asking = deniz.pair(mert.self!)!;
    await until(() => mert.incoming.value?.code != null);
    mert.incoming.value!.confirm();
    asking.confirm();
    await until(
      () =>
          deniz.isKnown(mert.self!.deviceId) &&
          mert.isKnown(deniz.self!.deviceId),
    );
    deniz.seenForTesting(mert.self!);
    mert.seenForTesting(deniz.self!);
    expect(deniz.self!.userId, isNot(mert.self!.userId));
    LiveShare.instance.listen(mert);
    final host = LiveShareHost(
      title: 'Bilirkişi itirazı',
      snapshot: () => (
        delta: (Delta()..insert('Bilirkişi raporuna itirazlarımız\n')).toJson(),
        blocks: <DocBlock>[],
      ),
      blockCount: () => 0,
      network: deniz,
    );
    // Paired, but not taken into an office: no channel.
    expect(
      await host.invite(mert.self!.deviceId, 'Av. Mert Yıldız', office: true),
      isFalse,
    );
    expect(LiveShare.instance.incoming.value, isEmpty);

    expect(await deniz.foundOffice('Kaya Hukuk Bürosu'), isNull);
    expect(await deniz.admit(mert.self!.deviceId, OfficeRole.lawyer), isNull);
    await until(() => mert.ledger.members.length == 2);
    expect(
      await host.invite(mert.self!.deviceId, 'Av. Mert Yıldız', office: true),
      isTrue,
    );
    await until(() => LiveShare.instance.incoming.value.isNotEmpty);
    final session = LiveShare.instance.incoming.value.single;
    expect(session.from, 'Av. Deniz Kaya');
    await until(() => session.ready);
    expect(
      session.document!.toPlainText(),
      'Bilirkişi raporuna itirazlarımız\n',
    );
    await host.remove(mert.self!.deviceId);
    await until(() => session.ended);
    expect(session.document, isNull);
  });

  test('a guest of no office and no pairing joins by a code both screens '
      'show, is shown the document, may do nothing else, and both forget '
      'each other when it ends', () async {
    final deniz = await folio('deniz-pc', name: 'Av. Deniz Kaya');
    final selin = await folio('selin-pc', name: 'Av. Selin Arı');
    // On the network, as the guest's quiet join would put them.
    deniz.seenForTesting(selin.self!);
    LiveShare.instance.listen(selin);
    LiveShare.instance.listen(deniz);
    final host = LiveShareHost(
      title: 'Kira sözleşmesi',
      snapshot: () => (
        delta: (Delta()..insert('Kiraya veren ve kiracı\n')).toJson(),
        blocks: <DocBlock>[],
      ),
      blockCount: () => 0,
      network: deniz,
    );
    await host.takeGuests(true);
    expect(deniz.guestsOpen, isTrue);
    expect(deniz.self!.live, isTrue);
    selin.seenForTesting(deniz.self!);
    expect(selin.liveHosts.map((p) => p.deviceId), [deniz.self!.deviceId]);

    final joining = selin.joinAsGuest(
      deniz.self!,
      name: 'Av. Selin Arı',
      office: 'Arı Hukuk',
    )!;
    await until(() => deniz.guestPairing.value?.code != null);
    final asked = deniz.guestPairing.value!;
    expect(asked.guestName, 'Av. Selin Arı');
    expect(asked.guestOffice, 'Arı Hukuk');
    await until(() => joining.code != null);
    // The same six digits on both screens, not a device's pairing code.
    expect(joining.code, asked.code);
    expect(joining.mine, isFalse);
    asked.confirm();
    joining.confirm();
    await until(() => LiveShare.instance.incoming.value.isNotEmpty);
    final session = LiveShare.instance.incoming.value.single;
    await until(() => session.ready);
    expect(session.document!.toPlainText(), 'Kiraya veren ve kiracı\n');
    expect(host.peers.value.single.name, 'Av. Selin Arı (Arı Hukuk)');
    // Not known as a device, not the person's, not the office's.
    expect(deniz.isKnown(selin.self!.deviceId), isFalse);
    expect(deniz.isGuestOnly(selin.self!.deviceId), isTrue);
    expect(selin.self!.userId, isNot(deniz.self!.userId));

    // The guest offering a document of its own is not shown it.
    final back = await selin.openStream(
      deniz.self!.deviceId,
      liveKind,
      guest: true,
      body: {'baslik': 'Sahte'},
    );
    if (back != null) await until(() => back.closed);
    expect(LiveShare.instance.incoming.value.length, 1);
    // Nor anything else a known device may.
    expect(await selin.askOwn(deniz.self!.deviceId, 'herhangi'), isNull);

    await host.close();
    await until(() => session.ended);
    expect(session.document, isNull);
    await until(() => !selin.isGuestOnly(deniz.self!.deviceId));
    expect(deniz.isGuestOnly(selin.self!.deviceId), isFalse);
    expect(deniz.guestsOpen, isFalse);
  });

  /// A sharer taking guests and a guest seeing it on the network.
  Future<(OfficeNetwork, OfficeNetwork, LiveShareHost)> guests() async {
    final deniz = await folio('deniz-pc', name: 'Av. Deniz Kaya');
    final selin = await folio('selin-pc', name: 'Av. Selin Arı');
    deniz.seenForTesting(selin.self!);
    LiveShare.instance.listen(selin);
    final host = LiveShareHost(
      title: 'Kira sözleşmesi',
      snapshot: () => (
        delta: (Delta()..insert('Kiraya veren ve kiracı\n')).toJson(),
        blocks: <DocBlock>[],
      ),
      blockCount: () => 0,
      network: deniz,
    );
    await host.takeGuests(true);
    selin.seenForTesting(deniz.self!);
    return (deniz, selin, host);
  }

  /// Waited for in a widget test: real time passing for the sockets, and
  /// the test's own zone let run between, where the dialogs' work is.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  testWidgets('the guest picks the sharer, gives a name, confirms the code '
      'and is handed the document once the sharer accepts', (tester) async {
    final (deniz, selin, host) = (await tester.runAsync(guests))!;
    LiveSession? came;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => came = await showDialog<LiveSession>(
              context: context,
              builder: (_) => LiveJoinDialog(network: selin),
            ),
            child: const Text('aç'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('live-host-${deniz.self!.deviceId}')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ValueKey('live-host-${deniz.self!.deviceId}')));
    await tester.enterText(
      find.byKey(const ValueKey('live-join-name')),
      'Av. Selin Arı',
    );
    await tester.enterText(
      find.byKey(const ValueKey('live-join-office')),
      'Arı Hukuk',
    );
    await tester.pump();
    // Tapped in real time: the pairing it starts talks over sockets.
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('live-join'))),
    );
    await settle(tester, () => deniz.guestPairing.value?.code != null);
    await tester.pump();
    final code = deniz.guestPairing.value!.code!;
    expect(find.text(code), findsOneWidget);
    deniz.guestPairing.value!.confirm();
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('live-join-confirm'))),
    );
    await settle(
      tester,
      () =>
          host.peers.value.isNotEmpty &&
          host.peers.value.single.state == LivePeerState.watching,
    );
    await tester.pump();
    expect(came, isNotNull);
    expect(came!.asGuest, isTrue);
    expect(came!.title, 'Kira sözleşmesi');
    expect(host.peers.value.single.name, 'Av. Selin Arı (Arı Hukuk)');
    await tester.runAsync(host.close);
    await settle(tester, () => came!.ended);
    // The pairing's own limit, run out in the test's time.
    await tester.pump(OfficePairing.limit);
  });

  testWidgets('the sharer is shown who asks and the code, and the guest is '
      'shown it only when accepted', (tester) async {
    final (deniz, selin, host) = (await tester.runAsync(guests))!;
    // Asked in real time: the pairing talks over sockets.
    final joining = (await tester.runAsync(
      () async => selin.joinAsGuest(
        deniz.self!,
        name: 'Av. Selin Arı',
        office: 'Arı Hukuk',
      )!,
    ))!;
    await settle(
      tester,
      () => deniz.guestPairing.value?.code != null && joining.code != null,
    );
    expect(deniz.guestPairingFor, 'Kira sözleşmesi');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => LiveGuestAskDialog.show(
              context,
              deniz.guestPairing.value!,
              title: deniz.guestPairingFor,
            ),
            child: const Text('aç'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining(
        'Av. Selin Arı (Arı Hukuk) “Kira sözleşmesi” belgesini canlı',
      ),
      findsOneWidget,
    );
    expect(find.text(joining.code!), findsOneWidget);
    await tester.runAsync(() async => joining.confirm());
    await settle(tester, () => joining.state == PairingState.confirmed);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(host.peers.value, isEmpty);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('live-guest-accept'))),
    );
    await settle(
      tester,
      () =>
          host.peers.value.isNotEmpty &&
          host.peers.value.single.state == LivePeerState.watching,
    );
    await tester.pump();
    expect(find.textContaining('izlemeye başladı'), findsOneWidget);
    // Gone by itself a moment later (its timer set where the pairing
    // told it, in real time).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LiveGuestAskDialog), findsNothing);
    await tester.runAsync(host.close);
    await settle(tester, () => host.peers.value.isEmpty || host.closed);
    await tester.pump(OfficePairing.limit);
  });

  test('a guest saying on the network it is the sharer\'s own device is '
      'still a guest: not known, nothing but the live channel, and shut out '
      'once forgotten', () async {
    final (deniz, selin, host) = await guests();
    final joining = selin.joinAsGuest(
      deniz.self!,
      name: 'Av. Selin Arı',
      office: 'Arı Hukuk',
    )!;
    await until(
      () => deniz.guestPairing.value?.code != null && joining.code != null,
    );
    deniz.guestPairing.value!.confirm();
    joining.confirm();
    await until(
      () =>
          host.peers.value.isNotEmpty &&
          host.peers.value.single.state == LivePeerState.watching,
    );
    final me = selin.self!;
    // The guest announces the sharer's person as its own.
    deniz.seenForTesting(
      OfficePeer(
        deviceId: me.deviceId,
        userId: deniz.self!.userId,
        name: me.name,
        device: me.device,
        platform: me.platform,
        host: me.host,
        port: me.port,
      ),
    );
    expect(deniz.isGuestOnly(me.deviceId), isTrue);
    Future<List<Map<String, Object?>>> asks(String word) async {
      final ch = await OfficeChannel.open(
        identity: identities[selin]!,
        peer: selin.guestGrant(deniz.self!.deviceId)!,
        host: '127.0.0.1',
        port: deniz.self!.port,
      );
      final heard = ch.messages.toList();
      await ch.send({'t': word});
      return heard.timeout(const Duration(seconds: 5));
    }

    // The office's records, or anything but the live channel: shut.
    expect(await asks('defter'), isEmpty);
    expect(deniz.isKnown(me.deviceId), isFalse);

    // Forgotten: not even that, and its channels are closed. The sharer's
    // real key kept, that the test is refused by the sharer, not by a key
    // missing here.
    final denizKey = selin.guestGrant(deniz.self!.deviceId)!.publicKey;
    await host.close();
    await until(() => !deniz.isGuestOnly(me.deviceId));
    await expectLater(
      OfficeChannel.open(
        identity: identities[selin]!,
        peer: KnownDevice(
          deviceId: deniz.self!.deviceId,
          userId: '',
          publicKey: denizKey,
          name: '',
          device: '',
          platform: OfficePlatform.linux,
          knownAt: DateTime.now(),
        ),
        host: '127.0.0.1',
        port: deniz.self!.port,
      ).then<Object?>((ch) => ch.messages.toList()),
      anyOf(throwsA(anything), completion(isEmpty)),
    );
  });

  test('one document takes guests at a time: the last to be set to, and the '
      'one before closing does not stop it', () async {
    final (deniz, _, a) = await guests();
    final b = LiveShareHost(
      title: 'Vekâletname',
      snapshot: () => (delta: (Delta()..insert('\n')).toJson(), blocks: []),
      blockCount: () => 0,
      network: deniz,
    );
    expect(a.takingGuests, isTrue);
    await b.takeGuests(true);
    expect(a.takingGuests, isFalse);
    expect(b.takingGuests, isTrue);
    await a.close();
    expect(deniz.guestsOpen, isTrue);
    expect(b.takingGuests, isTrue);
    await b.close();
    expect(deniz.guestsOpen, isFalse);
  });

  test('a grant let go is only that one: a later pairing\'s stays', () async {
    final (deniz, selin, host) = await guests();
    Future<KnownDevice> pairOnce() async {
      final joining = selin.joinAsGuest(deniz.self!, name: 'Av. Selin Arı')!;
      await until(
        () => deniz.guestPairing.value?.code != null && joining.code != null,
      );
      deniz.guestPairing.value!.confirm();
      joining.confirm();
      await until(() => joining.state == PairingState.done);
      await until(() => deniz.guestGrant(selin.self!.deviceId) != null);
      return deniz.guestGrant(selin.self!.deviceId)!;
    }

    final first = await pairOnce();
    await until(() => host.peers.value.isNotEmpty);
    await host.remove(selin.self!.deviceId);
    await until(() => deniz.guestGrant(selin.self!.deviceId) == null);
    final second = await pairOnce();
    expect(identical(first, second), isFalse);
    await deniz.forgetGuest(selin.self!.deviceId, first);
    expect(identical(deniz.guestGrant(selin.self!.deviceId), second), isTrue);
    await host.close();
  });

  test('written in turn: the pen asked for and given, the holder\'s words '
      'put in the sharer\'s document in order, a picture or table turned '
      'down, and the pen back when the sharer writes, on leaving it idle, '
      'on giving it back and when the right is taken', () async {
    final (pc, tablet) = await pair();
    final writer = Document.fromDelta(Delta()..insert('Kira sözleşmesi\n'));
    final host = LiveShareHost(
      title: 'Kira',
      snapshot: () => (delta: writer.toDelta().toJson(), blocks: []),
      blockCount: () => 0,
      network: pc,
      apply: (change) {
        if (!LiveShareHost.acceptable(change, writer)) return false;
        writer.compose(change, ChangeSource.remote);
        return true;
      },
    );
    writer.changes.listen((e) {
      if (e.source == ChangeSource.local) host.body(e.change);
    });
    final id = tablet.self!.deviceId;
    expect(await host.invite(id, 'tablet'), isTrue);
    await until(() => LiveShare.instance.incoming.value.isNotEmpty);
    final session = LiveShare.instance.incoming.value.single;
    await until(() => session.ready);
    bool alike() =>
        session.document != null &&
        jsonEncode(session.document!.toDelta().toJson()) ==
            jsonEncode(writer.toDelta().toJson());

    // Only seeing it: no pen to ask for, none to give.
    session.askPen();
    expect(session.askedPen, isFalse);
    expect(host.give(id), isFalse);

    host.setRight(id, LiveRight.edit);
    await until(() => session.right == LiveRight.edit);
    // Asked and turned down: told so, and may ask again.
    session.askPen();
    await until(() => host.asking.value.contains(id));
    host.turnDown(id);
    await until(() => session.refused && !session.askedPen);
    session.askPen();
    expect(session.refused, isFalse);
    await until(() => host.asking.value.contains(id));
    expect(host.give(id), isTrue);
    await until(() => session.holding);
    expect(host.asking.value, isEmpty);
    expect(host.penName, 'tablet');

    // Written there, several in a row before any is said to have gone in.
    void write(String t) => session.write(
      Delta()
        ..retain(session.document!.length - 1)
        ..insert(t),
    );
    for (final w in [' madde', ' 1', ': kira', ' bedeli']) {
      write(w);
    }
    await until(
      () => writer.toPlainText() == 'Kira sözleşmesi madde 1: kira bedeli\n',
    );
    await until(alike);

    // A table put in from there is not let in; it is shown the whole.
    session.write(
      Delta()
        ..retain(session.document!.length - 1)
        ..insert({'doc-table': 0}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await until(alike);
    expect(writer.toPlainText(), 'Kira sözleşmesi madde 1: kira bedeli\n');
    expect(session.holding, isTrue);

    // The sharer writes: the pen is theirs again.
    writer.compose(
      Delta()
        ..retain(writer.length - 1)
        ..insert('.'),
      ChangeSource.local,
    );
    await until(() => !session.holding);
    expect(host.pen.value, isNull);
    await until(alike);

    // Left idle: back with the sharer.
    host.penIdle = const Duration(milliseconds: 300);
    expect(host.give(id), isTrue);
    await until(() => session.holding);
    await until(() => !session.holding && host.pen.value == null);

    // Given back.
    expect(host.give(id), isTrue);
    await until(() => session.holding);
    session.releasePen();
    await until(() => host.pen.value == null);

    // The right taken while holding it.
    host.penIdle = const Duration(minutes: 2);
    expect(host.give(id), isTrue);
    await until(() => session.holding);
    host.setRight(id, LiveRight.view);
    await until(() => !session.holding && session.right == LiveRight.view);
    expect(host.pen.value, isNull);
    await host.close();
    await until(() => session.ended);
  });

  test('what another may write: words and marks, not a picture or a table '
      'put in, not one taken out, nothing past the end', () {
    final doc = Document.fromDelta(
      Delta()
        ..insert('Ab')
        ..insert({'doc-table': 0})
        ..insert('cd\n'),
    );
    bool ok(Delta d) => LiveShareHost.acceptable(d, doc);
    expect(ok(Delta()..insert('x')), isTrue);
    expect(
      ok(
        Delta()
          ..retain(1)
          ..retain(1, {'bold': true}),
      ),
      isTrue,
    );
    expect(ok(Delta()..delete(2)), isTrue);
    expect(
      ok(
        Delta()
          ..retain(3)
          ..delete(2),
      ),
      isTrue,
    );
    expect(ok(Delta()..insert({'doc-table': 1})), isFalse);
    expect(
      ok(
        Delta()
          ..retain(1)
          ..delete(2),
      ),
      isFalse,
    );
    expect(ok(Delta()..retain(99)), isFalse);
    expect(
      ok(
        Delta()..insert('x', {
          'link': {'a': 1},
        }),
      ),
      isFalse,
    );
    // Nothing after the last line's end, and that end never taken.
    expect(
      ok(
        Delta()
          ..retain(doc.length)
          ..insert('X'),
      ),
      isFalse,
    );
    expect(
      ok(
        Delta()
          ..retain(doc.length - 1)
          ..delete(1),
      ),
      isFalse,
    );
    expect(
      ok(
        Delta.fromJson([
          {'retain': -1},
        ]),
      ),
      isFalse,
    );
    // Marks of their kind only.
    expect(ok(Delta()..insert('x', {'font': 7})), isFalse);
    expect(ok(Delta()..insert('x', {'size': true})), isFalse);
    expect(ok(Delta()..insert('x', {'color': 'url(x)'})), isFalse);
    expect(ok(Delta()..insert('x', {'color': '#9C2525'})), isTrue);
    expect(ok(Delta()..insert('x', {'size': '16.0'})), isTrue);
    expect(ok(Delta()..insert('x', {'link': 'javascript:x'})), isFalse);
    expect(ok(Delta()..insert('x', {'nicht': true})), isFalse);
    // A line's marks only on a line's end.
    expect(ok(Delta()..insert('x', {'header': 1})), isFalse);
    expect(ok(Delta()..insert('\n', {'header': 1})), isTrue);
    expect(ok(Delta()..retain(2, {'align': 'center'})), isFalse);
    // A colour only as Quill reads it; a key unknown not even taken off.
    expect(ok(Delta()..insert('x', {'color': 'abcdef'})), isFalse);
    expect(ok(Delta()..insert('x', {'nicht': null})), isFalse);
    // A word's mark never on a line's end.
    expect(ok(Delta()..insert('a\nb', {'bold': true})), isFalse);
    expect(ok(Delta()), isFalse);
    // Marks taken off only from what is kept; none given empty.
    expect(ok(Delta()..insert('X', {'bold': null})), isFalse);
    expect(
      ok(
        Delta()
          ..insert('X')
          ..retain(2, {})
          ..insert('Y'),
      ),
      isFalse,
    );
  });

  test('a word\'s mark is not put over a line\'s end, and what was '
      'written elsewhere is undone apart from what is written here', () {
    final doc = Document.fromDelta(Delta()..insert('A\nB\n'));
    expect(
      LiveShareHost.acceptable(
        Delta()
          ..insert('X')
          ..retain(4, {'bold': true}),
        doc,
      ),
      isFalse,
    );
    expect(
      LiveShareHost.acceptable(Delta()..retain(1, {'bold': true}), doc),
      isTrue,
    );
    // Written there, then at once here: two steps, the last undone alone.
    doc.compose(
      Delta()
        ..retain(1)
        ..insert(' uzak'),
      ChangeSource.remote,
    );
    doc.compose(
      Delta()
        ..retain(6)
        ..insert(' yerel'),
      ChangeSource.local,
    );
    expect(doc.toPlainText(), 'A uzak yerel\nB\n');
    doc.undo();
    expect(doc.toPlainText(), 'A uzak\nB\n');
  });

  test('lines joined and split as a holder of the pen would, a line\'s '
      'layout only as one here has it', () {
    final layout = {'left': 0, 'first': 36};
    final doc = Document.fromDelta(
      Delta()
        ..insert('Bir')
        ..insert('\n', {'doc-layout': layout})
        ..insert('İki\n'),
    );
    bool ok(Delta d) => LiveShareHost.acceptable(d, doc);
    // The first line's end taken: the two lines joined.
    expect(
      ok(
        Delta()
          ..retain(3)
          ..delete(1),
      ),
      isTrue,
    );
    // A new line with the same layout, as Enter makes it.
    expect(
      ok(
        Delta()
          ..retain(2)
          ..insert('\n', {'doc-layout': layout}),
      ),
      isTrue,
    );
    expect(
      ok(
        Delta()
          ..retain(2)
          ..insert('\n', {
            'doc-layout': {'left': 999},
          }),
      ),
      isFalse,
    );
  });

  testWidgets('on the viewer\'s page: the pen asked for with one tap, and '
      'once given, what is typed there goes in the sharer\'s document; '
      'given back, the page is only read again', (tester) async {
    final (pc, tablet) = (await tester.runAsync(pair))!;
    final writer = Document.fromDelta(Delta()..insert('Vekâletname\n'));
    final host = LiveShareHost(
      title: 'Vekâletname',
      snapshot: () => (delta: writer.toDelta().toJson(), blocks: []),
      blockCount: () => 0,
      network: pc,
      apply: (change) {
        if (!LiveShareHost.acceptable(change, writer)) return false;
        writer.compose(change, ChangeSource.remote);
        return true;
      },
    );
    final id = tablet.self!.deviceId;
    host.setRight(id, LiveRight.edit);
    await tester.runAsync(() => host.invite(id, 'tablet'));
    await settle(tester, () => LiveShare.instance.incoming.value.isNotEmpty);
    final session = LiveShare.instance.incoming.value.single;
    await settle(tester, () => session.ready);
    await tester.pumpWidget(
      MaterialApp(home: LiveDocumentPage(session: session)),
    );
    await tester.pump();
    expect(find.textContaining('sırayla düzenleyebilirsiniz'), findsOneWidget);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('live-ask'))),
    );
    await settle(tester, () => host.asking.value.contains(id));
    await tester.runAsync(() async => host.give(id));
    await settle(tester, () => session.holding);
    await tester.pump();
    expect(find.textContaining('Kalem sizde'), findsOneWidget);
    final controller = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller;
    expect(controller.readOnly, isFalse);
    await tester.runAsync(
      () async => controller.replaceText(
        controller.document.length - 1,
        0,
        ' — Av. Deniz Kaya',
        null,
      ),
    );
    await settle(
      tester,
      () => writer.toPlainText() == 'Vekâletname — Av. Deniz Kaya\n',
    );
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('live-release'))),
    );
    await settle(tester, () => host.pen.value == null);
    await tester.pump();
    expect(
      tester.widget<QuillEditor>(find.byType(QuillEditor)).controller.readOnly,
      isTrue,
    );
    await tester.runAsync(host.close);
    await settle(tester, () => session.ended);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'what a real editor makes when one types, presses Enter, marks '
    'across lines and pastes lines all goes in, the two alike after',
    () async {
      final layout = {'left': 0, 'first': 36};
      Delta start() => Delta()
        ..insert('Birinci satır', {'size': '16.0', 'font': 'Times New Roman'})
        ..insert('\n', {'doc-layout': layout})
        ..insert('İkinci satır', {'size': '16.0'})
        ..insert('\n', {'doc-layout': layout});
      final sharer = Document.fromDelta(start());
      final holder = QuillController(
        document: Document.fromDelta(start()),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final refused = <Delta>[];
      holder.document.changes.listen((e) {
        if (e.source != ChangeSource.local) return;
        if (LiveShareHost.acceptable(e.change, sharer)) {
          sharer.compose(e.change, ChangeSource.remote);
        } else {
          refused.add(e.change);
        }
      });
      // Each change is told a moment after it is made.
      Future<void> told() => Future<void>.delayed(Duration.zero);
      // Typed at the end of the first line, then Enter, then more.
      holder.replaceText(
        13,
        0,
        ' ek',
        const TextSelection.collapsed(offset: 16),
      );
      await told();
      holder.replaceText(
        16,
        0,
        '\n',
        const TextSelection.collapsed(offset: 17),
      );
      await told();
      holder.replaceText(
        17,
        0,
        'yeni',
        const TextSelection.collapsed(offset: 21),
      );
      await told();
      // Bold across two lines.
      holder.formatText(0, 25, Attribute.bold);
      await told();
      // Lines pasted.
      holder.replaceText(3, 0, 'a\nb\nc', null);
      await told();
      // Two lines joined.
      holder.replaceText(16, 1, '', null);
      await told();
      expect(refused, isEmpty);
      expect(
        jsonEncode(sharer.toDelta().toJson()),
        jsonEncode(holder.document.toDelta().toJson()),
      );
    },
  );

  testWidgets('one\'s own device is listed by the name it was known under, '
      'though it says none on the network', (tester) async {
    final (pc, tablet) = (await tester.runAsync(pair))!;
    final t = tablet.self!;
    // Not open to the office: its announcement names nothing.
    pc.seenForTesting(
      OfficePeer(
        deviceId: t.deviceId,
        userId: t.userId,
        name: '',
        device: '',
        platform: t.platform,
        host: t.host,
        port: t.port,
      ),
    );
    final host = LiveShareHost(
      title: 'Dilekçe',
      snapshot: () => (delta: (Delta()..insert('\n')).toJson(), blocks: []),
      blockCount: () => 0,
      network: pc,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveShareDialog(host: host, network: pc),
        ),
      ),
    );
    expect(find.text('tablet'), findsOneWidget);
    await tester.runAsync(host.close);
  });
}

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
