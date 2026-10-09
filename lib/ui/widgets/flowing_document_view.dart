import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../models/document_model.dart';
import '../../services/editor/doc_delta_map.dart';
import '../../services/fonts/document_fonts.dart';
import 'editor_image_embed.dart';
import 'editor_line_layout.dart';
import 'editor_tab_spans.dart';
import 'editor_table_embed.dart';
import 'editor_units.dart';

/// A document read on a phone (UYGULAMAPLANI §13): its text flowing at the
/// screen's width, a little larger, as the editor's mobile view shows it,
/// but read-only. The document is the preview's own; nothing is changed,
/// and the page view is one tap away.
class FlowingDocumentView extends StatefulWidget {
  const FlowingDocumentView({
    super.key,
    required this.model,
    this.live,
    this.scale = zoom,
    this.editable = false,
  });

  /// A live document written here in turn: touched, given the keyboard,
  /// its caret shown; the controller says whether it may be changed.
  final bool editable;

  final DocModel model;

  /// A document shown as another device writes it: its controller, kept
  /// up from outside, and the blocks its embeds point at. [model] is not
  /// read then.
  final ({QuillController controller, List<DocBlock> Function() blocks})? live;

  /// How much larger than the page the text is shown.
  final double scale;

  /// The text larger, as a phone's reader expects; the editor's too.
  static const zoom = 1.3;

  @override
  State<FlowingDocumentView> createState() => _FlowingDocumentViewState();
}

class _FlowingDocumentViewState extends State<FlowingDocumentView> {
  late QuillController _own;
  late List<DocBlock> _kept;
  QuillController get _controller => widget.live?.controller ?? _own;
  List<DocBlock> get _blocks => widget.live?.blocks() ?? _kept;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(FlowingDocumentView old) {
    super.didUpdateWidget(old);
    if (widget.live == null && !identical(old.model, widget.model)) {
      _own.dispose();
      _open();
    }
  }

  void _open() {
    if (widget.live != null) {
      _kept = const [];
      _own = QuillController.basic();
      return;
    }
    final mapped = DocDeltaMap.modeldenDelta(widget.model);
    _kept = mapped.korunanlar;
    _own = QuillController(
      document: Document.fromDelta(mapped.delta),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
  }

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  static TextStyle get _text => TextStyle(
    color: Colors.black,
    fontFamily: DocumentFonts.family('Times New Roman'),
    fontSize: 12,
    height: 1.15,
  );

  @override
  Widget build(BuildContext context) {
    const gutter = 14.0;
    return LayoutBuilder(
      builder: (context, box) {
        final lineWidth =
            (box.maxWidth - 2 * gutter) /
            widget.scale /
            EditorUnits.pixelsPerPoint;
        return ColoredBox(
          color: Colors.white,
          child: SingleChildScrollView(
            key: const ValueKey('preview-flowing'),
            padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 96),
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(widget.scale)),
              child: Theme(
                data: Theme.of(context).copyWith(
                  brightness: Brightness.light,
                  textTheme: Theme.of(context).textTheme
                      .apply(bodyColor: Colors.black),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.black),
                  // Shown, not to be taken: one watching a document shared
                  // live can neither touch it nor give it the keyboard, so
                  // cannot select or copy it; the writer's selection, set
                  // from outside, still shows.
                  child: ExcludeFocus(
                    excluding: widget.live != null && !widget.editable,
                    child: IgnorePointer(
                      ignoring: widget.live != null && !widget.editable,
                      child: QuillEditor.basic(
                        controller: _controller,
                        config: QuillEditorConfig(
                          showCursor: widget.editable,
                          textSpanBuilder: EditorTabSpans.builder(
                            pageWidth: lineWidth,
                          ),
                          lineLayoutBuilder: EditorLineLayout.builder(
                            pageWidth: lineWidth,
                          ),
                          embedBuilders: [
                            EditorImageEmbed(),
                            EditorTableEmbed(
                              blocks: () => _blocks,
                              onChanged: (_, _) {},
                              onFocus: (_) {},
                              onDelete: (_) {},
                              onCellsGone: () {},
                              onPointerInside: () {},
                            ),
                          ],
                          customStyles: DefaultStyles(
                            paragraph: DefaultTextBlockStyle(
                              _text,
                              const HorizontalSpacing(0, 0),
                              const VerticalSpacing(0, 0),
                              const VerticalSpacing(0, 0),
                              null,
                            ),
                            lists: DefaultListBlockStyle(
                              _text,
                              const HorizontalSpacing(0, 0),
                              const VerticalSpacing(0, 0),
                              const VerticalSpacing(0, 0),
                              null,
                              null,
                            ),
                            indent: DefaultTextBlockStyle(
                              _text,
                              const HorizontalSpacing(0, 0),
                              const VerticalSpacing(0, 0),
                              const VerticalSpacing(0, 0),
                              null,
                            ),
                          ),
                          customStyleBuilder: (attribute) =>
                              attribute.key == 'font'
                              ? TextStyle(
                                  fontFamily: DocumentFonts.family(
                                    attribute.value as String?,
                                  ),
                                )
                              : const TextStyle(),
                          scrollable: false,
                          expands: false,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "Sayfa görünümü" on the flowing view, "Mobil görünüm" on the pages: the
/// switch the editor and the preview share on a phone.
class ViewSwitchChip extends StatelessWidget {
  const ViewSwitchChip({super.key, required this.flowing, required this.onTap});

  final bool flowing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                flowing ? Icons.description_outlined : Icons.smartphone,
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                flowing ? 'Sayfa görünümü' : 'Mobil görünüm',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
