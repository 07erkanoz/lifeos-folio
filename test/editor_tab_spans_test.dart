import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/ui/widgets/editor_tab_spans.dart';
import 'package:evrak_convert/ui/widgets/editor_units.dart';

/// Lays the built span out far enough to say where each piece sits.
///
/// A WidgetSpan is one character wide as far as offsets go but as wide as its
/// box when drawn, so the column a tab reaches is the running total of the
/// text measured and the boxes inserted.
double columnAfterTabs(InlineSpan span, TextStyle style) {
  var x = 0.0;
  void walk(InlineSpan node) {
    if (node is WidgetSpan) {
      x += ((node.child as SizedBox).width)!;
      return;
    }
    if (node is TextSpan) {
      final text = node.text;
      if (text != null && text.isNotEmpty) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        x += painter.width;
        painter.dispose();
      }
      for (final child in node.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  walk(span);
  return x;
}

/// The first leaf of the line holding [text], wired into a real document so
/// the builder can walk to the paragraph the way it does in the editor.
Node leafFor(String text, {String? tabSet, double? first}) {
  final delta = Delta()
    ..insert(text)
    ..insert('\n', {
      if (tabSet != null || first != null)
        'doc-layout': {'tabs': ?tabSet, 'first': ?first},
    });
  final line = Document.fromDelta(delta).root.children.first as Line;
  return line.children.first;
}

void main() {
  // Twelve point, the paragraph's default, laid out in points.
  const style = TextStyle(fontSize: 12);
  const px = EditorUnits.pixelsPerPoint;

  Future<InlineSpan> build(
    WidgetTester tester,
    String text, {
    String? tabSet,
    double? first,
  }) async {
    late InlineSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = EditorTabSpans.builder()(
              context,
              leafFor(text, tabSet: tabSet, first: first),
              0,
              text,
              style,
              null,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return span;
  }

  testWidgets('labels of different lengths bring their values to one column', (
    tester,
  ) async {
    // The line every tutanak is made of. Before this the two colons sat one
    // space after labels of different widths, so they never lined up.
    final long = await build(tester, 'Arabuluculuk Bürosu\t:SERİK');
    final short = await build(tester, 'Adı ve Soyadı\t\t:Çiğdem');
    final a = columnAfterTabs(_untilColon(long), style);
    final b = columnAfterTabs(_untilColon(short), style);
    expect((a - b).abs() < 0.5, isTrue, reason: 'sütunlar ayrıştı: $a ve $b');
  });

  testWidgets('a tab lands on the stop rather than beside the text', (
    tester,
  ) async {
    final span = await build(tester, 'Ad\tSoyad');
    final tab = _firstBox(span);
    final space = TextPainter(
      text: const TextSpan(text: ' ', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    // The whole point: the tab ends at the stop, wherever the text before it
    // happened to end — one inch, not one space past 'Ad'.
    final before = columnAfterTabs(const TextSpan(text: 'Ad'), style);
    expect(before + tab, closeTo(72 * px, 0.5));
    // It used to be exactly one space wide, which is the bug being fixed.
    expect(tab, greaterThan(space.width));
    space.dispose();
  });

  testWidgets('a tab on an indented first line goes to the stop past it', (
    tester,
  ) async {
    // The line draws a 36 pt first line indent ahead of the text; stops are
    // measured from the left indent, as Swing measures them. 'Ad' therefore
    // ends at 36 pt + its width, and the tab carries it to the 72 pt stop,
    // not to a stop counted from where 'Ad' would have been without it.
    final span = await build(tester, 'Ad\tSoyad', first: 36);
    final before = columnAfterTabs(const TextSpan(text: 'Ad'), style);
    expect(36 * px + before + _firstBox(span), closeTo(72 * px, 0.5));
  });

  testWidgets('the paragraph its own stops are used over the interval', (
    tester,
  ) async {
    // 40 pt is well inside the first default stop, so honouring it is visible:
    // the tab stops short of where the regular interval would have carried it.
    // (The test font draws every letter and space a whole em wide, so a stop
    // nearer than 24 pt would be passed by: a tab is never narrower than a
    // space.)
    final span = await build(tester, 'A\tB', tabSet: '40.0:0:0');
    final withStops = columnAfterTabs(_untilLast(span), style);
    final plain = await build(tester, 'A\tB');
    final without = columnAfterTabs(_untilLast(plain), style);
    expect(withStops, lessThan(without));
    expect(withStops, closeTo(40.0 * px, 0.5));
  });

  testWidgets('a line with no tab is left exactly as it was', (tester) async {
    final span = await build(tester, 'Sekmesiz satır');
    expect(span, isA<TextSpan>());
    expect((span as TextSpan).text, 'Sekmesiz satır');
    expect(span.children, isNull);
  });

  testWidgets('every tab advances, even past the last stop', (tester) async {
    // Three tabs on one line must produce three moves, not two and a stall.
    final span = await build(tester, 'A\t\t\tB', tabSet: '18.0:0:0');
    final boxes = _boxes(span);
    expect(boxes.length, 3);
    expect(boxes.every((w) => w > 0), isTrue);
  });
}

InlineSpan _untilColon(InlineSpan span) =>
    _trim(span, (s) => s.startsWith(':'));
InlineSpan _untilLast(InlineSpan span) => _trim(span, (s) => s == 'B');
double _firstBox(InlineSpan span) => _boxes(span).first;

List<double> _boxes(InlineSpan span) => [
  for (final c in (span as TextSpan).children ?? const <InlineSpan>[])
    if (c is WidgetSpan) ((c.child as SizedBox).width)!,
];

/// Everything up to the run that [stop] recognises, so the column a value
/// starts at can be measured without the value's own width.
InlineSpan _trim(InlineSpan span, bool Function(String) stop) {
  final kept = <InlineSpan>[];
  for (final child in (span as TextSpan).children ?? const <InlineSpan>[]) {
    if (child is TextSpan && child.text != null && stop(child.text!)) break;
    kept.add(child);
  }
  return TextSpan(children: kept);
}
