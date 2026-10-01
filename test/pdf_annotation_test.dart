import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/annotations/pdf_annotation.dart';
import 'package:evrak_convert/services/search/index_database.dart';
import 'package:evrak_convert/services/search/index_service.dart';

PdfHighlight _mark({
  int id = 0,
  String path = '/arsiv/karar.pdf',
  int page = 1,
  List<NormRect> rects = const [NormRect(0.1, 0.2, 0.5, 0.25)],
  int color = 0xFFFFE082,
  int rotation = 0,
  String text = 'örnek',
}) => PdfHighlight(
  id: id,
  docKey: PdfHighlight.keyFor(path),
  path: path,
  page: page,
  rects: rects,
  text: text,
  color: color,
  created: 1700000000000,
  rotation: rotation,
);

void main() {
  test('PDF page coordinates become top-left normalized rects', () {
    // PDF space: bottom-left origin, top > bottom. A band across the top of an
    // A4 page must land near the top of the unit square, not the bottom.
    final r = NormRect.fromPdf(59.5, 780.0, 535.5, 760.0, 595.0, 842.0);
    expect(r.left, closeTo(0.1, 1e-9));
    expect(r.right, closeTo(0.9, 1e-9));
    expect(r.top, closeTo((842 - 780) / 842, 1e-9));
    expect(r.bottom, closeTo((842 - 760) / 842, 1e-9));
    expect(r.top < r.bottom, isTrue, reason: 'ekran uzayında üst küçüktür');
  });

  test('out-of-page coordinates are clamped instead of drawing outside', () {
    final r = NormRect.fromPdf(-20, 900, 700, -30, 595, 842);
    expect(r.left, 0.0);
    expect(r.right, 1.0);
    expect(r.top, 0.0);
    expect(r.bottom, 1.0);
  });

  test('degenerate page size cannot produce NaN rectangles', () {
    final r = NormRect.fromPdf(10, 20, 30, 5, 0, 0);
    expect(r.isEmpty, isTrue);
    for (final v in r.toJson()) {
      expect(v.isFinite, isTrue);
    }
  });

  test('character boxes merge per visual line, not into one block', () {
    // Two lines of three characters each. A single bounding box would cover the
    // gap between the lines; the reader expects two bands.
    final line1 = [
      const NormRect(0.10, 0.20, 0.14, 0.23),
      const NormRect(0.14, 0.20, 0.18, 0.23),
      const NormRect(0.18, 0.201, 0.22, 0.229),
    ];
    final line2 = [
      const NormRect(0.10, 0.26, 0.14, 0.29),
      const NormRect(0.14, 0.26, 0.20, 0.29),
    ];
    final merged = PdfHighlight.mergeLines([...line1, ...line2]);
    expect(merged.length, 2);
    expect(merged.first.left, closeTo(0.10, 1e-9));
    expect(merged.first.right, closeTo(0.22, 1e-9));
    expect(merged.last.right, closeTo(0.20, 1e-9));
    // The band between the lines stays unpainted.
    expect(merged.first.bottom < merged.last.top, isTrue);
  });

  test('empty boxes are dropped so stray glyphs add no zero-width marks', () {
    final merged = PdfHighlight.mergeLines(const [
      NormRect(0.2, 0.2, 0.2, 0.3),
      NormRect(0.3, 0.4, 0.5, 0.45),
    ]);
    expect(merged.length, 1);
    expect(merged.single.left, closeTo(0.3, 1e-9));
  });

  test('four quarter turns return a rectangle to where it started', () {
    const start = NormRect(0.1, 0.2, 0.5, 0.25);
    final back = start.rotated(4);
    expect(back.left, closeTo(start.left, 1e-9));
    expect(back.top, closeTo(start.top, 1e-9));
    expect(back.right, closeTo(start.right, 1e-9));
    expect(back.bottom, closeTo(start.bottom, 1e-9));
  });

  test('a highlight follows the page when the viewer rotates it', () {
    // Made on an upright page, read back while the page is turned 90° CW.
    final mark = _mark(rects: const [NormRect(0.0, 0.0, 0.5, 0.25)]);
    final turned = mark.rectsFor(1).single;
    expect(turned.left, closeTo(0.75, 1e-9));
    expect(turned.top, closeTo(0.0, 1e-9));
    expect(turned.right, closeTo(1.0, 1e-9));
    expect(turned.bottom, closeTo(0.5, 1e-9));
    // Unrotated reading is untouched and keeps the identical list.
    expect(identical(mark.rectsFor(0), mark.rects), isTrue);
  });

  test('a highlight made on a turned page is corrected when turned back', () {
    // Stored in unrotated page space, so asking for the upright view returns it
    // untouched while the turned view is derived.
    final mark = _mark(rects: const [NormRect(0.75, 0.0, 1.0, 0.5)]);
    expect(mark.rectsFor(0).single.left, closeTo(0.75, 1e-9));
    final turned = mark.rectsFor(3).single;
    expect(turned.top, closeTo(0.0, 1e-9));
    expect(turned.bottom, closeTo(0.25, 1e-9));
  });

  test('turning a page and back leaves the highlight where it was', () {
    final mark = _mark(rects: const [NormRect(0.12, 0.31, 0.64, 0.36)]);
    for (var turns = 0; turns < 4; turns++) {
      final there = mark.rectsFor(turns);
      // Undoing the same number of turns must reproduce the stored geometry:
      // the reader can rotate freely without marks creeping across the page.
      final back = there.map((r) => r.rotated(-turns)).toList();
      expect(
        back.single.left,
        closeTo(0.12, 1e-9),
        reason: '$turns çeyrek tur',
      );
      expect(back.single.top, closeTo(0.31, 1e-9), reason: '$turns çeyrek tur');
      expect(
        back.single.right,
        closeTo(0.64, 1e-9),
        reason: '$turns çeyrek tur',
      );
      expect(
        back.single.bottom,
        closeTo(0.36, 1e-9),
        reason: '$turns çeyrek tur',
      );
    }
  });

  test('a rect stays inside the page through every turn', () {
    // A turn must not push a mark outside the unit square, which would clip it
    // or draw it over the neighbouring page.
    const mark = NormRect(0.02, 0.9, 0.44, 0.98);
    for (var turns = 0; turns < 4; turns++) {
      final r = mark.rotated(turns);
      expect(r.left, inInclusiveRange(0.0, 1.0));
      expect(r.top, inInclusiveRange(0.0, 1.0));
      expect(r.right, inInclusiveRange(0.0, 1.0));
      expect(r.bottom, inInclusiveRange(0.0, 1.0));
      expect(r.left < r.right, isTrue);
      expect(r.top < r.bottom, isTrue);
    }
  });

  test('highlights survive a database round trip', () {
    final db = IndexDatabase(':memory:');
    addTearDown(db.close);
    final id = db.saveAnnotation(_mark(rotation: 2).toMap());
    expect(id, greaterThan(0));

    final rows = db.annotations(PdfHighlight.keyFor('/arsiv/karar.pdf'));
    expect(rows.length, 1);
    final read = PdfHighlight.fromMap(rows.single);
    expect(read.id, id);
    expect(read.page, 1);
    expect(read.rotation, 2);
    expect(read.text, 'örnek');
    expect(read.rects.single.left, closeTo(0.1, 1e-9));
    expect(read.rects.single.bottom, closeTo(0.25, 1e-9));
  });

  test('saving with an id recolours in place instead of duplicating', () {
    final db = IndexDatabase(':memory:');
    addTearDown(db.close);
    final id = db.saveAnnotation(_mark().toMap());
    final key = PdfHighlight.keyFor('/arsiv/karar.pdf');
    final stored = PdfHighlight.fromMap(db.annotations(key).single);

    db.saveAnnotation(
      stored.copyWith(color: 0xFF90CAF9, note: 'itiraz').toMap(),
    );
    final rows = db.annotations(key);
    expect(rows.length, 1, reason: 'güncelleme yeni satır açmamalı');
    final updated = PdfHighlight.fromMap(rows.single);
    expect(updated.id, id);
    expect(updated.color, 0xFF90CAF9);
    expect(updated.note, 'itiraz');
    // Geometry is never rewritten by an edit, so a mark cannot drift.
    expect(updated.rects.single.left, closeTo(0.1, 1e-9));
  });

  test('highlights are scoped to one document and deleted individually', () {
    final db = IndexDatabase(':memory:');
    addTearDown(db.close);
    final first = db.saveAnnotation(_mark().toMap());
    db.saveAnnotation(_mark(page: 3).toMap());
    db.saveAnnotation(_mark(path: '/arsiv/dilekce.pdf').toMap());

    final key = PdfHighlight.keyFor('/arsiv/karar.pdf');
    expect(db.annotations(key).length, 2);
    expect(db.annotations(PdfHighlight.keyFor('/arsiv/dilekce.pdf')).length, 1);

    db.deleteAnnotation(first);
    expect(db.annotations(key).single.let((r) => r['page']), 3);
    expect(db.annotations(PdfHighlight.keyFor('/arsiv/dilekce.pdf')).length, 1);
  });

  test(
    'an index written by the previous version gains the annotation table',
    () async {
      final dir = await Directory.systemTemp.createTemp('folio-annotations-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/index.sqlite';

      var db = IndexDatabase(path);
      expect(
        db.db.select('PRAGMA user_version').first.values.first,
        10,
        reason: 'şema sürümü yükselmeli',
      );
      // Simulate an index created before highlights existed. Everything later
      // migrations added has to go, or replaying them hits a column that is
      // already there.
      db.db.execute('DROP TABLE annotations');
      db.db.execute('DROP INDEX documents_ocr');
      db.db.execute('ALTER TABLE documents DROP COLUMN ocr');
      db.db.execute('PRAGMA user_version=4');
      db.close();

      db = IndexDatabase(path);
      addTearDown(db.close);
      final id = db.saveAnnotation(_mark().toMap());
      expect(id, greaterThan(0));
      expect(db.annotations(PdfHighlight.keyFor('/arsiv/karar.pdf')).length, 1);
    },
  );

  test(
    'the isolate protocol keeps the annotation id out of the request id',
    () async {
      // A highlight carries its own 'id'. Sent flat it would overwrite the
      // request id and the reply could never be matched, hanging the caller.
      final dir = await Directory.systemTemp.createTemp('folio-annot-isolate-');
      addTearDown(() => dir.delete(recursive: true));
      final service = await IndexService.open('${dir.path}/index.sqlite');
      addTearDown(service.close);

      final stored = _mark(id: 4242);
      final newId = await service
          .request<int>('saveAnnotation', {'row': stored.toMap()})
          .timeout(const Duration(seconds: 10));
      expect(newId, 4242, reason: 'var olan kayıt güncellenmeli');

      final rows = await service
          .request<List>('annotations', {'docKey': stored.docKey})
          .timeout(const Duration(seconds: 10));
      expect(
        rows,
        isEmpty,
        reason: 'olmayan satırın güncellenmesi satır yaratmaz',
      );
    },
  );
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
