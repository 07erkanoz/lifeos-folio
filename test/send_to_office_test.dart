import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/ui/office/send_to_office.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
