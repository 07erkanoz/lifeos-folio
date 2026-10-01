import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/editor/spell_check.dart';
import 'package:evrak_convert/ui/widgets/editor_spelling.dart';

/// Stands in for the machine's own checker.
class _Bridge {
  _Bridge(this.channel, {this.available = true, this.errors = const []}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'available':
              return available;
            case 'check':
              return errors;
            case 'suggest':
              return ['mahkemeye', 'mahkemesine'];
            case 'add':
              learned.add((call.arguments as Map)['word'] as String);
              return null;
          }
          return null;
        });
  }
  final MethodChannel channel;
  final bool available;
  final List<Object?> errors;
  final calls = <String>[];
  final learned = <String>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('folio/spellcheck');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'what the machine reports comes back as offsets into the text',
    () async {
      _Bridge(
        channel,
        errors: [
          {'start': 8, 'length': 5, 'repeated': false},
        ],
      );
      final found = await SpellCheck(channel: channel).check('Sayın hakm bey');
      expect(found, [const Misspelling(start: 8, length: 5)]);
    },
  );

  test('a long document is checked in responsive offset-safe chunks', () async {
    final asked = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'available') return true;
          if (call.method != 'check') return null;
          final text = (call.arguments as Map)['text'] as String;
          asked.add(text);
          final at = text.indexOf('hatali');
          return at < 0
              ? const <Object?>[]
              : <Object?>[
                  {'start': at, 'length': 6, 'repeated': false},
                ];
        });
    final text = '${List.filled(11000, 'kelime').join(' ')} hatali';
    final found = await SpellCheck(channel: channel).check(text);

    expect(asked.length, greaterThan(1));
    expect(asked.every((part) => part.length <= 20000), isTrue);
    expect(found, [Misspelling(start: text.indexOf('hatali'), length: 6)]);
  });

  test('a machine that cannot check Turkish reports nothing', () async {
    final bridge = _Bridge(
      channel,
      available: false,
      errors: [
        {'start': 0, 'length': 3, 'repeated': false},
      ],
    );
    expect(await SpellCheck(channel: channel).check('abc'), isEmpty);
    expect(
      bridge.calls,
      isNot(contains('check')),
      reason: 'nothing should be asked of a checker that said no',
    );
  });

  test('a bridge that is not there is not an error', () async {
    // No handler at all: the channel throws MissingPluginException, which is
    // what every platform but Windows does today.
    final checker = SpellCheck(channel: const MethodChannel('folio/nothing'));
    expect(await checker.available, isFalse);
    expect(await checker.check('abc'), isEmpty);
    expect(await checker.suggest('abc'), isEmpty);
  });

  test('marks are only asked for once the typing stops', () async {
    final bridge = _Bridge(
      channel,
      errors: [
        {'start': 0, 'length': 4, 'repeated': false},
      ],
    );
    final marks = SpellingMarks(
      checker: SpellCheck(channel: channel),
      after: const Duration(milliseconds: 40),
    );
    addTearDown(marks.dispose);

    marks.changed('bir');
    marks.changed('bir i');
    marks.changed('bir ik');
    expect(bridge.calls, isNot(contains('check')));

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(bridge.calls.where((c) => c == 'check').length, 1);
    expect(marks.marks, [const Misspelling(start: 0, length: 4)]);
    expect(marks.at(2)?.start, 0);
    expect(marks.at(9), isNull);
  });

  test(
    'text that arrives while a check is in flight is still checked',
    () async {
      // The reader types on while the checker is thinking. The answer coming
      // back describes text that has already been replaced, so the later text
      // has to be asked about too, or the marks stay at offsets the document
      // no longer has.
      var checks = 0;
      final slow = Completer<void>();
      final asked = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'available') return true;
            if (call.method == 'check') {
              asked.add((call.arguments as Map)['text'] as String);
              if (++checks == 1) await slow.future;
              return [
                {'start': 0, 'length': 3, 'repeated': false},
              ];
            }
            return null;
          });

      final marks = SpellingMarks(
        checker: SpellCheck(channel: channel),
        after: const Duration(milliseconds: 10),
      );
      addTearDown(marks.dispose);

      marks.changed('ilk metin');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      marks.changed('sonraki metin, bambaşka');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      slow.complete();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(checks, 2);
      expect(asked.last, 'sonraki metin, bambaşka');
    },
  );

  test('a check is not asked twice for text that has not changed', () async {
    final bridge = _Bridge(channel);
    final marks = SpellingMarks(
      checker: SpellCheck(channel: channel),
      after: const Duration(milliseconds: 10),
    );
    addTearDown(marks.dispose);

    marks.changed('aynı metin');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    marks.changed('aynı metin');
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(bridge.calls.where((c) => c == 'check').length, 1);
  });

  test('a stretch with a mark in it is split, and one without is left be', () {
    const style = TextStyle(fontSize: 12);
    const marks = [Misspelling(start: 6, length: 4)];

    expect(spellingSpans('Sayın hakm bey', 0, style, marks), isNotNull);
    final spans = spellingSpans('Sayın hakm bey', 0, style, marks)!;
    expect(spans.map((s) => (s as TextSpan).text), ['Sayın ', 'hakm', ' bey']);
    expect(
      (spans[1] as TextSpan).style!.decorationStyle,
      TextDecorationStyle.wavy,
    );
    expect(
      (spans[0] as TextSpan).style!.decoration,
      isNot(TextDecoration.underline),
    );

    // A leaf the marks do not touch keeps the single span it had.
    expect(spellingSpans('Sayın', 100, style, marks), isNull);
    expect(spellingSpans('Sayın', 0, style, const []), isNull);
  });

  test('a mark reaching past the end of a leaf is cut to it', () {
    const marks = [Misspelling(start: 2, length: 20)];
    final spans = spellingSpans('abcde', 0, null, marks)!;
    expect(spans.map((s) => (s as TextSpan).text), ['ab', 'cde']);
  });
}
