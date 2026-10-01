import 'dart:math' as math;

import 'package:flutter_quill/flutter_quill.dart';

import '../../services/editor/tab_stops.dart';
import '../../services/fonts/document_fonts.dart';
import 'editor_list_marker.dart';
import 'editor_tab_spans.dart';
import 'editor_units.dart';

/// A paragraph's own indents and spacing, drawn the way the preview and the
/// printed page draw them.
///
/// Word and UYAP give every paragraph these, and [DocDeltaMap] carries them
/// on the line as `doc-layout`, but Quill only knows global styles: it drew
/// no space between paragraphs, no first line indent, no right indent, and
/// turned a left indent into whole steps of its own. Measured over 874 real
/// UDF files, 18% have paragraph spacing, 20% a left indent and 12% a first
/// line indent, so the editor and the preview disagreed on most petitions.
///
/// The values are points, as the document stores them; the page is drawn at
/// 96/72 pixels per point.
class EditorLineLayout {
  EditorLineLayout._();

  static const _pixelsPerPoint = EditorUnits.pixelsPerPoint;

  /// What the model calls one indent step, in points. Pressing the indent
  /// button moves a paragraph by this much, which is what the saved file
  /// gets too (see [DocDeltaMap.deltadanModel]).
  static const _indentStep = 36.0;

  /// A list level's indent, as UYAP sets a list: 25, 50, 75 points.
  static const _listStep = 25.0;

  /// The paragraph's line spacing as the model holds it, 1 + LineSpacing.
  /// A value picked from the toolbar wins over the one the file brought.
  static double spacingOf(Line line) {
    final attrs = line.style.attributes;
    final picked = attrs[Attribute.lineHeight.key]?.value;
    final raw = attrs['doc-layout']?.value;
    final stored = raw is Map ? raw['line'] : null;
    final value = picked is num
        ? picked.toDouble()
        : stored is num
        ? stored.toDouble()
        : 1.0;
    return value < 1 ? 1 : value;
  }

  /// A run's height as a multiple of its size: the row UYAP lays out for
  /// it — its font's natural row rounded up to a whole point, the
  /// paragraph's spacing added in whole points above and below — as the
  /// preview and the printed page do (see [FontLineMetrics.uyapRow]). So a
  /// page of the editor holds the rows a printed page does. A Word
  /// document's rows are its font's natural row times the spacing.
  static double runHeight(Node leaf) {
    final line = leaf.parent;
    final font = leaf.style.attributes[Attribute.font.key]?.value;
    return _rowOf(
      line is Line ? line : null,
      font is String ? font : null,
      _pixelsToPoints(leaf.style.attributes['size']?.value),
    );
  }

  /// A run's `size`, kept in 96 dpi pixels, in points.
  static double? _pixelsToPoints(Object? size) {
    final pixels = _points(size);
    return pixels == null ? null : pixels / EditorUnits.sizePixelsPerPoint;
  }

  /// Twelve point, the size a run without one is drawn at.
  static const _defaultSize = 12.0;

  static double? _points(Object? size) => switch (size) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static double _rowOf(Line? line, String? font, double? size) {
    final metrics = DocumentFonts.lineMetrics(font);
    final spacing = line == null ? 1.0 : spacingOf(line);
    if (line != null && _layoutOf(line)['rules'] == 'word') {
      return metrics.natural * spacing;
    }
    final points = size ?? _defaultSize;
    return metrics.uyapRow(points, spacing) / points;
  }

  /// Whose rules the paragraph's tabs and indents follow. A Word document's
  /// lines say so; everything else is laid out by UYAP's.
  static TabStops tabsOf(Line line) {
    final layout = _layoutOf(line);
    final word = layout['rules'] == 'word';
    return TabStops.parse(
      layout['tabs'] as String?,
      rules: word ? TabRules.word : TabRules.uyap,
      interval:
          (layout['interval'] as num?)?.toDouble() ??
          (word ? 36.0 : TabStops.defaultInterval),
    );
  }

  /// The paragraph's indents in points, as they are drawn: the left one with
  /// any steps pressed in the editor, and under UYAP's rules each cut to a
  /// whole point, since Swing keeps them in `short` insets — a first line
  /// indent of 35.4375 is drawn at 35. A list item is laid out as any
  /// paragraph, its number drawn in the indent (see [EditorListMarker]); one
  /// made in the editor, with no indent of its own, is set in 25 points a
  /// level, as UYAP sets its lists.
  static ({double left, double right, double first, double hanging})? indents(
    Line line,
  ) {
    final attrs = line.style.attributes;
    final layout = _layoutOf(line);
    if (attrs.containsKey(Attribute.list.key) && !layout.containsKey('left')) {
      final level = attrs[Attribute.indent.key]?.value;
      return (
        left: _listStep * math.max(1, level is int ? level : 0),
        right: 0,
        first: 0,
        hanging: 0,
      );
    }
    final whole = layout['rules'] != 'word';
    double points(double v) => whole ? v.truncateToDouble() : v;
    double value(String key) => (layout[key] as num?)?.toDouble() ?? 0;
    final level = attrs[Attribute.indent.key]?.value;
    final steps = level is int ? level : 0;
    final editorIndent = (layout['editorIndent'] as num?)?.toInt() ?? 0;
    // The same sum the save makes, so what is drawn is what is written.
    final step = attrs.containsKey(Attribute.list.key)
        ? _listStep
        : _indentStep;
    final left = points(
      (value('left') + (steps - editorIndent) * step).clamp(0.0, 1000.0),
    );
    return (
      left: left,
      right: math.max(0.0, points(value('right'))),
      // A hanging indent would need the first line pulled left of the rest;
      // it is drawn flush with the left indent instead.
      first: math.max(0.0, points(value('first'))),
      hanging: math.max(0.0, points(value('hanging'))),
    );
  }

  static Map _layoutOf(Line line) {
    final raw = line.style.attributes['doc-layout']?.value;
    return raw is Map ? raw : const {};
  }

  /// [of] for a page whose text area is [pageWidth] points wide, margin to
  /// margin. Knowing it, a paragraph's hanging indent is drawn too: finding
  /// where its lines break takes the width they break at.
  static QuillLineLayoutBuilder builder({double? pageWidth}) =>
      (line) => _layout(line, pageWidth);

  static QuillLineLayout? of(Line line) => _layout(line, null);

  static QuillLineLayout? _layout(Line line, double? pageWidth) {
    final attrs = line.style.attributes;
    final layout = _layoutOf(line);
    final whole = layout['rules'] != 'word';
    double value(String key) => (layout[key] as num?)?.toDouble() ?? 0;
    double points(double v) => whole ? v.truncateToDouble() : v;
    final before = math.max(0.0, points(value('before')));
    final after = math.max(0.0, points(value('after')));
    // The paragraph mark's row, which the last row is at least: in the size
    // and font it was written in (UYAP counts it as a run), or, where the
    // file does not say, the last run's, so it adds nothing.
    final last = line.children.isEmpty ? null : line.children.last;
    final font =
        layout['endFamily'] ??
        last?.style.attributes[Attribute.font.key]?.value;
    final size =
        _points(layout['endSize']) ??
        _pixelsToPoints(last?.style.attributes['size']?.value) ??
        _defaultSize;
    final rowHeight =
        _rowOf(line, font is String ? font : null, size) *
        size *
        _pixelsPerPoint;
    final indents = EditorLineLayout.indents(line);
    if (indents == null) {
      return QuillLineLayout(
        top: before * _pixelsPerPoint,
        bottom: after * _pixelsPerPoint,
        rowHeight: rowHeight,
      );
    }
    // A list item's number, where UYAP draws it: by the first row, whose
    // height its first run sets.
    final first = line.children.isEmpty ? null : line.children.first;
    final firstFont = first?.style.attributes[Attribute.font.key]?.value;
    final firstSize =
        _pixelsToPoints(first?.style.attributes['size']?.value) ?? _defaultSize;
    final leading = attrs.containsKey(Attribute.list.key)
        ? EditorListMarker.of(
            line,
            textStart: (indents.left + indents.first) * _pixelsPerPoint,
            row:
                _rowOf(
                  line,
                  firstFont is String ? firstFont : null,
                  firstSize,
                ) *
                firstSize *
                _pixelsPerPoint,
          )
        : null;
    return QuillLineLayout(
      leading: leading,
      horizontal: HorizontalSpacing(
        indents.left * _pixelsPerPoint,
        indents.right * _pixelsPerPoint,
      ),
      top: before * _pixelsPerPoint,
      bottom: after * _pixelsPerPoint,
      firstLine: indents.first * _pixelsPerPoint,
      rowHeight: rowHeight,
      hanging: indents.hanging * _pixelsPerPoint,
      width: pageWidth == null
          ? null
          : (pageWidth - indents.left - indents.right) * _pixelsPerPoint,
      // On a page, the rows the printed page has, so the editor breaks its
      // lines where the preview does.
      rows: pageWidth == null
          ? null
          : EditorTabSpans.rowStarts(line, pageWidth),
    );
  }
}
