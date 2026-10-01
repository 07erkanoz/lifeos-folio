// Screenshots of Folio for lifeos.com.tr, drawn from invented documents with
// the app's real fonts, offline. Not part of the test suite:
//
//   flutter test tool/screenshots/folio_screens_test.dart
//
// Pictures land in tool/screenshots/out/. The law articles and the decision
// are read from tool/screenshots/data/support/, which fetch_legal_test.dart
// fills once.
// The screenshots use the app's test seams; this is a test in all but its
// folder, which the analyser does not count as one.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:archive/archive.dart';
import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/services/legal/case_law.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:evrak_convert/ui/legal/case_law_search_screen.dart';
import 'package:evrak_convert/ui/widgets/editor_toolbar.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/file_preview.dart';
import 'package:evrak_convert/ui/widgets/uyap_case_panel.dart';
import 'package:evrak_convert/services/uyap/adalet_eimza.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:evrak_convert/services/pdf/pdfium_setup.dart';
import 'package:evrak_convert/services/platform/document_scan.dart';
import 'package:evrak_convert/services/signing/mobile_signature.dart';
import 'package:evrak_convert/services/signing/pkcs11/pkcs11_discovery.dart';
import 'package:evrak_convert/services/signing/pkcs11/pkcs11_session.dart';
import 'package:evrak_convert/services/signing/udf_signing_service.dart';
import 'package:evrak_convert/ui/widgets/signing_dialog.dart';
import 'package:evrak_convert/services/speech/speech_models.dart';
import 'package:evrak_convert/services/speech/speech_session.dart';
import 'package:evrak_convert/services/uyap/edevlet_window.dart';
import 'package:evrak_convert/services/uyap/uyap_case_links.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/widgets/uyap_operations_dialog.dart';
import 'package:evrak_convert/ui/widgets/uyap_send_dialog.dart';

import '../../test/support/fake_path_provider.dart';
import '../../test/support/pdfium.dart';
import '../../test/speech_session_test.dart'
    show FakeEar, FakeMicrophone, FakePlayer, FakeVoice;
import 'demo_documents.dart';
import 'demo_uyap.dart';

/// The size pictures are taken at: a 1440 × 900 window on a 2× screen.
const logical = Size(1440, 900);
const pixelRatio = 2.0;

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

  // Text with no family is drawn in the platform's font; flutter_test's
  // stand-in for it draws boxes. Liberation Sans stands in instead.
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
  final flutter = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  final material = '${flutter.path}/artifacts/material_fonts';
  await family('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await family('Roboto', [
    for (final style in ['Regular', 'Medium', 'Bold'])
      '$material/Roboto-$style.ttf',
  ]);
}

/// Lets both clocks move: file work on the real one, timers on the fake one.
Future<void> _settle(
  WidgetTester tester,
  bool Function() ready, {
  int rounds = 150,
}) async {
  for (var i = 0; i < rounds && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  for (var i = 0; i < 10; i++) {
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
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: const [Locale('tr', 'TR')],
    locale: const Locale('tr', 'TR'),
    home: Scaffold(body: home),
  ),
);

/// A private folder standing in for the app's own, with the kept law
/// articles and decision already in its support folder.
Directory _home() {
  final base = Directory.systemTemp.createTempSync('folio-screens-');
  addTearDown(() => base.deleteSync(recursive: true));
  final support = Directory('${base.path}/support')..createSync();
  for (final entity in Directory(
    'tool/screenshots/data/support',
  ).listSync(recursive: true)) {
    if (entity is! File) continue;
    final to = File(
      '${support.path}/${entity.path.substring('tool/screenshots/data/support/'.length)}',
    );
    to.parent.createSync(recursive: true);
    entity.copySync(to.path);
  }
  useFakePathProvider(base);
  DocumentHistory.instance = DocumentHistory(
    directory: Directory('${base.path}/history'),
  );
  return base;
}

DocBlock _block(DemoParagraph paragraph) {
  final bold = paragraph.bold < 0 ? paragraph.text.length : paragraph.bold;
  return DocBlock(
    plainText: paragraph.text,
    alignment: paragraph.center
        ? DocAlignment.center
        : paragraph.justify
        ? DocAlignment.justify
        : DocAlignment.left,
    spacingAfter: paragraph.text.isEmpty ? 0 : 6,
    spans: [
      if (bold > 0) DocSpan(startOffset: 0, length: bold, bold: true),
      if (bold < paragraph.text.length)
        DocSpan(startOffset: bold, length: paragraph.text.length - bold),
    ],
  );
}

String get _decision =>
    File('tool/screenshots/data/decision.txt').readAsStringSync().trim();

/// Writes the demo archive into [folder], dated as [DemoFile.daysAgo] says.
Future<void> _writeArchive(Directory folder) async {
  final now = DateTime.now();
  for (final demo in demoArchive(_decision)) {
    final model = DocModel(
      blocks: [for (final p in demo.paragraphs) _block(p)],
    );
    final file = File('${folder.path}/${demo.name}');
    await file.writeAsBytes(
      demo.name.endsWith('.pdf')
          ? await PdfService.modelToPdfBytes(model)
          : UdfWriter.writeBytes(model),
    );
    await file.setLastModified(
      now.subtract(Duration(days: demo.daysAgo, hours: demo.name.length % 7)),
    );
  }
}

/// Writes the demo petition into [base] and opens it in the editor.
Future<File> _openPetition(
  WidgetTester tester,
  Directory base, {
  CaseLaw? caseLaw,
}) async {
  final file = File('${base.path}/Boşanma Dava Dilekçesi.udf');
  await tester.runAsync(
    () => file.writeAsBytes(
      UdfWriter.writeBytes(
        DocModel(blocks: [for (final p in demoPetition(_decision)) _block(p)]),
      ),
    ),
  );
  await tester.pumpWidget(
    _app(
      EditorWidget(
        initialFilePath: file.path,
        initialFormat: EvrakFormat.udf,
        caseLaw: caseLaw,
      ),
    ),
  );
  await _settle(
    tester,
    () => find.byKey(const ValueKey('citation-status')).evaluate().isNotEmpty,
  );
  return file;
}

/// The voice models, as if fetched long ago.
class _Installed extends SpeechModelStore {
  @override
  Future<String?> installed(SpeechModel model) async => '/ses/${model.folder}';
}

/// The demo case of the UYAP scenes, kept on this computer as Folio keeps a
/// case: tied to the petition, fetched twice — the documents that came the
/// second time marked new — and some of its documents saved.
Future<UyapCaseStore> _demoCase(
  Directory base,
  String petition, {
  String? home,
}) async {
  final support = Directory('${base.path}/support');
  final settings = UyapSettings(directory: support, home: home ?? base.path);
  final store = UyapCaseStore(directory: support, settings: settings);
  UyapSettings.instance = settings;
  UyapCaseStore.instance = store;
  UyapCaseLinks.instance = UyapCaseLinks(directory: support);
  DemoUyap.content = (document) => Uint8List.fromList(
    UdfWriter.writeBytes(
      DocModel(
        blocks: [
          for (final p in [
            DemoParagraph.heading(document.type.toUpperCase(), center: true),
            const DemoParagraph(''),
            DemoParagraph('MAHKEME: ${DemoUyap.target.courtName}'),
            DemoParagraph('DOSYA NO: ${DemoUyap.target.number} Esas'),
            const DemoParagraph(''),
            ...demoUyapDocument(document.type),
          ])
            _block(p),
        ],
      ),
    ),
  );
  await UyapCaseLinks.instance.link(
    petition,
    UyapCaseLink(
      jurisdiction: '1',
      courtType: 'AILE',
      courtId: DemoUyap.court.id,
      court: DemoUyap.court.label,
      number: DemoUyap.target.number,
    ),
  );
  final parties = await DemoUyap().parties(DemoUyap.target);
  await store.keep(
    target: DemoUyap.target,
    details: DemoUyap.details,
    parties: parties,
    documents: UyapCaseDocuments(DemoUyap.documents(6)),
    now: DateTime.now().subtract(const Duration(days: 3)),
  );
  var record = await store.keep(
    target: DemoUyap.target,
    details: DemoUyap.details,
    parties: parties,
    documents: UyapCaseDocuments(DemoUyap.documents()),
  );
  for (final document in record.documents.where(
    (d) => ['101', '103', '105', '106'].contains(d.key),
  )) {
    (record, _) = await store.save(
      record,
      document,
      DemoUyap.content!(document),
    );
  }
  return store;
}

/// An e-signature card as a reader's machine would show one; invented.
const _card = SigningCard(
  Pkcs11ModuleInfo(
    name: 'AKİS',
    provider: 'TÜBİTAK BİLGEM',
    path: '/usr/lib/libakisp11.so',
  ),
  TokenInfo(
    slotId: 1,
    label: 'AKİS e-imza kartı',
    manufacturer: 'TÜBİTAK',
    model: 'AKİS',
    serialNumber: '0000',
    loginRequired: true,
    hasProtectedAuthPath: false,
    minPinLen: 4,
    maxPinLen: 12,
  ),
);

class _DemoCards extends UdfSigningService {
  @override
  Future<List<SigningCard>> cards({String? driver}) async => [_card];
}

/// [udf] with a detached CMS signature over its content.xml, made with a
/// key generated for this run and thrown away: an invented signer, "Av.
/// Deniz YILMAZ", self-signed. It passes the send dialog's check, which is
/// that the signature and the document match; no trust in the signer is
/// implied or claimed.
Future<Uint8List> _signDemo(Uint8List udf, Directory work) async {
  final archive = ZipDecoder().decodeBytes(udf);
  final content = archive.findFile('content.xml')!;
  final dir = Directory('${work.path}/demo-signer')..createSync();
  final xml = File('${dir.path}/content.xml')
    ..writeAsBytesSync(content.content);
  Future<void> openssl(List<String> args) async {
    final result = await Process.run('openssl', args);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
  }

  await openssl([
    'req',
    '-x509',
    '-newkey',
    'rsa:2048',
    '-nodes',
    '-days',
    '365',
    '-subj',
    '/CN=Av. Deniz YILMAZ/O=Demo',
    '-keyout',
    '${dir.path}/key.pem',
    '-out',
    '${dir.path}/cert.pem',
  ]);
  await openssl([
    'cms',
    '-sign',
    '-binary',
    '-outform',
    'DER',
    '-md',
    'sha256',
    '-signer',
    '${dir.path}/cert.pem',
    '-inkey',
    '${dir.path}/key.pem',
    '-in',
    xml.path,
    '-out',
    '${dir.path}/sign.sgn',
  ]);
  final signature = File('${dir.path}/sign.sgn').readAsBytesSync();
  dir.deleteSync(recursive: true);
  final signed = Archive();
  for (final file in archive.files) {
    if (file.name != 'sign.sgn') signed.addFile(file);
  }
  signed.addFile(ArchiveFile('sign.sgn', signature.length, signature));
  return Uint8List.fromList(ZipEncoder().encode(signed));
}

/// The decision bank's answers to the searches the screenshots make, kept in
/// tool/screenshots/data/case_law_search.json. With FOLIO_RECORD=1 a search
/// that is not kept yet goes to the real bank and is kept; otherwise nothing
/// leaves the machine.
Future<String> Function(String path, String? body) _replay() {
  final file = File('tool/screenshots/data/case_law_search.json');
  final kept = file.existsSync()
      ? (jsonDecode(file.readAsStringSync()) as Map).cast<String, String>()
      : <String, String>{};
  final record = Platform.environment['FOLIO_RECORD'] == '1';
  return (path, body) async {
    final key = '$path\n${body ?? ''}';
    final answer = kept[key];
    if (answer != null) return answer;
    if (!record) throw StateError('not kept: $path');
    final client = HttpClient();
    try {
      final uri = Uri.parse('https://bedesten.adalet.gov.tr$path');
      final request = body == null
          ? await client.getUrl(uri)
          : await client.postUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'Folio');
      if (body != null) {
        request.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        request.write(body);
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      kept[key] = text;
      file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(kept));
      return text;
    } finally {
      client.close(force: true);
    }
  };
}

void main() {
  // The screens show every login offered, whatever this machine has.
  AdaletEimza.check = () async => true;
  EdevletWindow.check = () => true;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _loadFonts();
    // The in-app PDF viewer loads PDFium on its own; the built bundle has it.
    Pdfrx.pdfiumModulePath = pdfiumLibrary();
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  });

  testWidgets('editor: a petition with its articles and decision', (
    tester,
  ) async {
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final base = _home();
    // flutter_test draws elevation as a flat grey rim; the app has soft
    // shadows. The flag must be back before the test body ends.
    debugDisableShadows = false;
    try {
      final file = File('${base.path}/Boşanma Dava Dilekçesi.udf');
      await tester.runAsync(
        () => file.writeAsBytes(
          UdfWriter.writeBytes(
            DocModel(
              blocks: [
                for (final paragraph in demoPetition(_decision))
                  _block(paragraph),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        _app(
          EditorWidget(
            initialFilePath: file.path,
            initialFormat: EvrakFormat.udf,
          ),
        ),
      );
      final status = find.byKey(const ValueKey('citation-status'));
      await _settle(tester, () => status.evaluate().isNotEmpty);
      await tester.tap(status);
      await _settle(
        tester,
        () => find.byKey(const ValueKey('citation-list')).evaluate().isNotEmpty,
        rounds: 20,
      );
      await _shot(tester, 'editor-dayanaklar');

      final decision = find.descendant(
        of: find.byKey(const ValueKey('citation-list')),
        matching: find.textContaining('2016/24019'),
      );
      await tester.tap(decision.first);
      await _settle(
        tester,
        () =>
            find
                .byKey(const ValueKey('decision-panel'))
                .evaluate()
                .isNotEmpty &&
            find.textContaining('aranıyor').evaluate().isEmpty,
        rounds: 80,
      );
      await _shot(tester, 'editor-emsal');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(
        tester,
        () => find.byKey(const ValueKey('decision-panel')).evaluate().isEmpty,
        rounds: 20,
      );
      final article = find.descendant(
        of: find.byKey(const ValueKey('citation-list')),
        matching: find.textContaining('166'),
      );
      await tester.tap(article.first);
      await _settle(
        tester,
        () =>
            find.byKey(const ValueKey('article-panel')).evaluate().isNotEmpty &&
            find.textContaining('getiriliyor').evaluate().isEmpty,
        rounds: 80,
      );
      await _shot(tester, 'editor-madde');
    } finally {
      debugDisableShadows = true;
    }
  });

  testWidgets('library: the archive, one place for every document', (
    tester,
  ) async {
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final base = _home();
    // A plain path on every card rather than a temporary folder's name.
    final archive = Directory(
      '${Directory.systemTemp.path}/Belgeler/Büro Arşivi',
    );
    if (archive.existsSync()) archive.deleteSync(recursive: true);
    archive.createSync(recursive: true);
    addTearDown(() => archive.parent.deleteSync(recursive: true));
    await tester.runAsync(() => _writeArchive(archive));
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    final theme = ThemeController(
      settingsPath: '${base.path}/appearance.json',
      mode: ThemeMode.light,
    );
    // PDFs are read through PDFium, which flutter_tester lacks; the built
    // bundle has one.
    PdfiumSetup.pathOverride = pdfiumLibrary();
    addTearDown(() => PdfiumSetup.pathOverride = null);
    await tester.runAsync(() async {
      await library.initialize();
      await library.addPaths([archive.path]);
      await library.waitForIdle();
    });
    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: _frame,
          child: EvrakConvertApp(library: library, appearance: theme),
        ),
      );
      await _settle(
        tester,
        () => find.textContaining('Kira').evaluate().isNotEmpty,
      );
      await _shot(tester, 'library-home');

      await tester.enterText(find.byType(TextField).first, 'kira bedeli');
      await tester.runAsync(library.searchNow);
      await _settle(tester, () => library.matches > 0, rounds: 30);
      await _shot(tester, 'library-search');
    } finally {
      debugDisableShadows = true;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      library.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    theme.dispose();
  });

  testWidgets('library: each UYAP case a category of its own', (tester) async {
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final base = _home();
    final archive = Directory(
      '${Directory.systemTemp.path}/Belgeler/Büro Arşivi',
    );
    if (archive.existsSync()) archive.deleteSync(recursive: true);
    archive.createSync(recursive: true);
    addTearDown(() => archive.parent.deleteSync(recursive: true));
    final stores = (
      UyapCaseStore.instance,
      UyapSettings.instance,
      UyapCaseLinks.instance,
    );
    addTearDown(() {
      UyapCaseStore.instance = stores.$1;
      UyapSettings.instance = stores.$2;
      UyapCaseLinks.instance = stores.$3;
    });
    await tester.runAsync(() async {
      await _writeArchive(archive);
      await _demoCase(
        base,
        '${archive.path}/Boşanma Dava Dilekçesi.udf',
        home: archive.parent.path,
      );
    });
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    final theme = ThemeController(
      settingsPath: '${base.path}/appearance.json',
      mode: ThemeMode.light,
    );
    PdfiumSetup.pathOverride = pdfiumLibrary();
    addTearDown(() => PdfiumSetup.pathOverride = null);
    await tester.runAsync(() async {
      await library.initialize();
      await library.addPaths([archive.path, UyapSettings.instance.folder]);
      await library.waitForIdle();
    });
    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: _frame,
          child: EvrakConvertApp(library: library, appearance: theme),
        ),
      );
      final tile = find.byWidgetPredicate(
        (w) => '${w.key}'.contains('uyap-case-'),
      );
      await _settle(tester, () => tile.evaluate().isNotEmpty, rounds: 60);
      await tester.tap(tile.first);
      await _settle(tester, () => false, rounds: 20);
      await _shot(tester, 'uyap-kategori');
    } finally {
      debugDisableShadows = true;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      library.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    theme.dispose();
  });

  testWidgets('signing: e-signature card and mobile signature', (tester) async {
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final base = _home();
    // The mobile signature asks UYAP's service; a stand-in here answers
    // with a code and then waits, as a phone not yet approved does.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final server = (await tester.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    ))!;
    addTearDown(() => server.close(force: true));
    final never = Completer<void>();
    await tester.runAsync(() async {
      server.listen((request) async {
        final operation = request.headers
            .value('soapaction')!
            .replaceAll('"', '');
        await utf8.decoder.bind(request).join();
        if (operation != 'getHash') await never.future;
        request.response.write(
          '<r><resultCode>0</resultCode><apTransId>T-1</apTransId>'
          '<fingerPrint>4F7A</fingerPrint></r>',
        );
        await request.response.close().catchError((_) {});
      });
    });

    debugDisableShadows = false;
    try {
      final file = await _openPetition(tester, base);
      final context = tester.element(find.byType(EditorWidget));
      unawaited(
        showDialog<String>(
          context: context,
          builder: (_) => SigningDialog(
            filePath: file.path,
            service: _DemoCards(),
            mobileClient: () => MobileSignatureClient(
              endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
            ),
          ),
        ),
      );
      await _settle(
        tester,
        () => find.text('Kart PIN’i').evaluate().isNotEmpty,
        rounds: 40,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Kart PIN’i'),
        '123456',
      );
      await _shot(tester, 'sign-card');

      await tester.tap(find.text('Mobil imza'));
      await _settle(
        tester,
        () => find.text('Cep telefonu').evaluate().isNotEmpty,
        rounds: 20,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Cep telefonu'),
        '0532 000 00 00',
      );
      await _shot(tester, 'sign-mobile');

      await tester.tap(find.text('Mobil imzayla imzala'));
      await _settle(
        tester,
        () => find.text('4F7A').evaluate().isNotEmpty,
        rounds: 60,
      );
      await _shot(tester, 'sign-mobile-code');
      await tester.tap(find.text('Beklemeyi bırak'));
      await _settle(tester, () => false, rounds: 5);
    } finally {
      debugDisableShadows = true;
    }
  });

  testWidgets('UYAP: send a signed document and follow it', (tester) async {
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final base = _home();
    PdfiumSetup.pathOverride = pdfiumLibrary();
    addTearDown(() => PdfiumSetup.pathOverride = null);
    final previous = UyapWebService.instance;
    UyapWebService.instance = DemoUyap();
    addTearDown(() => UyapWebService.instance = previous);
    final witnesses = demoArchive(_decision)
        .firstWhere((d) => d.name == 'Tanık Listesi.udf');
    final bytes = (await tester.runAsync(
      () => _signDemo(
        Uint8List.fromList(
          UdfWriter.writeBytes(
            DocModel(blocks: [for (final p in witnesses.paragraphs) _block(p)]),
          ),
        ),
        base,
      ),
    ))!;

    Future<void> pick(String field, String item) async {
      final box = find.widgetWithText(InputDecorator, field).first;
      await tester.ensureVisible(box);
      await tester.tap(box);
      await _settle(
        tester,
        () => find.text(item).evaluate().length > 1,
        rounds: 10,
      );
      await tester.tap(find.text(item).last);
      await _settle(tester, () => false, rounds: 5);
    }

    debugDisableShadows = false;
    try {
      await _openPetition(tester, base);
      final context = tester.element(find.byType(EditorWidget));
      final sent = showDialog<UyapSendReceipt>(
        context: context,
        barrierDismissible: false,
        builder: (_) => UyapSendDialog(
          documentName: witnesses.name,
          documentBytes: bytes,
          stillCurrent: () async => true,
        ),
      );
      await _settle(
        tester,
        () => find.text('Adalet E-İmza PIN').evaluate().isNotEmpty,
        rounds: 20,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Adalet E-İmza PIN'),
        '123456',
      );
      await _shot(tester, 'uyap-baglan');

      await tester.tap(find.byKey(const ValueKey('uyap-connect-button')));
      await _settle(
        tester,
        () => find.text('Mahkeme türü').evaluate().isNotEmpty,
        rounds: 30,
      );
      await pick('Mahkeme türü', 'Aile Mahkemesi');
      await pick('Mahkeme', DemoUyap.court.label);
      await tester.enterText(find.widgetWithText(TextField, 'Yıl'), '2026');
      await tester.enterText(find.widgetWithText(TextField, 'Esas no'), '1204');
      await tester.tap(find.text('Dosyaları getir'));
      await _settle(
        tester,
        () => find.textContaining('2026/1204').evaluate().isNotEmpty,
        rounds: 30,
      );
      await _shot(tester, 'uyap-dosya');

      await tester.tap(find.textContaining('2026/1204').first);
      await _settle(
        tester,
        () => find.textContaining('Zeynep KAYA').evaluate().isNotEmpty,
        rounds: 80,
      );
      // The dialog's list builds lazily: scroll the menu into being first.
      final types = find.byKey(const ValueKey('uyap-doc-types-d1'));
      await tester.scrollUntilVisible(
        types,
        200,
        scrollable: find
            .descendant(
              of: find.byType(UyapSendDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // The document's preview settles first, and the menu stays put.
      await _settle(tester, () => false, rounds: 10);
      await tester.tap(types);
      await _settle(tester, () => false, rounds: 5);
      await tester.tap(find.text('Tanık Listesi').last);
      await _settle(tester, () => false, rounds: 20);
      await _shot(tester, 'uyap-hedef');

      await tester.tap(find.text('Gönderimi incele'));
      await _settle(
        tester,
        () => find.text('Son kontrol · UYAP’a gönder').evaluate().isNotEmpty,
        rounds: 40,
      );
      // The signed document's preview is drawn by PDFium off the clock.
      await _settle(tester, () => false, rounds: 25);
      await _shot(tester, 'uyap-onay');

      await tester.tap(find.text('Dosyayı ve belgeyi kontrol ettim · Gönder'));
      UyapSendReceipt? receipt;
      unawaited(sent.then((value) => receipt = value));
      await _settle(tester, () => receipt != null, rounds: 40);
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => UyapOperationsDialog(focusReceipt: receipt),
        ),
      );
      await _settle(
        tester,
        () => find.textContaining('Gönderildi').evaluate().isNotEmpty,
        rounds: 40,
      );
      await _shot(tester, 'uyap-islemler');
    } finally {
      debugDisableShadows = true;
    }
  });

  testWidgets('voice: the page read aloud, and written by speaking', (
    tester,
  ) async {
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final base = _home();
    final reading = ReadAloud.instance;
    final dictation = Dictation.instance;
    final models = SpeechModelStore.instance;
    final ear = FakeEar();
    ReadAloud.instance = ReadAloud(
      openVoice: (_) async => FakeVoice(),
      player: FakePlayer(),
    );
    Dictation.instance = Dictation(
      openEar: (_) async => ear,
      microphone: FakeMicrophone(),
    );
    SpeechModelStore.instance = _Installed();
    addTearDown(() {
      ReadAloud.instance = reading;
      Dictation.instance = dictation;
      SpeechModelStore.instance = models;
    });
    debugDisableShadows = false;
    // The desktop the features are for: a selection without touch handles.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await _openPetition(tester, base);
      // The rulers a desktop shows would number in the test's stand-in font.
      final toolbar = tester.widget<EditorToolbar>(find.byType(EditorToolbar));
      toolbar.onHorizontalRuler();
      toolbar.onVerticalRuler();
      await tester.pump();
      final controller = tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller;
      void caret(String before, {bool end = false}) {
        final text = controller.document.toPlainText();
        final at = text.indexOf(before) + (end ? before.length : 0);
        controller.updateSelection(
          TextSelection.collapsed(offset: at),
          ChangeSource.local,
        );
      }

      caret('2. TMK m. 166/1');
      await tester.pump();
      await tester.tap(
        find.byTooltip('Sesli oku · seçimi ya da imleçten sonrasını'),
      );
      await _settle(
        tester,
        () => ReadAloud.instance.state == ReadState.reading,
        rounds: 40,
      );
      await _shot(tester, 'sesli-okuma');
      await tester.runAsync(ReadAloud.instance.stop);
      await tester.pump();

      caret('nafakasına hükmedilmesi gerekmektedir.', end: true);
      await tester.pump();
      await tester.tap(
        find.byTooltip('Sesli yaz · söylediğiniz imlecin yerine yazılır'),
      );
      await _settle(
        tester,
        () => Dictation.instance.state == ListenState.listening,
        rounds: 40,
      );
      ear.say(
        'Davalı, ortak konutu terk ettiğini cevap dilekçesinde de kabul '
        'etmektedir.',
      );
      await _settle(tester, () => false, rounds: 5);
      await _shot(tester, 'sesli-yazma');
      // Stopped in the test's own clock, where the listening began.
      unawaited(Dictation.instance.stop());
      await tester.pump(const Duration(seconds: 1));
    } finally {
      debugDisableShadows = true;
      debugDefaultTargetPlatformOverride = null;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 4));
  });

  testWidgets('UYAP: the case beside the page, its documents read there', (
    tester,
  ) async {
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final base = _home();
    PdfiumSetup.pathOverride = pdfiumLibrary();
    addTearDown(() => PdfiumSetup.pathOverride = null);
    final previous = UyapWebService.instance;
    final web = DemoUyap();
    UyapWebService.instance = web;
    final stores = (
      UyapCaseStore.instance,
      UyapSettings.instance,
      UyapCaseLinks.instance,
    );
    addTearDown(() {
      UyapWebService.instance = previous;
      UyapCaseStore.instance = stores.$1;
      UyapSettings.instance = stores.$2;
      UyapCaseLinks.instance = stores.$3;
    });
    await tester.runAsync(() async {
      await web.connect('123456');
      await _demoCase(base, '${base.path}/Boşanma Dava Dilekçesi.udf');
    });
    debugDisableShadows = false;
    try {
      await _openPetition(tester, base);
      await tester.tap(find.byTooltip('UYAP dosyası'));
      await _settle(
        tester,
        () => find.textContaining('Evraklar · 9').evaluate().isNotEmpty,
        rounds: 40,
      );
      await _shot(tester, 'uyap-panel');

      final panelList = find
          .descendant(
            of: find.byType(UyapCasePanel),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('uyap-doc-107')),
        200,
        scrollable: panelList,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('uyap-doc-107')));
      await _settle(
        tester,
        () => find.byType(FilePreview).evaluate().isNotEmpty,
        rounds: 60,
      );
      await _settle(tester, () => false, rounds: 25);
      await _shot(tester, 'uyap-onizleme');

      for (final key in ['108', '109', '104']) {
        final row = find.byKey(ValueKey('uyap-doc-$key'));
        await tester.scrollUntilVisible(
          row,
          200,
          scrollable: find
              .descendant(
                of: find.byType(UyapCasePanel),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(
          find.descendant(of: row, matching: find.byType(Checkbox)),
        );
        await tester.pump();
      }
      await _settle(tester, () => false, rounds: 5);
      await _shot(tester, 'uyap-secerek-indirme');
    } finally {
      debugDisableShadows = true;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('phone: home, a petition and an article', (tester) async {
    const phone = Size(390, 844);
    const ratio = 3.0;
    tester.view.physicalSize = phone * ratio;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    final base = _home();
    final archive = Directory(
      '${Directory.systemTemp.path}/Belgeler/Büro Arşivi',
    );
    if (archive.existsSync()) archive.deleteSync(recursive: true);
    archive.createSync(recursive: true);
    addTearDown(() => archive.parent.deleteSync(recursive: true));
    await tester.runAsync(() => _writeArchive(archive));
    // Son açılanlar, as the phone would remember them.
    final recent = [
      for (final name in [
        'Boşanma Dava Dilekçesi.udf',
        'Tanık Listesi.udf',
        'Kira Tahliye İhtarnamesi.udf',
        'Kira Sözleşmesi - Deneme Cad. No 12.pdf',
        'Cevap Dilekçesi - İşçilik Alacağı.udf',
      ])
        {
          'path': '${archive.path}/$name',
          'name': name,
          'size': File('${archive.path}/$name').lengthSync(),
        },
    ];
    File('${base.path}/support/recent-documents.json')
        .writeAsStringSync(jsonEncode(recent));
    DocumentScan.debugAvailable = true;
    addTearDown(() => DocumentScan.debugAvailable = null);
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    final theme = ThemeController(
      settingsPath: '${base.path}/appearance.json',
      mode: ThemeMode.light,
    );
    await tester.runAsync(library.initialize);

    Future<void> shot(String name) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final boundary =
          _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File('tool/screenshots/out/$name.png').writeAsBytesSync(bytes!);
    }

    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: _frame,
          child: EvrakConvertApp(library: library, appearance: theme),
        ),
      );
      await _settle(
        tester,
        () =>
            find.text('Kameradan PDF tara').evaluate().isNotEmpty &&
            find.textContaining('Tanık Listesi').evaluate().isNotEmpty,
        rounds: 60,
      );
      await shot('phone-home');

      await _openPetition(tester, base);
      // The page whole, as a phone opens it: A4 fits the width at 50%.
      await shot('phone-editor');

      await tester.tap(find.byKey(const ValueKey('citation-status')));
      await _settle(
        tester,
        () => find.byKey(const ValueKey('citation-list')).evaluate().isNotEmpty,
        rounds: 20,
      );
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const ValueKey('citation-list')),
              matching: find.textContaining('166'),
            )
            .first,
      );
      await _settle(
        tester,
        () =>
            find.textContaining('Madde 166').evaluate().isNotEmpty &&
            find.textContaining('getiriliyor').evaluate().isEmpty,
        rounds: 80,
      );
      await shot('phone-madde');
    } finally {
      debugDisableShadows = true;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      library.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    theme.dispose();
  });

  testWidgets('editor: searching the case law beside the page', (tester) async {
    tester.view.physicalSize = logical * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final base = _home();
    if (Platform.environment['FOLIO_RECORD'] == '1') {
      HttpOverrides.global = null;
    }
    final bank = CaseLaw(
      send: _replay(),
      cache: Directory('${base.path}/support/ictihat'),
      between: Duration.zero,
    );
    debugDisableShadows = false;
    try {
      await _openPetition(tester, base, caseLaw: bank);
      await tester.tap(find.byTooltip('İçtihat ara').first);
      await _settle(
        tester,
        () => find.text('Ara').evaluate().isNotEmpty,
        rounds: 20,
      );
      final words = find.descendant(
        of: find.byType(CaseLawSearchScreen),
        matching: find.byType(TextField),
      );
      await tester.enterText(
        words.first,
        'şiddetli geçimsizlik kusur tazminat',
      );
      await tester.tap(find.text('Ara'));
      await _settle(
        tester,
        () => find.textContaining('Hukuk Dairesi').evaluate().length > 2,
        rounds: 80,
      );
      await _shot(tester, 'editor-emsal-arama');
    } finally {
      debugDisableShadows = true;
    }
  });
}
