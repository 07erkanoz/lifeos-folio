import 'package:flutter/material.dart';

import '../../services/speech/speech_session.dart';

/// The controls of reading aloud or of dictation, floating over the page
/// that started it for as long as it goes on.
class SpeechBar extends StatelessWidget {
  SpeechBar({
    super.key,
    required this.owner,
    ReadAloud? reading,
    Dictation? dictation,
  }) : reading = reading ?? ReadAloud.instance,
       dictation = dictation ?? Dictation.instance;

  final Object owner;
  final ReadAloud reading;
  final Dictation dictation;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([reading, dictation]),
      builder: (context, _) {
        final Widget? bar;
        if (reading.state != ReadState.idle && reading.owner == owner) {
          bar = _reading(context);
        } else if (dictation.state != ListenState.idle &&
            dictation.owner == owner) {
          bar = _dictation(context);
        } else {
          bar = null;
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: bar ?? const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _pill(BuildContext context, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('speech-bar'),
      elevation: 6,
      color: scheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _reading(BuildContext context) {
    final loading = reading.state == ReadState.loading;
    final paused = reading.state == ReadState.paused;
    return _pill(context, [
      if (loading)
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      else
        const Icon(Icons.record_voice_over_outlined, size: 20),
      const SizedBox(width: 10),
      Text(
        loading
            ? 'Ses hazırlanıyor…'
            : '${paused ? 'Duraklatıldı' : 'Okunuyor'} · '
                  '${reading.index + 1} / ${reading.count}',
      ),
      const SizedBox(width: 6),
      PopupMenuButton<double>(
        tooltip: 'Okuma hızı',
        initialValue: reading.speed,
        onSelected: (v) => reading.speed = v,
        itemBuilder: (_) => [
          for (final v in const [0.8, 0.9, 1.0, 1.1, 1.25, 1.5])
            PopupMenuItem(value: v, child: Text(_speed(v))),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Text(_speed(reading.speed)),
        ),
      ),
      IconButton(
        tooltip: paused ? 'Sürdür' : 'Duraklat',
        onPressed: loading
            ? null
            : paused
            ? reading.resume
            : reading.pause,
        icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
      ),
      IconButton(
        tooltip: 'Okumayı durdur',
        onPressed: reading.stop,
        icon: const Icon(Icons.stop_rounded),
      ),
    ]);
  }

  static String _speed(double v) =>
      '${v.toStringAsFixed(v * 10 == (v * 10).roundToDouble() ? 1 : 2).replaceAll('.', ',')}×';

  Widget _dictation(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loading = dictation.state == ListenState.loading;
    return _pill(context, [
      if (loading)
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      else
        Icon(Icons.mic_rounded, size: 20, color: scheme.error),
      const SizedBox(width: 10),
      Text(
        loading
            ? 'Hazırlanıyor…'
            : dictation.writing
            ? 'Yazıya dökülüyor…'
            : 'Dinleniyor, konuşabilirsiniz',
      ),
      const SizedBox(width: 8),
      TextButton.icon(
        onPressed: dictation.stop,
        icon: const Icon(Icons.stop_rounded, size: 18),
        label: const Text('Bitir'),
      ),
    ]);
  }
}
