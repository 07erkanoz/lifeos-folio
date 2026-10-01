import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/speech/reading_text.dart';
import 'package:evrak_convert/services/speech/speech_engine.dart';
import 'package:evrak_convert/services/speech/speech_models.dart';
import 'package:evrak_convert/services/speech/speech_session.dart';
import 'package:evrak_convert/ui/widgets/speech_bar.dart';
import 'package:evrak_convert/ui/widgets/speech_download_dialog.dart';

/// Says each sentence as its length in samples, and keeps what it was asked.
class FakeVoice implements Voice {
  final asked = <String>[];
  bool disposed = false;
  @override
  Future<SpokenAudio> say(String text, {double speed = 1.0}) async {
    asked.add(text);
    return SpokenAudio(Float32List(text.length), 16000);
  }

  @override
  void dispose() => disposed = true;
}

/// Plays until told the sound is over.
class FakePlayer implements SpeechPlayer {
  final played = <int>[];
  Completer<void>? playing;
  bool? paused;
  @override
  Future<void> play(SpokenAudio audio) {
    played.add(audio.samples.length);
    return (playing = Completer<void>()).future;
  }

  void finish() => playing?.complete();
  @override
  void pause(bool value) => paused = value;
  @override
  Future<void> stop() async {
    if (!(playing?.isCompleted ?? true)) playing!.complete();
  }
}

class FakeEar implements Ear {
  final heard = <double>[];
  final _texts = StreamController<String>.broadcast();
  final _busy = StreamController<bool>.broadcast();
  bool flushed = false;
  String? onFlush;
  void say(String text) => _texts.add(text);
  @override
  Stream<String> get texts => _texts.stream;
  @override
  Stream<bool> get busy => _busy.stream;
  @override
  void feed(Float32List samples) => heard.addAll(samples);
  @override
  Future<void> flush() async {
    flushed = true;
    if (onFlush != null) _texts.add(onFlush!);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  void dispose() {}
}

class FakeMicrophone implements Microphone {
  StreamController<Float32List>? controller;
  int? rate;
  bool closed = false;
  @override
  Future<Stream<Float32List>> open(int sampleRate) async {
    rate = sampleRate;
    closed = false;
    return (controller = StreamController<Float32List>()).stream;
  }

  @override
  Future<void> close() async {
    closed = true;
    await controller?.close();
  }
}

List<ReadingSentence> sentences(List<String> texts) {
  var at = 0;
  return [
    for (final t in texts)
      ReadingSentence(at, at += t.length, t, t.toLowerCase()),
  ];
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('reading aloud', () {
    test(
      'each sentence is said in turn, the next made while one plays',
      () async {
        final voice = FakeVoice();
        final player = FakePlayer();
        final reading = ReadAloud(
          openVoice: (_) async => voice,
          player: player,
        );
        final begun = <String>[];
        final done = reading.read(
          sentences(['Bir.', 'İkinci cümle.', 'Üç.']),
          modelDir: '/ses',
          owner: 'sayfa',
          onSentence: (s) => begun.add(s.text),
        );
        await settle();
        expect(reading.state, ReadState.reading);
        expect(reading.owner, 'sayfa');
        expect(begun, ['Bir.']);
        // What is said is the sentence in words, and the next is on its way.
        expect(voice.asked, ['bir.', 'ikinci cümle.']);
        player.finish();
        await settle();
        expect(begun, ['Bir.', 'İkinci cümle.']);
        expect(reading.index, 1);
        player.finish();
        await settle();
        player.finish();
        await done;
        expect(player.played, [4, 13, 3]);
        expect(reading.state, ReadState.idle);
        expect(reading.owner, isNull);
      },
    );

    test('paused, it waits; resumed, it goes on; stopped, it ends', () async {
      final player = FakePlayer();
      final reading = ReadAloud(
        openVoice: (_) async => FakeVoice(),
        player: player,
      );
      final done = reading.read(
        sentences(['Bir.', 'İki.', 'Üç.']),
        modelDir: '/ses',
      );
      await settle();
      reading.pause();
      expect(reading.state, ReadState.paused);
      expect(player.paused, isTrue);
      player.finish();
      await settle();
      // The next sentence is not started while paused.
      expect(player.played.length, 1);
      reading.resume();
      await settle();
      expect(player.played.length, 2);
      await reading.stop();
      await done;
      expect(reading.state, ReadState.idle);
      expect(player.played.length, 2);
    });

    test('a voice that will not open says why', () async {
      final reading = ReadAloud(
        openVoice: (_) async => throw StateError('bozuk model'),
        player: FakePlayer(),
      );
      await reading.read(sentences(['Bir.']), modelDir: '/ses');
      expect(reading.state, ReadState.idle);
      expect(reading.error, contains('bozuk model'));
    });
  });

  group('dictation', () {
    test('what the microphone hears is written down, and what was still '
        'being said when it stopped', () async {
      final ear = FakeEar();
      final microphone = FakeMicrophone();
      final dictation = Dictation(
        openEar: (_) async => ear,
        microphone: microphone,
      );
      final written = <String>[];
      await dictation.start(
        modelDir: '/ses',
        owner: 'sayfa',
        onText: written.add,
      );
      expect(dictation.state, ListenState.listening);
      expect(microphone.rate, ListenWorker.sampleRate);
      microphone.controller!.add(Float32List.fromList([0.1, 0.2]));
      await settle();
      expect(ear.heard.length, 2);
      ear.say('Sayın Mahkemeye,');
      await settle();
      expect(written, ['Sayın Mahkemeye,']);
      ear.onFlush = 'arz ederiz.';
      await dictation.stop();
      expect(ear.flushed, isTrue);
      expect(microphone.closed, isTrue);
      expect(written, ['Sayın Mahkemeye,', 'arz ederiz.']);
      expect(dictation.state, ListenState.idle);
    });

    test('a microphone that cannot be opened says so', () async {
      final dictation = Dictation(
        openEar: (_) async => FakeEar(),
        microphone: _BrokenMicrophone(),
      );
      await dictation.start(modelDir: '/ses', onText: (_) {});
      expect(dictation.state, ListenState.idle);
      expect(dictation.error, contains('Mikrofon açılamadı'));
    });
  });

  testWidgets('the bar shows the reading to the page that asked for it, and '
      'stops it', (tester) async {
    final player = FakePlayer();
    final reading = ReadAloud(
      openVoice: (_) async => FakeVoice(),
      player: player,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SpeechBar(owner: 'sayfa', reading: reading),
              SpeechBar(owner: 'başka', reading: reading),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('speech-bar')), findsNothing);
    unawaited(
      reading.read(
        sentences(['Bir.', 'İki.']),
        modelDir: '/ses',
        owner: 'sayfa',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('speech-bar')), findsOneWidget);
    expect(find.text('Okunuyor · 1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Duraklat'));
    await tester.pump();
    expect(find.text('Duraklatıldı · 1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Okumayı durdur'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('speech-bar')), findsNothing);
    // The voice is let go of a while after the reading ends.
    await tester.pump(const Duration(minutes: 4));
  });

  group('the download question', () {
    testWidgets('asks, shows the download coming, and hands back the folder', (
      tester,
    ) async {
      final store = _FakeStore();
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await SpeechDownloadDialog.ensure(
                context,
                SpeechModel.reading,
                store: store,
              ),
              child: const Text('oku'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('oku'));
      await tester.pumpAndSettle();
      expect(find.text('Sesli okuma'), findsOneWidget);
      expect(
        find.textContaining(
          'Sesli okuma için ses modelinin indirilmesi gerekiyor (124 MB).',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('OpenRAIL-M'), findsOneWidget);
      expect(store.started, isFalse, reason: 'nothing before it is agreed to');

      await tester.tap(find.byKey(const ValueKey('speech-download')));
      await tester.pump();
      store.progress!(72500000, SpeechModel.reading.size);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('speech-download-progress')),
        findsOneWidget,
      );
      expect(find.text('72,5 MB / 124 MB · %58'), findsOneWidget);
      expect(find.text('İptal'), findsOneWidget);
      store.finish.complete('/ses/okuma');
      await tester.pumpAndSettle();
      expect(result, '/ses/okuma');
      expect(find.text('Sesli okuma'), findsNothing);

      // Once it is here, nothing is asked.
      store.here = '/ses/okuma';
      result = null;
      await tester.tap(find.text('oku'));
      await tester.pumpAndSettle();
      expect(result, '/ses/okuma');
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('declined, nothing is fetched', (tester) async {
      final store = _FakeStore();
      String? result = 'x';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await SpeechDownloadDialog.ensure(
                context,
                SpeechModel.dictation,
                store: store,
              ),
              child: const Text('yaz'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('yaz'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'konuşma tanıma modelinin indirilmesi gerekiyor (608 MB)',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(store.started, isFalse);
    });
  });
}

class _BrokenMicrophone implements Microphone {
  @override
  Future<Stream<Float32List>> open(int sampleRate) async =>
      throw StateError('aygıt yok');
  @override
  Future<void> close() async {}
}

class _FakeStore extends SpeechModelStore {
  String? here;
  bool started = false;
  void Function(int, int)? progress;
  final finish = Completer<String>();

  @override
  Future<String?> installed(SpeechModel model) async => here;

  @override
  Future<String> download(
    SpeechModel model, {
    void Function(int received, int total)? progress,
    DownloadCancel? cancel,
  }) {
    started = true;
    this.progress = progress;
    return finish.future;
  }
}
