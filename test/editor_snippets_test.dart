import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/editor/snippets.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:evrak_convert/ui/widgets/snippet_fill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:intl/intl.dart';

/// Gerçek editörde Ctrl+Space: kullanıcının gördüğü yol bu.
const cumle = 'Tahliye taahhüdü geçersizdir.';

void main() {
  late SnippetStore store;

  setUp(() {
    store = SnippetStore.memory();
    SnippetStore.useShared(store);
    // Never the reader's own profile.
    LawyerProfile.use(const LawyerProfile());
  });
  tearDown(() => LawyerProfile.use(null));

  const office = LawyerProfile(
    lawyers: [
      Lawyer(name: 'DENEME AVUKAT', bar: 'Antalya'),
      Lawyer(name: 'İKİNCİ AVUKAT'),
    ],
  );

  Future<QuillController> openEditor(WidgetTester tester) async {
    final draft = EditorDrafts().draft('new', 'Yeni evrak');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(body: EditorWidget(draft: draft)),
      ),
    );
    await tester.pump();
    return tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
  }

  Future<void> pressPalette(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('with a selection the palette offers to keep it', (tester) async {
    final controller = await openEditor(tester);
    controller.replaceText(
      0,
      0,
      cumle,
      TextSelection(baseOffset: 0, extentOffset: cumle.length),
    );
    await tester.pump();

    await pressPalette(tester);
    expect(find.byKey(const ValueKey('snippet-search')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('snippet-keep')),
      findsOneWidget,
      reason: 'seçim varken kalıba alma sunulmalı',
    );
  });

  testWidgets('without a selection there is nothing to keep', (tester) async {
    await openEditor(tester);
    await pressPalette(tester);
    expect(find.byKey(const ValueKey('snippet-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('snippet-keep')), findsNothing);
  });

  testWidgets('a selection is kept and then put back in', (tester) async {
    final controller = await openEditor(tester);
    controller.replaceText(
      0,
      0,
      cumle,
      TextSelection(baseOffset: 0, extentOffset: cumle.length),
    );
    await tester.pump();

    await pressPalette(tester);
    await tester.tap(find.byKey(const ValueKey('snippet-keep')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('snippet-keep-save')));
    await tester.pumpAndSettle();
    expect(store.all, hasLength(1));
    expect(store.all.single.preview, cumle);

    // Belgenin sonuna geç ve kalıbı yerleştir.
    final end = controller.document.length - 1;
    controller.updateSelection(
      TextSelection.collapsed(offset: end),
      ChangeSource.local,
    );
    await tester.pump();
    await pressPalette(tester);
    await tester.tap(find.text(store.all.single.name).first);
    await tester.pumpAndSettle();

    final text = controller.document.toPlainText();
    expect(
      cumle.allMatches(text).length,
      2,
      reason: 'kalıp bir kez daha girmeli',
    );
    expect(store.all.single.used, 1, reason: 'kullanım sayılmalı');
  });

  testWidgets('the toolbar carries it without pushing anything off', (
    tester,
  ) async {
    // Geniş şerit: 1000×550'nin üstünde açılıyor.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openEditor(tester);
    await tester.pumpAndSettle();

    final kalip = find.byTooltip('Kalıp metin · Ctrl+Boşluk');
    expect(kalip, findsOneWidget);
    // Geçen sefer buraya eklenen bir düğme bunu ekrandan taşırmıştı.
    expect(find.byTooltip('Belge geçmişi'), findsOneWidget);
    final pencere = tester.getSize(find.byType(MaterialApp));
    for (final hedef in [kalip, find.byTooltip('Belge geçmişi')]) {
      final kutu = tester.getRect(hedef);
      expect(
        kutu.right,
        lessThanOrEqualTo(pencere.width),
        reason: 'düğme pencerenin dışına taşmamalı',
      );
    }

    await tester.tap(kalip);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('snippet-search')), findsOneWidget);
  });

  testWidgets('a narrow window keeps it in the overflow menu', (tester) async {
    tester.view.physicalSize = const Size(700, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openEditor(tester);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Kalıp metin · Ctrl+Boşluk'), findsNothing);
    await tester.tap(find.byTooltip('Diğer düzenleme araçları'));
    await tester.pumpAndSettle();
    expect(find.text('Kalıp metin · Ctrl+Boşluk'), findsOneWidget);
    await tester.tap(find.text('Kalıp metin · Ctrl+Boşluk'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('snippet-search')), findsOneWidget);
  });

  testWidgets('blanks the profile of the lawyer knows go in without asking', (
    tester,
  ) async {
    LawyerProfile.use(office);
    await store.add(
      'Vekâlet',
      Delta()..insert('Davacı vekilleri [VEKİLLER], [BARO], [BUGÜN]\n'),
    );
    final controller = await openEditor(tester);
    await pressPalette(tester);
    await tester.tap(find.text('Vekâlet').first);
    await tester.pumpAndSettle();

    expect(find.byType(SnippetFill), findsNothing, reason: 'sorulacak yer yok');
    final today = DateFormat('dd.MM.yyyy').format(DateTime.now());
    expect(
      controller.document.toPlainText(),
      contains(
        'Davacı vekilleri Av. DENEME AVUKAT - Av. İKİNCİ AVUKAT, '
        'Antalya Barosu, $today',
      ),
    );
  });

  testWidgets('what the profile does not know is asked, what it knows comes '
      'filled and can be changed', (tester) async {
    LawyerProfile.use(office);
    await store.add(
      'Vekâletname',
      Delta()..insert('[MÜVEKKİL] adına [AVUKAT]\n'),
    );
    final controller = await openEditor(tester);
    await pressPalette(tester);
    await tester.tap(find.text('Vekâletname').first);
    await tester.pumpAndSettle();

    expect(find.byType(SnippetFill), findsOneWidget);
    final lawyer = find.byKey(const ValueKey('snippet-blank-AVUKAT'));
    expect(
      tester.widget<TextField>(lawyer).controller!.text,
      'Av. DENEME AVUKAT',
    );
    expect(find.text('Avukat profilinden'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('snippet-blank-MÜVEKKİL')),
      'Ayşe Deneme',
    );
    await tester.tap(find.byKey(const ValueKey('snippet-blanks-fill')));
    await tester.pumpAndSettle();
    expect(
      controller.document.toPlainText(),
      contains('Ayşe Deneme adına Av. DENEME AVUKAT'),
    );
  });

  Future<void> typeAtEnd(
    WidgetTester tester,
    QuillController controller,
    String text,
  ) async {
    final end = controller.document.length - 1;
    controller.replaceText(
      end,
      0,
      text,
      TextSelection.collapsed(offset: end + text.length),
    );
    await tester.pump();
  }

  testWidgets('a keyword and Tab write the passage, its body and bold, '
      'never its name', (tester) async {
    final giris = await store.add(
      'Dilekçe girişi',
      Delta()
        ..insert('SAYIN MAHKEMEYE', {'bold': true})
        ..insert('\n'),
    );
    await store.update(giris.copyWith(keyword: 'dil1'));
    final controller = await openEditor(tester);
    await typeAtEnd(tester, controller, 'Giriş: DİL1');

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    final text = controller.document.toPlainText();
    expect(text, startsWith('Giriş: SAYIN MAHKEMEYE'));
    expect(text, isNot(contains('DİL1')));
    expect(text, isNot(contains('Dilekçe girişi')));
    final run = controller.document.toDelta().toList().firstWhere(
      (op) => '${op.data}'.contains('SAYIN'),
    );
    expect(run.attributes?['bold'], isTrue);
    expect(store.all.single.used, 1);

    // One undo takes the passage back out and the keyword back in.
    controller.undo();
    await tester.pump();
    expect(controller.document.toPlainText(), startsWith('Giriş: DİL1'));
  });

  testWidgets('Tab without a keyword, or inside a word, is still a tab', (
    tester,
  ) async {
    final giris = await store.add('Giriş', Delta()..insert('SAYIN\n'));
    await store.update(giris.copyWith(keyword: 'dil1'));
    final controller = await openEditor(tester);
    await typeAtEnd(tester, controller, 'başka');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.document.toPlainText(), startsWith('başka\t'));

    // "dil1" with the cursor before its last letter is not a keyword yet.
    await typeAtEnd(tester, controller, ' dil1');
    final end = controller.document.length - 1;
    controller.updateSelection(
      TextSelection.collapsed(offset: end - 1),
      ChangeSource.local,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.document.toPlainText(), contains('dil\t1'));
    expect(store.all.single.used, 0);
  });

  testWidgets('Alt+F2 writes the passage on that key; a free key says so', (
    tester,
  ) async {
    final kapanis = await store.add(
      'Kapanış',
      Delta()..insert('Saygılarımla arz ederim.\n'),
    );
    await store.update(kapanis.copyWith(hotkey: () => 2));
    final controller = await openEditor(tester);
    await typeAtEnd(tester, controller, 'Son: ');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(
      controller.document.toPlainText(),
      startsWith('Son: Saygılarımla arz ederim.'),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(find.text('Alt+F7 bir kalıba atanmamış.'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  testWidgets('the library is tidied from the palette: keyword and key set, a '
      'keyword already taken refused, a passage deleted', (tester) async {
    await store.add('Giriş', Delta()..insert('SAYIN MAHKEMEYE\n'));
    final other = await store.add('Kapanış', Delta()..insert('Saygılarımla\n'));
    await store.update(other.copyWith(keyword: 'kap'));
    await openEditor(tester);
    await pressPalette(tester);
    await tester.tap(find.byKey(const ValueKey('snippet-manage')));
    await tester.pumpAndSettle();
    expect(find.text('Kalıplarım'), findsOneWidget);

    // Taken keyword: refused, and said why.
    await tester.tap(find.text('Giriş').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('snippet-edit-keyword')),
      'KAP',
    );
    await tester.tap(find.byKey(const ValueKey('snippet-edit-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('snippet-edit-error')), findsOneWidget);
    expect(find.textContaining('“Kapanış” kalıbının'), findsOneWidget);

    // A free keyword and a key: kept.
    await tester.enterText(
      find.byKey(const ValueKey('snippet-edit-keyword')),
      'dil1',
    );
    await tester.tap(find.byKey(const ValueKey('snippet-edit-hotkey')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alt+F5').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('snippet-edit-save')));
    await tester.pumpAndSettle();
    final giris = store.all.firstWhere((s) => s.name == 'Giriş');
    expect(giris.keyword, 'dil1');
    expect(giris.hotkey, 5);
    expect(find.text('dil1 + Tab'), findsOneWidget);
    expect(find.text('Alt+F5'), findsOneWidget);

    // Deleted after asking.
    await tester.tap(find.byKey(ValueKey('snippet-delete-${other.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('snippet-delete-confirm')));
    await tester.pumpAndSettle();
    expect(store.all.map((s) => s.name), ['Giriş']);
  });

  /// Types [text] a letter at a time at the end, as a reader would.
  Future<void> typeLetters(
    WidgetTester tester,
    QuillController controller,
    String text,
  ) async {
    for (final letter in text.split('')) {
      await typeAtEnd(tester, controller, letter);
    }
    await tester.pump();
  }

  testWidgets('a profile blank typed into the text fills as its bracket '
      'closes, and undo brings the blank back', (tester) async {
    LawyerProfile.use(office);
    final controller = await openEditor(tester);
    await typeLetters(tester, controller, 'Vekili: [AVUKAT]');
    expect(
      controller.document.toPlainText(),
      startsWith('Vekili: Av. DENEME AVUKAT'),
    );
    controller.undo();
    await tester.pump();
    expect(controller.document.toPlainText(), startsWith('Vekili: [AVUKAT]'));

    // Not a profile blank: left for the reader.
    await typeLetters(tester, controller, ' [MÜVEKKİL]');
    expect(controller.document.toPlainText(), contains('[MÜVEKKİL]'));

    // A profile blank the profile has nothing for: said, and left.
    await typeLetters(tester, controller, ' [KEP]');
    expect(controller.document.toPlainText(), contains('[KEP]'));
    expect(find.text('Avukat profilinde “KEP adresi” yok.'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // Pasted, not typed: kept as it came.
    await typeAtEnd(tester, controller, ' [BARO]');
    await tester.pump();
    expect(controller.document.toPlainText(), contains('[BARO]'));
  });

  testWidgets('the palette offers the profile: a button when nothing is '
      'typed, a line when searched', (tester) async {
    LawyerProfile.use(office);
    final controller = await openEditor(tester);
    await pressPalette(tester);
    await tester.tap(find.byKey(const ValueKey('profile-Avukat')));
    await tester.pumpAndSettle();
    expect(controller.document.toPlainText(), startsWith('Av. DENEME AVUKAT'));

    await typeAtEnd(tester, controller, ', ');
    await pressPalette(tester);
    await tester.enterText(
      find.byKey(const ValueKey('snippet-search')),
      'baro',
    );
    await tester.pumpAndSettle();
    expect(find.text('Antalya Barosu'), findsOneWidget);
    expect(find.text('Profilden · Baro'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(
      controller.document.toPlainText(),
      startsWith('Av. DENEME AVUKAT, Antalya Barosu'),
    );
  });

  testWidgets('with no profile the palette offers to fill one in', (
    tester,
  ) async {
    await openEditor(tester);
    await pressPalette(tester);
    expect(find.byKey(const ValueKey('profile-Avukat')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('profile-fill')));
    await tester.pumpAndSettle();
    expect(find.text('Avukat profili'), findsOneWidget);
  });
}
