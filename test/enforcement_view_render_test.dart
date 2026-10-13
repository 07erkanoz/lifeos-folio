import 'dart:io';
import 'dart:ui';

import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/enforcement/enforcement_ledger.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_enforcement.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/portfolio/enforcement_ledger_dialog.dart';
import 'package:evrak_convert/ui/portfolio/enforcement_view.dart';
import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:evrak_convert/ui/theme/folio_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/real_fonts.dart';

/// Where the renders go, when asked: flutter test --dart-define=SHOTS=dir.
const _out = String.fromEnvironment('SHOTS');

final _account = [
  {
    'grupId': 1,
    'textAlan': 'Takipte Kesinlesen Miktar',
    'degerAlan': '250000.00',
  },
  {'grupId': 1, 'textAlan': 'Toplam Faiz Miktari', 'degerAlan': '46387.58'},
  {'grupId': 1, 'textAlan': 'Vekalet Ucreti', 'degerAlan': '17320'},
  {'grupId': 1, 'textAlan': 'Masraf Miktari', 'degerAlan': '1.640,40'},
  {'grupId': 1, 'textAlan': 'Basvurma Harci', 'degerAlan': '427.60'},
  {'grupId': 1, 'textAlan': 'Pesin Harc', 'degerAlan': '1250.00'},
  {'grupId': 1, 'textAlan': 'Tahsil Harci', 'degerAlan': '1509.68'},
  {'grupId': 1, 'textAlan': 'Toplam Alacak', 'degerAlan': '318640.50'},
  {'grupId': 2, 'textAlan': 'Yatan Para', 'degerAlan': '50033.65'},
  {'grupId': 1, 'textAlan': 'Bakiye Borc Miktari', 'degerAlan': '268606.85'},
];

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  if (_out.isEmpty) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    await File('$_out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _shotScreen(WidgetTester tester, String name) async {
  if (_out.isEmpty) return;
  await tester.runAsync(() async {
    final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & tester.view.physicalSize);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    await File('$_out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final (name, size, dark) in [
    ('wide', const Size(1400, 1250), false),
    ('phone', const Size(400, 2600), false),
    ('dark', const Size(1400, 1250), true),
  ]) {
    testWidgets('enforcement view $name', (tester) async {
      await tester.runAsync(() async {
        await loadRealFonts();
        final inter = FontLoader('Inter');
        for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          inter.addFont(
            Future.value(
              ByteData.sublistView(
                File('fonts/ui/Inter-$w.ttf').readAsBytesSync(),
              ),
            ),
          );
        }
        await inter.load();
      });
      FolioPalette.dark = dark;
      addTearDown(() => FolioPalette.dark = false);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);
      db.setRepresentation('k1', const [
        (ad: 'BORA YAPI A.Ş.', rol: 'Alacaklı'),
      ]);
      final at = DateTime(2026, 10, 10);
      db.saveClientRecord(
        ClientRecord(
          id: 'l1',
          clientId: 'buro',
          kind: ClientRecordKind.enforcement,
          data: {
            'dosya': 'k1',
            'tur': LedgerKind.external.code,
            'tutar': 1000000,
            'zaman': at.toIso8601String(),
            'borclu': 'Mehmet Tunç',
            'odeme': 'Nakit',
          },
          created: at,
          by: 'Av. Deniz Kaya',
          updated: at,
        ),
      );
      final record = UyapCaseRecord(
        court: 'Manavgat İcra Dairesi',
        number: '2025/1904',
        fetchedAt: DateTime(2026, 10, 9),
        parties: const [
          UyapParty('BORA YAPI A.Ş.', 'Alacaklı', 'DENİZ KAYA', 'Kurum'),
          UyapParty('MEHMET TUNÇ', 'Borçlu', '', 'Kişi'),
          UyapParty('AYŞE TUNÇ', 'Borçlu', '', 'Kişi'),
        ],
        enforcement: UyapEnforcement(
          lines: UyapEnforcement.linesFromJson(_account),
          debtors: const [
            UyapDebtor(
              id: '1',
              name: 'MEHMET TUNÇ',
              idNo: '1•••••••••4',
              moved: true,
            ),
            UyapDebtor(id: '2', name: 'AYŞE TUNÇ', idNo: '2•••••••••8'),
          ],
        ),
        money: const UyapCaseMoney(
          collected: 50033.65,
          paidOut: 8400,
          collections: [
            UyapMoneyItem(
              kind: 'Maaş Kesintisi',
              date: '04.09.2026',
              amount: 17500,
            ),
            UyapMoneyItem(kind: 'Haciz', date: '04.05.2026', amount: 32533.65),
          ],
          payments: [
            UyapMoneyItem(
              kind: 'Vekile ödeme',
              date: '25.09.2026',
              amount: 8400,
              receipt: 'R-77',
            ),
          ],
        ),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: dark
                      ? const Color(0xFF15171C)
                      : const Color(0xFFF5F6F8),
                  child: EnforcementView(
                    record: record,
                    caseKey: 'k1',
                    title: '2025/1904 · Manavgat İcra Dairesi',
                    database: () async => db,
                    lawyer: 'Av. Deniz Kaya',
                    wide: size.width > 900,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _shot(tester, key, 'enforcement-$name');
      if (name != 'wide') return;
      // The requests' window, over the page.
      await tester.tap(find.byKey(const ValueKey('enforcement-requests')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('request-Maaş haczi')), findsOneWidget);
      await _shotScreen(tester, 'enforcement-requests');
    });
  }

  testWidgets('the payment made outside asks what it needs', (tester) async {
    await tester.runAsync(loadRealFonts);
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const LedgerDialog(
                    kind: LedgerKind.external,
                    debtors: ['Mehmet Tunç', 'Ayşe Tunç'],
                    left: 26860685,
                  ),
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
    expect(find.text("Folio'ya göre kalan borç 268.606,85 TL"), findsOneWidget);
    await _shot(tester, key, 'enforcement-dialog');
  });
}
