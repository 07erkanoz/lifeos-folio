import 'dart:convert';

import '../editor/document_history.dart';

/// Highlights live in the index database, never inside the PDF. The source file
/// stays byte-identical, so read-only, signed and cloud-offline documents can be
/// marked up too. "Notlarla dışa aktar" writes a separate annotated copy.
///
/// Rectangles are stored normalized (0..1) against the page box with a top-left
/// origin, so a highlight keeps its place at any zoom, rotation-free, and
/// survives the viewer switching page sizes.
class NormRect {
  final double left, top, right, bottom;
  const NormRect(this.left, this.top, this.right, this.bottom);

  /// PDF page coordinates use a bottom-left origin and `top > bottom`; screen
  /// space is the other way round. Convert once, on the way in.
  factory NormRect.fromPdf(
    double left,
    double top,
    double right,
    double bottom,
    double pageWidth,
    double pageHeight,
  ) {
    if (pageWidth <= 0 || pageHeight <= 0) {
      return const NormRect(0, 0, 0, 0);
    }
    return NormRect(
      (left / pageWidth).clamp(0.0, 1.0),
      ((pageHeight - top) / pageHeight).clamp(0.0, 1.0),
      (right / pageWidth).clamp(0.0, 1.0),
      ((pageHeight - bottom) / pageHeight).clamp(0.0, 1.0),
    );
  }

  bool get isEmpty => right <= left || bottom <= top;
  double get width => right - left;
  double get height => bottom - top;

  List<double> toJson() => [left, top, right, bottom];
  static NormRect fromJson(List raw) => NormRect(
    (raw[0] as num).toDouble(),
    (raw[1] as num).toDouble(),
    (raw[2] as num).toDouble(),
    (raw[3] as num).toDouble(),
  );

  /// Merge two rects that belong to the same visual line.
  NormRect merge(NormRect other) => NormRect(
    left < other.left ? left : other.left,
    top < other.top ? top : other.top,
    right > other.right ? right : other.right,
    bottom > other.bottom ? bottom : other.bottom,
  );

  /// Rotate inside the unit square by [quarterTurns] clockwise. The viewer can
  /// rotate pages in memory after a highlight was made; without this the mark
  /// would stay where the text used to be.
  NormRect rotated(int quarterTurns) {
    var r = this;
    for (var i = 0; i < (quarterTurns % 4 + 4) % 4; i++) {
      r = NormRect(1 - r.bottom, r.left, 1 - r.top, r.right);
    }
    return r;
  }

  /// Two character boxes share a line when their vertical bands mostly overlap.
  /// Character heights differ within a line (accents, punctuation), so compare
  /// the overlap against the shorter box rather than demanding equal tops.
  bool sameLineAs(NormRect other) {
    final overlap =
        (bottom < other.bottom ? bottom : other.bottom) -
        (top > other.top ? top : other.top);
    final shorter = height < other.height ? height : other.height;
    return shorter > 0 && overlap > shorter * 0.5;
  }
}

class PdfHighlight {
  final int id;
  final String docKey;
  final String path;

  /// 1-based, matching `PdfPage.pageNumber`.
  final int page;
  final List<NormRect> rects;

  /// The selected text, kept so a highlight can be shown in a list and checked
  /// against the document later. If the file changed underneath, the text no
  /// longer matches and the highlight is flagged instead of drawn in the wrong
  /// place.
  final String text;
  final int color;
  final String? note;
  final int created;

  /// Page rotation in quarter turns at the moment the highlight was made.
  /// Rects are normalized against the page as it looked then; drawing compares
  /// this with the page's current rotation and turns them to match.
  final int rotation;

  const PdfHighlight({
    this.id = 0,
    required this.docKey,
    required this.path,
    required this.page,
    required this.rects,
    this.text = '',
    required this.color,
    this.note,
    required this.created,
    this.rotation = 0,
  });

  /// Rects placed for a page currently turned to [quarterTurns].
  List<NormRect> rectsFor(int quarterTurns) {
    final delta = quarterTurns - rotation;
    if (delta % 4 == 0) return rects;
    return rects.map((r) => r.rotated(delta)).toList();
  }

  static String keyFor(String path) => DocumentHistory.documentKey(path);

  PdfHighlight copyWith({int? id, int? color, String? note}) => PdfHighlight(
    id: id ?? this.id,
    docKey: docKey,
    path: path,
    page: page,
    rects: rects,
    text: text,
    color: color ?? this.color,
    note: note ?? this.note,
    created: created,
    rotation: rotation,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'docKey': docKey,
    'path': path,
    'page': page,
    'rects': jsonEncode(rects.map((r) => r.toJson()).toList()),
    'text': text,
    'color': color,
    'note': note,
    'created': created,
    'rotation': rotation,
  };

  factory PdfHighlight.fromMap(Map row) => PdfHighlight(
    id: row['id'] as int? ?? 0,
    docKey: row['docKey'] as String,
    path: row['path'] as String,
    page: row['page'] as int,
    rects: (jsonDecode(row['rects'] as String) as List)
        .map((r) => NormRect.fromJson(r as List))
        .toList(),
    text: row['text'] as String? ?? '',
    color: row['color'] as int,
    note: row['note'] as String?,
    created: row['created'] as int,
    rotation: row['rotation'] as int? ?? 0,
  );

  /// Default highlighter colours, kept opaque in storage and drawn translucent.
  static const palette = <int>[
    0xFFFFE082, // sarı
    0xFFA5D6A7, // yeşil
    0xFF90CAF9, // mavi
    0xFFF48FB1, // pembe
    0xFFCE93D8, // mor
  ];

  /// Collapse per-character boxes into one rectangle per visual line, so a
  /// multi-line selection draws as text lines instead of one block covering the
  /// whole paragraph including its margins.
  static List<NormRect> mergeLines(Iterable<NormRect> boxes) {
    final result = <NormRect>[];
    for (final box in boxes) {
      if (box.isEmpty) continue;
      final last = result.isEmpty ? null : result.last;
      if (last != null && last.sameLineAs(box)) {
        result[result.length - 1] = last.merge(box);
      } else {
        result.add(box);
      }
    }
    return result;
  }
}
