import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:evrak_convert/services/signing/pkcs11/pkcs11_discovery.dart';
import 'package:evrak_convert/services/signing/pkcs11/pkcs11_session.dart';
import 'package:evrak_convert/services/signing/udf_signing_service.dart';
import 'package:evrak_convert/services/signing/x509_parser.dart';
import 'package:evrak_convert/ui/widgets/signing_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const card = SigningCard(
  Pkcs11ModuleInfo(name: 'AKİS', provider: 'Test', path: '/test/driver.so'),
  TokenInfo(
    slotId: 1,
    label: 'Test e-imza kartı',
    manufacturer: 'Test',
    model: 'Test',
    serialNumber: '123',
    loginRequired: true,
    hasProtectedAuthPath: false,
    minPinLen: 4,
    maxPinLen: 12,
  ),
);

class FakeSigningService extends UdfSigningService {
  int scans = 0;
  int logins = 0;
  int signatures = 0;
  SigningCertificate? signedWith;
  Future<List<SigningCertificate>> Function() certificateResult = () async =>
      [];
  Future<List<SigningCard>> Function() result = () async => [card];

  @override
  Future<List<SigningCard>> cards({String? driver}) {
    scans++;
    return result();
  }

  @override
  Future<List<SigningCertificate>> certificates(
    SigningCard card,
    String pin,
  ) async {
    logins++;
    return certificateResult();
  }

  @override
  Future<String> sign(
    String path,
    SigningCard card,
    SigningCertificate certificate,
    String pin,
  ) async {
    signatures++;
    signedWith = certificate;
    return '/test_imzali.udf';
  }
}

SigningCertificate certificate(String name, {bool expired = false}) {
  final bytes = Uint8List.fromList([1]);
  return SigningCertificate(
    CertificateInfo(
      keyId: bytes,
      derBytes: bytes,
      label: name,
      issuerDer: bytes,
      serialNumberDer: bytes,
      subjectDer: bytes,
    ),
    X509CertInfo(
      subjectCN: name,
      issuerCN: 'Test',
      serialNumber: name,
      notBefore: DateTime.now().subtract(const Duration(days: 10)),
      notAfter: DateTime.now().add(Duration(days: expired ? -1 : 10)),
      issuerDer: bytes,
      serialNumberDer: bytes,
    ),
  );
}

Future<void> openDialog(
  WidgetTester tester,
  FakeSigningService service, {
  String? filePath = '/test.udf',
}) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) =>
                    SigningDialog(filePath: filePath, service: service),
              ),
              child: const Text('Open signing'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open signing'));
    await tester.pump();
    // Settings use asynchronous filesystem I/O outside the widget fake clock.
    for (var i = 0; i < 100 && service.scans == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
}

void main() {
  final signButton = find.widgetWithText(FilledButton, 'İmzala ve kaydet');
  final pinField = find.widgetWithText(TextField, 'Kart PIN’i');

  testWidgets('PIN enables signing; one click reads certificate and signs', (
    tester,
  ) async {
    final cert = certificate('Test İmzacı');
    final service = FakeSigningService()
      ..certificateResult = () async => [cert];
    await openDialog(tester, service);
    await tester.pumpAndSettle();
    expect(find.text('Sertifikaları oku'), findsNothing);
    expect(tester.widget<FilledButton>(signButton).onPressed, isNull);
    await tester.enterText(pinField, '1234');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(signButton).onPressed, isNotNull);
    expect(service.logins, 0);
    expect(service.signatures, 0);
    await tester.enterText(pinField, '');
    await tester.pump();
    expect(tester.widget<FilledButton>(signButton).onPressed, isNull);
    await tester.enterText(pinField, '1234');
    await tester.pump();
    await tester.tap(signButton);
    await tester.pumpAndSettle();
    expect(service.logins, 1);
    expect(service.signatures, 1);
    expect(service.signedWith, cert);
    expect(find.byType(SigningDialog), findsNothing);
  });

  testWidgets('incorrect PIN stops without signing or automatic retry', (
    tester,
  ) async {
    final service = FakeSigningService()
      ..certificateResult = () async => throw StateError('PIN hatalı.');
    await openDialog(tester, service);
    await tester.pumpAndSettle();
    await tester.enterText(pinField, '1234');
    await tester.pump();
    await tester.tap(signButton);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('PIN hatalı.'), findsOneWidget);
    expect(service.logins, 1);
    expect(service.signatures, 0);
  });

  testWidgets(
    'multiple suitable certificates require a choice before signing',
    (tester) async {
      final first = certificate('İmzacı Bir');
      final second = certificate('İmzacı İki');
      final service = FakeSigningService()
        ..certificateResult = () async => [first, second];
      await openDialog(tester, service);
      await tester.pumpAndSettle();
      await tester.enterText(pinField, '1234');
      await tester.pump();
      await tester.tap(signButton);
      await tester.pumpAndSettle();
      expect(service.signatures, 0);
      expect(tester.widget<FilledButton>(signButton).onPressed, isNull);
      final choices = find.byType(DropdownButton<SigningCertificate>);
      await tester.ensureVisible(choices);
      await tester.tap(choices);
      await tester.pumpAndSettle();
      await tester.tap(find.text('İmzacı İki').last);
      await tester.pumpAndSettle();
      await tester.tap(signButton);
      await tester.pumpAndSettle();
      expect(service.logins, 1);
      expect(service.signatures, 1);
      expect(service.signedWith, second);
    },
  );

  testWidgets('expired certificates cannot sign', (tester) async {
    final service = FakeSigningService()
      ..certificateResult = () async => [
        certificate('Eski sertifika', expired: true),
      ];
    await openDialog(tester, service);
    await tester.pumpAndSettle();
    await tester.enterText(pinField, '1234');
    await tester.pump();
    await tester.tap(signButton);
    await tester.pumpAndSettle();
    expect(
      find.text('Kartta tarihi geçerli bir imzacı sertifikası bulunamadı.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(signButton).onPressed, isNull);
    expect(service.signatures, 0);
  });

  testWidgets(
    'opening automatically lists cards without login or driver selection',
    (tester) async {
      final service = FakeSigningService();
      await openDialog(tester, service);
      await tester.pumpAndSettle();
      expect(service.scans, 1);
      expect(service.logins, 0);
      expect(find.text('Sürücü seç'), findsNothing);
      expect(find.text('Kartları bul'), findsNothing);
      expect(find.text('1 kart bulundu.'), findsOneWidget);
      final dropdown = tester.widget<DropdownButton<SigningCard>>(
        find.byType(DropdownButton<SigningCard>),
      );
      expect(dropdown.value, card);
      expect(find.widgetWithText(TextField, 'Kart PIN’i'), findsOneWidget);
      await tester.ensureVisible(find.text('Gelişmiş ayarlar'));
      await tester.tap(find.text('Gelişmiş ayarlar'));
      await tester.pumpAndSettle();
      expect(find.text('Sürücü seç'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty list can refresh and failed refresh clears stale card and PIN',
    (tester) async {
      final service = FakeSigningService()..result = () async => [];
      await openDialog(tester, service);
      await tester.pumpAndSettle();
      expect(
        find.text('Kart bulunamadı. E-imza kartınızı takıp yenileyin.'),
        findsOneWidget,
      );
      service.result = () async => [card];
      await tester.tap(find.byTooltip('Kartları yenile'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Kart PIN’i'),
        '1234',
      );
      service.result = () async =>
          throw StateError('Test kart bağlantı hatası');
      await tester.tap(find.byTooltip('Kartları yenile'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<SigningCard>), findsNothing);
      expect(find.widgetWithText(TextField, 'Kart PIN’i'), findsNothing);
      expect(find.textContaining('Test kart bağlantı hatası'), findsOneWidget);
      final sign = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'İmzala ve kaydet'),
      );
      expect(sign.onPressed, isNull);
      expect(service.scans, 3);
      expect(service.logins, 0);
    },
  );

  testWidgets('pending automatic scan cannot overlap and tolerates disposal', (
    tester,
  ) async {
    final pending = Completer<List<SigningCard>>();
    final service = FakeSigningService()..result = () => pending.future;
    await openDialog(tester, service, filePath: null);
    await tester.pump();
    await tester.pump();
    expect(service.scans, 1);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Kartları yenile',
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    pending.complete([card]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test(
    'driver discovery skips missing paths and deduplicates symlinks',
    () async {
      final dir = await Directory.systemTemp.createTemp('lifeos-driver-test-');
      addTearDown(() => dir.delete(recursive: true));
      final file = await File('${dir.path}/test.so').writeAsString('test');
      final link = await Link('${dir.path}/alias.so').create(file.path);
      final modules = detectInstalledModules(
        extraPaths: [file.path, link.path, file.path, '${dir.path}/missing.so'],
      );
      expect(
        modules.where((module) => module.path.startsWith(dir.path)).length,
        1,
      );
    },
  );
}
