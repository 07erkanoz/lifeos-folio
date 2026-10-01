import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:evrak_convert/services/editor/tab_stops.dart';
import 'package:evrak_convert/services/layout/paragraph_rows.dart';

/// The expectations are UYAP's own: its editor was run on documents built for
/// each case and asked where it had put every character. Positions are points
/// from the margin; UYAP's are read to about a fifth of a point.
void main() {
  // Liberation Serif is drawn to Times New Roman's widths, and it is the one
  // every machine that runs these tests has.
  final font = PdfTtfFont(
    PdfDocument(),
    ByteData.sublistView(
      File('fonts/pdf/LiberationSerif-Regular.ttf').readAsBytesSync(),
    ),
  );
  // A line break inside a paragraph is drawn as nothing, as the preview
  // draws it.
  double width(String text) {
    final drawn = text.replaceAll('\n', '');
    return drawn.isEmpty ? 0 : font.stringMetrics(drawn).advanceWidth * 12;
  }

  // The text area of a UYAP page with its usual 42.52 pt margins.
  const page = 595.28 - 2 * 42.51968479156494;

  List<ParagraphRow> rows(
    String text, {
    String? tabSet,
    RowAlign align = RowAlign.left,
    double left = 0,
    double first = 0,
    double hanging = 0,
  }) => ParagraphRows(
    text: text,
    measure: (a, b) => width(text.substring(a, b)),
    space: (_) => width(' '),
    width: page,
    leftIndent: left,
    firstLineIndent: first,
    hanging: hanging,
    align: align,
    tabs: TabStops.parse(tabSet),
  ).layout();

  /// Where the character at [offset] is drawn.
  double at(List<ParagraphRow> laid, int offset) {
    for (final row in laid) {
      for (final p in row.pieces) {
        if (offset >= p.start && offset < p.end) {
          return p.x +
              (p.kind == PieceKind.text
                  ? width(laidText!.substring(p.start, offset))
                  : 0);
        }
      }
    }
    throw StateError('$offset yok');
  }

  int rowOf(List<ParagraphRow> laid, int offset) =>
      laid.indexWhere((r) => offset >= r.start && offset < r.end);

  double x(String text, String needle, {String? tabSet, double left = 0}) {
    laidText = text;
    return at(rows(text, tabSet: tabSet, left: left), text.indexOf(needle));
  }

  test('past the last stop a tab moves five points, from a whole point', () {
    expect(x('Ad\tB\tC\tD', 'B', tabSet: '50.0:0:0'), closeTo(50, .01));
    expect(x('Ad\tB\tC\tD', 'C', tabSet: '50.0:0:0'), closeTo(63, .01));
    expect(x('Ad\tB\tC\tD', 'D', tabSet: '50.0:0:0'), closeTo(76, .01));
    // 102.3 points of label, rounded to 102: UYAP put the B at 107.0.
    expect(
      x('Uzun bir etiket metni\tB', 'B', tabSet: '50.0:0:0'),
      closeTo(107, .01),
    );
  });

  test('with no stops of its own a paragraph has one every 72 points', () {
    expect(x('Ad\tB\tC\tD', 'B'), closeTo(72, .01));
    expect(x('Ad\tB\tC\tD', 'C'), closeTo(144, .01));
    expect(x('Ad\tB\tC\tD', 'D'), closeTo(216, .01));
  });

  test('stops are counted from the left indent, past a first line indent', () {
    expect(x('A\tB', 'B', left: 40), closeTo(112, .01));
    expect(x('A\tB', 'B', left: 40, tabSet: '50.0:0:0'), closeTo(90, .01));
    laidText = 'A\tB';
    final indented = rows('A\tB', first: 30);
    expect(at(indented, 0), closeTo(30, .01));
    expect(at(indented, 2), closeTo(72, .01));
  });

  test('centre and right stops line the text up against themselves', () {
    // UYAP: T.C. at 55.9, MANAVGAT at 32.0, Sağa at 177.0, Orta at 138.9.
    expect(x('\tT.C.', 'T', tabSet: '67.0:2:0'), closeTo(55.9, .5));
    expect(x('\tMANAVGAT', 'M', tabSet: '67.0:2:0'), closeTo(32.0, .5));
    expect(x('Ad\tSağa', 'S', tabSet: '200.0:1:0'), closeTo(177.0, .5));
    const both = 'Ad\tOrta\tSol';
    expect(x(both, 'O', tabSet: '150.0:2:0,300.0:0:0'), closeTo(138.9, .5));
    expect(x(both, 'Sol', tabSet: '150.0:2:0,300.0:0:0'), closeTo(300, .01));
  });

  test('a tab is never narrower than a space past its whole point', () {
    // A centred heading too wide for its stop, a stop just past the text, a
    // stop just past the margin: 3.0, 38.0 and 3.0 in UYAP.
    expect(
      x('\tUZUN BİR BAŞLIK METNİ BURADA', 'U', tabSet: '20.0:2:0'),
      closeTo(3, .01),
    );
    expect(x('AAAA\tB', 'B', tabSet: '35.5:0:0'), closeTo(38, .01));
    expect(x('\tB', 'B', tabSet: '1.0:0:0'), closeTo(3, .01));
    expect(
      x('Ad\tUZUN BİR SAĞ METİN', 'U', tabSet: '30.0:1:0'),
      closeTo(18, .01),
    );
  });

  test('a line of tabs stays on one row, as it did in UYAP', () {
    // 74 tabs to push a witness's name across the page: one to the stop,
    // then five points each. Counted as 72-point stops it ran over rows.
    final text = '${'\t' * 74}TANIK UĞUR KAYA';
    laidText = text;
    final laid = rows(text, tabSet: '35.0:0:0');
    expect(at(laid, text.indexOf('TANIK')), closeTo(400, .01));
    expect(rowOf(laid, text.indexOf('TANIK')), 0);
    expect(rowOf(laid, text.indexOf('KAYA')), 1);
  });

  test('a tab that does not fit starts the next row, counted from there', () {
    // Twelve tabs at 72 points: seven fit, the rest go below, and İMZA lands
    // on the fifth stop of the second row.
    final text = '${'\t' * 12}İMZA';
    laidText = text;
    final laid = rows(text);
    expect(rowOf(laid, 6), 0);
    expect(rowOf(laid, 7), 1);
    expect(at(laid, text.indexOf('İMZA')), closeTo(360, .01));
  });

  test('a hanging indent carries every row but the first', () {
    const long =
        'Davacı ile müvekkil arasında imzalanan sözleşme gereğince yapılan '
        'ödemelerin iadesi talep edilmiş olup mahkemece yapılan yargılama '
        'sonucunda davanın kısmen kabulüne karar verilmiştir.';
    const text = 'DAVACI\t: $long';
    laidText = text;
    final laid = rows(text, tabSet: '150.0:0:0', hanging: 160);
    expect(at(laid, text.indexOf(':')), closeTo(150, .01));
    expect(laid.length, greaterThan(1));
    for (final row in laid.skip(1)) {
      expect(row.pieces.first.x, closeTo(160, .01));
    }
    final firsts = rows(long, first: 20, hanging: 30);
    expect(firsts.first.pieces.first.x, 20);
    expect(firsts[1].pieces.first.x, 30);
  });

  test('a word wider than a row is cut where it stops fitting', () {
    final text = '${'M' * 60} son';
    laidText = text;
    final laid = rows(text);
    expect(laid.first.end, 47, reason: 'UYAP kept 47 of them on the row');
  });

  test('a justified row spreads between words and not after a tab', () {
    const long =
        'Davacı ile müvekkil arasında imzalanan sözleşme gereğince yapılan '
        'ödemelerin iadesi talep edilmiş olup mahkemece yapılan yargılama '
        'sonucunda davanın kısmen kabulüne karar verilmiştir.';
    // The first word straight after the tab, as in UYAP and in Flutter; the
    // preview used to spread room between the tab and the word too.
    final tabbed = '\t$long';
    laidText = tabbed;
    final laid = rows(tabbed, align: RowAlign.justify);
    expect(at(laid, 1), closeTo(72, .01));
    expect(laid.first.right, closeTo(page, .01));
    // A space ahead of the row's first word takes no room.
    final spaced = ' $long';
    laidText = spaced;
    expect(at(rows(spaced, align: RowAlign.justify), 1), closeTo(0, .01));
    // Spaces before a tab are spread too, and push it along: UYAP drew this
    // colon at 115.9, three points past its stop.
    final label = 'DAVACI VEKİLİ\t: Av. $long';
    laidText = label;
    final withLabel = rows(label, tabSet: '113.0:0:0', align: RowAlign.justify);
    expect(at(withLabel, label.indexOf(':')), closeTo(115.9, 1.5));
    // The last row is set as it stands.
    expect(withLabel.last.right, lessThan(page - 50));
  });

  test('a line break inside a paragraph is drawn as nothing', () {
    // UYAP set "burada" and "İkinci" side by side on one row, the break
    // between them taking no room; a Word document breaks there.
    const text = 'Birinci satır burada\nİkinci satır burada';
    laidText = text;
    final uyap = rows(text, align: RowAlign.justify);
    expect(uyap.length, 1);
    final end = text.indexOf('\n');
    expect(at(uyap, end + 1), closeTo(at(uyap, 14) + width('burada'), .01));
    final word = ParagraphRows(
      text: text,
      measure: (a, b) => width(text.substring(a, b)),
      space: (_) => width(' '),
      width: page,
      lineBreaks: true,
    ).layout();
    expect(word.length, 2);
    expect(word.first.last, isTrue, reason: 'a broken row is not spread');
  });

  test('an em space is a wide space a line can break at', () {
    // UYAP: twelve points wide, and the row broke after it.
    const label = 'VEKİLİ\u2003\t\t: Av. ALİ';
    expect(x(label, ':'), closeTo(144, .01));
    final text = '${'a ' * 58}bb\u2003ccc ddd';
    laidText = text;
    final laid = rows(text);
    expect(rowOf(laid, text.indexOf('ccc')), 1);
    expect(rowOf(laid, text.indexOf('bb')), 0);
  });

  test('a centred or right-aligned paragraph counts its closing spaces', () {
    // UYAP drew 'SAĞ METİN   ' ending at the margin with its spaces.
    const text = 'SAĞ METİN   ';
    laidText = text;
    final right = rows(text, align: RowAlign.right);
    expect(right.first.pieces.last.x + width(' '), closeTo(page, .01));
  });
}

String? laidText;
