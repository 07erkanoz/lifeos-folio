import 'package:flutter/material.dart';

import '../../models/evrak_file.dart';
import '../../services/editor/text_anchor.dart';
import 'data_preview_widget.dart';
import 'document_preview_widget.dart';
import 'image_viewer_widget.dart';
import 'pdf_viewer_widget.dart';
import 'spreadsheet_viewer.dart';
import 'tiff_viewer_widget.dart';
import '../../services/platform/app_language.dart';

/// A document shown, from its path, by the viewer its kind needs: a PDF on
/// its own pages, a UDF or Word file laid out as it prints, a scan page by
/// page. What a UYAP document is shown in, beside the page being written
/// or in a window of its own.
class FilePreview extends StatelessWidget {
  const FilePreview({
    super.key,
    required this.path,
    this.chrome = true,
    this.onEditAt,
    this.onCropped,
  });

  final String path;
  final bool chrome;

  /// A text document's page double-clicked: opened to be written in, at
  /// the place clicked.
  final ValueChanged<TextAnchor>? onEditAt;

  /// A crop of a picture written beside it.
  final ValueChanged<String>? onCropped;

  @override
  Widget build(BuildContext context) {
    final file = EvrakFile.fromPath(path);
    return switch (file.format) {
      EvrakFormat.pdf => PdfViewerWidget(
        key: ValueKey('pdf_$path'),
        filePath: path,
        chrome: chrome,
      ),
      EvrakFormat.tif => TiffViewerWidget(
        key: ValueKey('tif_$path'),
        filePath: path,
      ),
      EvrakFormat.image || EvrakFormat.svg => ImageViewerWidget(
        key: ValueKey('img_$path'),
        filePath: path,
        chrome: chrome,
        onCropped: onCropped,
      ),
      EvrakFormat.spreadsheet => SpreadsheetViewer(
        key: ValueKey('sheet_$path'),
        path: path,
      ),
      EvrakFormat.data => DataPreviewWidget(
        key: ValueKey('data_$path'),
        filePath: path,
      ),
      EvrakFormat.udf ||
      EvrakFormat.docx ||
      EvrakFormat.odt ||
      EvrakFormat.rtf ||
      EvrakFormat.doc ||
      EvrakFormat.html ||
      EvrakFormat.markdown ||
      EvrakFormat.text => DocumentPreviewWidget(
        key: ValueKey('doc_$path'),
        file: file,
        chrome: chrome,
        onEditAt: onEditAt,
      ),
      _ => Center(child: Text(context.l.viewFormatNotPreviewable)),
    };
  }
}
