import 'package:evrak_convert/ui/mobile/document_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget home({VoidCallback? onScan}) => MaterialApp(
    home: Scaffold(
      body: MobileDocumentHome(
        recent: const [],
        onOpen: () {},
        onNew: () {},
        onArchive: () {},
        onGallery: () {},
        onScan: onScan,
        onRecovery: () {},
        onRecent: (_) {},
        onShare: (_) {},
        recoveryCount: 0,
      ),
    ),
  );

  testWidgets('a phone with a scanner can scan to PDF from home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var scans = 0;
    await tester.pumpWidget(home(onScan: () => scans++));
    await tester.tap(find.text('Kameradan PDF tara'));
    expect(scans, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a scanner there is no scan button', (tester) async {
    await tester.pumpWidget(home());
    expect(find.byKey(const ValueKey('mobile-scan')), findsNothing);
  });
}
