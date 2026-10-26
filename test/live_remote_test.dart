import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/editor/document_lock.dart';
import 'package:evrak_convert/services/live/live_remote.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:evrak_convert/services/live/live_share.dart';
import 'package:evrak_convert/services/office/office_chat.dart';
import 'package:evrak_convert/services/office/office_known.dart';
import 'package:evrak_convert/services/office/office_ledger.dart';
import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/services/office/office_task.dart';
import 'package:evrak_convert/ui/live/live_remote_dialogs.dart';
import 'package:evrak_convert/ui/live/live_share_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show ChangeSource, Document;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/canli_relay/relay.dart';

void main() {
  late RelayServer relay;
  late Directory dir;
  final server = LiveRelay.server;

  setUp(() async {
    // Flutter's test binding answers every HTTP request itself; the relay
    // here is a real one, on this computer.
    HttpOverrides.global = null;
    dir = Directory.systemTemp.createTempSync('folio_uzak_');
    relay = await RelayServer.start();
    LiveRelay.server = Uri.parse('ws://127.0.0.1:${relay.port}');
    LiveRelay.rounds = 1000;
  });
  tearDown(() async {
    await relay.close();
    LiveRelay.server = server;
    dir.deleteSync(recursive: true);
  });

  OfficeNetwork network() => OfficeNetwork(
    settings: () async => File('${dir.path}/buro.json'),
    known: KnownDevices(file: () async => File('${dir.path}/k.json')),
    ledger: OfficeLedger(file: () async => File('${dir.path}/d.json')),
    tasks: OfficeTasks(file: () async => File('${dir.path}/g.json')),
    chats: OfficeChats(file: () async => File('${dir.path}/m.json')),
  );

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  test('a code reads as typed, pasted or in its link; nothing else is one', () {
    final code = RemoteCode.make();
    expect(code, hasLength(9));
    expect(RemoteCode.read(RemoteCode.shown(code)), code);
    expect(RemoteCode.read(RemoteCode.link(code).toString()), code);
    expect(RemoteCode.read('k7q 4mp 2xd'), 'K7Q4MP2XD');
    // Read as Crockford reads them.
    expect(RemoteCode.read('O1L-IAB-CDE'), '011-1AB-CDE'.replaceAll('-', ''));
    expect(RemoteCode.read('K7Q4MP2X'), isNull);
    expect(RemoteCode.read('K7Q4MP2XU'), isNull);
    expect(RemoteCode.message(code, 'Cevap'), contains(RemoteCode.shown(code)));
  });

  test('another office joins by the code: asked first, the same digits on '
      'both screens, then the document comes and goes both ways in turn; '
      'the relay never has the code', () async {
    final writer = Document()..insert(0, 'Davacı vekili');
    final host = LiveShareHost(
      title: 'Cevap dilekçesi',
      snapshot: () => (delta: writer.toDelta().toJson(), blocks: const []),
      blockCount: () => 0,
      network: network(),
      apply: (change) {
        writer.compose(change, ChangeSource.remote);
        return true;
      },
    );
    writer.changes.listen((e) {
      if (e.source == ChangeSource.local) host.body(e.change);
    });
    final invite = host.inviteRemote();
    await until(() => invite.state == RemoteInviteState.waiting);
    expect(relay.rooms, 1);

    final join = RemoteJoin.start(
      RemoteCode.read(RemoteCode.shown(invite.code))!,
      name: 'Av. Ayşe Demir',
      office: 'Demir Hukuk',
    );
    await until(() => invite.state == RemoteInviteState.arrived);
    await until(() => join.state == RemoteJoinState.asking);
    expect(invite.name, 'Av. Ayşe Demir');
    expect(invite.office, 'Demir Hukuk');
    expect(invite.digits, matches(RegExp(r'^\d\d \d\d$')));
    expect(join.digits, invite.digits);
    // Nothing of the document yet: the sharer has not let them in.
    expect(LiveShare.instance.incoming.value, isEmpty);

    final ch = invite.accept()!;
    expect(
      await host.showRemote(
        invite.deviceId!,
        invite.name,
        ch,
        LiveRight.edit,
        from: 'Av. Mehmet Kaya',
      ),
      isTrue,
    );
    expect(host.isRemote(invite.deviceId!), isTrue);
    await until(() => join.state == RemoteJoinState.joined);
    final session = join.session!;
    expect(session.from, 'Av. Mehmet Kaya');
    expect(session.title, 'Cevap dilekçesi');
    await until(() => session.ready);
    expect(session.document!.toPlainText(), 'Davacı vekili\n');

    // Written by the sharer: seen there.
    writer.insert(writer.length - 1, ' cevaplarımızı sunar.');
    await until(
      () =>
          session.document!.toPlainText() ==
          'Davacı vekili cevaplarımızı sunar.\n',
    );

    // Given the pen: written there, put in here.
    session.askPen();
    await until(() => host.asking.value.contains(invite.deviceId));
    host.give(invite.deviceId!);
    await until(() => session.holding);
    session.write(Delta()..insert('Sayın Mahkeme, '));
    await until(
      () => writer.toPlainText().startsWith('Sayın Mahkeme, Davacı vekili'),
    );

    // The talk beside it, both ways, under each one's name; a note of who
    // came on the sharer's side.
    host.me = 'Av. Mehmet Kaya';
    host.say('1. maddeyi sen yazar mısın?');
    await until(() => session.chat.value.isNotEmpty);
    expect(session.chat.value.single.from, 'Av. Mehmet Kaya');
    expect(session.chat.value.single.text, '1. maddeyi sen yazar mısın?');
    session.say(
      'Madde numarası 7.2 olabilir.',
      quote: 'sözleşmenin 7. maddesindeki',
    );
    await until(() => host.chat.value.any((m) => m.text.contains('7.2')));
    final heard = host.chat.value.last;
    expect(heard.from, 'Av. Ayşe Demir');
    expect(heard.quote, 'sözleşmenin 7. maddesindeki');
    expect(heard.mine, isFalse);
    expect(
      host.chat.value.where((m) => m.note).single.text,
      contains('katıldı'),
    );
    // Nothing said is let through as nothing, nor without end.
    session.say('   ');
    session.say('x' * 5000);
    await until(() => host.chat.value.last.text.length == 2000);

    // The code never reached the relay: its room is named otherwise.
    expect(relay.rooms, 1);

    await host.close();
    await until(() => session.ended);
    await until(() => relay.rooms == 0);
    expect(LiveShare.instance.incoming.value, isEmpty);
    // Nothing of the talk kept on either side.
    expect(host.chat.value, isEmpty);
    expect(session.chat.value, isEmpty);
  });

  test('a wrong code finds nothing; a used one is not let in twice', () async {
    final wrong = RemoteJoin.start(RemoteCode.make(), name: 'Av. Ayşe Demir');
    await until(() => wrong.state == RemoteJoinState.failed);
    expect(wrong.error, contains('bulunamadı'));

    final invite = RemoteInvite.make();
    await until(() => invite.state == RemoteInviteState.waiting);
    final first = RemoteJoin.start(invite.code, name: 'Birinci');
    await until(() => invite.state == RemoteInviteState.arrived);
    final second = RemoteJoin.start(invite.code, name: 'İkinci');
    await until(() => second.state == RemoteJoinState.failed);
    expect(second.error, contains('kullanılmış'));
    expect(first.state, RemoteJoinState.asking);
    await invite.decline();
    await until(() => first.state == RemoteJoinState.declined);
  });

  test('one who knows the room but not the code is not let in, and the '
      'invitation is spent', () async {
    final invite = RemoteInvite.make();
    await until(() => invite.state == RemoteInviteState.waiting);
    // The relay's view: a room's name, not the code. One who has the
    // name alone (the relay itself, say) says hello with a key of its own
    // and cannot prove the code.
    final probe = await HttpClient().get('127.0.0.1', relay.port, '/saglik');
    expect((await probe.close()).statusCode, 200);
    final room = await RemoteCode.roomOf(invite.code);
    expect(room, isNot(contains(invite.code)));
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:${relay.port}/v1/oda/$room?rol=katilan',
    );
    final heard = <Map<String, Object?>>[];
    ws.listen((d) => heard.add(jsonDecode(d as String)));
    ws.add(
      jsonEncode({
        't': 'merhaba',
        'v': 1,
        'eph': base64Encode(List.filled(32, 9)),
      }),
    );
    await until(() => heard.isNotEmpty);
    ws.add(jsonEncode({'t': 'onay', 'mac': base64Encode(List.filled(32, 1))}));
    await until(() => invite.state == RemoteInviteState.failed);
    expect(invite.error, contains('doğrulayamadı'));
    await ws.close();
  });

  test('the relay keeps a room only so long, and takes no message larger '
      'than it allows', () async {
    await relay.close();
    relay = await RelayServer.start(
      limits: const RelayLimits(
        waiting: Duration(milliseconds: 300),
        message: 1024,
      ),
    );
    LiveRelay.server = Uri.parse('ws://127.0.0.1:${relay.port}');
    final invite = RemoteInvite.make();
    await until(() => invite.state == RemoteInviteState.expired);
    expect(relay.rooms, 0);

    final room = 'a' * 43;
    final sharer = await WebSocket.connect(
      'ws://127.0.0.1:${relay.port}/v1/oda/$room?rol=paylasan',
    );
    final joiner = await WebSocket.connect(
      'ws://127.0.0.1:${relay.port}/v1/oda/$room?rol=katilan',
    );
    sharer.listen((_) {});
    joiner.listen((_) {});
    joiner.add('x' * 2048);
    await until(() => joiner.closeCode != null && sharer.closeCode != null);
    expect(relay.rooms, 0);
  });

  testWidgets('in the dialog: Uzaktan makes a code; the one joining types '
      'it, both see the same digits, and the sharer lets them in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> ready(bool Function() done) async {
      for (var i = 0; i < 300 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        // The test's clock moved on too: the timers set meanwhile run.
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(done(), isTrue);
    }

    final host = LiveShareHost(
      title: 'Kira sözleşmesi',
      snapshot: () => (
        delta: (Delta()..insert('Kiraya veren\n')).toJson(),
        blocks: const [],
      ),
      blockCount: () => 0,
      network: network(),
      apply: (_) => true,
    );
    LiveSession? joined;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Row(
              children: [
                Expanded(child: LiveShareDialog(host: host)),
                Expanded(
                  child: Center(
                    child: TextButton(
                      key: const ValueKey('join-open'),
                      onPressed: () async =>
                          joined = await RemoteJoinDialog.show(context),
                      child: const Text('katıl'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Uzaktan'));
    await tester.pump();
    await ready(
      () => find.byKey(const ValueKey('remote-code')).evaluate().isNotEmpty,
    );
    final code = host.remoteInvite.value!.code;
    expect(find.text(RemoteCode.shown(code)), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('join-open')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('remote-join-go')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('remote-join-code')),
      RemoteCode.link(code).toString(),
    );
    await tester.enterText(
      find.byKey(const ValueKey('remote-join-name')),
      'Av. Ayşe Demir',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('remote-join-go')));
    await ready(
      () => find.byKey(const ValueKey('remote-request')).evaluate().isNotEmpty,
    );
    await ready(
      () => find
          .byKey(const ValueKey('remote-join-asking'))
          .evaluate()
          .isNotEmpty,
    );
    final digits = host.remoteInvite.value!.digits;
    expect(find.text(digits), findsNWidgets(2));
    expect(find.text('Av. Ayşe Demir'), findsOneWidget);

    // The joining dialog's barrier covers this half: on two computers it
    // would not, so the sharer's button is pressed as a click would.
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('remote-let-edit')))
        .onPressed!();
    await ready(() => joined != null);
    await tester.pump();
    expect(find.text('UZAKTAN KATILANLAR'), findsOneWidget);
    expect(find.text('Bir kişi daha davet et'), findsOneWidget);
    await ready(() => joined!.ready);
    expect(joined!.document!.toPlainText(), 'Kiraya veren\n');
    expect(joined!.right, LiveRight.edit);

    await tester.runAsync(host.close);
    await ready(() => joined!.ended);
    await tester.pumpWidget(const SizedBox());
    // Their timers (answers waited for, beats) run out.
    await tester.pump(const Duration(minutes: 20));
  });

  testWidgets('asked from the home page, a phone\'s editor opens the sharing '
      'from below on its Uzaktan side, WhatsApp first; closed, it opens '
      'again when someone comes with the code', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> ready(bool Function() done) async {
      for (var i = 0; i < 300 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(done(), isTrue);
    }

    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    final lockFolder = DocumentLock.folder;
    DocumentLock.folder = () async => Directory('${dir.path}/acik');
    addTearDown(() => DocumentLock.folder = lockFolder);
    final file = File('${dir.path}/Kira sözleşmesi.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'Kiraya veren')]),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: EditorWidget(
            initialFilePath: file.path,
            initialFormat: EvrakFormat.udf,
            liveAsk: 1,
          ),
        ),
      ),
    );
    final code = find.byKey(const ValueKey('remote-code'));
    await ready(() => code.evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('WhatsApp ile gönder'), findsOneWidget);
    // From below, not a dialog in the middle.
    expect(find.byType(BottomSheet), findsOneWidget);
    final shown = (tester.widget(code) as SelectableText).data!;

    // Put away; someone comes with the code: asked about at once.
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    final join = RemoteJoin.start(
      RemoteCode.read(shown)!,
      name: 'Av. Ayşe Demir',
    );
    await ready(
      () => find.byKey(const ValueKey('remote-request')).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('remote-let-view')));
    await tester.tap(find.byKey(const ValueKey('remote-let-view')));
    await ready(() => join.state == RemoteJoinState.joined);
    await ready(() => join.session!.ready);
    expect(join.session!.document!.toPlainText(), startsWith('Kiraya veren'));
    expect(join.session!.right, LiveRight.view);

    await tester.pumpWidget(const SizedBox());
    await ready(() => join.session!.ended);
    await tester.pump(const Duration(minutes: 20));
  });
}
