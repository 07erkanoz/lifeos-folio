// Pictures of live sharing written in turn (the share dialog with the pen
// given, the viewer's page asking for it and holding it), from invented
// names over two Folios on this computer, for checking them by eye. Not
// part of the test suite:
//
//   flutter test tool/screenshots/live_screens_test.dart
//
// Pictures land in tool/screenshots/out/.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:evrak_convert/ui/live/live_document_page.dart';
import 'package:evrak_convert/ui/live/live_share_dialog.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show ChangeSource, Document;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

const pixelRatio = 1.5;
final _frame = GlobalKey();

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  for (final name in ['FlutterTest', 'Ahem']) {
    await family(name, [
      for (final style in ['Regular', 'Bold'])
        'fonts/pdf/LiberationSans-$style.ttf',
    ]);
  }
  for (final name in ['Sans', 'Serif', 'Mono']) {
    await family('Liberation$name', [
      for (final style in ['Regular', 'Bold', 'Italic', 'BoldItalic'])
        'fonts/pdf/Liberation$name-$style.ttf',
    ]);
  }
  await family('Consolas', [
    for (final style in ['Regular', 'Bold'])
      'fonts/pdf/LiberationMono-$style.ttf',
  ]);
  final flutter = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  final material = '${flutter.path}/artifacts/material_fonts';
  await family('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await family('Roboto', [
    for (final style in ['Regular', 'Medium', 'Bold'])
      '$material/Roboto-$style.ttf',
  ]);
}

Future<void> _shot(WidgetTester tester, String name) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  final boundary =
      _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final out = File('tool/screenshots/out/$name.png');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes!);
}

Widget _app(Widget home) => RepaintBoundary(
  key: _frame,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    locale: const Locale('tr'),
    supportedLocales: const [Locale('tr')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
  ),
);

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

void main() {
  setUpAll(_loadFonts);

  testWidgets('live sharing written in turn', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 640));
    final dir = Directory.systemTemp.createTempSync('folio_live_shots_');
    Future<OfficeNetwork> folio(String device) async {
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
      );
      final identity = await OfficeIdentity.load(store: _Store());
      await net.listenForTesting(
        identity,
        OfficePeer(
          deviceId: identity.deviceId,
          userId: identity.userId,
          name: 'Av. Deniz Kaya',
          device: device,
          platform: OfficePlatform.linux,
        ),
      );
      return net;
    }

    Future<void> wait(bool Function() done) async {
      for (var i = 0; i < 500 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }

    final (pc, tablet) = (await tester.runAsync(() async {
      final pc = await folio('masaustu'), tablet = await folio('Tablet');
      pc.seenForTesting(tablet.self!);
      tablet.seenForTesting(pc.self!);
      final asking = pc.pair(tablet.self!)!;
      while (tablet.incoming.value?.code == null || asking.code == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      tablet.incoming.value!.confirm();
      asking.confirm();
      while (pc.self!.userId != tablet.self!.userId) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      pc.seenForTesting(tablet.self!);
      tablet.seenForTesting(pc.self!);
      LiveShare.instance.listen(tablet);
      return (pc, tablet);
    }))!;
    final writer = Document.fromDelta(
      Delta()
        ..insert(
          '4. Kiracı, kira bedelini her ayın beşine kadar kiraya verenin '
          'banka hesabına öder.\n',
        )
        ..insert({'doc-table': 0})
        ..insert('\n'),
    );
    DocBlock cell(String text, {bool bold = false}) => DocBlock(
      plainText: text,
      spans: [
        if (bold) DocSpan(startOffset: 0, length: text.length, bold: true),
      ],
    );
    final blocks = [
      DocBlock(
        type: DocBlockType.table,
        plainText: '',
        table: DocTable(
          rows: [
            DocTableRow(
              cells: [
                DocTableCell(blocks: [cell('Kira bedeli', bold: true)]),
                DocTableCell(blocks: [cell('25.000 TL')]),
              ],
            ),
          ],
        ),
      ),
    ];
    final host = LiveShareHost(
      title: 'Kira sözleşmesi',
      snapshot: () => (delta: writer.toDelta().toJson(), blocks: blocks),
      blockCount: () => blocks.length,
      network: pc,
      apply: (change) {
        writer.compose(change, ChangeSource.remote);
        return true;
      },
    );
    final id = tablet.self!.deviceId;
    host.setRight(id, LiveRight.edit);
    await tester.runAsync(() => host.invite(id, 'Tablet'));
    await wait(() => LiveShare.instance.incoming.value.isNotEmpty);
    final session = LiveShare.instance.incoming.value.single;
    await wait(() => session.ready);

    await tester.pumpWidget(_app(LiveDocumentPage(session: session)));
    await _shot(tester, 'canli-izleyen-iste');

    await tester.runAsync(() async => host.give(id));
    await wait(() => session.holding);
    await _shot(tester, 'canli-izleyen-kalem');

    await tester.pumpWidget(
      _app(
        Scaffold(
          backgroundColor: const Color(0xFFE9EBEF),
          body: Center(
            child: LiveShareDialog(host: host, network: pc),
          ),
        ),
      ),
    );
    await _shot(tester, 'canli-pencere-kalem');

    await tester.runAsync(host.close);
    await wait(() => session.ended);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 4));
  });
}
