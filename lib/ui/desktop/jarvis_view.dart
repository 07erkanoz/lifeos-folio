import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/voice/folio_ajan.dart';
import '../../services/voice/live_conversation.dart';
import 'ajan_theme.dart';
import 'folio_mark.dart';

export 'ajan_theme.dart' show liveStateLabel;

const _days = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];
const _short = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
const _months = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// The approved mock-up's colours for this screen (always dark).
class _K {
  static const text = Color(0xFFE8ECF4);
  static const bright = Color(0xFFF2F5FA);
  static const muted = Color(0xFF9AA5B8);
  static const faint = Color(0xFF8B95A8);
  static const soft = Color(0xFFC9D0DC);
  static const line = Color(0xFF243047);
  static const frame = Color(0xFF263044);
  static const label = Color(0xFF8FB0FF);
  static const red = Color(0xFFFF9C9C);
  static const amber = Color(0xFFF5C46B);
  static const green = Color(0xFF3DD68C);
  static const sky = Color(0xFF9DB7FF);
}

/// What the screen shows: nothing yet, or one of the voice's moments.
enum _Mood { idle, listening, speaking, working }

/// Folio Ajan's full screen, as the approved mock-up draws it: the light
/// sphere in the middle (large while nothing is said, settling up when the
/// words come), the caption under it, the day at the left, what came in at
/// the right; spoken to without a button when the voice is on.
class JarvisView extends StatefulWidget {
  const JarvisView({
    super.key,
    required this.ajan,
    required this.onMinimize,
    required this.onMain,
    required this.onClose,
  });

  final FolioAjan ajan;
  final VoidCallback onMinimize, onMain, onClose;

  @override
  State<JarvisView> createState() => _JarvisViewState();
}

class _JarvisViewState extends State<JarvisView>
    with SingleTickerProviderStateMixin {
  /// Seconds since shown; the sphere runs on it.
  final _clock = ValueNotifier<double>(0);
  final _motion = _Motion();
  late final Ticker _ticker = createTicker(_tick);
  late final Timer _minute;
  final _text = TextEditingController();
  final _focus = FocusNode();
  double _last = 0;

  FolioAjan get ajan => widget.ajan;

  @override
  void initState() {
    super.initState();
    ajan.addListener(_changed);
    ajan.enterJarvis();
    _minute = Timer.periodic(const Duration(seconds: 20), (_) => _changed());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _ticker.isActive) _ticker.stop();
    if (!still && !_ticker.isActive) _ticker.start();
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final dt = (t - _last).clamp(0.0, .1);
    _last = t;
    _motion.step(t, dt * 60, _mood, ajan.voice.level.value);
    _clock.value = t;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ajan.removeListener(_changed);
    ajan.leaveJarvis();
    _minute.cancel();
    _ticker.dispose();
    _clock.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Spoken when the voice is on, written otherwise.
  void _ask(String text) {
    text = text.trim();
    if (text.isEmpty) return;
    if (ajan.settings.on && ajan.voice.active) {
      ajan.voice.send(text);
    } else {
      ajan.ask(text);
    }
  }

  void _send() {
    final t = _text.text;
    _text.clear();
    _ask(t);
  }

  bool get _spoken => ajan.voice.lines.isNotEmpty;

  String get _heard {
    if (_spoken) {
      for (final l in ajan.voice.lines.reversed) {
        if (l.who == 'avukat' && l.text.trim().isNotEmpty) return l.text.trim();
      }
      return '';
    }
    return ajan.question;
  }

  String get _answer {
    if (_spoken) {
      for (final l in ajan.voice.lines.reversed) {
        if (l.who == 'avukat') break;
        if (l.who == 'ajan' && l.text.trim().isNotEmpty) return l.text.trim();
      }
      return '';
    }
    return ajan.answer;
  }

  bool get _working =>
      ajan.asking ||
      ajan.voice.state == LiveState.working ||
      ajan.voice.state == LiveState.thinking;

  _Mood get _mood {
    if (_working) return _Mood.working;
    return switch (ajan.voice.state) {
      LiveState.speaking => _Mood.speaking,
      LiveState.listening || LiveState.waiting => _Mood.listening,
      _ => _Mood.idle,
    };
  }

  /// Words on the screen: then the sphere makes room for them.
  bool get _talking =>
      _heard.isNotEmpty ||
      _answer.isNotEmpty ||
      ajan.voice.error != null ||
      ajan.askError != null;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 1100;
    final side = wide ? 360.0 : 24.0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onMinimize,
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true):
            widget.onMinimize,
      },
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(
            bodyColor: _K.text,
            displayColor: _K.text,
            fontFamily: 'Inter',
          ),
        ),
        child: Material(
          color: const Color(0xFF07090F),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: _K.text,
              fontSize: 13,
              height: 1.4,
              fontFamily: 'Inter',
            ),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -.2),
                        radius: .62,
                        colors: [
                          Color(0xFF12203D),
                          Color(0xFF0B111C),
                          Color(0xFF07090F),
                        ],
                        stops: [0, .55, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(left: 0, right: 0, top: 0, child: _header()),
                if (wide) ...[
                  Positioned(
                    left: 28,
                    top: 96,
                    width: 300,
                    bottom: 24,
                    child: _left(),
                  ),
                  Positioned(
                    right: 28,
                    top: 96,
                    width: 300,
                    bottom: 24,
                    child: _right(),
                  ),
                ],
                Positioned(
                  left: side,
                  right: side,
                  top: 72,
                  bottom: 150,
                  child: _middle(),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 36,
                  child: Center(
                    child: SizedBox(
                      width: math.min(720, size.width - 48),
                      child: _bottom(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(String label, VoidCallback? onTap, {String? tip}) {
    final button = Material(
      color: const Color(0x08FFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: const BorderSide(color: _K.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _K.soft,
            ),
          ),
        ),
      ),
    );
    return tip == null ? button : Tooltip(message: tip, child: button);
  }

  Widget _iconButton(IconData icon, String tip, VoidCallback onTap) => Tooltip(
    message: tip,
    child: Material(
      color: const Color(0x0DFFFFFF),
      borderRadius: BorderRadius.circular(9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 16, color: _K.soft),
        ),
      ),
    ),
  );

  Widget _header() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final voiceOn = ajan.settings.on;
    final (pillFill, pillInk, dot, word) = switch (_mood) {
      _ when !voiceOn => (
        const Color(0x0FFFFFFF),
        _K.muted,
        _K.faint,
        'Ses kapalı',
      ),
      _Mood.speaking => (
        const Color.fromRGBO(61, 214, 140, .12),
        const Color(0xFF7EE2B0),
        _K.green,
        'Konuşuyor',
      ),
      _Mood.listening => (
        const Color.fromRGBO(37, 99, 235, .16),
        _K.sky,
        const Color(0xFF4F86FF),
        'Dinliyor',
      ),
      _Mood.working => (
        const Color.fromRGBO(245, 181, 68, .13),
        _K.amber,
        _K.amber,
        'Araçlara bakıyor',
      ),
      _Mood.idle => (const Color(0x0FFFFFFF), _K.muted, _K.faint, 'Hazır'),
    };
    final voiceName = identical(ajan.voice, ajan.codex)
        ? ajan.settings.codexVoice
        : ajan.settings.voice;
    final voiceText = voiceOn
        ? 'Ses: ${ajan.voice.label}'
              '${voiceName.isEmpty ? '' : ' · ${voiceName[0].toUpperCase()}${voiceName.substring(1)}'}'
        : 'Ses kapalı';
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x0DFFFFFF))),
      ),
      child: Row(
        children: [
          FolioMark(size: 26, live: _mood == _Mood.speaking),
          const SizedBox(width: 14),
          const Text(
            'Folio Ajan',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -.1,
            ),
          ),
          const SizedBox(width: 14),
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: pillFill,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dot,
                    boxShadow: [BoxShadow(color: dot, blurRadius: 8)],
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  word,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: pillInk,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _button(
            voiceText,
            voiceOn ? ajan.toggleTalk : null,
            tip: voiceOn
                ? (ajan.voice.active ? 'Konuşmayı bitir' : 'Konuşmayı başlat')
                : 'Sesi açmak için: Ayarlar › Hızlı arama',
          ),
          if (voiceOn && identical(ajan.voice, ajan.codex)) ...[
            const SizedBox(width: 14),
            _button(
              'Düşünme: ${ajan.effortLabel}',
              ajan.nextEffort,
              tip:
                  'Codex’in düşünmesi: arttıkça cevap gecikir, kota daha çok '
                  'harcanır. Kaydedilir; sonraki konuşmada geçerli olur.',
            ),
            // Only where Claude is there to hand work to.
            if (ajan.claude != null) ...[
              const SizedBox(width: 14),
              _button(
                'Ağır işler: ${ajan.heavyLabel}',
                ajan.toggleHandOn,
                tip:
                    'Taslak, uzun inceleme ve emsal araştırması kimde: '
                    'Claude’da ya da Codex’in kendisinde. Kısa sorular her '
                    'zaman Codex’te. Kaydedilir.',
              ),
            ],
          ],
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 18),
            color: _K.line,
          ),
          Text(
            '${_short[now.weekday - 1]} ${two(now.day)}.${two(now.month)}.'
            '${now.year} · ${two(now.hour)}:${two(now.minute)}',
            style: const TextStyle(
              fontFamily: ajanMono,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _K.muted,
            ),
          ),
          const SizedBox(width: 14),
          _iconButton(
            Icons.close_fullscreen_rounded,
            'Küçült, hızlı panele dön (Esc)',
            widget.onMinimize,
          ),
          const SizedBox(width: 14),
          _iconButton(Icons.close_rounded, 'Kapat', widget.onClose),
        ],
      ),
    );
  }

  Widget _heading(String text, String note) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: _K.faint,
          ),
        ),
        const Spacer(),
        Text(note, style: const TextStyle(fontSize: 12, color: _K.faint)),
      ],
    ),
  );

  Widget _box(List<Widget> rows) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: const Color(0x09FFFFFF),
      border: Border.all(color: const Color(0x0FFFFFFF)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(children: rows),
  );

  Widget _quiet(String text) => Padding(
    padding: const EdgeInsets.all(10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: const TextStyle(color: _K.muted)),
    ),
  );

  Widget _tag(String text, Color fill, Color ink) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      maxLines: 1,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink),
    ),
  );

  Widget _mono(String text, {bool dim = false}) => SizedBox(
    width: 44,
    child: Text(
      text,
      style: TextStyle(
        fontFamily: ajanMono,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: dim ? _K.muted : _K.soft,
      ),
    ),
  );

  Widget _row(
    Widget lead,
    String title,
    String sub, {
    bool hot = false,
    bool past = false,
    bool strong = false,
    String? ask,
  }) => Opacity(
    opacity: past ? .6 : 1,
    child: Material(
      color: hot
          ? const Color.fromRGBO(255, 107, 107, .08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: ask == null ? null : () => _ask(ask),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              lead,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: title),
                          if (past)
                            const WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: _Passed(),
                            ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: _K.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String _dayName(int days) =>
      _short[DateTime.now().add(Duration(days: days)).weekday - 1];

  Widget _deadlineTag(BriefItem d) {
    final days = d.days;
    if (days == null) return _mono(d.when);
    if (days <= 0) {
      return _tag(
        days < 0 ? 'Geçti' : 'Bugün',
        const Color.fromRGBO(255, 107, 107, .14),
        _K.red,
      );
    }
    return _tag(
      '$days gün',
      const Color.fromRGBO(245, 181, 68, .13),
      days <= 3 ? _K.amber : _K.soft,
    );
  }

  Widget _left() {
    final brief = ajan.brief;
    final now = DateTime.now();
    final hearings = brief?.hearings ?? const <BriefItem>[];
    final deadlines = brief?.deadlines ?? const <BriefItem>[];
    final todayRows = <Widget>[
      for (final d in deadlines.where((d) => (d.days ?? 1) <= 0))
        _row(
          _deadlineTag(d),
          d.title,
          d.detail,
          hot: true,
          strong: true,
          ask: 'Şu süreyi anlat: ${d.title} ${d.detail}',
        ),
      for (final h in hearings.where((h) => h.days == 0))
        _row(
          _mono(h.clock.isEmpty ? 'Bugün' : h.clock),
          h.detail,
          h.title,
          ask: 'Şu duruşma hakkında bilgi ver: ${h.title} ${h.when}',
        ),
    ];
    final week = <(int, Widget)>[
      for (final h in hearings.where((h) => h.days != 0))
        (
          h.days ?? 99,
          _row(
            _mono(
              h.days == null
                  ? h.when
                  : '${_dayName(h.days!)}\n${h.clock.isEmpty ? '' : h.clock}',
              dim: (h.days ?? 0) < 0,
            ),
            h.detail,
            h.title,
            past: (h.days ?? 0) < 0,
            ask: 'Şu duruşma hakkında bilgi ver: ${h.title} ${h.when}',
          ),
        ),
      for (final d in deadlines.where((d) => (d.days ?? 1) > 0))
        (
          d.days ?? 99,
          _row(
            _deadlineTag(d),
            d.title,
            [
              d.detail,
              if (d.when.isNotEmpty) 'son gün ${d.when}',
            ].where((s) => s.isNotEmpty).join(' · '),
            ask: 'Şu süreyi anlat: ${d.title} ${d.detail}',
          ),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final weekHearings = hearings.where((h) => h.days != 0).length;
    final weekDeadlines = deadlines.where((d) => (d.days ?? 1) > 0).length;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            'BUGÜN',
            '${now.day} ${_months[now.month - 1]} ${_days[now.weekday - 1]}',
          ),
          _box(
            brief == null
                ? [_quiet(ajan.briefLoading ? 'Okunuyor…' : 'Brifing yok')]
                : todayRows.isEmpty
                ? [_quiet('Bugün için kayıtlı bir şey yok')]
                : todayRows,
          ),
          const SizedBox(height: 20),
          _heading('BU HAFTA', '$weekHearings duruşma · $weekDeadlines süre'),
          _box(
            week.isEmpty
                ? [_quiet('Bu hafta başka kayıt yok')]
                : [for (final w in week.take(6)) w.$2],
          ),
        ],
      ),
    );
  }

  Widget _right() {
    final brief = ajan.brief;
    final incoming = brief?.incoming ?? const <BriefItem>[];
    final tasks = brief?.tasks ?? const <BriefItem>[];
    Widget icon(IconData i, Color fill, Color ink) => Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(i, size: 15, color: ink),
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('YENİ GELENLER', '${incoming.length} okunmadı'),
          _box(
            incoming.isEmpty
                ? [_quiet(brief == null ? '' : 'Okunmamış yok')]
                : [
                    for (final n in incoming.take(5))
                      _row(
                        n.title.startsWith('Tebligat')
                            ? icon(
                                Icons.mail_outline_rounded,
                                const Color.fromRGBO(76, 125, 255, .14),
                                _K.sky,
                              )
                            : icon(
                                Icons.notifications_none_rounded,
                                const Color.fromRGBO(245, 181, 68, .13),
                                _K.amber,
                              ),
                        n.title,
                        [
                          n.detail,
                          n.when,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        ask: 'Şunu kısaca özetle: ${n.title} ${n.detail}',
                      ),
                  ],
          ),
          const SizedBox(height: 20),
          _heading('GÖREVLER', '${tasks.length} açık'),
          _box(
            tasks.isEmpty
                ? [_quiet(brief == null ? '' : 'Açık görev yok')]
                : [
                    for (final t in tasks.take(6))
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                border: Border.all(color: _K.faint),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                t.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  String get _moodLabel {
    if (!ajan.settings.on && !ajan.asking) return 'SES KAPALI';
    if (ajan.voice.state == LiveState.connecting) return 'BAĞLANIYOR';
    return switch (_mood) {
      _Mood.idle => 'HAZIR',
      _Mood.listening => 'DİNLİYOR',
      _Mood.speaking => 'KONUŞUYOR',
      _Mood.working => 'ARAÇLARA BAKIYOR',
    };
  }

  /// The sphere, the tools, the caption.
  Widget _middle() {
    final talking = _talking;
    final voice = ajan.voice;
    final steps = _spoken || voice.active ? voice.steps : ajan.steps;
    final shown = steps.length > 3 ? steps.sublist(steps.length - 3) : steps;
    final error = ajan.voice.error ?? ajan.askError;
    final answer = _answer;
    const curve = Cubic(.2, .8, .2, 1);
    const move = Duration(milliseconds: 700);
    Widget fade(Widget child, int delay) => AnimatedOpacity(
      opacity: talking ? 1 : 0,
      duration: Duration(milliseconds: 500 + delay),
      curve: Interval(delay / (500 + delay), 1),
      child: child,
    );
    return LayoutBuilder(
      builder: (context, box) {
        // Large while nothing is said; settled at the top when words come.
        final big = math.min(520.0, box.maxHeight - 90);
        final sphere = talking ? math.min(320.0, big) : big;
        return Column(
          children: [
            AnimatedContainer(
              duration: move,
              curve: curve,
              margin: EdgeInsets.only(top: talking ? 0 : 40),
              width: sphere,
              height: sphere,
              child: Semantics(
                button: true,
                label: ajan.settings.on
                    ? (voice.active ? 'Dinlemeyi durdur' : 'Dinlemeye başla')
                    : 'Ses kapalı',
                child: MouseRegion(
                  cursor: ajan.settings.on
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: GestureDetector(
                    onTap: ajan.settings.on ? ajan.toggleTalk : null,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _Sphere(_clock, _motion),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Text(
              _moodLabel,
              style: const TextStyle(
                fontFamily: ajanMono,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
                color: _K.label,
              ),
            ),
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 6),
              fade(
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final (i, s) in shown.indexed)
                      _chip(s, done: !_working || i < shown.length - 1),
                  ],
                ),
                300,
              ),
            ],
            const SizedBox(height: 20),
            if (_heard.isNotEmpty)
              fade(
                Text(
                  '“$_heard”',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: _K.muted),
                ),
                350,
              ),
            const SizedBox(height: 8),
            Expanded(
              child: fade(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      error ?? (answer.isEmpty && _working ? '…' : answer),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 19,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -.2,
                        color: error != null ? _K.red : _K.bright,
                      ),
                    ),
                  ),
                ),
                400,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _chip(String name, {required bool done}) => Container(
    height: 26,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: const Color(0x0DFFFFFF),
      border: Border.all(color: const Color(0x0FFFFFFF)),
      borderRadius: BorderRadius.circular(999),
    ),

    child: Align(
      widthFactor: 1,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: done ? '✓ ' : '… ',
              style: TextStyle(color: done ? _K.green : _K.label),
            ),
            TextSpan(text: name),
          ],
        ),
        style: const TextStyle(
          fontFamily: ajanMono,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: _K.muted,
        ),
      ),
    ),
  );

  Widget _suggestion(String label, VoidCallback onTap) => Material(
    color: const Color(0x08FFFFFF),
    shape: const StadiumBorder(side: BorderSide(color: _K.line)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 13),

        child: Align(
          widthFactor: 1,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: _K.soft,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _bottom() {
    final voiceOn = ajan.settings.on;
    final talking = ajan.voice.active;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (voiceOn && ajan.brief != null)
              _suggestion('Brifingi sesli oku', ajan.speakBrief)
            else
              _suggestion(
                'Bugün neler var?',
                () => _ask('Bugün neler var, önce acil olanı söyle.'),
              ),
            _suggestion(
              'Bu haftanın süreleri',
              () => _ask('Bu hafta dolan sürelerim neler?'),
            ),
            _suggestion(
              'Yeni tebligatlar',
              () => _ask(
                'Okunmamış tebligatlarımı ve UYAP bildirimlerimi kısaca özetle.',
              ),
            ),
            _suggestion('Brifingi yenile', ajan.loadBrief),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 56,
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
          decoration: BoxDecoration(
            color: const Color(0x0DFFFFFF),
            border: Border.all(color: _K.frame),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x59000000),
                blurRadius: 60,
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  onSubmitted: (_) => _send(),
                  style: const TextStyle(fontSize: 16, color: _K.bright),
                  cursorColor: AjanColors.blue,
                  decoration: const InputDecoration(
                    hintText: 'Yazın ya da konuşun…',
                    hintStyle: TextStyle(color: Color(0xFF7D879A)),
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                !voiceOn
                    ? 'Ses kapalı · Esc küçültür'
                    : talking
                    ? '“kapan” deyin ya da Esc'
                    : 'Mikrofona dokunun ya da Esc',
                style: const TextStyle(fontSize: 12, color: _K.faint),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: !voiceOn
                    ? 'Ses kapalı: Ayarlar › Hızlı arama'
                    : talking
                    ? 'Konuşmayı bitir'
                    : 'Konuşmayı başlat',
                child: Material(
                  color: voiceOn ? AjanColors.blue : const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: voiceOn ? ajan.toggleTalk : null,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        talking
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_none_rounded,
                        size: 18,
                        color: voiceOn ? Colors.white : _K.faint,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "geçti", the small outlined tag after a past hearing.
class _Passed extends StatelessWidget {
  const _Passed();
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFF2A3446)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: const Text(
      'geçti',
      style: TextStyle(fontSize: 11, color: _K.muted, height: 1.3),
    ),
  );
}

/// The sphere's state between frames: how loud, how far it has turned.
class _Motion {
  double level = 0, spin = 0, t = 0;
  _Mood mood = _Mood.idle;

  void step(double t, double frames, _Mood mood, double sound) {
    this.t = t;
    this.mood = mood;
    final s = sound.clamp(0.0, 1.0);
    final target = switch (mood) {
      _Mood.idle => .05 + .03 * math.sin(t * .9),
      _Mood.listening => .08 + .05 * math.sin(t * 1.3) + s * .5,
      _Mood.speaking => .25 + s * 1.1,
      _Mood.working => .3,
    };
    level += (target - level) * (1 - math.pow(1 - .18, frames));
    spin +=
        (mood == _Mood.working ? .035 : .006 + level * .01) * frames.toDouble();
  }
}

/// The approved sphere: 720 points on a sphere, turning, swelling with the
/// voice; three glowing ribbons through it.
class _Sphere extends CustomPainter {
  _Sphere(this.clock, this.m) : super(repaint: clock);
  final ValueListenable<double> clock;
  final _Motion m;

  static final List<List<double>> _points = () {
    const n = 720;
    final g = math.pi * (3 - math.sqrt(5));
    return [
      for (var i = 0; i < n; i++)
        () {
          final y = 1 - (i / (n - 1)) * 2;
          final r = math.sqrt(1 - y * y);
          final th = g * i;
          return [math.cos(th) * r, y, math.sin(th) * r];
        }(),
    ];
  }();

  static const _ribbons = [
    (Color(0xFF4F86FF), .021, 2.4, 0.0, 1.0),
    (Color(0xFF5FE1FF), .017, -1.8, 2.0, .8),
    (Color(0xFF9B8CFF), .026, 3.1, 4.0, .6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = m.t, l = m.level, mood = m.mood;
    final k = size.width / 380;
    final cx = size.width / 2, cy = size.height / 2;
    final r = (104 + l * 10) * k;
    final center = Offset(cx, cy);

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.fromRGBO(70, 120, 255, (.30 + l * .35).clamp(0, 1)),
            Color.fromRGBO(40, 80, 200, (.10 + l * .12).clamp(0, 1)),
            const Color.fromRGBO(10, 20, 60, 0),
          ],
          stops: const [0, .45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: 190 * k)),
    );

    final ay = m.spin, ax = .42 + math.sin(t * .3) * .12;
    final sa = math.sin(ay), ca = math.cos(ay);
    final sb = math.sin(ax), cb = math.cos(ax);
    final dot = Paint()..blendMode = BlendMode.plus;
    for (final p in _points) {
      var d =
          1 +
          l *
              .22 *
              math.sin(3.1 * p[0] + t * 2.3) *
              math.cos(2.4 * p[1] - t * 1.9) +
          l * .08 * math.sin(6 * p[2] + t * 4.1);
      if (mood == _Mood.working) d += .05 * math.sin(p[1] * 9 + t * 6);
      final px = p[0] * d, py = p[1] * d, pz = p[2] * d;
      final x1 = px * ca + pz * sa, z1 = -px * sa + pz * ca;
      final y2 = py * cb - z1 * sb, z2 = py * sb + z1 * cb;
      final f = 2.8 / (2.8 + z2);
      final depth = (1 - z2) / 2;
      final hue = mood == _Mood.working
          ? 205 + depth * 30
          : 215 + (1 - depth) * 25 - l * 25;
      dot.color = HSLColor.fromAHSL(
        (.12 + depth * .75).clamp(0.0, 1.0),
        hue.clamp(0.0, 360.0),
        .95,
        ((62 + depth * 20) / 100).clamp(0.0, 1.0),
      ).toColor();
      canvas.drawCircle(
        Offset(cx + x1 * r * f, cy + y2 * r * f),
        (.6 + depth * 1.5) * f * k,
        dot,
      );
    }

    for (final (color, freq, speed, phase, amp) in _ribbons) {
      final path = Path();
      for (var i = -150; i <= 150; i += 3) {
        final env = math.pow(1 - (i / 150) * (i / 150), 2);
        final y =
            cy +
            math.sin(i * freq + t * speed + phase) *
                (8 + l * 70) *
                k *
                amp *
                env;
        if (i == -150) {
          path.moveTo(cx + i * k, y);
        } else {
          path.lineTo(cx + i * k, y);
        }
      }
      final width = (2 + l * 2.5) * k;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..blendMode = BlendMode.plus
          ..color = color.withValues(alpha: .9)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 * k),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus
          ..color = color.withValues(alpha: (.25 + l * .6).clamp(0, 1)),
      );
    }
  }

  @override
  bool shouldRepaint(_Sphere old) => false;
}
