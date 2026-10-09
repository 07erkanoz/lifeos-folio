import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_messages.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/ui/clients/client_message_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a Turkish number is written as WhatsApp and SMS take it', () {
    expect(phoneDigits('0532 000 00 41'), '905320000041');
    expect(phoneDigits('532-000-0041'), '905320000041');
    expect(phoneDigits('+90 (532) 000 00 41'), '905320000041');
    expect(phoneDigits('0090 532 000 00 41'), '905320000041');
    expect(phoneDigits('+49 151 2345 6789'), '4915123456789');
    expect(phoneDigits('12'), '');
  });

  test('the message opens in WhatsApp with its words, the e-mail with its '
      'subject; none without a number or an address', () {
    final wa = messageLinks(
      MessageChannel.whatsapp,
      phone: '0532 000 00 41',
      email: '',
      subject: '',
      text: 'Sayın Ayşe Karaca,\nduruşma 22 Ekim',
    );
    expect(wa, isNotEmpty);
    expect(wa.first.toString(), contains('905320000041'));
    expect(
      Uri.decodeComponent(wa.first.toString()),
      contains('Sayın Ayşe Karaca,\nduruşma 22 Ekim'),
    );
    final mail = messageLinks(
      MessageChannel.email,
      phone: '',
      email: 'ayse@ornek.com',
      subject: 'Duruşma hatırlatması',
      text: 'Merhaba',
    ).single;
    expect(mail.scheme, 'mailto');
    expect(mail.toString(), contains('subject=Duru%C5%9Fma'));
    expect(
      messageLinks(
        MessageChannel.sms,
        phone: '',
        email: '',
        subject: '',
        text: 'x',
      ),
      isEmpty,
    );
  });

  test('a hearing\'s reminder names the court and the day, not the case\'s '
      'number', () {
    final m = messageText(
      MessageKind.hearing,
      client: 'Ayşe Karaca',
      lawyer: 'Av. Deniz Kaya',
      court: 'Antalya 3. Asliye Hukuk Mahkemesi',
      at: DateTime(2026, 10, 22, 10, 30),
    );
    expect(m.body, startsWith('Sayın Ayşe Karaca,'));
    expect(m.body, contains("Antalya 3. Asliye Hukuk Mahkemesi'ndeki"));
    expect(m.body, contains('22 Ekim 2026 Perşembe saat 10:30'));
    expect(m.body, endsWith('Av. Deniz Kaya'));
    expect(m.subject, 'Duruşma hatırlatması · 22.10.2026');
  });

  group('the day\'s messages', () {
    late PortalDatabase db;
    final now = DateTime(2026, 10, 19, 9);
    setUp(() {
      db = PortalDatabase.memory();
      db.mergeCases(
        [
          PortalCase(
            key: caseKey('2024/318', 'Antalya 3. Asliye Hukuk Mahkemesi'),
            number: '2024/318',
            court: 'Antalya 3. Asliye Hukuk Mahkemesi',
          ),
        ],
        portfolio: true,
        baseline: true,
      );
      final key = caseKey('2024/318', 'Antalya 3. Asliye Hukuk Mahkemesi');
      db.setRepresentation(key, const [(ad: 'AYŞE KARACA', rol: 'Davacı')]);
      final at = DateTime(2026, 10, 22, 10, 30);
      db.mergeHearings(PortalChannel.uyapWeb, DateTime(2026), DateTime(2027), [
        PortalHearing(
          key: hearingKey('2024/318', 'Antalya 3. Asliye Hukuk Mahkemesi', at),
          caseKey: key,
          number: '2024/318',
          court: 'Antalya 3. Asliye Hukuk Mahkemesi',
          at: at,
          kind: Observed('Tahkikat', PortalChannel.uyapWeb, now),
        ),
      ], complete: true);
    });
    tearDown(() => db.dispose());

    test('ask only of clients who wish it, and not again once told', () {
      db.saveClient(
        Client(
          id: 'c1',
          name: 'AYŞE KARACA',
          phone: '0532 000 00 41',
          updated: DateTime(2026),
        ),
      );
      expect(dueMessages(db, now, db.clientEntries()), isEmpty);
      db.saveClient(db.clientCard('c1')!.copyWith(messages: true));
      final due = dueMessages(db, now, db.clientEntries()).single;
      expect(due.kind, MessageKind.hearing);
      expect(due.daysLeft, 3);
      db.saveClientRecord(
        messageRecord(
          clientId: 'c1',
          channel: MessageChannel.whatsapp,
          kind: MessageKind.hearing,
          text: 'x',
          lawyer: 'Av. Deniz Kaya',
          about: due.about,
        ),
      );
      expect(dueMessages(db, now, db.clientEntries()), isEmpty);
    });

    testWidgets('the message is written from the hearing kept, read over '
        'before it goes', (tester) async {
      db.saveClient(
        Client(
          id: 'c1',
          name: 'AYŞE KARACA',
          phone: '0532 000 00 41',
          messages: true,
          updated: DateTime(2026),
        ),
      );
      final e = db.clientEntries().single;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientMessageDialog(
              client: e.client!,
              cases: e.cases,
              database: db,
              lawyer: 'Av. Deniz Kaya',
              due: dueMessages(db, now, [e]).single,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = tester
          .widget<TextField>(find.byKey(const ValueKey('message-text')))
          .controller!
          .text;
      expect(text, contains('22 Ekim 2026 Perşembe saat 10:30'));
      expect(text, isNot(contains('2024/318')));
      expect(find.text('WhatsApp\'ta aç'), findsOneWidget);
    });
  });
}
