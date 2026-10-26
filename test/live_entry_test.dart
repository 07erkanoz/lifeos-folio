import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/live/live_links.dart';
import 'package:evrak_convert/services/live/live_remote.dart';
import 'package:evrak_convert/services/platform/document_launch.dart';
import 'package:evrak_convert/ui/live/live_hub.dart';
import 'package:evrak_convert/ui/mobile/document_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an invitation link names its code, on a phone and on a computer; '
      'nothing else does', () {
    expect(
      LiveLinks.codeOf('https://canli.lifeos.com.tr/#K7Q4MP2XD'),
      'K7Q4MP2XD',
    );
    expect(LiveLinks.codeOf('lifeos-folio://katil/k7q4mp2xd'), 'K7Q4MP2XD');
    expect(LiveLinks.codeOf('https://ornek.com/#K7Q4MP2XD'), isNull);
    expect(LiveLinks.codeOf('lifeos-folio://baska/K7Q4MP2XD'), isNull);
    expect(LiveLinks.codeOf('https://canli.lifeos.com.tr/'), isNull);
    expect(LiveLinks.deepLink('K7Q4MP2XD'), 'lifeos-folio://katil/K7Q4MP2XD');

    final before = LiveLinks.came.value?.n ?? 0;
    expect(LiveLinks.take('lifeos-folio://katil/K7Q4MP2XD'), isTrue);
    expect(LiveLinks.take('https://ornek.com'), isFalse);
    expect(LiveLinks.came.value?.code, 'K7Q4MP2XD');
    // The same code opened again asks again.
    LiveLinks.take('https://canli.lifeos.com.tr/#K7Q4MP2XD');
    expect(LiveLinks.came.value!.n, before + 2);
  });

  test('a code is found in an invitation as WhatsApp carries it', () {
    final message = RemoteCode.message('K7Q4MP2XD', 'Cevap dilekçesi');
    expect(RemoteCode.find(message), 'K7Q4MP2XD');
    expect(RemoteCode.find('kod: k7q 4mp 2xd'), 'K7Q4MP2XD');
    expect(RemoteCode.find('Duruşma 2024-700 saat 10:30'), isNull);
  });

  test('Folio started by a link takes it as an invitation, not a document, '
      'and hands it on to the Folio already open', () {
    final launch = DocumentLaunch.parse(['lifeos-folio://katil/K7Q4MP2XD']);
    expect(launch.paths, isEmpty);
    expect(launch.link, 'lifeos-folio://katil/K7Q4MP2XD');
    expect(launch.forwarded, isNotEmpty);
    expect(
      DocumentLaunch.parse(launch.forwarded).link,
      'lifeos-folio://katil/K7Q4MP2XD',
    );
    expect(DocumentLaunch.parse(const []).forwarded, isEmpty);
  });

  testWidgets('Canlı belge: the code from the clipboard in place, joined '
      'with a tap; a recent document shared with another, no PDF among '
      'them', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return {'text': RemoteCode.message('M3N8PQ4RT', 'Cevap')};
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final done = <String>[];
    final recent = [
      EvrakFile.fromPath('/belgeler/Cevap dilekçesi.udf'),
      EvrakFile.fromPath('/belgeler/Bilirkişi raporu.pdf'),
      EvrakFile.fromPath('/belgeler/Kira sözleşmesi.docx'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => LiveHub.show(
                  context,
                  recent: recent,
                  onJoin: (code) => done.add('join:$code'),
                  onShare: (f) => done.add('share:${f.name}'),
                  onPick: () => done.add('pick'),
                ),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    expect(find.text('M3N-8PQ-4RT'), findsOneWidget);
    expect(find.text('Cevap dilekçesi'), findsOneWidget);
    expect(find.text('Kira sözleşmesi'), findsOneWidget);
    expect(find.text('Bilirkişi raporu'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('live-hub-join')));
    await tester.pumpAndSettle();
    expect(done, ['join:M3N8PQ4RT']);
    // Closed, and what was chosen done after.
    expect(find.byKey(const ValueKey('live-hub')), findsNothing);

    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kira sözleşmesi'));
    await tester.pumpAndSettle();
    expect(done.last, 'share:Kira sözleşmesi.docx');
  });

  testWidgets('the phone\'s home page has Canlı belge among the documents\' '
      'buttons, across the row', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var live = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileDocumentHome(
            recent: const [],
            onOpen: () {},
            onNew: () {},
            onArchive: () {},
            onGallery: () {},
            onLive: () => live++,
            onRecovery: () {},
            onRecent: (_) {},
            onShare: (_) {},
            recoveryCount: 0,
          ),
        ),
      ),
    );
    await tester.pump();
    final tile = find.byKey(const ValueKey('mobile-live'));
    await tester.ensureVisible(tile);
    expect(tester.getSize(tile).width, greaterThan(300));
    await tester.tap(tile);
    expect(live, 1);
  });
}
