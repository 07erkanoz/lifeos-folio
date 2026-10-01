import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:evrak_convert/services/legal/citation.dart';
import 'package:evrak_convert/services/legal/pdf_citations.dart';

CitationScanner _scanner() =>
    CitationScanner.parse(File('assets/mevzuat/laws.json').readAsStringSync());

/// A page 600 wide and 800 tall, one line of characters 10 wide and 12 tall
/// sitting 100 up from the foot of it. PDF counts from the bottom left, so
/// the top of a character is the bigger number.
const _pageWidth = 600.0;
const _pageHeight = 800.0;
const _charWidth = 10.0;
const _baseline = 100.0;

List<PdfRect> _oneLine(String body) => [
  for (var i = 0; i < body.length; i++)
    PdfRect(i * _charWidth, _baseline + 12, (i + 1) * _charWidth, _baseline),
];

/// The same, but wrapping onto a second line after [breakAt] characters.
List<PdfRect> _twoLines(String body, int breakAt) => [
  for (var i = 0; i < body.length; i++)
    if (i < breakAt)
      PdfRect(i * _charWidth, _baseline + 12, (i + 1) * _charWidth, _baseline)
    else
      PdfRect(
        (i - breakAt) * _charWidth,
        _baseline - 8,
        (i - breakAt + 1) * _charWidth,
        _baseline - 20,
      ),
];

void main() {
  test('a law cited on a page is found where its characters are', () {
    const body = 'Boşanma TMK m. 166 uyarınca talep edilmiştir.';
    final found = PdfCitations.citationsIn(
      _scanner(),
      body,
      _oneLine(body),
      _pageWidth,
      _pageHeight,
    );

    expect(found, hasLength(1));
    final one = found.single;
    expect(one.citation!.law.number, 4721);
    expect(one.citation!.article, 166);

    // One line, so one rectangle, and it spans exactly the cited characters.
    expect(one.rects, hasLength(1));
    final at = body.indexOf('TMK m. 166');
    final rect = one.rects.single;
    expect(rect.left * _pageWidth, closeTo(at * _charWidth, 0.01));
    expect(
      rect.right * _pageWidth,
      closeTo((at + 'TMK m. 166'.length) * _charWidth, 0.01),
    );
    // Measured from the top of the page, not the foot of it.
    expect(rect.top * _pageHeight, closeTo(_pageHeight - _baseline - 12, 0.01));
  });

  test('a citation broken across two lines gives a rectangle for each', () {
    const body = 'Uyarınca TMK m. 166 hükmü';
    final at = body.indexOf('TMK m. 166');
    final found = PdfCitations.citationsIn(
      _scanner(),
      body,
      _twoLines(body, at + 4),
      _pageWidth,
      _pageHeight,
    );
    expect(found, hasLength(1));
    expect(
      found.single.rects,
      hasLength(2),
      reason: 'iki satıra yayılan atıf iki dikdörtgen vermeli',
    );
  });

  test('a page that cites nothing gives nothing', () {
    const body = 'Dosya 2024/1234 esas sayılıdır ve 15 Mart tarihlidir.';
    expect(
      PdfCitations.citationsIn(
        _scanner(),
        body,
        _oneLine(body),
        _pageWidth,
        _pageHeight,
      ),
      isEmpty,
    );
  });

  test('a page with no text at all gives nothing', () {
    expect(
      PdfCitations.citationsIn(
        _scanner(),
        '',
        const [],
        _pageWidth,
        _pageHeight,
      ),
      isEmpty,
    );
  });

  test('several laws on one page are each placed on their own', () {
    const body = 'TMK m. 166 ve HMK m. 119 ve İİK 89 birlikte.';
    final found = PdfCitations.citationsIn(
      _scanner(),
      body,
      _oneLine(body),
      _pageWidth,
      _pageHeight,
    );
    expect(found.map((c) => c.citation!.law.number), [4721, 6100, 2004]);
    // Left to right, in the order they are written.
    final lefts = [for (final c in found) c.rects.first.left];
    expect(lefts, orderedEquals([...lefts]..sort()));
  });

  test('a text layer shorter than its own text does not run off the end', () {
    // A damaged page can report fewer rectangles than characters; the reader
    // should see less rather than have the viewer throw.
    const body = 'Boşanma TMK m. 166 uyarınca';
    final short = _oneLine(body).take(body.indexOf('166')).toList();
    final found = PdfCitations.citationsIn(
      _scanner(),
      body,
      short,
      _pageWidth,
      _pageHeight,
    );
    expect(found, hasLength(1));
    expect(found.single.rects, isNotEmpty);
  });
}
