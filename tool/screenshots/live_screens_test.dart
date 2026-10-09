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
import 'package:evrak_convert/ui/widgets/flowing_document_view.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show ChangeSource, Document, QuillController;
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
        ..insert('KİRA SÖZLEŞMESİ', {'bold': true})
        ..insert('\n', {'align': 'center'})
        ..insert(
          '1. Kiraya veren Deniz Yılmaz, Muratpaşa / Antalya’daki 3 numaralı '
          'bağımsız bölümü, kiracı Örnek Lojistik A.Ş.’ye büro olarak '
          'kullanılmak üzere kiraya vermiştir.\n'
          '2. Kira süresi 1 Kasım 2026’dan başlamak üzere bir yıldır. Süre '
          'bitiminden on beş gün önce yazılı bildirimde bulunulmadıkça '
          'sözleşme aynı koşullarla bir yıl uzar.\n'
          '3. Kiracı, kiralananı özenle kullanmak ve komşulara saygı göstermekle '
          'yükümlüdür; kiralananı kiraya verenin yazılı izni olmadan başkasına '
          'kullandıramaz.\n'
          '4. Kiracı, kira bedelini her ayın beşine kadar kiraya verenin '
          'banka hesabına öder.\n',
        )
        ..insert({'doc-table': 0})
        ..insert('\n')
        ..insert(
          '5. Kira bedeli her kira yılının başında, bir önceki kira yılının '
          'on iki aylık tüketici fiyat endeksi ortalamasına göre artırılır.\n'
          '6. Kiracı, kiralananın olağan kullanımından doğan küçük onarımları '
          'kendisi yaptırır; esaslı onarımlar kiraya verene aittir.\n',
        ),
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

    // The scene for the site: the sharer's computer, its document only
    // read while the other side's lawyer writes on her phone, both the
    // same contract as it is written.
    await tester.runAsync(() async {
      final doc = session.document!;
      session.write(
        Delta()
          ..retain(doc.length - 1)
          ..insert(
            '\n7. Taraflar, bu sözleşmeden doğan uyuşmazlıklarda Antalya '
            'mahkemelerinin ve icra dairelerinin yetkili olduğunu kabul eder.',
          ),
      );
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (writer.toPlainText().contains('7. Taraflar')) break;
      }
    });
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    debugDisableShadows = false;
    final sharerView = QuillController(
      document: Document.fromDelta(writer.toDelta()),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
    Widget label(String who, String what, Color dot) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: dot),
        const SizedBox(width: 8),
        Text(
          who,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        Text(
          '  ·  $what',
          style: const TextStyle(fontSize: 14, color: Color(0xFF5B6576)),
        ),
      ],
    );
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            return Material(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE8EEF8), Color(0xFFF4F6F9)],
                  ),
                ),
                child: Stack(
                  children: [
                    // The sharer's computer.
                    Positioned(
                      left: 40,
                      top: 70,
                      width: 1060,
                      height: 860,
                      child: Material(
                        elevation: 24,
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              height: 44,
                              color: const Color(0xFFF1F3F7),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.description_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Kira sözleşmesi.udf',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Spacer(),
                                  Icon(
                                    Icons.cast_connected_rounded,
                                    size: 18,
                                    color: Color(0xFF2D5AA8),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Canlı paylaşılıyor · 2 kişi',
                                    style: TextStyle(
                                      color: Color(0xFF2D5AA8),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // The editor's own strip while another holds the pen.
                            Material(
                              color: scheme.tertiaryContainer,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                      color: scheme.onTertiaryContainer,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Av. Selin Arı yazıyor · belgeniz şu an '
                                        'yalnız okunur',
                                        style: TextStyle(
                                          color: scheme.onTertiaryContainer,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {},
                                      child: const Text('Kalemi geri al'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: FlowingDocumentView(
                                model: DocModel(blocks: const []),
                                scale: 1.45,
                                live: (
                                  controller: sharerView,
                                  blocks: () => blocks,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // The other side's lawyer's phone, writing.
                    Positioned(
                      right: 60,
                      top: 120,
                      width: 400,
                      height: 820,
                      child: Material(
                        elevation: 30,
                        color: const Color(0xFF1D2330),
                        borderRadius: BorderRadius.circular(52),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(40),
                            child: MediaQuery(
                              data: MediaQuery.of(context)
                                  .copyWith(size: const Size(372, 792)),
                              child: LiveDocumentPage(session: session),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 48,
                      top: 26,
                      child: label(
                        'Av. Deniz Kaya',
                        'paylaşan, bilgisayarında',
                        const Color(0xFF2D5AA8),
                      ),
                    ),
                    Positioned(
                      right: 70,
                      top: 76,
                      child: label(
                        'Av. Selin Arı',
                        'karşı vekil, telefonunda',
                        const Color(0xFF16754F),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, 'canli-sahne');
    debugDisableShadows = true;

    await tester.runAsync(host.close);
    await wait(() => session.ended);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 4));
  });
}
