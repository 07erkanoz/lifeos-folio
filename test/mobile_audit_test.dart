import 'dart:io';

import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:evrak_convert/services/uyap/adalet_eimza.dart';
import 'package:evrak_convert/ui/agenda/uets_connect.dart';
import 'package:evrak_convert/ui/mobile/lawyer_profile_page.dart';
import 'package:evrak_convert/ui/settings/settings_page.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:evrak_convert/ui/widgets/portfolio_picker.dart';
import 'package:evrak_convert/ui/widgets/uyap_case_picker.dart';
import 'package:evrak_convert/ui/widgets/uyap_connect_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone's screens at a small phone's width with the large type a
/// lawyer may have chosen: nothing may run off its edge.
void main() {
  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final tray = AdaletEimza.check;
    AdaletEimza.check = () async => false;
    addTearDown(() => AdaletEimza.check = tray);
  }

  Future<void> open(
    WidgetTester tester,
    Future<void> Function(BuildContext context) show,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => show(context),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the web portal’s login fits', (tester) async {
    await phone(tester);
    await open(tester, (c) => connectUyapWeb(c));
    expect(find.text('Mobil imza ile'), findsOne);
  });

  testWidgets('UETS’s login fits', (tester) async {
    await phone(tester);
    final dir = Directory.systemTemp.createTempSync('folio-audit-');
    addTearDown(() => dir.deleteSync(recursive: true));
    await open(
      tester,
      (c) => connectUets(c, secrets: SecretStore(directory: () async => dir)),
    );
    expect(find.text('Bağlan'), findsOne);
  });

  testWidgets('the case search fits', (tester) async {
    await phone(tester);
    await open(tester, (c) => UyapCasePicker.show(c));
    expect(find.text('UYAP dosyası bağla'), findsOne);
  });

  testWidgets('the portfolio is a page of its own on a phone, and fits', (
    tester,
  ) async {
    await phone(tester);
    await open(
      tester,
      (c) => PortfolioPicker.show(c, [
        for (var i = 0; i < 6; i++)
          PortalCase.create(
            number: '2026/${100 + i}',
            court: 'Antalya Bölge Adliye Mahkemesi ${i + 1}. Hukuk Dairesi',
          ),
      ]),
    );
    expect(find.text('Portföyden dosya ekle'), findsOne);
    await tester.tap(
      find.byKey(
        const ValueKey(
          'portfolio-unit-check-Antalya Bölge Adliye Mahkemesi 1. Hukuk Dairesi',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('1 dosyayı ekle'), findsOne);
  });

  testWidgets('the settings and the profile fit', (tester) async {
    await phone(tester);
    LawyerProfile.use(const LawyerProfile());
    addTearDown(() => LawyerProfile.use(null));
    final library = LibraryController(watchFolders: false);
    addTearDown(library.dispose);
    final appearance = ThemeController();
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(library: library, appearance: appearance),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: LawyerProfilePage()));
    await tester.pumpAndSettle();
    expect(find.text('Avukat ekle'), findsOne);
  });
}
