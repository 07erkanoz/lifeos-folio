import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/editor/tab_stops.dart';

/// UYAP's behaviour, read off its own editor (see [TabStops]).
void main() {
  test('a tab always moves, even from exactly on a stop', () {
    const stops = TabStops(interval: 72);
    expect(stops.end(0), 72);
    // Standing on a stop and being told to stay there is what makes the key
    // look dead; the caret has to land on the following one.
    expect(stops.end(72), 144);
    expect(stops.end(69), 72);
    // Two points short of a stop is closer than a space: UYAP carried the
    // text after 70.66 points of capitals to 74, not to 72.
    expect(stops.end(70.66, space: 3), 74);
  });

  test('labels of different lengths reach the same column', () {
    // The pattern the whole feature exists for: a long label spends one tab,
    // a short one spends two, and the values line up.
    const stops = TabStops(interval: 72);
    final long = stops.end(130.0);
    final short = stops.end(stops.end(40.0));
    expect(long, short);
  });

  test('an explicit stop is used, and past the last one a tab moves 5 pt', () {
    final stops = TabStops.parse('18.0:0:0,69.0:2:0,136.0:0:0');
    expect(stops.stops.map((s) => s.position), [18.0, 69.0, 136.0]);
    expect(stops.end(0), 18.0);
    expect(stops.end(70), 136.0);
    // Not another stop 72 points on: UYAP's `nextTabStop` has none to give
    // and moves the pen five points, from the whole point it rounds to.
    expect(stops.end(140), 145);
    expect(stops.end(140.4), 145);
    expect(stops.end(140.6), 146);
  });

  test('a centre or right stop lines the following text up against it', () {
    final stops = TabStops.parse('100.0:2:0,200.0:1:0');
    expect(stops.end(0, following: () => 40), 80);
    expect(stops.end(120, following: () => 30), 170);
    // Text too wide to centre starts where the tab did, a space along.
    expect(stops.end(10, following: () => 400, space: 3), 13);
  });

  test('a tab is never narrower than a space', () {
    final stops = TabStops.parse('35.5:0:0');
    // 34.66 points of text round to 35; the stop half a point on is passed
    // by, and the tab ends a space past the whole point. UYAP: 38.0.
    expect(stops.end(34.66, space: 3), 38);
  });

  test('stop alignments are Swing\'s own codes', () {
    final stops = TabStops.parse(
      '10.0:0:0,20.0:1:0,30.0:2:0,40.0:4:0,50.0:5:0,60.0:3:0',
    );
    expect(stops.stops.map((s) => s.align), [
      TabAlign.left,
      TabAlign.right,
      TabAlign.centre,
      TabAlign.decimal,
      TabAlign.bar,
      TabAlign.left,
    ]);
  });

  test('stops arrive sorted however they were written', () {
    final stops = TabStops.parse('136.0:0:0,18.0:0:0');
    expect(stops.stops.map((s) => s.position), [18.0, 136.0]);
  });

  test('an unreadable TabSet, or none, has a stop every 72 points', () {
    for (final value in ['bozuk', '0:0:0', null]) {
      final stops = TabStops.parse(value);
      expect(stops.stops, isEmpty, reason: 'girdi: $value');
      expect(stops.end(0), TabStops.defaultInterval);
    }
  });

  test('an empty TabSet has no stops at all: every tab moves five points', () {
    // As UYAP drew them: six tabs in 34 points, 33 on one row.
    for (final value in ['', '   ']) {
      final stops = TabStops.parse(value);
      expect(stops.stops, isEmpty, reason: 'girdi: "$value"');
      expect(stops.end(0), TabStops.uyapPastLast);
      expect(stops.end(100.4), 105);
    }
    // A Word document's own default stops carry on regardless.
    expect(
      TabStops.parse('', interval: 35.4, rules: TabRules.word).end(0),
      35.4,
    );
  });

  test('a Word document keeps its default stops past its own', () {
    final stops = TabStops.parse(
      '100.0:0:0',
      interval: 35.4,
      rules: TabRules.word,
    );
    expect(stops.end(0), 100);
    // Past the last stop, the next of the document's default stops.
    expect(stops.end(101), closeTo(106.2, 1e-9));
    expect(TabStops(interval: 35.4, rules: TabRules.word).end(0), 35.4);
  });
}
