import 'package:flutter/foundation.dart';

import 'live_conversation.dart';

/// Folio Ajan's spoken conversation, whichever voice carries it: Codex
/// (the lawyer's ChatGPT subscription, [CodexConversation]) or Gemini Live
/// (a paid API key, [LiveConversation]).
abstract class AjanVoice implements Listenable {
  LiveState get state;
  bool get active;
  String? get error;

  /// What was said, both sides, the latest last.
  List<LiveLine> get lines;

  /// The tools called, the latest last.
  List<String> get steps;

  /// How loud, 0–1, for the orb: the voice speaking, or the microphone.
  ValueListenable<double> get level;

  /// Shown beside the state ("Codex", "Gemini").
  String get label;

  /// [handsFree]: Jarvis mode, the conversation listening on its own.
  Future<void> start({bool handsFree = false});
  Future<void> stop();

  /// A written question or request, answered aloud.
  Future<void> send(String text);
}

/// The lawyer telling Folio Ajan to stop: a short utterance with one of
/// these words ("kapan", "sus", "yeter", "konuşmayı bitir"…). Heard on this
/// computer from the transcript, so the conversation ends at once, without
/// asking the model.
bool isStopCommand(String said) {
  final words = said
      .toLowerCase()
      .replaceAll('İ', 'i')
      .replaceAll(RegExp(r"[^a-zçğıöşü\s]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty || words.length > 5) return false;
  const stops = {
    'kapan',
    'kapat',
    'sus',
    'susun',
    'sussana',
    'yeter',
    'dur',
    'bitir',
    'bitti',
    'görüşürüz',
    'hoşçakal',
  };
  // "kapatabilirsin", "kapatır mısın", "yeterli": the word's root is
  // enough ("Gerek yok, kapatabilirsin" was not heard, 21 Kasım 2026).
  if (words.any(
    (w) =>
        stops.contains(w) ||
        w.startsWith('kapan') ||
        w.startsWith('kapat') ||
        w.startsWith('bitir') ||
        w.startsWith('yeter'),
  )) {
    return true;
  }
  // A thank-you or "gerek yok" alone is an ending too: the conversation
  // costs while it is open.
  const endings = {'teşekkürler', 'teşekkür', 'sağol', 'sağolun', 'eyvallah'};
  if (words.length <= 3 && words.any(endings.contains)) return true;
  return words.length <= 3 && words.contains('gerek') && words.contains('yok');
}
