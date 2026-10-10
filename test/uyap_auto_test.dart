import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/settings/uyap_auto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('UYAP is read of itself only once the lawyer has read what '
      'it means and agreed; the help page says how Folio reaches UYAP', (
    tester,
  ) async {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    final sync = PortalSync(
      web: UyapWebService.forTesting(),
      mobile: UyapMobileApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
      database: () async => db,
    );
    addTearDown(sync.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UyapAutoRow(sync: sync)),
      ),
    );
    expect(sync.autoFetch, isFalse);
    expect(find.textContaining('bir tarayıcı gibi'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-uyap-auto-switch')));
    await tester.pumpAndSettle();
    // Not before it is read and agreed to.
    final yes = find.byKey(const ValueKey('uyap-auto-yes'));
    expect(tester.widget<FilledButton>(yes).onPressed, isNull);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(sync.autoFetch, isFalse);
    await tester.tap(find.byKey(const ValueKey('settings-uyap-auto-switch')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('uyap-auto-read')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uyap-auto-read')));
    await tester.pump();
    await tester.tap(yes);
    await tester.pumpAndSettle();
    expect(sync.autoFetch, isTrue);
    expect(db.meta(PortalSync.autoKey), '1');
    // Turned off again without asking.
    await tester.tap(find.byKey(const ValueKey('settings-uyap-auto-switch')));
    await tester.pumpAndSettle();
    expect(sync.autoFetch, isFalse);
    expect(db.meta(PortalSync.autoKey), '0');
    await tester.tap(find.byKey(const ValueKey('settings-uyap-help')));
    await tester.pumpAndSettle();
    expect(find.text('Folio bir tarayıcı gibi çalışır'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('yapay zekâ'), 200);
    expect(find.textContaining('yapay zekâ'), findsOneWidget);
  });
}
