import 'package:flutter/material.dart';

import '../../models/evrak_file.dart';
import 'document_preview_widget.dart';
import 'image_viewer_widget.dart';
import 'pdf_viewer_widget.dart';
import 'tiff_viewer_widget.dart';

/// A document shown, from its path, by the viewer its kind needs: a PDF on
/// its own pages, a UDF or Word file laid out as it prints, a scan page by
/// page. What a UYAP document is shown in, beside the page being written
/// or in a window of its own.
class FilePreview extends StatelessWidget {
  const FilePreview({super.key, required this.path, this.chrome = true});

  final String path;
  final bool chrome;

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
      ),
      _ => const Center(child: Text('Bu biçim önizlenemiyor.')),
    };
  }
}
