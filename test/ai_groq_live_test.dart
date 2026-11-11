@Tags(['slow'])
library;

import 'dart:io';

import 'package:evrak_convert/services/ai/ai_assistant.dart';
import 'package:evrak_convert/services/ai/ai_audit.dart';
import 'package:evrak_convert/services/ai/ai_groq.dart';
import 'package:evrak_convert/services/ai/ai_guide.dart';
import 'package:evrak_convert/services/ai/folio_mcp.dart';
import 'package:flutter_test/flutter_test.dart';

/// Groq asked as Folio's panel asks it: the guide's topic added, Folio's
/// tools from a built Folio, the answer audited and written again. Run by
/// hand, with a key and a build:
///   GROQ_KEY_FILE=… FOLIO_BUILD=…/lifeos_folio GROQ_OUT=… flutter test
///   test/ai_groq_live_test.dart
void main() {
  // The tables Folio reads come from its assets; the test binding would
  // answer every request with 400, so the real network is put back.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final keyFile = Platform.environment['GROQ_KEY_FILE'];
  final build = Platform.environment['FOLIO_BUILD'];
  final out = Platform.environment['GROQ_OUT'];
  final runs = int.tryParse(Platform.environment['GROQ_RUNS'] ?? '') ?? 1;
  final skip = keyFile == null || build == null || out == null;

  const questions = {
    'iade':
        'İşverenin haklı neden olmadan iş sözleşmesini feshettiği durumda '
        'işçinin işe iade davası açma süresi ve arabuluculuk şartı hakkında '
        'Yargıtay\'ın güncel bir kararını bul. Kararın künyesini ve ilgili '
        'kısmını karar_ara ve karar_getir araçlarıyla oku, ezberden yazma.',
    'icra':
        'Müvekkilime ilamsız icra takibinde ödeme emri tebliğ edildi. Borca '
        'itiraz süresi kaç gündür ve hangi maddeye dayanır? Maddeyi araçla '
        'oku.',
    'tuzak':
        '6098 sayılı Türk Borçlar Kanunu\'nun 1050. maddesine göre kira '
        'bedelinin artırılma oranı nedir? Müvekkilime bu maddeye dayanarak '
        'dilekçe yazacağım.',
  };

  for (final MapEntry(key: name, value: question) in questions.entries) {
    for (var run = 1; run <= runs; run++) {
      test(
        '$name $run',
        skip: skip,
        timeout: const Timeout(Duration(minutes: 15)),
        () async {
          GroqChat.keyForTest = File(keyFile!).readAsStringSync().trim();
          GroqChat.folioForTest = build;
          final guide = (await LegalGuide.load()).blockFor(question);
          final prompt = AiAssistant.prompt(
            task: AiTask.question,
            question: question,
            guide: guide,
          );
          final thread = AiThread('canli-$name-$run');
          final steps = <String, AiStep>{};
          final began = DateTime.now();
          var answer = await AiAssistant.ask(
            AiProvider.groq,
            prompt,
            tier: AiTier.strong,
            thread: thread,
            onEvent: (e) {
              if (e is AiStep) steps[e.id] = e;
            },
          );
          final first = answer;
          var rounds = 0, read = 0;
          final mcp = FolioMcp();
          for (var round = 0; round < 2; round++) {
            final feedback = await AnswerAudit(mcp)
                .feedback(answer, steps.values, said: (_) => read++);
            if (feedback == null) break;
            if (!await AiAssistant.goesOn(AiProvider.groq, thread)) break;
            final again = await AiAssistant.ask(
              AiProvider.groq,
              feedback,
              tier: AiTier.strong,
              thread: thread,
              onEvent: (e) {
                if (e is AiStep) steps['d$round-${e.id}'] = e;
              },
            );
            if (again.trim().isNotEmpty) answer = again;
            rounds++;
          }
          final took = DateTime.now().difference(began).inSeconds;
          File('$out/$name-$run.txt')
              .writeAsStringSync('$answer\n\n--- ilk cevap ---\n$first\n');
          File('$out/tablo.txt').writeAsStringSync(
            '$name $run | $took sn | araç ${steps.length} '
            '(${steps.values.map((s) => s.tool).toSet().join(',')}) | '
            'rehber ${guide == null ? '-' : LegalGuide.parse(File(LegalGuide.asset).readAsStringSync()).topicsIn(question).take(2).join(',')} | '
            'denetim $rounds tur, $read madde | cevap ${answer.length}\n',
            mode: FileMode.append,
          );
          expect(answer, isNotEmpty);
        },
      );
    }
  }
}
