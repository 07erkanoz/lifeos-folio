import 'package:flutter/material.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/editor/snippets.dart';
import 'package:evrak_convert/services/search/index_database.dart';
import 'package:evrak_convert/ui/widgets/snippet_fill.dart';
import 'package:evrak_convert/ui/widgets/snippet_harvest.dart';

Snippet _with(String text) =>
    Snippet(id: '1', name: 'Kalıp', body: Delta()..insert('$text\n'));

void main() {
  group('blanks in a passage', () {
    test('they are found once each, in the order met', () {
      final one = _with(
        '[MAHKEME] Mahkemesi [ESAS] esas sayılı dosyada, [MAHKEME] '
        'kararı uyarınca müvekkil [MÜVEKKİL] adına.',
      );
      expect(one.blanks, ['MAHKEME', 'ESAS', 'MÜVEKKİL']);
    });

    test('ordinary brackets are not blanks', () {
      // Bir dilekçe köşeli parantez kullanabilir; yalnız büyük harfle
      // yazılmış kısa bir ad boşluk sayılır.
      expect(
        _with('(bkz. [1]) ve [bkz] ve [çok uzun bir açıklama]').blanks,
        isEmpty,
      );
    });

    test('what is given is put in, what is not stays showing', () {
      final filled = _with('[MAHKEME] Mahkemesi, [ESAS] esas.')
          .withBlanks({'MAHKEME': 'Kemer 1. Asliye Hukuk'});
      final text = filled.toList().map((o) => o.data).join();
      expect(text, contains('Kemer 1. Asliye Hukuk Mahkemesi'));
      expect(text, contains('[ESAS]'), reason: 'boş kalan görünür kalmalı');
    });

    test('filling keeps the formatting', () {
      final one = Snippet(
        id: '1',
        name: 'K',
        body: Delta()
          ..insert('[BAŞLIK]', {'bold': true})
          ..insert('\ngövde\n'),
      );
      final filled = one.withBlanks({'BAŞLIK': 'İHTARNAME'}).toList();
      expect(filled.first.data, 'İHTARNAME');
      expect(filled.first.attributes?['bold'], isTrue);
    });
  });

  group('the fill dialog', () {
    testWidgets('one field per blank, and filling hands them back', (
      tester,
    ) async {
      Map<String, String>? given;
      final one = _with('[MAHKEME] Mahkemesi [ESAS] esas.');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    given = await SnippetFill.ask(context, one),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('snippet-blank-MAHKEME')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('snippet-blank-ESAS')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('snippet-blank-MAHKEME')),
        'Kemer 1. Asliye Hukuk',
      );
      await tester.tap(find.byKey(const ValueKey('snippet-blanks-fill')));
      await tester.pumpAndSettle();
      expect(given, {'MAHKEME': 'Kemer 1. Asliye Hukuk'});
    });

    testWidgets('leaving them blank is allowed and says so', (tester) async {
      Map<String, String>? given;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => given = await SnippetFill.ask(
                  context,
                  _with('[ESAS] esas.'),
                ),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('snippet-blanks-skip')));
      await tester.pumpAndSettle();
      expect(given, isEmpty);
    });
  });

  group('harvesting from the archive', () {
    test('what belongs to one case becomes a blank', () {
      const text =
          'Kemer İcra Müdürlüğü 2019/3931 sayılı dosyada '
          '12.03.2024 tarihinde 15.000,00 TL ödenmiştir. TC: 12345678901';
      final out = SnippetHarvest.blanked(text);
      expect(out, contains('[ESAS]'));
      expect(out, contains('[TARİH]'));
      expect(out, contains('[TUTAR]'));
      expect(out, contains('[TC]'));
      expect(out, isNot(contains('2019/3931')));
      expect(out, isNot(contains('12345678901')));
    });

    test('the name comes from the opening words', () {
      expect(
        SnippetHarvest.nameFor(
          'Taraflar söz alarak arabuluculuğun temel '
          'ilkelerini dinlemiştir.',
        ),
        'Taraflar söz alarak arabuluculuğun temel ilkelerini',
      );
    });

    test('a passage in five files is offered, one in four is not', () {
      final db = IndexDatabase(':memory:');
      addTearDown(db.close);
      const shared =
          'Taraflar söz alarak arabuluculuğun temel ilkelerini ve '
          'sürecin işleyişini dinlemiş, anlaşmaya varılmıştır.';
      const rare =
          'Bu paragraf yalnızca birkaç belgede geçmektedir ve '
          'kalıba alınacak kadar sık değildir efendim.';
      for (var i = 0; i < 6; i++) {
        db.db.execute(
          'INSERT INTO documents(path,name,extension,size,modified,changed,'
          'text,state) VALUES(?,?,?,?,?,?,?,?)',
          [
            '/a/$i.udf',
            '$i.udf',
            'udf',
            1,
            1,
            1,
            '$shared\n\n${i < 4 ? rare : "başka bir şey"}\n',
            'ready',
          ],
        );
      }
      final found = db.repeatedPassages();
      expect(found.map((one) => one.text), contains(shared));
      expect(found.map((one) => one.text), isNot(contains(rare)));
      expect(found.firstWhere((one) => one.text == shared).documents, 6);
    });

    test('a passage repeated inside one file counts once', () {
      final db = IndexDatabase(':memory:');
      addTearDown(db.close);
      const passage =
          'Aynı belgede üç kez geçen ve bu yüzden üç belge gibi '
          'görünmemesi gereken bir paragraftır bu.';
      db.db.execute(
        'INSERT INTO documents(path,name,extension,size,modified,changed,'
        'text,state) VALUES(?,?,?,?,?,?,?,?)',
        [
          '/a/1.udf',
          '1.udf',
          'udf',
          1,
          1,
          1,
          '$passage\n\n$passage\n\n$passage\n',
          'ready',
        ],
      );
      expect(db.repeatedPassages(inAtLeast: 2), isEmpty);
      expect(db.repeatedPassages(inAtLeast: 1).single.documents, 1);
    });
  });
}
