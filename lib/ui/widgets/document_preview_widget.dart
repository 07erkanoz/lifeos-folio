import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../models/evrak_file.dart';
import '../../services/editor/text_anchor.dart';
import '../../services/preview/preview_cache.dart';
import 'flowing_document_view.dart';
import 'pdf_viewer_widget.dart';
import 'signature_banner.dart';

class DocumentPreviewWidget extends StatefulWidget {
  final EvrakFile file;

  /// Passed through to the page viewer, for a swipe that runs past the last
  /// page of this document.
  final void Function(bool forward)? onPastEnd;

  /// Passed through as well; in full screen the page takes the whole screen.
  final bool chrome;

  /// Passed through too: a double-click on a page opens the editor there.
  final ValueChanged<TextAnchor>? onEditAt;

  const DocumentPreviewWidget({
    super.key,
    required this.file,
    this.onPastEnd,
    this.chrome = true,
    this.onEditAt,
  });
  @override
  State<DocumentPreviewWidget> createState() => _DocumentPreviewWidgetState();
}

class _DocumentPreviewWidgetState extends State<DocumentPreviewWidget> {
  late Future<DocumentPreview> _preview;

  /// The reader's choice of view; null for the width's: on a phone the
  /// text flows at its width (UYGULAMAPLANI §13), on a computer the pages.
  bool? _flowChoice;

  /// The view's switch, out of the text's way while it is read downwards
  /// and back as soon as it is scrolled up.
  bool _switchShown = true;

  bool _scrolled(UserScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final shown = switch (n.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _switchShown,
    };
    if (shown != _switchShown) setState(() => _switchShown = shown);
    return false;
  }

  Future<DocumentPreview> _load() => PreviewCache.load(widget.file);
  @override
  void initState() {
    super.initState();
    _preview = _load();
  }

  @override
  void didUpdateWidget(covariant DocumentPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) _preview = _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DocumentPreview>(
    future: _preview,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: SelectableText('Önizleme açılamadı: ${snapshot.error}'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final model = snapshot.data!.model;
      final bytes = snapshot.data!.pdfBytes;
      final width = MediaQuery.sizeOf(context).width;
      final flows = _flowChoice ?? width < 600;
      return Column(
        children: [
          if (model.metadata['previewNote'] case final String note)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(note, style: const TextStyle(fontSize: 12)),
            ),
          if (widget.chrome) SignatureBanner(model: model),
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              onNotification: _scrolled,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (flows)
                    FlowingDocumentView(model: model)
                  else
                    PdfViewerWidget(
                      bytes: bytes,
                      onPastEnd: widget.onPastEnd,
                      chrome: widget.chrome,
                      onEditAt: widget.onEditAt,
                    ),
                  // A phone's view and the page's, one tap apart.
                  if (width < 900)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IgnorePointer(
                        ignoring: !_switchShown,
                        child: AnimatedSlide(
                          offset: _switchShown
                              ? Offset.zero
                              : const Offset(0, -1.6),
                          duration: const Duration(milliseconds: 180),
                          child: AnimatedOpacity(
                            opacity: _switchShown ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: ViewSwitchChip(
                              key: const ValueKey('preview-view-switch'),
                              flowing: flows,
                              onTap: () => setState(() => _flowChoice = !flows),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
