import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/ui/office/send_to_office.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Net extends OfficeNetwork {
  _Net(this.targets);
  final List<SendTarget> targets;
  final sent = <String>[];
  @override
  List<SendTarget> get sendTargets => targets;
  @override
  Future<String?> sendTo(
    SendTarget to,
    List<String> paths, {
    String text = '',
  }) async {
    sent.add('${to.deviceId} ${paths.join(',')}');
    return null;
  }
}

const _computer = SendTarget(
  deviceId: 'pc',
  name: 'Kendi cihazım',
  detail: 'buro-pc',
  member: false,
  online: true,
);

Future<void> _scanned(WidgetTester tester, OfficeNetwork net) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                offerSendAfterScan(context, '/tarama.pdf', network: net),
            child: const Text('tara'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('tara'));
  // The notice slid in.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 750));
}

void main() {
  testWidgets('after a scan, one tap sends it to the own computer on the '
      'network', (tester) async {
    final net = _Net([_computer]);
    await _scanned(tester, net);
    expect(find.textContaining('buro-pc ağda'), findsOneWidget);
    await tester.tap(find.text('Gönder'));
    await tester.pump();
    expect(net.sent, ['pc /tarama.pdf']);
  });

  testWidgets('after a scan, nothing is offered with no one to send to', (
    tester,
  ) async {
    await _scanned(tester, _Net(const []));
    expect(find.text('Tarama kaydedildi'), findsNothing);
  });

  testWidgets('after a scan, an own device away is not sent to at once', (
    tester,
  ) async {
    final net = _Net(const [
      SendTarget(
        deviceId: 'pc',
        name: 'Kendi cihazım',
        detail: 'buro-pc',
        member: false,
        online: false,
      ),
    ]);
    await _scanned(tester, net);
    expect(find.textContaining('ağda'), findsNothing);
    await tester.tap(find.text('Gönder'));
    await tester.pumpAndSettle();
    expect(net.sent, isEmpty);
    // The list instead, where it shows as away.
    expect(find.textContaining('ağda değil'), findsOneWidget);
  });

  testWidgets('no one to send to, no "Gönder"', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SendToOfficeButton(
            paths: () => const ['/yok.pdf'],
            network: OfficeNetwork(),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('send-to-office')), findsNothing);
  });
}
