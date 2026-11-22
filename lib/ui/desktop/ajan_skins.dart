import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// What Folio Ajan's full screen shows: nothing yet, or one of the voice's
/// moments.
enum AjanMood { idle, listening, speaking, working }

/// The middle figure's state between frames: how loud, how far it has
/// turned.
class AjanMotion {
  double level = 0, spin = 0, t = 0;
  AjanMood mood = AjanMood.idle;

  void step(double t, double frames, AjanMood mood, double sound) {
    this.t = t;
    this.mood = mood;
    final s = sound.clamp(0.0, 1.0);
    final target = switch (mood) {
      AjanMood.idle => .05 + .03 * math.sin(t * .9),
      AjanMood.listening => .08 + .05 * math.sin(t * 1.3) + s * .5,
      AjanMood.speaking => .25 + s * 1.1,
      AjanMood.working => .3,
    };
    level += (target - level) * (1 - math.pow(1 - .18, frames));
    spin +=
        (mood == AjanMood.working ? .035 : .006 + level * .01) *
        frames.toDouble();
  }
}

/// The full screen's looks, the lawyer's choice (22 Kasım 2026); drawn from
/// the mock-ups in artifact 6Gdh8XbGpgbyiSLVfPUTzU.
enum AjanSkin {
  kure('Küre'),
  reaktor('Reaktör'),
  hologram('Hologram'),
  aura('Aura'),
  kehribar('Kehribar');

  const AjanSkin(this.label);
  final String label;

  static AjanSkin of(String id) =>
      values.firstWhere((s) => s.name == id, orElse: () => kure);

  AjanSkinStyle get style => switch (this) {
    kure => AjanSkinStyle.kure,
    reaktor => AjanSkinStyle.reaktor,
    hologram => AjanSkinStyle.hologram,
    aura => AjanSkinStyle.aura,
    kehribar => AjanSkinStyle.kehribar,
  };

  /// The middle figure.
  CustomPainter figure(ValueListenable<double> clock, AjanMotion m) =>
      switch (this) {
        kure => SpherePainter(clock, m),
        reaktor => ReactorPainter(clock, m),
        hologram => GlobePainter(clock, m),
        aura => AuraPainter(clock, m),
        kehribar => RadarPainter(clock, m),
      };

  /// Behind everything: a grid, hexagons, or slow colour clouds.
  CustomPainter? backdrop(ValueListenable<double> clock) => switch (this) {
    kure => null,
    reaktor => GridBackdrop(clock, const Color(0xFF3FE0FF)),
    kehribar => GridBackdrop(clock, const Color(0xFFFFB347)),
    hologram => HexBackdrop(clock),
    aura => CloudBackdrop(clock),
  };
}

/// A look's colours and shapes.
class AjanSkinStyle {
  const AjanSkinStyle({
    required this.ground,
    required this.text,
    required this.bright,
    required this.muted,
    required this.faint,
    required this.soft,
    required this.line,
    required this.frame,
    required this.label,
    required this.accent,
    required this.panel,
    required this.panelLine,
    required this.red,
    required this.amber,
    required this.green,
    required this.sky,
    required this.hot,
    this.radius = 14,
    this.bevel = false,
    this.corners = false,
    this.blur = 0,
    this.headCaps = false,
    this.headTrack = 1.2,
    this.answerWeight = FontWeight.w500,
    this.answerSize = 19,
    this.answerGlow = false,
    this.scan,
    this.mono = false,
  });

  /// The screen's ground, centre to edge.
  final List<Color> ground;
  final Color text, bright, muted, faint, soft, line, frame, label, accent;
  final Color panel, panelLine, red, amber, green, sky, hot;

  /// Panels' corners; [bevel] cuts them instead of rounding.
  final double radius;
  final bool bevel;

  /// Bracket marks on two corners of each panel.
  final bool corners;

  /// Frosted panels: the ground blurred behind them.
  final double blur;

  /// Headings in capitals, spaced.
  final bool headCaps;
  final double headTrack;
  final FontWeight answerWeight;
  final double answerSize;
  final bool answerGlow;

  /// Thin lines over the whole screen, like an old monitor.
  final Color? scan;

  /// Headings and the brand in the mono face.
  final bool mono;

  ShapeBorder shape({double? r, Color? side}) {
    final border = side == null ? BorderSide.none : BorderSide(color: side);
    final rr = r ?? radius;
    return bevel
        ? BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(rr * .7),
            side: border,
          )
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rr),
            side: border,
          );
  }

  static const kure = AjanSkinStyle(
    ground: [Color(0xFF12203D), Color(0xFF0B111C), Color(0xFF07090F)],
    text: Color(0xFFE8ECF4),
    bright: Color(0xFFF2F5FA),
    muted: Color(0xFF9AA5B8),
    faint: Color(0xFF8B95A8),
    soft: Color(0xFFC9D0DC),
    line: Color(0xFF243047),
    frame: Color(0xFF263044),
    label: Color(0xFF8FB0FF),
    accent: Color(0xFF2563EB),
    panel: Color(0x09FFFFFF),
    panelLine: Color(0x0FFFFFFF),
    red: Color(0xFFFF9C9C),
    amber: Color(0xFFF5C46B),
    green: Color(0xFF3DD68C),
    sky: Color(0xFF9DB7FF),
    hot: Color.fromRGBO(255, 107, 107, .08),
  );

  static const reaktor = AjanSkinStyle(
    ground: [Color(0xFF071A24), Color(0xFF030A0F), Color(0xFF010406)],
    text: Color(0xFFDFF8FF),
    bright: Color(0xFFEFFCFF),
    muted: Color(0xFF7FB3C3),
    faint: Color(0xFF6FA3B3),
    soft: Color(0xFFBDEFFB),
    line: Color(0x293FE0FF),
    frame: Color(0x663FE0FF),
    label: Color(0xFF3FE0FF),
    accent: Color(0xFF1FA9C9),
    panel: Color(0xB805161E),
    panelLine: Color(0x383FE0FF),
    red: Color(0xFFFF8D8D),
    amber: Color(0xFFFFCF73),
    green: Color(0xFF3FE0FF),
    sky: Color(0xFF3FE0FF),
    hot: Color.fromRGBO(255, 80, 80, .08),
    radius: 4,
    bevel: true,
    corners: true,
    headCaps: true,
    headTrack: 2,
    answerWeight: FontWeight.w600,
    answerSize: 20,
    answerGlow: true,
    scan: Color(0x073FE0FF),
  );

  static const hologram = AjanSkinStyle(
    ground: [Color(0xFF04211B), Color(0xFF020E0C), Color(0xFF020B0A)],
    text: Color(0xFFD9FFF4),
    bright: Color(0xFFEFFFFA),
    muted: Color(0xFF6DB5A4),
    faint: Color(0xFF5FA898),
    soft: Color(0xFFBFF7E7),
    line: Color(0x262BFFC6),
    frame: Color(0x732BFFC6),
    label: Color(0xFF2BFFC6),
    accent: Color(0xFF12A884),
    panel: Color(0x8C041A16),
    panelLine: Color(0x402BFFC6),
    red: Color(0xFFFF95AD),
    amber: Color(0xFFFFE082),
    green: Color(0xFF2BFFC6),
    sky: Color(0xFF2BFFC6),
    hot: Color.fromRGBO(255, 90, 120, .09),
    radius: 0,
    corners: true,
    blur: 6,
    headCaps: true,
    headTrack: 1.6,
    answerGlow: true,
    scan: Color(0x2E000000),
    mono: true,
  );

  static const aura = AjanSkinStyle(
    ground: [Color(0xFF1A0F2E), Color(0xFF0E0918), Color(0xFF0A0712)],
    text: Color(0xFFF6F1FF),
    bright: Color(0xFFFFFFFF),
    muted: Color(0xFFB4A8CC),
    faint: Color(0xFFA99CC4),
    soft: Color(0xFFE4DAF5),
    line: Color(0x17FFFFFF),
    frame: Color(0x26FFFFFF),
    label: Color(0xFFE9B8FF),
    accent: Color(0xFF8B5CF6),
    panel: Color(0x0DFFFFFF),
    panelLine: Color(0x1AFFFFFF),
    red: Color(0xFFFFB0BD),
    amber: Color(0xFFFFD59A),
    green: Color(0xFF9FF5C9),
    sky: Color(0xFFE9B8FF),
    hot: Color.fromRGBO(255, 120, 140, .1),
    radius: 18,
    blur: 18,
    answerWeight: FontWeight.w400,
    answerSize: 20,
  );

  static const kehribar = AjanSkinStyle(
    ground: [Color(0xFF1A1003), Color(0xFF0B0702), Color(0xFF050301)],
    text: Color(0xFFFFE9C7),
    bright: Color(0xFFFFF3DE),
    muted: Color(0xFFC0975C),
    faint: Color(0xFFB08850),
    soft: Color(0xFFF5D7A8),
    line: Color(0x29FFB347),
    frame: Color(0x73FFB347),
    label: Color(0xFFFFB347),
    accent: Color(0xFFB8741A),
    panel: Color(0xB31C1204),
    panelLine: Color(0x3DFFB347),
    red: Color(0xFFFF9A7A),
    amber: Color(0xFFFFE38A),
    green: Color(0xFFFFB347),
    sky: Color(0xFFFFB347),
    hot: Color.fromRGBO(255, 90, 60, .11),
    radius: 5,
    headCaps: true,
    headTrack: 1.8,
    answerWeight: FontWeight.w600,
    answerSize: 19,
    answerGlow: true,
    scan: Color(0x08FFB347),
  );
}

/// Two bracket marks on a panel's corners (Reaktör, Hologram).
class CornerMarks extends CustomPainter {
  const CornerMarks(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const s = 10.0;
    canvas.drawPath(
      Path()
        ..moveTo(0, s)
        ..lineTo(0, 0)
        ..lineTo(s, 0)
        ..moveTo(size.width - s, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, size.height - s),
      p,
    );
  }

  @override
  bool shouldRepaint(CornerMarks old) => old.color != color;
}

/// Thin horizontal lines over the screen.
class ScanLines extends CustomPainter {
  const ScanLines(this.color, {this.every = 3});
  final Color color;
  final double every;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var y = 0.0; y < size.height; y += every) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(ScanLines old) => old.color != color;
}

// ---- Küre ------------------------------------------------------------------

/// The approved sphere: 720 points on a sphere, turning, swelling with the
/// voice; three glowing ribbons through it.
class SpherePainter extends CustomPainter {
  SpherePainter(this.clock, this.m) : super(repaint: clock);
  final ValueListenable<double> clock;
  final AjanMotion m;

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
      if (mood == AjanMood.working) d += .05 * math.sin(p[1] * 9 + t * 6);
      final px = p[0] * d, py = p[1] * d, pz = p[2] * d;
      final x1 = px * ca + pz * sa, z1 = -px * sa + pz * ca;
      final y2 = py * cb - z1 * sb, z2 = py * sb + z1 * cb;
      final f = 2.8 / (2.8 + z2);
      final depth = (1 - z2) / 2;
      final hue = mood == AjanMood.working
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
  bool shouldRepaint(SpherePainter old) => false;
}

// ---- Reaktör ----------------------------------------------------------------

TextPainter _label(String text, Color color, double size, {String? font}) =>
    TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: font ?? 'JetBrainsMono',
          letterSpacing: size * .08,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

/// Rings inside rings, turning against each other; the voice in bars round
/// a bright core.
class ReactorPainter extends CustomPainter {
  ReactorPainter(this.clock, this.m) : super(repaint: clock);
  final ValueListenable<double> clock;
  final AjanMotion m;

  static const c = Color(0xFF3FE0FF);

  void _ring(
    Canvas canvas,
    Offset o,
    double r,
    double w,
    int segs,
    double gap,
    double rot,
    double alpha,
  ) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = c.withValues(alpha: alpha.clamp(0, 1));
    final step = math.pi * 2 / segs;
    final rect = Rect.fromCircle(center: o, radius: r);
    for (var i = 0; i < segs; i++) {
      canvas.drawArc(rect, rot + i * step, step - gap, false, p);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = m.t, l = m.level, s = m.spin;
    final u = size.width / 440;
    final o = size.center(Offset.zero);
    final working = m.mood == AjanMood.working;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            c.withValues(alpha: (.18 + l * .25).clamp(0, 1)),
            c.withValues(alpha: .04),
            c.withValues(alpha: 0),
          ],
          stops: const [0, .5, 1],
        ).createShader(Rect.fromCircle(center: o, radius: size.width / 2)),
    );

    final tick = Paint()..color = c;
    for (var i = 0; i < 120; i++) {
      final a = i / 120 * math.pi * 2 + s * .2;
      final long = i % 10 == 0;
      tick
        ..strokeWidth = (long ? 2 : 1) * u
        ..color = c.withValues(alpha: long ? .8 : .35);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        o + dir * 200 * u,
        o + dir * (long ? 186 : 193) * u,
        tick,
      );
    }
    _ring(canvas, o, 172 * u, 3 * u, 3, .5, -s * .6, .55);
    _ring(canvas, o, 158 * u, 10 * u, 36, .06, s * .9, .22 + l * .3);
    _ring(canvas, o, 140 * u, 1.5 * u, 1, 0, 0, .35);
    _ring(canvas, o, 124 * u, 6 * u, 8, .28, -s * 1.4, .7);

    final bar = Paint()
      ..strokeWidth = 2.2 * u
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 64; i++) {
      final a = i / 64 * math.pi * 2 - math.pi / 2;
      final v =
          l * (.4 + .6 * math.sin(i * 1.7 + t * 6).abs()) * (working ? .3 : 1);
      final dir = Offset(math.cos(a), math.sin(a));
      bar.color = c.withValues(alpha: (.5 + v * .5).clamp(0, 1));
      canvas.drawLine(o + dir * 96 * u, o + dir * (100 + v * 22) * u, bar);
    }
    _ring(canvas, o, 84 * u, 2 * u, 6, .45, s * 2.2, .9);

    if (working) {
      canvas.drawArc(
        Rect.fromCircle(center: o, radius: 140 * u),
        t * 3,
        .9,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * u
          ..color = c.withValues(alpha: .9)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * u),
      );
    }

    final cr = (46 + l * 14) * u;
    canvas.drawCircle(
      o,
      cr,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: .95),
            const Color(0xFF96F0FF)
                .withValues(alpha: (.7 + l * .3).clamp(0, 1)),
            c.withValues(alpha: 0),
          ],
          stops: const [0, .35, 1],
        ).createShader(Rect.fromCircle(center: o, radius: cr)),
    );
    final tri = Path();
    for (var i = 0; i < 3; i++) {
      final a = -math.pi / 2 + i * math.pi * 2 / 3 + s * .3;
      final p = o + Offset(math.cos(a), math.sin(a)) * 28 * u;
      i == 0 ? tri.moveTo(p.dx, p.dy) : tri.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      tri..close(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * u
        ..color = const Color(0xBFDCFAFF),
    );

    final db = (l * 60 + 18).round().toString().padLeft(2, '0');
    _label(
      'SES $db dB',
      c.withValues(alpha: .75),
      11 * u,
    ).paint(canvas, o + Offset(140 * u, -196 * u));
  }

  @override
  bool shouldRepaint(ReactorPainter old) => false;
}

// ---- Hologram ----------------------------------------------------------------

/// A wire globe turning, lit points on its face, two orbits and a scan.
class GlobePainter extends CustomPainter {
  GlobePainter(this.clock, this.m) : super(repaint: clock);
  final ValueListenable<double> clock;
  final AjanMotion m;

  static const c = Color(0xFF2BFFC6);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = m.t, l = m.level;
    final u = size.width / 440;
    final o = size.center(Offset.zero);
    final r = (120 + l * 12) * u, ay = m.spin * 1.2;
    const tilt = .35;
    (Offset, double) at(double lat, double lon) {
      final x = math.cos(lat) * math.cos(lon + ay);
      final z = math.cos(lat) * math.sin(lon + ay);
      final y = math.sin(lat);
      final y2 = y * math.cos(tilt) - z * math.sin(tilt);
      final z2 = y * math.sin(tilt) + z * math.cos(tilt);
      return (o + Offset(x * r, -y2 * r), z2);
    }

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            c.withValues(alpha: (.12 + l * .2).clamp(0, 1)),
            c.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: o, radius: r * 1.6)),
    );

    final front = Paint()
      ..color = c.withValues(alpha: .7)
      ..strokeWidth = u;
    final back = Paint()
      ..color = c.withValues(alpha: .14)
      ..strokeWidth = u;
    void line(List<(Offset, double)> pts) {
      for (var i = 1; i < pts.length; i++) {
        final z = (pts[i].$2 + pts[i - 1].$2) / 2;
        canvas.drawLine(pts[i - 1].$1, pts[i].$1, z > 0 ? front : back);
      }
    }

    const deg = math.pi / 180;
    for (var la = -75; la <= 75; la += 15) {
      line([for (var lo = 0; lo <= 360; lo += 8) at(la * deg, lo * deg)]);
    }
    for (var lo = 0; lo < 360; lo += 20) {
      line([for (var la = -90; la <= 90; la += 8) at(la * deg, lo * deg)]);
    }

    final lit = Paint()
      ..color = c.withValues(alpha: .95)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 * u);
    for (var i = 0; i < 40; i++) {
      final (p, z) = at(math.sin(i * 12.9) * 1.3, i * 2.4);
      if (z <= 0) continue;
      canvas.drawCircle(p, (1.2 + l * 3 * math.sin(t * 5 + i).abs()) * u, lit);
    }

    for (var k = 0; k < 2; k++) {
      canvas.save();
      canvas.translate(o.dx, o.dy);
      canvas.rotate(k == 1 ? -.5 : .4);
      canvas.scale(1, .28);
      final rr = r * (1.45 + k * .2);
      canvas.drawCircle(
        Offset.zero,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u / .28 * .5
          ..color = c.withValues(alpha: .35),
      );
      final a = t * (k == 1 ? -.9 : .7);
      canvas.drawCircle(
        Offset(math.cos(a) * rr, math.sin(a) * rr),
        4 * u,
        Paint()..color = Colors.white,
      );
      canvas.restore();
    }

    final sy = o.dy + math.sin(t * (m.mood == AjanMood.working ? 2.4 : .8)) * r;
    canvas.drawRect(
      Rect.fromLTWH(o.dx - r * 1.1, sy - 20 * u, r * 2.2, 22 * u),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.withValues(alpha: 0), c.withValues(alpha: .35)],
        ).createShader(Rect.fromLTWH(0, sy - 20 * u, 1, 22 * u)),
    );

    final b = r * 1.35, s = 18 * u;
    final mark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * u
      ..color = c.withValues(alpha: .6);
    for (final (dx, dy) in const [(-1, -1), (1, -1), (-1, 1), (1, 1)]) {
      final corner = o + Offset(dx * b, dy * b);
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy - dy * s)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(corner.dx - dx * s, corner.dy),
        mark,
      );
    }
    _label(
      'AĞ ● CANLI',
      c.withValues(alpha: .7),
      10 * u,
    ).paint(canvas, o + Offset(-b, b + 8 * u));
  }

  @override
  bool shouldRepaint(GlobePainter old) => false;
}

// ---- Aura -------------------------------------------------------------------

/// Three soft colour bodies breathing into each other with the voice.
class AuraPainter extends CustomPainter {
  AuraPainter(this.clock, this.m) : super(repaint: clock);
  final ValueListenable<double> clock;
  final AjanMotion m;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = m.t, l = m.level;
    final u = size.width / 440;
    final o = size.center(Offset.zero);
    final base = 110 + l * 20;

    void body(Color color, double phase, double r, double speed) {
      final path = Path();
      for (var i = 0; i <= 64; i++) {
        final a = i / 64 * math.pi * 2;
        final w =
            1 +
            (.06 + l * .16) * math.sin(a * 3 + t * speed + phase) +
            (.04 + l * .1) * math.sin(a * 5 - t * speed * 1.3 + phase * 2);
        final p = o + Offset(math.cos(a), math.sin(a)) * r * w * u;
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * u)
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: .5),
              color.withValues(alpha: .28),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .7, 1],
          ).createShader(Rect.fromCircle(center: o, radius: r * 1.2 * u)),
      );
    }

    body(const Color(0xFF8B5CF6), 0, base * 1.15, 1.1);
    body(const Color(0xFFEC4899), 2, base, 1.5);
    body(const Color(0xFFFBBF24), 4, base * .7, 2.1);
    canvas.drawCircle(
      o,
      base * .8 * u,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          center: const Alignment(0, -.2),
          colors: [
            const Color(0xFFFFF0FA).withValues(alpha: .35),
            const Color(0x00FFFFFF),
          ],
        ).createShader(Rect.fromCircle(center: o, radius: base * .8 * u)),
    );
    if (m.mood == AjanMood.working) {
      canvas.drawArc(
        Rect.fromCircle(center: o, radius: (base + 46) * u),
        t * 2,
        1.2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2 * u
          ..color = Colors.white.withValues(alpha: .55),
      );
    }
  }

  @override
  bool shouldRepaint(AuraPainter old) => false;
}

// ---- Kehribar -----------------------------------------------------------------

/// A radar sweeping, the voice in bars round its rim.
class RadarPainter extends CustomPainter {
  RadarPainter(this.clock, this.m) : super(repaint: clock);
  final ValueListenable<double> clock;
  final AjanMotion m;

  static const c = Color(0xFFFFB347);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = m.t, l = m.level;
    final u = size.width / 440;
    final o = size.center(Offset.zero);

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u
      ..color = c.withValues(alpha: .25);
    for (var r = 40.0; r <= 160; r += 40) {
      canvas.drawCircle(o, r * u, grid);
    }
    canvas
      ..drawLine(o - Offset(170 * u, 0), o + Offset(170 * u, 0), grid)
      ..drawLine(o - Offset(0, 170 * u), o + Offset(0, 170 * u), grid);

    final a = t * (m.mood == AjanMood.working ? 3 : 1.1);
    // The trail behind the beam, drawn turned so the sweep's angles stay
    // inside one turn.
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.rotate(a % (math.pi * 2));
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: 160 * u),
      -1.0,
      1.0,
      true,
      Paint()
        ..shader = ui.Gradient.sweep(
          Offset.zero,
          [c.withValues(alpha: 0), c.withValues(alpha: .32)],
          null,
          TileMode.clamp,
          math.pi * 2 - 1,
          math.pi * 2,
        ),
    );
    canvas.restore();
    canvas.drawLine(
      o,
      o + Offset(math.cos(a), math.sin(a)) * 160 * u,
      Paint()
        ..strokeWidth = 2 * u
        ..color = c.withValues(alpha: .95)
        ..maskFilter = MaskFilter.blur(BlurStyle.solid, 3 * u),
    );

    for (final (b, r) in const [(.7, 110.0), (2.4, 70.0), (4.1, 135.0)]) {
      final age = ((a - b) % (math.pi * 2) + math.pi * 2) % (math.pi * 2);
      final al = math.max(0.0, 1 - age / 3);
      canvas.drawCircle(
        o + Offset(math.cos(b), math.sin(b)) * r * u,
        (3 + al * 3) * u,
        Paint()..color = c.withValues(alpha: .25 + al * .75),
      );
    }

    final bar = Paint()
      ..strokeWidth = 2.4 * u
      ..strokeCap = StrokeCap.butt;
    for (var i = 0; i < 90; i++) {
      final ang = i / 90 * math.pi * 2;
      final v =
          l *
          (.35 +
              .65 *
                  (math.sin(i * .9 + t * 7) * math.cos(i * .23 - t * 3)).abs());
      final dir = Offset(math.cos(ang), math.sin(ang));
      bar.color = c.withValues(alpha: (.4 + v * .6).clamp(0, 1));
      canvas.drawLine(o + dir * 176 * u, o + dir * (179 + v * 34) * u, bar);
    }

    final cr = (22 + l * 12) * u;
    canvas.drawCircle(
      o,
      cr,
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFFFFF0D2), c.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: o, radius: cr)),
    );
  }

  @override
  bool shouldRepaint(RadarPainter old) => false;
}

// ---- Backdrops ----------------------------------------------------------------

/// A faint square grid from the centre out.
class GridBackdrop extends CustomPainter {
  GridBackdrop(this.clock, this.color);
  final ValueListenable<double> clock;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: .05)
      ..strokeWidth = 1;
    const s = 40.0;
    for (var x = (size.width / 2) % s; x < size.width; x += s) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = (size.height / 2) % s; y < size.height; y += s) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(GridBackdrop old) => old.color != color;
}

/// Hexagons, brightest round the figure.
class HexBackdrop extends CustomPainter {
  HexBackdrop(this.clock);
  final ValueListenable<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    const s = 26.0;
    final hh = s * math.sqrt(3) / 2;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final cx = size.width / 2, cy = size.height * .42;
    var row = 0;
    for (var y = 0.0; y < size.height + s; y += hh, row++) {
      for (
        var x = (row.isOdd ? s * .75 : 0.0);
        x < size.width + s;
        x += s * 1.5
      ) {
        final d =
            math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) /
            (size.width * .6);
        final al = math.max(0.0, .16 - d * .12);
        if (al <= .005) continue;
        p.color = GlobePainter.c.withValues(alpha: al);
        final path = Path();
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          final q = Offset(x + math.cos(a) * s / 2, y + math.sin(a) * s / 2);
          i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(path..close(), p);
      }
    }
  }

  @override
  bool shouldRepaint(HexBackdrop old) => false;
}

/// Slow colour clouds drifting behind frosted panels.
class CloudBackdrop extends CustomPainter {
  CloudBackdrop(this.clock) : super(repaint: clock);
  final ValueListenable<double> clock;

  static const _clouds = [
    (.2, .25, Color(0xFF8B5CF6), .7),
    (.8, .3, Color(0xFFEC4899), .9),
    (.55, .85, Color(0xFFFB923C), .6),
    (.15, .8, Color(0xFF38BDF8), .5),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final w = size.width, h = size.height;
    final r = math.max(w, h) * .45;
    for (final (i, (fx, fy, color, sp)) in _clouds.indexed) {
      final c = Offset(
        w * (fx + .08 * math.sin(t * .2 * sp + i)),
        h * (fy + .08 * math.cos(t * .17 * sp + i * 2)),
      );
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: .22), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(CloudBackdrop old) => false;
}
