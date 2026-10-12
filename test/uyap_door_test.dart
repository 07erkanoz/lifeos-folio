// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/uyap/adalet_eimza.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/agenda/mobile_connect.dart';
import 'package:evrak_convert/ui/widgets/uyap_connect_view.dart';

class _Web extends UyapWebService {
  _Web({this.on = false}) : super.forTesting();

  final bool on;

  @override
  bool get connected => on;
}

class _Mobile extends UyapMobileApi {
  _Mobile({this.on = false}) : super.forTesting(Uri.parse('http://127.0.0.1'));

  final bool on;

  @override
  bool get connected => on;
}

/// The ways offered, in order, by their names.
List<String> _ways(WidgetTester tester) => [
  for (final tile in tester.widgetList<RadioListTile<Object?>>(
    find.byWidgetPredicate((w) => w is RadioListTile),
  ))
    find
            .descendant(of: find.byWidget(tile), matching: find.byType(Text))
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .first ??
        '',
];

void main() {
  late UyapWebService saved;
  final check = AdaletEimza.check;
  setUp(() {
    saved = UyapWebService.instance;
    UyapWebService.instance = _Web();
    AdaletEimza.check = () async => true;
    UyapDoorMemory.reset();
  });
  tearDown(() {
    UyapWebService.instance = saved;
    AdaletEimza.check = check;
    phoneOverride = null;
  });

  Future<void> show(WidgetTester tester, Set<PortalChannel> channels) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UyapConnectView(
              channels: channels,
              mobile: _Mobile(),
              onConnected: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('on a computer the card and the web portal come first and are '
      'recommended; UYAP Mobil last, under its own name', (tester) async {
    await show(tester, const {PortalChannel.uyapWeb, PortalChannel.uyapMobile});
    expect(_ways(tester), [
      'Adalet E-İmza ile',
      'Mobil imza ile',
      'E-imza ile, e-Devlet üzerinden',
      'UYAP Mobil ile',
    ]);
    expect(find.text('UYAP WEB PORTAL'), findsOneWidget);
    expect(find.text('UYAP MOBİL'), findsOneWidget);
    final recommended = find.byKey(const ValueKey('uyap-route-recommended'));
    expect(recommended, findsOneWidget);
    expect(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is RadioListTile).first,
        matching: recommended,
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'E-imza PIN'), findsOneWidget);
  });

  testWidgets('on a phone UYAP Mobil comes first, and there is no card: '
      'neither Adalet E-İmza nor the e-signature through e-Devlet', (
    tester,
  ) async {
    phoneOverride = true;
    await show(tester, const {PortalChannel.uyapWeb, PortalChannel.uyapMobile});
    expect(_ways(tester), ['UYAP Mobil ile', 'Mobil imza ile']);
    expect(find.text('Adalet E-İmza ile'), findsNothing);
    expect(find.text('E-imza ile, e-Devlet üzerinden'), findsNothing);
    expect(find.widgetWithText(TextField, 'E-imza PIN'), findsNothing);
    expect(uyapMobileHint, contains('Mobil İmza ile'));
    expect(uyapMobileHint, isNot(contains('e-imza')));
  });

  testWidgets('the web portal alone where only it can do the work', (
    tester,
  ) async {
    phoneOverride = true;
    await show(tester, const {PortalChannel.uyapWeb});
    expect(_ways(tester), ['Mobil imza ile']);
    expect(find.byKey(const ValueKey('uyap-route-recommended')), findsNothing);
  });

  test('what each work can be done with, from the one table', () {
    expect(uyapChannelsFor(UyapOp.details), {
      PortalChannel.uyapWeb,
      PortalChannel.uyapMobile,
    });
    expect(uyapChannelsFor(UyapOp.send), {PortalChannel.uyapWeb});
    expect(uyapChannelsFor(UyapOp.excuse), {PortalChannel.uyapMobile});
    expect(uyapChannelsFor(null), {
      PortalChannel.uyapWeb,
      PortalChannel.uyapMobile,
    });
  });

  testWidgets('nothing is asked when a portal that can do the work is '
      'connected; sending with UYAP Mobil alone asks for the web portal', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    // UYAP Mobil reads the case: no door.
    expect(
      await ensureUyap(
        context,
        UyapOp.details,
        web: _Web(),
        mobile: _Mobile(on: true),
      ),
      isTrue,
    );
    expect(find.byType(UyapConnectView), findsNothing);

    // Sending is the web portal's alone: the door opens, with its ways only.
    final sent = ensureUyap(
      context,
      UyapOp.send,
      web: _Web(),
      mobile: _Mobile(on: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('UYAP Web’e bağlan'), findsOneWidget);
    expect(find.text('UYAP Mobil ile'), findsNothing);
    expect(find.text('Adalet E-İmza ile'), findsOneWidget);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    expect(await sent, isFalse);
  });
}
