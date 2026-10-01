// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/uyap/adalet_eimza.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/widgets/uyap_connect_view.dart';
import 'package:evrak_convert/ui/widgets/uyap_session_chip.dart';

/// Logs in by card and PIN, as the Adalet E-İmza application would.
class _CardUyap extends UyapWebService {
  _CardUyap() : super.forTesting();

  String? pin;
  int cancelled = 0;

  @override
  bool get connected => session.value != null;

  @override
  void disconnect() => session.value = null;

  @override
  void cancelConnect() {
    cancelled++;
    disconnect();
  }

  @override
  Future<String> connect(
    String pin, {
    void Function(String stage)? onProgress,
  }) async {
    this.pin = pin;
    session.value = UyapSession(
      user: 'Av. Deniz Yılmaz',
      since: DateTime.now().subtract(const Duration(minutes: 20)),
      route: UyapLoginRoute.tray,
    );
    return 'Av. Deniz Yılmaz';
  }
}

void main() {
  late UyapWebService saved;
  late _CardUyap web;
  final check = AdaletEimza.check;
  setUp(() {
    saved = UyapWebService.instance;
    web = _CardUyap();
    UyapWebService.instance = web;
    AdaletEimza.check = () async => true;
  });
  tearDown(() {
    UyapWebService.instance = saved;
    AdaletEimza.check = check;
  });

  testWidgets('without Adalet E-İmza on the computer its way in cannot be '
      'chosen, and where to get it is offered', (tester) async {
    AdaletEimza.check = () async => false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UyapConnectView(onConnected: (_) async {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // First of the ways in, and not to be chosen.
    final first = tester
        .widgetList<RadioListTile<Object?>>(
          find.byWidgetPredicate((w) => w is RadioListTile),
        )
        .first;
    expect((first.title as Text).data, 'Adalet E-İmza ile');
    expect(first.enabled, isFalse);
    expect(find.text('Bu bilgisayarda kurulu değil.'), findsOneWidget);
    expect(find.byKey(const ValueKey('adalet-eimza-download')), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Adalet E-İmza PIN'), findsNothing);
    // And with no e-Devlet window beside the test runner either, there is
    // no way in at all: the button says so by not being there to press.
    final connect = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Bağlan'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(connect.onPressed, isNull);

    // Installed after all: looked at again, it is the way in.
    AdaletEimza.check = () async => true;
    await tester.tap(find.text('Yeniden denetle'));
    await tester.pumpAndSettle();
    expect(find.text('Bu bilgisayarda kurulu değil.'), findsNothing);
    expect(find.widgetWithText(TextField, 'Adalet E-İmza PIN'), findsOneWidget);
  });

  testWidgets('without an e-Devlet window, the card and PIN is the way in; '
      'the session then shows who and for how long', (tester) async {
    String? connectedAs;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const UyapSessionChip(),
                UyapConnectView(
                  onConnected: (user) async => connectedAs = user,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mobil imza ile'), findsOneWidget);
    // No e-Devlet window beside the test runner: the e-Devlet ways are
    // offered but cannot be chosen, and why is said.
    expect(find.textContaining('WebKitGTK'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Adalet E-İmza PIN'), findsOneWidget);

    // Asked without a PIN, it says so rather than trying.
    await tester.tap(find.byKey(const ValueKey('uyap-connect-button')));
    await tester.pumpAndSettle();
    expect(find.text('Adalet E-İmza PIN kodunu girin.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Adalet E-İmza PIN'),
      '123456',
    );
    await tester.tap(find.byKey(const ValueKey('uyap-connect-button')));
    await tester.pumpAndSettle();
    expect(web.pin, '123456');
    expect(connectedAs, 'Av. Deniz Yılmaz');
    // 2 h 55 min, twenty minutes in: the minute under way is not counted.
    expect(find.text('UYAP · Av. Deniz Yılmaz · 2 sa 34 dk'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('uyap-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bağlantıyı kes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uyap-session')), findsNothing);
  });

  testWidgets('a session opened is kept when the view goes away, as it does '
      'the moment its caller sees the session', (tester) async {
    final loading = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<UyapSession?>(
            valueListenable: web.session,
            builder: (context, session, _) => session != null
                ? const UyapSessionChip()
                : SingleChildScrollView(
                    child: UyapConnectView(onConnected: (_) => loading.future),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Adalet E-İmza PIN'),
      '123456',
    );
    await tester.tap(find.byKey(const ValueKey('uyap-connect-button')));
    await tester.pumpAndSettle();
    // The view is gone while its caller is still loading; the session stays.
    expect(find.byType(UyapConnectView), findsNothing);
    expect(web.cancelled, 0);
    expect(web.session.value, isNotNull);
    loading.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('uyap-session')), findsOneWidget);
  });
}
