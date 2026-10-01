import 'dart:math' as math;

/// How text sits against a tab stop.
///
/// Across 1007 documents in a working archive 7338 stops were left and 1801
/// centre, and nothing else. The rest are parsed because the format allows
/// them and a stop in the right place beats ignoring it.
enum TabAlign {
  left,
  right,
  centre,
  decimal,
  bar;

  /// UDF writes Swing's own `TabStop` constants: 1 right, 2 centre, 4 decimal
  /// and 5 bar. There is no 3; anything unknown is a left stop, as it is to
  /// Swing.
  static TabAlign fromCode(String? code) => switch (code) {
    '1' => TabAlign.right,
    '2' => TabAlign.centre,
    '4' => TabAlign.decimal,
    '5' => TabAlign.bar,
    _ => TabAlign.left,
  };
}

/// One stop, in points from where the paragraph's tabs are counted.
class TabStop {
  const TabStop(this.position, [this.align = TabAlign.left]);
  final double position;
  final TabAlign align;

  @override
  bool operator ==(Object other) =>
      other is TabStop && other.position == position && other.align == align;

  @override
  int get hashCode => Object.hash(position, align);

  @override
  String toString() => '${position}pt ${align.name}';
}

/// Whose rules a document's tabs follow.
///
/// A UDF is laid out by UYAP, a DOCX by Word, and they disagree on what a tab
/// does once the paragraph's own stops run out.
enum TabRules {
  /// Counted from the left indent; past the last stop a tab moves five
  /// points; with no stops at all there is one every 72 points.
  uyap,

  /// Counted from the margin; past the last stop, and with none, the
  /// document's default stops carry on at their interval.
  word,
}

/// Where a tab lands on a line.
///
/// A tab is not a wide space. It moves to the next stop, which is what lets a
/// filing line up a column of values after labels of different lengths — the
/// pattern every UYAP tutanak is built from:
///
/// ```
/// Arabuluculuk Bürosu<TAB>:SERİK Adliyesi
/// Adı ve Soyadı<TAB><TAB>: Av. Çiğdem Öz
/// ```
///
/// Drawn as single spaces, which is all Flutter does with a tab on its own,
/// the colons scatter and the document stops looking like the original.
///
/// The rules below were read off UYAP itself: its editor was run on documents
/// built to test each one, and asked where it had put every character
/// (`nextTabStop` in its paragraph view is Swing's, with one change).
class TabStops {
  const TabStops({
    this.stops = const [],
    this.interval = defaultInterval,
    this.rules = TabRules.uyap,
    this.declared = false,
  });

  /// Spacing of the stops a paragraph with no TabSet of its own gets, which is
  /// most of them. Swing's, and so UYAP's: `((int) x / 72 + 1) * 72`.
  static const defaultInterval = 72.0;

  /// How far UYAP moves a tab that has run past the paragraph's last stop.
  /// Not a stop at all: `x + 5`, whatever the font.
  static const uyapPastLast = 5.0;

  /// Explicit stops, ascending.
  final List<TabStop> stops;

  /// Spacing of the implied stops: UYAP's 72 points, or a Word document's
  /// default tab stop.
  final double interval;

  final TabRules rules;

  /// The paragraph names a tab set, if an empty one: then UYAP has no
  /// implied stops either, and every tab moves as one past the last stop.
  final bool declared;

  /// The x a tab that starts at [x] ends at, both counted from where the
  /// paragraph's tabs are measured.
  ///
  /// [following] measures the text after the tab up to the next tab or the
  /// end of the paragraph, which a right or centre stop lines up against;
  /// [toDecimal] measures it up to the first full stop, for a decimal stop.
  /// [space] is a space in the tab's font.
  double end(
    double x, {
    double Function()? following,
    double Function()? toDecimal,
    double space = 3,
  }) => switch (rules) {
    TabRules.uyap => _uyap(x, following, toDecimal, space),
    TabRules.word => _word(x, following, toDecimal),
  };

  double _uyap(
    double x,
    double Function()? following,
    double Function()? toDecimal,
    double space,
  ) {
    // UYAP rounds the pen to a whole point before it places a tab: after a
    // label 102.3 points wide a tab past the last stop ends at 107, not
    // 107.3, and one that has run past a stop never ends less than a space
    // beyond that whole point.
    final at = x.roundToDouble();
    final double end;
    if (stops.isEmpty && !declared) {
      end = interval <= 0 ? at : ((at / interval).truncate() + 1) * interval;
    } else {
      final stop = stops.where((s) => s.position >= at + .01).firstOrNull;
      end = stop == null
          ? at + uyapPastLast
          : _aligned(stop, at, following, toDecimal);
    }
    return math.max(end, at + space);
  }

  double _word(
    double x,
    double Function()? following,
    double Function()? toDecimal,
  ) {
    final stop = stops.where((s) => s.position > x + .01).firstOrNull;
    if (stop != null) {
      final end = _aligned(stop, x, following, toDecimal);
      if (end > x + .01) return end;
    }
    if (interval <= 0) return x;
    return ((x + .01) / interval).floor() * interval + interval;
  }

  static double _aligned(
    TabStop stop,
    double x,
    double Function()? following,
    double Function()? toDecimal,
  ) => switch (stop.align) {
    TabAlign.left || TabAlign.bar => stop.position,
    TabAlign.right => math.max(x, stop.position - (following?.call() ?? 0)),
    TabAlign.centre => math.max(
      x,
      stop.position - (following?.call() ?? 0) / 2,
    ),
    TabAlign.decimal => math.max(
      x,
      stop.position - (toDecimal?.call() ?? following?.call() ?? 0),
    ),
  };

  /// Reads UDF's `TabSet`: stops separated by commas, each one
  /// `position:alignment:leader`, as in `18.0:0:0,69.0:2:0,136.0:0:0`.
  ///
  /// A paragraph without the attribute gets the regular interval. One with
  /// `TabSet=""` does not: UYAP takes it as a set with no stops in it, and
  /// moves every tab five points, as past the last stop — six tabs came to
  /// 34 points in UYAP, and 33 to one row, where stops every 72 points would
  /// have made six rows of them (three documents of a real archive).
  static TabStops parse(
    String? tabSet, {
    double interval = defaultInterval,
    TabRules rules = TabRules.uyap,
  }) {
    if (tabSet == null) return TabStops(interval: interval, rules: rules);
    if (tabSet.trim().isEmpty) {
      return TabStops(
        interval: interval,
        rules: rules,
        declared: rules == TabRules.uyap,
      );
    }
    final found = <TabStop>[];
    for (final part in tabSet.split(',')) {
      final bits = part.trim().split(':');
      if (bits.isEmpty) continue;
      final position = double.tryParse(bits.first);
      if (position == null || position <= 0) continue;
      found.add(
        TabStop(position, TabAlign.fromCode(bits.length > 1 ? bits[1] : null)),
      );
    }
    found.sort((a, b) => a.position.compareTo(b.position));
    return TabStops(
      stops: List.unmodifiable(found),
      interval: interval,
      rules: rules,
    );
  }
}
