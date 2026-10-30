import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/ai/ai_assistant.dart';
import 'package:evrak_convert/services/ai/ai_login.dart';
import 'package:evrak_convert/ui/ai/ai_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_path_provider.dart';

// The lawyer's own AI programs, run by Folio with no terminal: read-only,
// every tool off, given only the text of the document chosen; the consent
// asked once and kept.
void main() {
  test('off until the lawyer turns it on; off, nothing of it is shown', () {
    addTearDown(() {
      AiAssistant.availableForTest = null;
      AiSettings.on.value = false;
    });
    expect(const AiSettings().enabled, isFalse);
    expect(AiSettings.fromJson(const {}).enabled, isFalse);
    expect(AiSettings.fromJson({'acik': true}).enabled, isTrue);
    expect(
      AiSettings.fromJson(const AiSettings().copyWith(enabled: true).toJson())
          .enabled,
      isTrue,
    );
    AiAssistant.availableForTest = true;
    AiSettings.on.value = false;
    expect(AiAssistant.shown, isFalse);
    AiSettings.on.value = true;
    expect(AiAssistant.shown, isTrue);
    AiAssistant.availableForTest = false;
    expect(AiAssistant.shown, isFalse);
  });

  group('the programs, run safe', () {
    test('Claude: print mode, no tools, no settings, nothing kept', () {
      final args = AiAssistant.arguments(AiProvider.claude, '/tmp/x');
      expect(
        args,
        containsAllInOrder(['-p', '--output-format', 'stream-json']),
      );
      final tools = args.indexOf('--tools');
      expect(args[tools + 1], '');
      expect(
        args,
        containsAll([
          '--restricted',
          '--strict-mcp-config',
          '--no-session-persistence',
          '--disable-slash-commands',
        ]),
      );
      // --bare would not read the subscription's sign-in.
      expect(args, isNot(contains('--bare')));
      // Folio's rules in place of its coding persona; the tier's model.
      expect(args, containsAllInOrder(['--system-prompt', AiPrompts.core]));
      expect(
        AiAssistant.arguments(AiProvider.claude, '/tmp/x', model: 'opus'),
        containsAllInOrder(['--model', 'opus']),
      );
      expect(args, isNot(contains('--model')));
    });

    test(
      'Codex: read-only, its shell and browser off, in the empty folder',
      () {
        final args = AiAssistant.arguments(AiProvider.codex, '/tmp/x');
        expect(args.first, 'exec');
        expect(args, containsAllInOrder(['-s', 'read-only']));
        expect(args, containsAllInOrder(['-C', '/tmp/x']));
        for (final f in [
          'shell_tool',
          'unified_exec',
          'browser_use',
          'computer_use',
        ]) {
          expect(args, containsAllInOrder(['--disable', f]));
        }
        expect(args, containsAll(['--ephemeral', '--ignore-user-config']));
        expect(args, containsAllInOrder(['-c', 'web_search="disabled"']));
        for (final f in ['multi_agent', 'plugins', 'view_image']) {
          expect(args, containsAllInOrder(['--disable', f]));
        }
        expect(args.last, '-');
        expect(
          args,
          containsAllInOrder([
            '-c',
            'model_instructions_file="/tmp/x/talimat.md"',
          ]),
        );
        expect(
          AiAssistant.arguments(
            AiProvider.codex,
            '/tmp/x',
            model: 'gpt-6-luna',
          ),
          containsAllInOrder(['-m', 'gpt-6-luna']),
        );
      },
    );

    test('Antigravity: its stream on stdin, the print flag with its value', () {
      final args = AiAssistant.arguments(AiProvider.antigravity, '/tmp/x');
      expect(args, contains('--sandbox'));
      expect(args.last, '--print=');
      final line = AiAssistant.input(AiProvider.antigravity, 'Özetle');
      final json = jsonDecode(line.trim()) as Map;
      expect(json['event'], 'user');
      // It takes no instructions apart: Folio's rules lead the message.
      expect(
        (json['message'] as Map)['content'],
        '${AiPrompts.core}\n\nÖzetle',
      );
      expect(AiAssistant.input(AiProvider.claude, 'Özetle'), 'Özetle');
    });

    test('found where installers put them, beyond a desktop\'s short PATH', () {
      final path = AiAssistant.searchPath({
        'HOME': '/home/a',
        'PATH': '/usr/bin',
      });
      expect(path.first, '/usr/bin');
      expect(path, contains('/home/a/.local/bin'));
      expect(path.where((d) => d == '/usr/bin'), hasLength(1));
    });
  });

  group('the answers read', () {
    test('Claude\'s result, and a sign-in it lacks said in Turkish', () {
      expect(
        AiAssistant.answer(
          AiProvider.claude,
          jsonEncode({'result': ' Özet. ', 'is_error': false}),
          null,
        ),
        'Özet.',
      );
      expect(
        () => AiAssistant.answer(
          AiProvider.claude,
          jsonEncode({
            'result': 'Not logged in · Please run /login',
            'is_error': true,
          }),
          null,
        ),
        throwsA(
          isA<AiFailure>().having(
            (e) => e.message,
            'message',
            contains('oturum açık değil'),
          ),
        ),
      );
      expect(
        () => AiAssistant.answer(AiProvider.claude, 'bozuk', null),
        throwsA(isA<AiFailure>()),
      );
    });

    test('what Markdown a program writes anyway is taken off', () {
      expect(
        AiAssistant.plain(
          '## Özet\n**Belgenin niteliği**\n- Madde\n```\nkod\n```',
        ),
        'Özet\nBelgenin niteliği\n- Madde\n\nkod',
      );
    });

    test('Codex\'s last message from its file', () {
      expect(
        AiAssistant.answer(
          AiProvider.codex,
          '{"type":"turn.started"}',
          'Yanıt\n',
        ),
        'Yanıt',
      );
      expect(
        () => AiAssistant.answer(AiProvider.codex, '', null),
        throwsA(isA<AiFailure>()),
      );
    });

    test('Antigravity\'s result event', () {
      const out =
          '{"event":"init"}\n'
          '{"event":"step_update"}\n'
          '{"event":"result","result":{"status":"SUCCESS","response":"Tamam\\n"}}\n';
      expect(AiAssistant.answer(AiProvider.antigravity, out, null), 'Tamam');
    });
  });

  test('the question: the document alone, cut when too long, said so', () {
    final short = AiAssistant.prompt(
      task: AiTask.summary,
      name: 'rapor.pdf',
      text: 'Bilirkişi raporu metni',
    );
    expect(short, contains('<belge ad="rapor.pdf">'));
    expect(short, contains('Bilirkişi raporu metni'));
    // Folio's rules go apart, as the program's instructions.
    expect(short, isNot(contains(AiPrompts.core)));
    expect(short, contains('Evrak türü'));
    expect(short, isNot(contains('gönderilmedi')));
    final long = AiAssistant.prompt(
      task: AiTask.question,
      name: 'uzun.udf',
      text: 'a' * (AiAssistant.maxCharacters + 10),
      question: 'Süre ne?',
      history: [(question: 'Kim?', answer: 'Davacı.')],
    );
    expect(
      long,
      contains('[Belgenin geri kalanı uzunluğu yüzünden gönderilmedi.]'),
    );
    expect(long, contains('Önceki soru: Kim?'));
    expect(long.trim().endsWith('Soru: Süre ne?'), isTrue);
  });

  test('only identity numbers that check out are hidden', () {
    // 10000000146 is a valid number; 12345678901 is not.
    expect(
      AiAssistant.maskIdentityNumbers(
        'TC 10000000146, dosya 12345678901, tel 05321234567',
      ),
      'TC ***********, dosya 12345678901, tel 05321234567',
    );
    expect(AiAssistant.maskIdentityNumbers('x100000001460'), 'x100000001460');
  });

  test('the settings kept: consent, its version, the mask, the program', () {
    final given = const AiSettings().copyWith(
      consentVersion: AiSettings.currentConsent,
      consentAt: DateTime(2026, 10, 30, 14, 12),
      consentBy: 'Av. Deniz Yılmaz',
      provider: AiProvider.codex,
    );
    final read = AiSettings.fromJson(jsonDecode(jsonEncode(given.toJson())));
    expect(read.consented, isTrue);
    expect(read.consentBy, 'Av. Deniz Yılmaz');
    expect(read.provider, AiProvider.codex);
    expect(read.mask, isTrue);
    // A consent to an older text does not count.
    expect(
      AiSettings.fromJson({'onaySurumu': AiSettings.currentConsent - 1})
          .consented,
      isFalse,
    );
    final revoked = read.copyWith(revoke: true);
    expect(revoked.consented, isFalse);
    expect(revoked.consentAt, isNull);
    expect(revoked.provider, AiProvider.codex);
  });

  test('two tiers: each task its own, each program a model for each, the '
      'lawyer\'s choice kept', () {
    expect(AiTask.summary.tier, AiTier.normal);
    expect(AiTask.question.tier, AiTier.strong);
    expect(AiProvider.claude.defaultModel(AiTier.normal), 'sonnet');
    expect(AiProvider.claude.defaultModel(AiTier.strong), 'opus');
    expect(AiProvider.codex.defaultModel(AiTier.normal), 'gpt-6-luna');
    expect(AiProvider.codex.defaultModel(AiTier.strong), 'gpt-6.1-sol');
    expect(
      AiProvider.antigravity.defaultModel(AiTier.normal),
      startsWith('gemini-3.8-flash'),
    );
    const chosen = AiSettings(models: {'codex.strong': 'gpt-6.1-terra'});
    expect(chosen.modelFor(AiProvider.codex, AiTier.strong), 'gpt-6.1-terra');
    expect(chosen.modelFor(AiProvider.codex, AiTier.normal), 'gpt-6-luna');
    final read = AiSettings.fromJson(jsonDecode(jsonEncode(chosen.toJson())));
    expect(read.models, {'codex.strong': 'gpt-6.1-terra'});
  });

  test('a sign-in\'s address and code read from what the program says', () {
    final login = AiLogin(AiProvider.codex);
    login.read(
      '\x1B[1mOpen this link:\x1B[0m https://auth.openai.com/codex/device',
    );
    login.read('Enter this one-time code: KXQ4-7TPM');
    expect(login.address, 'https://auth.openai.com/codex/device');
    expect(login.code, 'KXQ4-7TPM');
    expect(AiLogin.arguments(AiProvider.codex), ['login', '--device-auth']);
    expect(AiLogin.arguments(AiProvider.claude), [
      'auth',
      'login',
      '--claudeai',
    ]);
    expect(AiProvider.antigravity.signsInFromFolio, isFalse);
    login.dispose();
  });

  testWidgets('the consent: asked once, not given without the box ticked, '
      'kept after', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-yz-onay-'),
    ))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    useFakePathProvider(dir);
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    bool? first;
    unawaited(askAiConsent(ctx).then((v) => first = v));
    await settle();
    expect(find.byKey(const ValueKey('ai-consent')), findsOneWidget);
    // Not given until the box is ticked.
    await tester.tap(find.byKey(const ValueKey('ai-consent-accept')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-consent')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('ai-consent-read')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-consent-read')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-consent-accept')));
    await settle();
    expect(first, isTrue);
    expect(find.byKey(const ValueKey('ai-consent')), findsNothing);
    final kept = (await tester.runAsync(AiSettings.load))!;
    expect(kept.consented, isTrue);
    expect(kept.consentAt, isNotNull);
    // Asked again: given already, no dialog.
    bool? again;
    unawaited(askAiConsent(ctx).then((v) => again = v));
    await settle();
    expect(again, isTrue);
    expect(find.byKey(const ValueKey('ai-consent')), findsNothing);
  });
}
