import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/live/live_share.dart';
import 'package:evrak_convert/services/office/office_chat.dart';
import 'package:evrak_convert/services/office/office_identity.dart';
import 'package:evrak_convert/services/office/office_known.dart';
import 'package:evrak_convert/services/office/office_ledger.dart';
import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/services/office/office_peer.dart';
import 'package:evrak_convert/services/office/office_task.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:flutter_quill/flutter_quill.dart' show ChangeSource, Document;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('folio_live_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<OfficeNetwork> folio(String device) async {
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
    await net.listenForTesting(
      identity,
      OfficePeer(
        deviceId: identity.deviceId,
        userId: identity.userId,
        name: 'Av. Erkan Öz',
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
