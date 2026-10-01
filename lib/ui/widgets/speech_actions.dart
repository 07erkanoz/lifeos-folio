import 'package:flutter/material.dart';

import '../../services/speech/reading_text.dart';
import '../../services/speech/speech_models.dart';
import '../../services/speech/speech_session.dart';
import 'notice.dart';
import 'speech_download_dialog.dart';

/// Who reads in the preview. The preview's button and the viewer's
/// right-click menu are the one reader, so either can stop the other.
final previewSpeech = Object();

/// Reads [text] aloud for [owner]: the model is asked for the first time,
/// then the text is read a sentence at a time. [offset] places the
/// sentences in a larger text, for [onSentence] to find them there.
Future<void> readAloud(
  BuildContext context, {
  required Object owner,
  required Future<String?> Function() text,
  int offset = 0,
  ValueChanged<ReadingSentence>? onSentence,
  String? emptyDetail,
}) async {
  await Dictation.instance.stop();
  if (!context.mounted) return;
  final dir = await SpeechDownloadDialog.ensure(context, SpeechModel.reading);
  if (dir == null || !context.mounted) return;
  final List<ReadingSentence> sentences;
  try {
    final written = await text();
    final reader = await ReadingText.shared();
    sentences = [
      for (final s in reader.sentences(written ?? '')) s.shifted(offset),
    ];
  } catch (e) {
    if (context.mounted) {
      showNotice(
        context,
        'Metin okunamadı',
        detail: '$e',
        kind: NoticeKind.error,
      );
    }
    return;
  }
  if (sentences.isEmpty) {
    if (context.mounted) {
      showNotice(context, 'Okunacak metin yok', detail: emptyDetail);
    }
    return;
  }
  if (!context.mounted) return;
  final reading = ReadAloud.instance;
  await reading.read(
    sentences,
    modelDir: dir,
    owner: owner,
    onSentence: onSentence,
  );
  if (reading.error != null && context.mounted) {
    showNotice(
      context,
      'Sesli okuma durdu',
      detail: reading.error,
      kind: NoticeKind.error,
    );
  }
}
