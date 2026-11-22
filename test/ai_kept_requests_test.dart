import 'dart:io';

import 'package:evrak_convert/services/ai/ai_case.dart';
import 'package:flutter_test/flutter_test.dart';

/// Folio Ajan's folder is kept between conversations: a refresh answered
/// last night is not done again at the next start (it asked for the
/// e-signature PIN each time, 23 Kasım 2026).
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ajan-oturum'));
  tearDown(() => dir.deleteSync(recursive: true));

  File ask(String id, {Duration age = Duration.zero}) {
    final f = File('${dir.path}/guncelle-$id.json')
      ..writeAsStringSync('{"kapsam":"tebligatlar"}');
    f.setLastModifiedSync(DateTime.now().subtract(age));
    return f;
  }

  test('one answered already is not asked again', () async {
    ask('a');
    File('${dir.path}/guncelle-a.sonuc.json').writeAsStringSync('{}');
    ask('b');
    final r = await AiCaseSession.at(dir).refreshes();
    expect([for (final x in r) x.id], ['b']);
  });

  test('one no one waits for any more is taken away, not done', () async {
    final old = ask('c', age: const Duration(minutes: 30));
    expect(await AiCaseSession.at(dir).refreshes(), isEmpty);
    expect(old.existsSync(), isFalse);
  });

  test('a new conversation starts with none left', () async {
    ask('d');
    File('${dir.path}/indir-e.json').writeAsStringSync('{"anahtar":"k"}');
    File('${dir.path}/dosya.json').writeAsStringSync('{}');
    final session = AiCaseSession.at(dir);
    await session.forgetRequests();
    expect(await session.refreshes(), isEmpty);
    expect(await session.pending(), isEmpty);
    expect(File('${dir.path}/dosya.json').existsSync(), isTrue);
  });
}
