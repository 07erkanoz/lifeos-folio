import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../services/fonts/document_fonts.dart';
import '../../services/layout/page_numbers.dart';
import 'editor_image_embed.dart';
import 'editor_line_layout.dart';
import 'editor_tab_spans.dart';

/// The header or footer strip, edited in place at the top or bottom of the
/// page.
///
/// Courts read the header: which chamber, which case number, which page. The
/// editor could carry one through a save but never show it, so the one line of
/// a document that names the case was the one line nobody could correct.
///
/// It is drawn where UYAP and the printed page draw it, on every page: in the
/// margin, at its offset from the edge, and as tall as its own text, which
/// is laid out as the preview lays it out. Nothing else takes room: the label
/// and the line under a header are drawn outside it, and the button that
/// takes it away floats over the page while it has the cursor.
class EditorRegionBand extends StatefulWidget {
  final QuillController controller;
  final FocusNode? focusNode;

  /// Header bands sit above the body, footers below; the line and the label
  /// follow.
  final bool isHeader;
  final bool focused;
  final VoidCallback onRemove;

  /// The text area's width in points, which the band's lines break at.
  final double pageWidth;

  /// The page's number and how it is drawn, when the band numbers pages.
  final PageNumbering? numbering;
  final String? numberLabel;

  /// Why the band does not print on this page, which shows it faded.
  final String? note;

  const EditorRegionBand({
    super.key,
    required this.controller,
    required this.isHeader,
    required this.focused,
    required this.onRemove,
    required this.pageWidth,
    this.focusNode,
    this.numbering,
    this.numberLabel,
    this.note,
  });

  static const _labelStyle = TextStyle(
    fontSize: 7.5,
    height: 1,
    color: Color(0xFF7A8396),
    letterSpacing: .2,
  );

  @override
  State<EditorRegionBand> createState() => _EditorRegionBandState();
}

class _EditorRegionBandState extends State<EditorRegionBand> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _portal.show();
    });
  }

  @override
  Widget build(BuildContext context) {
    final header = widget.isHeader;
    final editor = QuillEditor.basic(
      controller: widget.controller,
      focusNode: widget.focusNode,
      config: QuillEditorConfig(
        embedBuilders: [EditorImageEmbed()],
        lineLayoutBuilder: EditorLineLayout.builder(
          pageWidth: widget.pageWidth,
        ),
        textSpanBuilder: EditorTabSpans.builder(pageWidth: widget.pageWidth),
        customStyles: DefaultStyles(
          paragraph: DefaultTextBlockStyle(
            TextStyle(
              color: Colors.black,
              fontFamily: DocumentFonts.family('Times New Roman'),
              fontSize: 12,
              height: 1.15,
            ),
            const HorizontalSpacing(0, 0),
            const VerticalSpacing(0, 0),
            const VerticalSpacing(0, 0),
            null,
          ),
          lists: DefaultListBlockStyle(
            TextStyle(
              color: Colors.black,
              fontFamily: DocumentFonts.family('Times New Roman'),
              fontSize: 12,
              height: 1.15,
            ),
            const HorizontalSpacing(0, 0),
            const VerticalSpacing(0, 0),
            const VerticalSpacing(0, 0),
            null,
            null,
          ),
          // Nor between the lines of an indented block, which Quill spaces
          // 6 apart by default: the page does not.
          indent: DefaultTextBlockStyle(
            TextStyle(
              color: Colors.black,
              fontFamily: DocumentFonts.family('Times New Roman'),
              fontSize: 12,
              height: 1.15,
            ),
            const HorizontalSpacing(0, 0),
            const VerticalSpacing(0, 0),
            const VerticalSpacing(0, 0),
            null,
          ),
        ),
        customStyleBuilder: (attribute) => attribute.key == 'font'
            ? TextStyle(
                fontFamily: DocumentFonts.family(attribute.value as String?),
              )
            : const TextStyle(),
        // Not over a page number, which an empty band is often there for.
        placeholder: widget.numberLabel != null
            ? null
            : header
            ? 'Üst bilgi — her sayfanın başında yazılır'
            : 'Alt bilgi — her sayfanın sonunda yazılır',
        scrollable: false,
        expands: false,
        padding: EdgeInsets.zero,
      ),
    );
    final line = widget.focused
        ? const Color(0xFF9AA6BF)
        : const Color(0xFFDCE0E8);
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => widget.focused
          ? Align(
              alignment: Alignment.topLeft,
              child: CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                // Beside the band's far end, in the margin.
                targetAnchor: header
                    ? Alignment.topRight
                    : Alignment.bottomRight,
                followerAnchor: header
                    ? Alignment.bottomRight
                    : Alignment.topRight,
                // Only offered while the band has the cursor: an X floating
                // over every document would be one stray click away from
                // deleting the header.
                child: Material(
                  color: Colors.white,
                  elevation: 1,
                  borderRadius: BorderRadius.circular(3),
                  child: InkWell(
                    onTap: widget.onRemove,
                    borderRadius: BorderRadius.circular(3),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'KALDIR',
                        style: EditorRegionBand._labelStyle,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
      child: CompositedTransformTarget(
        link: _link,
        child: _faded(
          Stack(
            clipBehavior: Clip.none,
            children: [
              editor,
              if (widget.numbering case final numbering?)
                if (widget.numberLabel case final label?)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const ValueKey('page-number'),
                        painter: _PageNumberPainter(numbering, label),
                      ),
                    ),
                  ),
              // The label and the line, outside the band: painted, not laid
              // out, so the band is as tall as its text.
              Positioned(
                left: 0,
                right: 0,
                top: header ? null : -3,
                bottom: header ? -3 : null,
                height: 1,
                child: IgnorePointer(child: ColoredBox(color: line)),
              ),
              Positioned(
                left: 0,
                top: header ? -10 : null,
                bottom: header ? null : -10,
                child: IgnorePointer(
                  child: Text(
                    [
                      header ? 'ÜST BİLGİ' : 'ALT BİLGİ',
                      ?widget.note,
                    ].join(' · '),
                    style: EditorRegionBand._labelStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _faded(Widget child) =>
      widget.note == null ? child : Opacity(opacity: .4, child: child);
}

/// The page number over a band, placed as UYAP places it (see
/// [PageNumbering.place]).
class _PageNumberPainter extends CustomPainter {
  _PageNumberPainter(this.numbering, this.label);

  final PageNumbering numbering;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Color(numbering.color),
          fontFamily: DocumentFonts.family(numbering.fontFace),
          fontSize: numbering.fontSize,
          fontWeight: numbering.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: numbering.italic ? FontStyle.italic : FontStyle.normal,
          fontFeatures: const [FontFeature.disable('kern')],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = numbering.place(
      width: size.width,
      height: size.height,
      advance: painter.width,
      ink: numbering.ink(label),
    );
    painter
      ..paint(
        canvas,
        Offset(
          at.x,
          at.baseline -
              painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        ),
      )
      ..dispose();
  }

  @override
  bool shouldRepaint(_PageNumberPainter old) =>
      old.label != label || old.numbering != numbering;
}
