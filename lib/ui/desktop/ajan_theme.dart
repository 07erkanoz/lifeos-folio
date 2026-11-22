import 'package:flutter/material.dart';

import '../../services/voice/live_conversation.dart';

/// Folio Ajan's colours: the approved mock-up's tokens ("Birleşik"), dark
/// and light, shared by the palette and Jarvis mode.
class AjanColors {
  const AjanColors({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.panel,
    required this.border,
    required this.text,
    required this.muted,
    required this.chip,
    required this.accentText,
    required this.accentFill,
    required this.accentLine,
    required this.select,
    required this.glow,
    required this.ring1,
    required this.ring2,
    required this.redFill,
    required this.redText,
    required this.amberFill,
    required this.amberText,
    required this.pane,
    required this.frame,
    required this.line,
    required this.faint,
    required this.card,
  });

  final bool dark;
  final Color bg, surface, panel, border, text, muted, chip, accentText;
  final Color accentFill, accentLine, select, glow, ring1, ring2;
  final Color redFill, redText, amberFill, amberText, pane, frame;

  /// Chip and key outlines; section labels ("BUGÜN"); the quiet cards
  /// (passages, suggestions).
  final Color line, faint, card;

  static const blue = Color(0xFF2563EB);
  static const red = Color(0xFFE5484D);
  static const amber = Color(0xFFF59E0B);
  static const green = Color(0xFF16A34A);
  static const sky = Color(0xFF7AA7FF);

  static const night = AjanColors(
    dark: true,
    bg: Color(0xFF07090F),
    surface: Color(0xF50D1119),
    panel: Color(0xFF121927),
    border: Color(0xFF1C2432),
    text: Color(0xFFE8ECF4),
    muted: Color(0xFF9AA5B8),
    chip: Color(0xFFC9D0DC),
    accentText: Color(0xFF9DB7FF),
    accentFill: Color.fromRGBO(37, 99, 235, .10),
    accentLine: Color(0xFF23324F),
    select: Color(0xFF1A2232),
    glow: Color.fromRGBO(37, 99, 235, .24),
    ring1: Color.fromRGBO(122, 167, 255, .38),
    ring2: Color.fromRGBO(122, 167, 255, .16),
    redFill: Color.fromRGBO(255, 107, 107, .08),
    redText: Color(0xFFFF9C9C),
    amberFill: Color.fromRGBO(245, 181, 68, .13),
    amberText: Color(0xFFF5C46B),
    pane: Color(0x00000000),
    frame: Color(0xFF263044),
    line: Color(0xFF2A3446),
    faint: Color(0xFF8B95A8),
    card: Color(0xFF121927),
  );

  static const day = AjanColors(
    dark: false,
    bg: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    panel: Color(0xFFF0F2F5),
    border: Color(0xFFE4E7EC),
    text: Color(0xFF111827),
    muted: Color(0xFF5B6472),
    chip: Color(0xFF1E40AF),
    accentText: Color(0xFF1D4ED8),
    accentFill: Color(0xFFEAF1FF),
    accentLine: Color(0xFFBFD3FF),
    select: Color(0xFFEAF1FF),
    glow: Color.fromRGBO(37, 99, 235, .14),
    ring1: Color.fromRGBO(37, 99, 235, .35),
    ring2: Color.fromRGBO(37, 99, 235, .14),
    redFill: Color(0xFFFDECEC),
    redText: Color(0xFF9B1C1C),
    amberFill: Color(0xFFFFFBEB),
    amberText: Color(0xFF92400E),
    pane: Color(0xFFFAFBFC),
    frame: Color(0xFFE4E7EC),
    line: Color(0xFFE4E7EC),
    faint: Color(0xFF6B7280),
    card: Color(0xFFF7F8FA),
  );

  /// The lawyer's choice, or Folio's own theme.
  static AjanColors of(BuildContext context, bool? dark) =>
      (dark ?? Theme.of(context).brightness == Brightness.dark) ? night : day;
}

/// The mock-up's monospace: JetBrains Mono, bundled with Folio (OFL).
const ajanMono = 'JetBrainsMono';

String liveStateLabel(LiveState s) => switch (s) {
  LiveState.off => 'Ses kapalı',
  LiveState.waiting => 'Konuşunca dinlerim',
  LiveState.connecting => 'Bağlanıyor…',
  LiveState.listening => 'Dinliyorum',
  LiveState.thinking => 'Düşünüyorum',
  LiveState.working => 'Folio’ya bakıyorum',
  LiveState.speaking => 'Konuşuyorum',
};

/// The small blue sphere: Folio Ajan's mark.
class AjanDot extends StatelessWidget {
  const AjanDot({super.key, this.size = 28, this.glow = 18});
  final double size, glow;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const RadialGradient(
        center: Alignment(-.2, -.3),
        radius: .75,
        colors: [Color(0xFFA9C6FF), AjanColors.blue, Color(0xFF0B1B3A)],
        stops: [0, .45, 1],
      ),
      boxShadow: [
        BoxShadow(
          color: const Color.fromRGBO(37, 99, 235, .45),
          blurRadius: glow,
        ),
      ],
    ),
  );
}

/// A key, as the mock-up writes it: "Tab", "Esc".
class Kbd extends StatelessWidget {
  const Kbd(this.label, {super.key, required this.colors});
  final String label;
  final AjanColors colors;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: colors.line),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontFamily: ajanMono,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: colors.chip,
      ),
    ),
  );
}

/// A rounded pill button (Jarvis's top bar and answer actions).
class AjanPill extends StatelessWidget {
  const AjanPill(
    this.label, {
    super.key,
    required this.colors,
    required this.onTap,
    this.height = 34,
    this.primary = false,
    this.radius = 999,
  });
  final String label;
  final AjanColors colors;
  final VoidCallback? onTap;
  final double height, radius;
  final bool primary;
  @override
  Widget build(BuildContext context) => Material(
    color: primary ? AjanColors.blue : colors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: primary ? BorderSide.none : BorderSide(color: colors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: height > 40 ? 13 : 12,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
            color: primary ? Colors.white : colors.text,
          ),
        ),
      ),
    ),
  );
}

/// A tool Folio Ajan used, in the mock-up's monospace: "✓ ajanda",
/// "… sure_hesapla".
String toolTrace(String name, {required bool done}) =>
    '${done ? '✓' : '…'} $name';
