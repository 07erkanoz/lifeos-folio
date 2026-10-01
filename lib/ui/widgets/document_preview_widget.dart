import 'package:flutter/material.dart';

import '../../models/evrak_file.dart';
import '../../services/editor/text_anchor.dart';
import '../../services/preview/preview_cache.dart';
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
      return Column(
        children: [
          if (model.metadata['previewNote'] case final String note)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(note, style: const TextStyle(fontSize: 12)),
            ),
          SignatureBanner(model: model),
          Expanded(
            child: PdfViewerWidget(
              bytes: bytes,
              onPastEnd: widget.onPastEnd,
              chrome: widget.chrome,
              onEditAt: widget.onEditAt,
            ),
          ),
        ],
      );
    },
  );
}
