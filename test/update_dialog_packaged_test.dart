import 'package:evrak_convert/services/update/update_installer.dart';
import 'package:evrak_convert/services/update/update_manifest.dart';
import 'package:evrak_convert/ui/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A Folio that LifeOS Mağaza or the system installed is not sent to the
// site for its update: kur.sh would install a second Folio beside it.
void main() {
  final manifest = UpdateManifest(
    platform: 'linux-x64',
    version: '9.9.9',
    build: 999,
    url: Uri.parse(
      'https://lifeos.com.tr/downloads/LifeOS-Folio-9.9.9-Linux-x64.tar.gz',
    ),
    sha256: '0' * 64,
    size: 1 << 20,
    notes: const {'tr': '- Hata düzeltmeleri'},
    published: DateTime(2026, 10, 28),
  );

  Future<void> show(WidgetTester tester, LinuxUpdater by) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: UpdateDialog(manifest: manifest, packagedBy: by),
      ),
    ),
  );

  testWidgets('from LifeOS Mağaza: the Store is offered, no download', (
    tester,
  ) async {
    await show(tester, LinuxUpdater.lifeosStore);
    expect(find.textContaining('LifeOS Mağaza’dan gelir'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-store')), findsOneWidget);
    expect(find.text('İndirme sayfasını aç'), findsNothing);
    expect(find.byKey(const ValueKey('update-download')), findsNothing);
    expect(find.textContaining('imzalı sürüm bilgisiyle'), findsNothing);
    expect(find.text('- Hata düzeltmeleri'), findsOneWidget);
  });

  testWidgets('from the system: said so, and nothing to download', (
    tester,
  ) async {
    await show(tester, LinuxUpdater.system);
    expect(
      find.text('Yeni sürüm sistem güncellemesiyle gelir.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('update-store')), findsNothing);
    expect(find.text('İndirme sayfasını aç'), findsNothing);
    expect(find.byKey(const ValueKey('update-download')), findsNothing);
    expect(find.text('Sonra'), findsOneWidget);
  });
}
