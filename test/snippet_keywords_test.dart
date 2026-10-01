import 'dart:convert';

import 'package:evrak_convert/services/editor/snippets.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

Delta _text(String text) => Delta()..insert('$text\n');

void main() {
  test('a keyword is a short word; a key is F1 to F12 but not F4', () {
    expect(Snippet.validKeyword('dil1'), isTrue);
    expect(Snippet.validKeyword('İHTAR'), isTrue);
    expect(Snippet.validKeyword('a'), isFalse);
    expect(Snippet.validKeyword('iki kelime'), isFalse);
    expect(Snippet.validKeyword('çok-uzun'), isFalse);
    expect(Snippet.hotkeys, isNot(contains(4)));
    expect(Snippet.hotkeys, hasLength(11));
  });

  test('keyword and key are kept, and a bad one read from a file is '
      'dropped rather than trusted', () {
    final one = Snippet(
      id: 'a',
      name: 'Dilekçe girişi',
      body: _text('SAYIN MAHKEMEYE'),
      keyword: 'dil1',
      hotkey: 2,
    );
    final back = Snippet.fromJson(
      jsonDecode(jsonEncode(one.toJson())) as Map<String, Object?>,
    )!;
    expect(back.keyword, 'dil1');
    expect(back.hotkey, 2);

    final bad = Snippet.fromJson({
      'id': 'b',
      'ad': 'Bozuk',
      'govde': _text('x').toJson(),
      'anahtar': 'iki kelime',
      'kisayol': 4,
    })!;
    expect(bad.keyword, isEmpty);
    expect(bad.hotkey, isNull);
  });

  test('a keyword is found however its letters were typed, and two passages '
      'cannot share a keyword or a key', () async {
    final store = SnippetStore.memory();
    final ihtar = await store.add('İhtarname', _text('İHTARNAME'));
    await store.update(ihtar.copyWith(keyword: 'İHTAR', hotkey: () => 3));
    final other = await store.add('Diğer', _text('başka'));

    expect(store.byKeyword('ihtar')?.id, ihtar.id);
    expect(store.byKeyword('IHTAR')?.id, ihtar.id);
    expect(store.byKeyword('ihtarname'), isNull);
    expect(store.byHotkey(3)?.id, ihtar.id);

    expect(store.keywordTaken('ihtar', except: other.id)?.id, ihtar.id);
    expect(store.keywordTaken('ihtar', except: ihtar.id), isNull);
    expect(store.hotkeyTaken(3, except: other.id)?.id, ihtar.id);
    expect(store.hotkeyTaken(5), isNull);
  });

  test('passages added in one go each get an id of their own, so changing '
      'one leaves the others alone', () async {
    final store = SnippetStore.memory();
    final added = [
      for (var i = 0; i < 50; i++) await store.add('Kalıp $i', _text('$i')),
    ];
    expect(added.map((s) => s.id).toSet(), hasLength(50));
    await store.update(added.first.copyWith(name: 'Değişti'));
    expect(store.all.where((s) => s.name == 'Değişti'), hasLength(1));
    await store.remove(added.last.id);
    expect(store.all, hasLength(49));
  });

  test('importing adds what is new, once, and never takes a keyword or key '
      'another passage has', () async {
    final source = SnippetStore.memory();
    final a = await source.add('Giriş', _text('SAYIN MAHKEMEYE'));
    await source.update(a.copyWith(keyword: 'dil1', hotkey: () => 2));
    await source.add('Kapanış', _text('Saygılarımla arz ederim.'));
    final exported = source.export();

    final target = SnippetStore.memory();
    final mine = await target.add('Benim', _text('benim metnim'));
    await target.update(mine.copyWith(keyword: 'dil1'));

    expect(await target.import(exported), 2);
    expect(target.all, hasLength(3));
    final giris = target.all.firstWhere((s) => s.name == 'Giriş');
    expect(giris.keyword, isEmpty, reason: 'dil1 zaten “Benim” kalıbında');
    expect(giris.hotkey, 2);
    // The same file again adds nothing.
    expect(await target.import(exported), 0);
    expect(target.all, hasLength(3));
    expect(() => target.import('{"değil": "liste"}'), throwsFormatException);
  });
}
