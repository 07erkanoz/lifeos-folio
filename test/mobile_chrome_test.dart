import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/agenda/channel_bar.dart';
import 'package:evrak_convert/ui/mobile/scroll_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a scrolled list folds the headings away; pulled back, they '
      'return', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(ScrollChrome.show);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChromeScrollWatcher(
            child: Column(
              children: [
                const FoldingChrome(
                  child: SizedBox(height: 120, child: Text('Başlık')),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (var i = 0; i < 60; i++)
                        SizedBox(height: 48, child: Text('Evrak $i')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Başlık'), findsOne);
    await tester.drag(find.text('Evrak 3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Başlık'), findsNothing);
    await tester.drag(find.text('Evrak 10'), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(find.text('Başlık'), findsOne);
  });

  testWidgets('a phone shows the portals as small chips in one row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PortalChannelBar(
            sync: PortalSync(
              web: UyapWebService.forTesting(),
              mobile: UyapMobileApi.forTesting(
                Uri.parse('http://127.0.0.1:9/'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Mobil'), findsOne);
    expect(find.text('UETS'), findsOne);
    expect(find.text('UYAP Mobil · bağlan'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('channel-uyapMobile'))).height,
      lessThan(28),
    );
  });
}
