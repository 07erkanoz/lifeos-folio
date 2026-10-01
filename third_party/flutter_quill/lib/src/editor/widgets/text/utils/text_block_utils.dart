import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../common/structs/horizontal_spacing.dart';
import '../../../../document/attribute.dart';
import '../../../../document/nodes/block.dart';
import '../../../../document/nodes/line.dart';
import '../../../../document/nodes/node.dart';
import '../../default_styles.dart';

typedef LeadingBlockIndentWidth = HorizontalSpacing Function(
    Block block,
    BuildContext context,
    int count,
    LeadingBlockNumberPointWidth numberPointWidthDelegate);

typedef LeadingBlockNumberPointWidth = double Function(
    double fontSize, int count);

// FOLIO PATCH: per-line layout. Quill takes a paragraph's indents and
// spacing from global styles only; a document read from Word or UYAP carries
// its own for every paragraph. See third_party/flutter_quill/FOLIO_PATCH.md.
@immutable
class QuillLineLayout {
  const QuillLineLayout({
    this.horizontal,
    this.top = 0,
    this.bottom = 0,
    this.firstLine = 0,
    this.rowHeight,
    this.leading,
    this.hanging = 0,
    this.width,
    this.rows,
  });

  /// Replaces the left/right spacing Quill would give the line when set.
  final HorizontalSpacing? horizontal;

  /// Added to the vertical spacing Quill would give the line.
  final double top, bottom;

  /// Extra room before the first visual line of the paragraph only.
  final double firstLine;

  /// The row, in pixels, of the paragraph mark, which is drawn at the end of
  /// the line in the line's own style and so sets the last row as a run does
  /// — all of an empty line's. It also turns the strut off,
  /// so every run sets its row by its own style rather than being held to the
  /// paragraph's default size.
  final double? rowHeight;

  /// Drawn in place of the list number or bullet Quill would draw, in the
  /// room the line's left spacing leaves beside it.
  final Widget? leading;

  /// Extra room before every visual line of the paragraph but the first.
  final double hanging;

  /// The width the paragraph's text is laid out in, which finding where its
  /// lines break takes before it is drawn. A hanging indent is only drawn
  /// with it.
  final double? width;

  /// Where the paragraph's rows start, as offsets in the line, the first
  /// row's 0 left out: laid out by the app by the rules the printed page is
  /// laid out by. The line then breaks there and nowhere else, so the
  /// editor's rows are the page's.
  final List<int>? rows;
}

typedef QuillLineLayoutBuilder = QuillLineLayout? Function(Line line);

typedef TextSpanBuilder = InlineSpan Function(
  BuildContext context,
  Node node,
  int nodeOffset,
  String text,
  TextStyle? style,
  GestureRecognizer? recognizer,
);

TextSpan defaultSpanBuilder(
  BuildContext context,
  Node node,
  int textOffset,
  String text,
  TextStyle? style,
  GestureRecognizer? recognizer,
) =>
    TextSpan(
      text: text,
      style: style,
      recognizer: recognizer,
      mouseCursor: (recognizer != null) ? SystemMouseCursors.click : null,
    );

abstract final class TextBlockUtils {
  /// Get the horizontalSpacing using the default
  /// implementation provided by [Flutter Quill]
  static HorizontalSpacing defaultIndentWidthBuilder(
      Block block,
      BuildContext context,
      int count,
      LeadingBlockNumberPointWidth numberPointWidthBuilder) {
    final defaultStyles = QuillStyles.getStyles(context, false)!;
    final fontSize = defaultStyles.paragraph?.style.fontSize ?? 16;
    final attrs = block.style.attributes;

    final indent = attrs[Attribute.indent.key];
    var extraIndent = 0.0;
    if (indent != null && indent.value != null) {
      extraIndent = fontSize * indent.value;
    }

    if (attrs.containsKey(Attribute.blockQuote.key)) {
      return HorizontalSpacing(fontSize + extraIndent, 0);
    }

    var baseIndent = 0.0;

    if (attrs.containsKey(Attribute.list.key)) {
      baseIndent = fontSize * 2;
      if (attrs[Attribute.list.key] == Attribute.ol) {
        baseIndent = numberPointWidthBuilder(fontSize, count);
      } else if (attrs.containsKey(Attribute.codeBlock.key)) {
        baseIndent = numberPointWidthBuilder(fontSize, count);
      }
    }

    return HorizontalSpacing(baseIndent + extraIndent, 0);
  }

  /// Get the width for the number point leading using the default
  /// implementation provided by [Flutter Quill]
  static double defaultNumberPointWidthBuilder(double fontSize, int count) {
    final length = '$count'.length;
    switch (length) {
      case 1:
      case 2:
        return fontSize * 2;
      default:
        // 3 -> 2.5
        // 4 -> 3
        // 5 -> 3.5
        return fontSize * (length - (length - 2) / 2);
    }
  }
}
