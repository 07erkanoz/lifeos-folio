import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/signing/mobile_signature.dart';
import 'package:evrak_convert/services/signing/signed_data.dart';
import 'package:evrak_convert/services/signing/udf_signing_service.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/widgets/signing_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_drafts_test.dart' as helpers;
import 'mobile_signature_test.dart' as mobile;
import 'support/fake_path_provider.dart';
import 'support/temp_directory.dart';

class _NoCards extends UdfSigningService {
  int scans = 0;
  @override
  Future<List<SigningCard>> cards({String? driver}) async {
    scans++;
    return const [];
  }
}

/// A UDF on disk, a stand-in for UYAP's service that answers the phone only
/// when [approve] completes, and a button that opens the dialog on the file.
class _Setup {
  _Setup(this.dir, this.file, this.original, this.server);
  final Directory dir;
  final File file;
  final Uint8List original;
  final HttpServer server;
  final cards = _NoCards();
  final approve = Completer<void>();
  String? result;
  bool closed = false;

  static Future<_Setup> start(WidgetTester tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-mobile-dialog-'),
    ))!;
    // Settings go here, never into the reader's own signing.json.
    useFakePathProvider(Directory('${dir.path}/paths'));
    // The widget binding answers every HttpClient with 400 itself; the
    // requests here are meant for the stand-in server.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final previous = DocumentHistory.instance;
    DocumentHistory.instance = DocumentHistory(
      directory: Directory('${dir.path}/history'),
    );
    addTearDown(() => DocumentHistory.instance = previous);
    final file = File('${dir.path}/dilekce.udf');
    final udf = Uint8List.fromList(
      UdfWriter.writeBytes(DocModel(blocks: [DocBlock(plainText: 'Dilekçe')])),
    );
    await tester.runAsync(() => file.writeAsBytes(udf));
    final content = SignedData.content(udf);
    final server = (await tester.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    ))!;
    addTearDown(() => server.close(force: true));
    final setup = _Setup(dir, file, udf, server);
    await tester.runAsync(() async {
      server.listen((request) async {
        final operation = request.headers
            .value('soapaction')!
            .replaceAll('"', '');
        try {
          await utf8.decoder.bind(request).join();
        } on HttpException {
          // Beklemeyi bırak closed the connection before the request was in.
          return;
        }
        // The signer takes a moment to reach for the phone.
        if (operation == 'getSignature') await setup.approve.future;
        request.response.write(
          operation == 'getHash'
              ? '<r><resultCode>0</resultCode><apTransId>T-1</apTransId>'
                    '<fingerPrint>9C4E</fingerPrint></r>'
              : '<r><resultCode>0</resultCode><identityNo>1</identityNo><data>'
                    '${base64Encode(mobile.signatureForTest(content))}</data></r>',
        );
        // Once given up on, the reader is gone before the answer is out.
        await request.response.close().catchError((_) {});
      });
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                setup.closed = false;
                setup.result = await showDialog<String>(
                  context: context,
                  builder: (_) => SigningDialog(
                    filePath: file.path,
                    service: setup.cards,
                    mobileClient: () => MobileSignatureClient(
                      endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
                    ),
                  ),
                );
                setup.closed = true;
              },
              child: const Text('İmzala'),
            ),
          ),
        ),
      ),
    );
    return setup;
  }

  Future<Uint8List> bytes(WidgetTester tester) async =>
      (await tester.runAsync(file.readAsBytes))!;

  /// The settings the dialog kept, wherever the host put its folder. They are
  /// written after the dialog closes, so they are given a moment to arrive.
  Future<Map<String, dynamic>?> settings(
    WidgetTester tester, {
    bool wait = true,
  }) async {
    Future<Map<String, dynamic>?> read() async {
      await for (final entry in Directory(
        '${dir.path}/paths',
      ).list(recursive: true)) {
        if (entry is File && entry.path.endsWith('signing.json')) {
          return jsonDecode(await entry.readAsString()) as Map<String, dynamic>;
        }
      }
      return null;
    }

    for (var i = 0; i < 100; i++) {
      final found = await tester.runAsync(read);
      if (found != null || !wait) return found;
      // The file is written on the real clock: on a slow disk the test's
      // own clock alone ran out before it got there.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    return null;
  }
}

/// Opens the dialog and waits until it has finished looking for cards: the
/// choice of method is locked until then.
Future<void> _open(WidgetTester tester, _Setup setup, String settled) async {
  await tester.tap(find.text('İmzala'));
  await tester.pump();
  await helpers.ready(tester, () => find.text(settled).evaluate().isNotEmpty);
  await helpers.ready(
    tester,
    () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
  );
}

Future<void> _askPhone(WidgetTester tester) async {
  await tester.tap(find.text('Mobil imza'));
  await tester.pump();
  await tester.enterText(
    find.byKey(const ValueKey('mobile-phone')),
    '0532 123 45 67',
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('sign-mobile')));
  await tester.pump();
  // The code to compare with the phone's, while the phone is being asked.
  await helpers.ready(tester, () => find.text('9C4E').evaluate().isNotEmpty);
  expect(find.text('Beklemeyi bırak'), findsOneWidget);
}

void main() {
  testWidgets('a UDF is signed from the dialog with a mobile signature: the '
      'code is shown while the phone is asked, then the file is signed, and '
      'the next document starts from the mobile signature', (tester) async {
    final setup = await _Setup.start(tester);
    await _open(
      tester,
      setup,
      'Kart bulunamadı. E-imza kartınızı takıp yenileyin.',
    );
    await _askPhone(tester);
    expect(UdfSigningService.isSigned(await setup.bytes(tester)), isFalse);

    setup.approve.complete();
    await helpers.ready(tester, () => setup.closed);
    expect(setup.result, setup.file.path);
    final signed = await setup.bytes(tester);
    expect(UdfReader.readBytes(signed)!.metadata['hasSignature'], isTrue);
    expect(await setup.settings(tester), {
      'method': 'mobile',
      'phone': '0532 123 45 67',
      'operator': MobileOperator.turkcell.code,
    });

    // Opened again: straight to the phone, number filled in, no card search,
    // and told that the signature joins the one already there.
    final scans = setup.cards.scans;
    await _open(
      tester,
      setup,
      'Numaranızı ve operatörünüzü kontrol edip imzalayın.',
    );
    expect(find.text('0532 123 45 67'), findsOneWidget);
    expect(find.textContaining('Bu belge imzalı.'), findsOneWidget);
    expect(setup.cards.scans, scans);
    await tester.tap(find.text('Kapat'));
    await helpers.ready(tester, () => setup.closed);
    expect(setup.result, isNull);
    await tester.pumpAndSettle();
    await removeTemporaryDirectory(tester, setup.dir);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('giving up on the phone leaves the document as it was and the '
      'dialog ready to try again', (tester) async {
    final setup = await _Setup.start(tester);
    await _open(
      tester,
      setup,
      'Kart bulunamadı. E-imza kartınızı takıp yenileyin.',
    );
    await _askPhone(tester);

    await tester.tap(find.text('Beklemeyi bırak'));
    await tester.pump();
    await helpers.ready(
      tester,
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    expect(
      find.text('İmza beklemesi bırakıldı. Belge değişmedi.'),
      findsOneWidget,
    );
    expect(find.text('9C4E'), findsNothing);
    expect(setup.closed, isFalse);
    expect(await setup.bytes(tester), setup.original);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('sign-mobile')))
          .onPressed,
      isNotNull,
    );
    expect(await setup.settings(tester, wait: false), isNull);

    await tester.tap(find.text('Kapat'));
    await helpers.ready(tester, () => setup.closed);
    await tester.pumpAndSettle();
    await removeTemporaryDirectory(tester, setup.dir);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
