import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/ai/ai_assistant.dart';
import 'package:evrak_convert/services/ai/ai_memory.dart';
import 'package:evrak_convert/services/ai/ai_relay.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/ui/ai/case_ai_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_path_provider.dart';

// Asked on the phone, answered by the lawyer's computer: the question goes
// as a waiting turn with Senkron, the computer's AI program answers it in
// its place, and what it offered comes back for the phone to keep.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    useFakePathProvider();
    await AiSettings.reload();
    await const AiSettings()
        .copyWith(enabled: true, consentVersion: AiSettings.currentConsent)
        .save();
  });

  tearDown(() {
    AiAssistant.availableForTest = null;
    AiSettings.on.value = false;
  });

  test('a phone\'s question answered by the computer, once', () async {
    final phone = PortalDatabase.memory(), computer = PortalDatabase.memory();
    addTearDown(phone.dispose);
    addTearDown(computer.dispose);
    const key = '2026/470|manavgat 3 is mahkemesi';
    phone.putAiRecord('c1', AiMemory.chat, key, {
      ...AiMemory.chatRecord(
        title: 'İtiraz süresi',
        document: '',
        started: DateTime(2026, 10, 30),
        turns: [
          {'soru': 'Önceki soru', 'cevap': 'Önceki cevap', 'yazan': 'Claude'},
          {'soru': 'İtiraz süresi ne zaman doluyor?', 'bekliyor': true},
        ],
        court: 'Manavgat 3. İş Mahkemesi',
        number: '2026/470',
      ),
    });
    expect(computer.aiMerge(phone.aiExport()), isTrue);

    final asked = <String>[];
    final relay = AiRelay(
      database: () async => computer,
      provider: (_) async => AiProvider.claude,
      ask: (provider, prompt, session, model, _) async {
        asked.add(prompt);
        // The program offers a finding as it works.
        await File('${session!.folder.path}/bulgu-1.json').writeAsString(
          jsonEncode({
            'bulgular': [
              {'tur': 'yapilacak', 'metin': 'Tebliğ tarihi teyit edilmeli.'},
            ],
          }),
        );
        return 'Tebliğden itibaren iki hafta.';
      },
    );
    // A phone never takes a question.
    AiAssistant.availableForTest = false;
    expect(await relay.poke(), isFalse);

    AiAssistant.availableForTest = true;
    expect(await relay.poke(), isTrue);
    expect(asked.single, contains('İtiraz süresi ne zaman doluyor?'));
    expect(asked.single, contains('Önceki cevap'));
    expect(asked.single, contains('Manavgat 3. İş Mahkemesi 2026/470'));
    // Answered: nothing waits.
    expect(await relay.poke(), isFalse);

    expect(phone.aiMerge(computer.aiExport()), isTrue);
    final last = AiMemory.turnsOf(phone.aiRecords(AiMemory.chat).single).last;
    expect(last['bekliyor'], isFalse);
    expect(last['cevap'], 'Tebliğden itibaren iki hafta.');
    expect(last['yazan'], 'Claude · Güçlü');
    expect(last['cevaplayan'], isNotNull);
    final offer = (last['teklifler'] as List).single as Map;
    expect(offer['tur'], AiMemory.finding);
    expect((offer['bulgular'] as List).single['tur'], 'yapilacak');
    // Kept at once, as the case's, as on the computer.
    expect(offer['karar'], '1 bulgu dosyanın hafızasına kaydedildi');
    expect(
      phone.aiRecords(AiMemory.finding).single['metin'],
      'Tebliğ tarihi teyit edilmeli.',
    );
  });

  test('a computer with no program signed in says so in the question\'s '
      'place', () async {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.putAiRecord('c2', AiMemory.chat, '', {
      ...AiMemory.chatRecord(
        title: 'Soru',
        document: '',
        started: DateTime(2026, 10, 30),
        turns: [
          {'soru': 'Soru', 'bekliyor': true},
        ],
      ),
    });
    AiAssistant.availableForTest = true;
    final relay = AiRelay(
      database: () async => db,
      provider: (_) async => null,
      ask: (_, _, _, _, _) async => fail('not asked'),
    );
    expect(await relay.poke(), isTrue);
    final last = AiMemory.turnsOf(db.aiRecords(AiMemory.chat).single).last;
    expect(last['bekliyor'], isFalse);
    expect(last['hata'], contains('oturumu açık'));
  });

  testWidgets('on the phone: asked, waiting, answered, and what was '
      'offered kept', (tester) async {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    const key = '2026/470|manavgat 3 is mahkemesi';
    AiAssistant.availableForTest = false;
    AiSettings.on.value = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 700,
            child: CaseAiTab(
              caseKey: key,
              record: UyapCaseRecord(
                court: 'Manavgat 3. İş Mahkemesi',
                number: '2026/470',
                fetchedAt: DateTime(2026, 10, 1),
              ),
              database: () async => db,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('case-ai-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('case-ai-relay-question')),
      'İtiraz süresi ne zaman doluyor?',
    );
    await tester.tap(find.byKey(const ValueKey('case-ai-relay-send')));
    await tester.pumpAndSettle();
    final chat = db.aiRecords(AiMemory.chat, caseKey: key).single;
    expect(AiMemory.turnsOf(chat).single['bekliyor'], isTrue);
    expect(find.textContaining('açılınca'), findsOneWidget);

    // The computer's answer comes with Senkron.
    db.putAiRecord('${chat['id']}', AiMemory.chat, key, {
      ...chat,
      'turlar': [
        {
          ...AiMemory.turnsOf(chat).single,
          'bekliyor': false,
          'cevap': 'Tebliğden itibaren iki hafta.',
          'yazan': 'Claude · Güçlü',
          'teklifler': [
            {
              'tur': AiMemory.finding,
              'bulgular': [
                {'tur': 'yapilacak', 'metin': 'Tebliğ tarihi teyit edilmeli.'},
              ],
            },
          ],
        },
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('Tebliğden itibaren iki hafta.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('case-ai-relay-keep-0-0')));
    await tester.pumpAndSettle();
    expect(
      db.aiRecords(AiMemory.finding, caseKey: key).single['metin'],
      'Tebliğ tarihi teyit edilmeli.',
    );
    expect(find.text('1 bulgu dosyaya kaydedildi'), findsOneWidget);
  });
}
