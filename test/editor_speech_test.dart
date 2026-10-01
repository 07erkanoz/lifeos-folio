import 'dart:io';

import 'package:evrak_convert/services/editor/editor_drafts.dart';
import 'package:evrak_convert/services/editor/editor_settings.dart';
import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/editor/snippets.dart';
import 'package:evrak_convert/services/speech/reading_text.dart';
import 'package:evrak_convert/services/speech/speech_models.dart';
import 'package:evrak_convert/services/speech/speech_session.dart';
import 'package:evrak_convert/ui/widgets/editor_toolbar.dart';
import 'package:evrak_convert/ui/widgets/editor_widget.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'speech_session_test.dart'
    show FakeEar, FakeMicrophone, FakePlayer, FakeVoice;
import 'support/real_fonts.dart';

/// Reading aloud and dictation in the editor itself: the page follows the
/// voice, and what is said lands where the caret is.
void main() {
  late Directory settingsDir;
  late FakeVoice voice;
  late FakePlayer player;
  late FakeEar ear;
  late FakeMicrophone microphone;
  final reading = ReadAloud.instance;
  final dictation = Dictation.instance;
  final store = SpeechModelStore.instance;

  setUpAll(loadRealFonts);

  setUp(() {
    // Each test reads the tables afresh: a load kept from the last test's
    // fake clock never completes in this one.
    ReadingText.forget();
    rootBundle.clear();
    SnippetStore.useShared(SnippetStore.memory());
    LawyerProfile.use(const LawyerProfile());
    settingsDir = Directory.systemTemp.createTempSync('folio-editor-ses-');
    EditorSettings.instance = EditorSettings(directory: settingsDir);
    voice = FakeVoice();
    player = FakePlayer();
    ear = FakeEar();
    microphone = FakeMicrophone();
    ReadAloud.instance = ReadAloud(
      openVoice: (_) async => voice,
      player: player,
    );
    Dictation.instance = Dictation(
      openEar: (_) async => ear,
      microphone: microphone,
    );
    SpeechModelStore.instance = _Installed();
  });
  tearDown(() {
    LawyerProfile.use(null);
    EditorSettings.instance = EditorSettings();
    ReadAloud.instance = reading;
    Dictation.instance = dictation;
    SpeechModelStore.instance = store;
    settingsDir.deleteSync(recursive: true);
  });

  Future<QuillController> openEditor(WidgetTester tester, String text) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: EditorWidget(draft: EditorDrafts().draft('new', 'Yeni evrak')),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    final controller = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller;
    controller.replaceText(
      0,
      controller.document.length - 1,
      text,
      const TextSelection.collapsed(offset: 0),
    );
    await tester.pump();
    return controller;
  }

  /// Until the reading has begun: the tables it needs are read from the
  /// asset bundle, which takes turns of the real event loop.
  Future<void> untilReading(WidgetTester tester) async {
    for (var i = 0; i < 50; i++) {
      if (ReadAloud.instance.state == ReadState.reading) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(ReadAloud.instance.state, ReadState.reading);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // The models are let go of a while after they were last used.
    await tester.pump(const Duration(minutes: 4));
  }

  testWidgets('the page is read a sentence at a time, each one selected as '
      'it is said', (tester) async {
    final controller = await openEditor(
      tester,
      'HMK m. 119 uyarınca dava açıldı. Kabulü gerekir.',
    );
    await tester.tap(
      find.byTooltip('Sesli oku · seçimi ya da imleçten sonrasını'),
    );
    await untilReading(tester);
    // The first sentence, selected, and said in words.
    expect(controller.selection.start, 0);
    expect(controller.selection.end, 'HMK m. 119 uyarınca dava açıldı.'.length);
    expect(
      voice.asked.first,
      "Hukuk Muhakemeleri Kanunu'nun yüz on dokuzuncu maddesi uyarınca dava "
      'açıldı.',
    );
    expect(find.text('Okunuyor · 1 / 2'), findsOneWidget);

    player.finish();
    await tester.pumpAndSettle();
    expect(
      controller.document.toPlainText().substring(
        controller.selection.start,
        controller.selection.end,
      ),
      'Kabulü gerekir.',
    );
    // Pressed again, it stops.
    await tester.tap(find.byTooltip('Okumayı durdur'));
    await tester.pumpAndSettle();
    expect(ReadAloud.instance.state, ReadState.idle);
    await close(tester);
  });

  testWidgets('a selection is read aloud from the right-click menu, and '
      'only it', (tester) async {
    final controller = await openEditor(
      tester,
      'Birinci cümle burada. İkinci cümle burada.',
    );
    controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 21),
      ChangeSource.local,
    );
    await tester.pump();
    await tester.tapAt(
      tester.getTopLeft(find.byType(QuillEditor)) + const Offset(20, 8),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sesli oku'));
    await untilReading(tester);
    expect(voice.asked, ['Birinci cümle burada.']);
    expect(find.text('Okunuyor · 1 / 1'), findsOneWidget);
    player.finish();
    await tester.pumpAndSettle();
    expect(ReadAloud.instance.state, ReadState.idle);
    await close(tester);
  });

  testWidgets('on a wide screen the voice has a group of its own, and every '
      'tool is named', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: EditorWidget(draft: EditorDrafts().draft('new', 'Yeni evrak')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Ses'), findsOneWidget);
    expect(find.text('Sesli oku'), findsOneWidget);
    expect(find.text('Sesli yaz'), findsOneWidget);
    expect(find.text('Yazdır'), findsOneWidget);
    // The tools that are only icons on a narrower screen are named too.
    for (final name in [
      'Kalıp metin',
      'Belge geçmişi',
      'İçtihat ara',
      'Kısayollar',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    // And nothing has been pushed out of sight for it.
    final strip = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(EditorToolbar),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(strip.position.maxScrollExtent, 0);
    await tester.tap(find.text('Sesli yaz'));
    await tester.pumpAndSettle();
    expect(Dictation.instance.state, ListenState.listening);
    await tester.tap(find.text('Bitir'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await close(tester);
  });

  testWidgets('what is said is written where the caret is', (tester) async {
    final controller = await openEditor(tester, 'Sayın Mahkemeye');
    controller.updateSelection(
      const TextSelection.collapsed(offset: 15),
      ChangeSource.local,
    );
    await tester.pump();
    await tester.tap(
      find.byTooltip('Sesli yaz · söylediğiniz imlecin yerine yazılır'),
    );
    await tester.pumpAndSettle();
    expect(Dictation.instance.state, ListenState.listening);
    expect(find.text('Dinleniyor, konuşabilirsiniz'), findsOneWidget);
    ear.say('dava dilekçemizdir.');
    await tester.pumpAndSettle();
    expect(
      controller.document.toPlainText(),
      'Sayın Mahkemeye dava dilekçemizdir.\n',
    );
    expect(controller.selection.baseOffset, 35);
    await tester.tap(find.text('Bitir'));
    // Closing the microphone takes a turn of the real event loop.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(Dictation.instance.state, ListenState.idle);
    expect(microphone.closed, isTrue);
    expect(ear.flushed, isTrue);
    await close(tester);
  });
}

class _Installed extends SpeechModelStore {
  @override
  Future<String?> installed(SpeechModel model) async => '/ses/${model.folder}';
}
