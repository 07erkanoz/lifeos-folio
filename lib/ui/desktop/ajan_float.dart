import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/voice/folio_ajan.dart';
import '../../services/voice/live_conversation.dart';
import 'ajan_theme.dart';
import 'folio_mark.dart';

/// Whether the small voice window is open in Folio's main window. It lives
/// above the pages (in the window's frame), so moving between pages does
/// not touch it.
final ajanFloatOpen = ValueNotifier<bool>(false);

/// Opens the window and starts talking; closes it and stops.
Future<void> toggleAjanFloat(FolioAjan ajan) async {
  if (ajanFloatOpen.value) {
    ajanFloatOpen.value = false;
    if (ajan.voice.active) await ajan.voice.stop();
    return;
  }
  ajanFloatOpen.value = true;
  await ajan.loadSettings(quick: true);
  if (ajan.settings.on && !ajan.voice.active) {
    await ajan.startVoice(handsFree: true);
  }
}

/// The top bar's button: Folio's mark, "Folio Ajan", and four small bars
/// that move while it talks or listens. Shown only when the voice is on in
/// Settings.
class AjanVoicePill extends StatelessWidget {
  const AjanVoicePill({super.key, required this.ajan});
  final FolioAjan ajan;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([ajan, ajanFloatOpen]),
    builder: (context, _) {
      if (!ajan.available || !ajan.settings.on) return const SizedBox.shrink();
      final c = AjanColors.of(context, null);
      final on = ajanFloatOpen.value;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Tooltip(
          message: on ? 'Konuşmayı bitir' : 'Folio Ajan ile sesli konuş',
          child: Material(
            color: on ? c.accentFill : c.surface,
            shape: StadiumBorder(
              side: BorderSide(color: on ? c.accentLine : c.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => toggleAjanFloat(ajan),
              child: Container(
                height: 28,
                padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FolioMark(size: 20, live: on && ajan.voice.active),
                    const SizedBox(width: 7),
                    Text(
                      'Folio Ajan',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: on ? c.accentText : c.text,
                      ),
                    ),
                    if (on && ajan.voice.active) ...[
                      const SizedBox(width: 7),
                      _Bars(ajan: ajan, count: 4, height: 12, width: 2.5),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The small window: Folio Ajan's last words and a line of sound, in
/// Folio's own colours, at the top right of the window.
class AjanFloat extends StatefulWidget {
  const AjanFloat({super.key, required this.ajan, this.onFull});
  final FolioAjan ajan;

  /// To Folio Ajan's full screen, the conversation going on.
  final VoidCallback? onFull;

  @override
  State<AjanFloat> createState() => _AjanFloatState();
}

class _AjanFloatState extends State<AjanFloat> {
  bool _wasActive = false;
  Timer? _closing;

  FolioAjan get ajan => widget.ajan;

  @override
  void initState() {
    super.initState();
    ajan.addListener(_changed);
  }

  /// The conversation ended by itself ("kapan", or quiet for long): the
  /// window goes a moment later.
  void _changed() {
    final active = ajan.voice.active;
    if (_wasActive && !active && ajanFloatOpen.value) {
      _closing?.cancel();
      _closing = Timer(const Duration(milliseconds: 1500), () {
        if (!ajan.voice.active) ajanFloatOpen.value = false;
      });
    }
    if (active) _closing?.cancel();
    _wasActive = active;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _closing?.cancel();
    ajan.removeListener(_changed);
    super.dispose();
  }

  String get _words {
    final voice = ajan.voice;
    if (voice.error != null) return voice.error!;
    for (final l in voice.lines.reversed) {
      if (l.who == 'ajan' && l.text.trim().isNotEmpty) return l.text.trim();
      if (l.who == 'bilgi' && l.text.trim().isNotEmpty) return l.text.trim();
    }
    return switch (voice.state) {
      LiveState.connecting => 'Bağlanıyor…',
      LiveState.off => 'Konuşma kapalı.',
      _ => 'Dinliyorum. Sorunuzu söyleyin.',
    };
  }

  String get _state => switch (ajan.voice.state) {
    LiveState.speaking => 'konuşuyor',
    LiveState.listening || LiveState.waiting => 'dinliyor',
    LiveState.thinking || LiveState.working => 'bakıyor',
    LiveState.connecting => 'bağlanıyor',
    LiveState.off => 'kapalı',
  };

  void _close() {
    ajanFloatOpen.value = false;
    if (ajan.voice.active) ajan.voice.stop();
  }

  @override
  Widget build(BuildContext context) {
    final c = AjanColors.of(context, null);
    final voice = ajan.voice;
    Widget icon(IconData i, String tip, VoidCallback? onTap) => Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(i, size: 15, color: c.faint),
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: true,
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            color: c.dark ? const Color(0xFF15181E) : Colors.white,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24111827),
                blurRadius: 48,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: c.text,
                height: 1.4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
                    child: Row(
                      children: [
                        FolioMark(
                          size: 24,
                          live: voice.state == LiveState.speaking,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Folio Ajan',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _state,
                          style: TextStyle(fontSize: 12, color: c.faint),
                        ),
                        const Spacer(),
                        if (widget.onFull != null)
                          icon(
                            Icons.open_in_full_rounded,
                            'Folio Ajan tam ekran (konuşma sürer)',
                            widget.onFull,
                          ),
                        icon(Icons.close_rounded, 'Konuşmayı bitir', _close),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: Text(
                          _words,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: voice.error != null
                                ? AjanColors.red
                                : c.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: _Bars(ajan: ajan, count: 28, height: 18, wide: true),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Text(
                      '“kapan” deyin ya da Esc',
                      style: TextStyle(fontSize: 11, color: c.faint),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bars that rise with the voice (the speaker while it talks, the
/// microphone while it listens); still when nothing is heard.
class _Bars extends StatefulWidget {
  const _Bars({
    required this.ajan,
    required this.count,
    required this.height,
    this.width = 0,
    this.wide = false,
  });
  final FolioAjan ajan;
  final int count;
  final double height, width;
  final bool wide;

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> with SingleTickerProviderStateMixin {
  final _t = ValueNotifier<double>(0);
  double _level = 0;
  late final Ticker _ticker = createTicker((d) {
    final target = widget.ajan.voice.active
        ? widget.ajan.voice.level.value.clamp(0.0, 1.0)
        : 0.0;
    _level += (target - _level) * .25;
    _t.value = d.inMicroseconds / 1e6;
  });

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      height: widget.height,
      width: widget.wide ? double.infinity : widget.count * (widget.width + 2),
      child: CustomPaint(painter: _BarsPainter(_t, this)),
    ),
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.t, this.s) : super(repaint: t);
  final ValueNotifier<double> t;
  final _BarsState s;

  @override
  void paint(Canvas canvas, Size size) {
    final n = s.widget.count;
    final gap = s.widget.wide ? 3.0 : 2.0;
    final w = (size.width - gap * (n - 1)) / n;
    final time = t.value;
    final level = s._level;
    final shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF8FD6BF), AjanColors.blue],
    ).createShader(Offset.zero & size);
    final paint = Paint()..shader = shader;
    for (var i = 0; i < n; i++) {
      // Each bar its own pace, as the mock-up's: never all in step.
      final wobble =
          .5 + .5 * math.sin(time * (5 + (i * 37 % 9) * .9) + i * 1.7);
      final h = size.height * (.2 + .8 * (.15 + .85 * level) * wobble);
      final x = i * (w + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, w, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => false;
}
