import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:evrak_convert/services/editor/snippets.dart';
import 'package:evrak_convert/ui/widgets/snippet_palette.dart';

Future<SnippetStore> _store(Directory dir) async {
  final store = SnippetStore(file: File('${dir.path}/kaliplar.json'));
  await store.load();
  return store;
}

/// Bir widget testinde dosya okumak gerçek zamanda olur; sahte saat onu
/// ilerletmediği için runAsync olmadan beklemek testi askıda bırakır.
Future<SnippetStore> _storeIn(WidgetTester tester, Directory dir) async =>
    (await tester.runAsync(() => _store(dir)))!;

Future<void> _addIn(
  WidgetTester tester,
  SnippetStore store,
  String name,
  Delta body,
) async => tester.runAsync(() => store.add(name, body));

Delta _bold(String text) => Delta()
  ..insert(text, {'bold': true})
  ..insert('\n');

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('kalip-'));
  tearDown(() async => dir.delete(recursive: true));

  group('the library on disk', () {
    test('a passage keeps its formatting across a save and a load', () async {
      final store = await _store(dir);
      await store.add('İhtarname girişi', _bold('İhtar olunur'));

      // Yeniden okunduğunda kalın kalın kalmalı: düz metne düşerse her
      // yerleştirmeden sonra elle biçimlendirmek gerekir.
      final later = await _store(dir);
      expect(later.all, hasLength(1));
      final body = later.all.single.body.toList();
      expect(body.first.data, 'İhtar olunur');
      expect(body.first.attributes?['bold'], isTrue);
    });

    test('the ones reached for most rise on their own', () async {
      final store = await _store(dir);
      final az = await store.add('Az kullanılan', _bold('a'));
      final cok = await store.add('Çok kullanılan', _bold('b'));
      expect(store.all.first.id, az.id, reason: 'başta alfabetik');
      await store.reached(cok.id);
      await store.reached(cok.id);
      expect(store.all.first.id, cok.id);
      expect(store.all.first.used, 2);
    });

    test('a damaged file leaves the editor working', () async {
      await File('${dir.path}/kaliplar.json').writeAsString('{bozuk');
      final store = await _store(dir);
      expect(store.all, isEmpty);
      // Ve üstüne yazılmaz: bakılmadan silinmiş olmaz.
      expect(await File('${dir.path}/kaliplar.json').readAsString(), '{bozuk');
    });

    test(
      'a row from a later version is skipped, the rest still load',
      () async {
        await File('${dir.path}/kaliplar.json').writeAsString(
          jsonEncode([
            {
              'id': '1',
              'ad': 'Sağlam',
              'govde': [
                {'insert': 'metin\n'},
              ],
            },
            {'id': '2', 'bilinmeyen': true},
          ]),
        );
        final store = await _store(dir);
        expect(store.all.map((k) => k.name), ['Sağlam']);
      },
    );
  });

  group('finding one', () {
    test('searching forgives the letters people skip', () async {
      final store = await _store(dir);
      await store.add('İhtarname', _bold('a'));
      await store.add('Islah dilekçesi', _bold('b'));
      await store.add('Tahliye taahhüdü', _bold('c'));

      expect(store.matching('ihtar').map((k) => k.name), ['İhtarname']);
      expect(store.matching('İHTAR').map((k) => k.name), ['İhtarname']);
      // Katı Türkçede "Islah" noktasız ı ile başlar ve "islah" onu bulmaz.
      // Arama kutusunda bu yanlış takas: kaçırmak kalıbı kaybettirir,
      // gevşek eşleşme yirmi satırlık listeye bir satır ekler.
      expect(store.matching('islah').map((k) => k.name), ['Islah dilekçesi']);
      expect(store.matching('ıslah').map((k) => k.name), ['Islah dilekçesi']);
      // Şapkasız yazmak da bulmalı.
      expect(store.matching('taahhudu').map((k) => k.name), [
        'Tahliye taahhüdü',
      ]);
      expect(store.matching('yok böyle bir şey'), isEmpty);
    });

    test('the name outranks the passage', () async {
      final store = await _store(dir);
      await store.add('Tahliye taahhüdü', _bold('başka bir konu'));
      await store.add('Başka kalıp', _bold('tahliye taahhüdü geçersizdir'));
      expect(store.matching('tahliye').first.name, 'Tahliye taahhüdü');
      expect(store.matching('tahliye'), hasLength(2));
    });

    test('every word must be met, not just one', () async {
      final store = await _store(dir);
      await store.add('Arabuluculuk temel ilkeler', _bold('a'));
      await store.add('Arabuluculuk yetki notu', _bold('b'));
      expect(store.matching('arabuluculuk yetki'), hasLength(1));
    });
  });

  group('the palette', () {
    Future<SnippetChoice?> open(
      WidgetTester tester,
      SnippetStore store, {
      String selection = '',
    }) async {
      SnippetChoice? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => chosen = await SnippetPalette.show(
                  context,
                  store: store,
                  selection: selection,
                ),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      return chosen;
    }

    testWidgets('an empty library says how to start one', (tester) async {
      final store = await _storeIn(tester, dir);
      await open(tester, store);
      expect(find.textContaining('Henüz kalıp yok'), findsOneWidget);
      // Seçim yokken ilk adım yazılı olmalı, yoksa ekran çıkmaz sokak.
      expect(find.textContaining('belgede seçin'), findsOneWidget);
      expect(find.byKey(const ValueKey('snippet-keep')), findsNothing);
    });

    testWidgets('keeping the selection is offered only when there is one', (
      tester,
    ) async {
      final store = await _storeIn(tester, dir);
      await open(tester, store, selection: 'saklanacak metin');
      expect(find.byKey(const ValueKey('snippet-keep')), findsOneWidget);
    });

    testWidgets('typing narrows the list', (tester) async {
      final store = await _storeIn(tester, dir);
      await _addIn(tester, store, 'İhtarname', _bold('a'));
      await _addIn(tester, store, 'Tahliye taahhüdü', _bold('b'));
      await open(tester, store);
      expect(find.text('İhtarname'), findsOneWidget);
      expect(find.text('Tahliye taahhüdü'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('snippet-search')),
        'ihtar',
      );
      await tester.pumpAndSettle();
      expect(find.text('İhtarname'), findsOneWidget);
      expect(find.text('Tahliye taahhüdü'), findsNothing);
    });

    testWidgets('pressing one hands it back to be inserted', (tester) async {
      final store = await _storeIn(tester, dir);
      await _addIn(tester, store, 'İhtarname', _bold('İhtar olunur'));
      SnippetChoice? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    chosen = await SnippetPalette.show(context, store: store),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İhtarname'));
      await tester.pumpAndSettle();
      expect(chosen, isA<InsertSnippet>());
      expect((chosen! as InsertSnippet).snippet.name, 'İhtarname');
    });

    testWidgets('keeping the selection asks for a name first', (tester) async {
      final store = await _storeIn(tester, dir);
      SnippetChoice? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => chosen = await SnippetPalette.show(
                  context,
                  store: store,
                  selection: 'Tahliye taahhüdü geçersizdir',
                ),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('snippet-keep')));
      await tester.pumpAndSettle();
      // Ad, seçimin ilk kelimelerinden önerilir.
      expect(find.text('Tahliye taahhüdü geçersizdir'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('snippet-keep-save')));
      await tester.pumpAndSettle();
      expect(chosen, isA<KeepSelection>());
      expect((chosen! as KeepSelection).name, 'Tahliye taahhüdü geçersizdir');
    });
  });
}
