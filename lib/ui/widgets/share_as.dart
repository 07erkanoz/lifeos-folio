import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/evrak_file.dart';
import '../../services/platform/file_actions.dart';
import '../../services/preview/preview_cache.dart';
import '../../services/tiff/tiff_service.dart';
import 'share_document_dialog.dart';

/// Shares the document at [path]: as it is when it is a PDF or a picture;
/// a TIFF always as a PDF, which every phone opens; a UDF or a Word file
/// as it is ("UDF olarak") or made a PDF first ("PDF olarak"), the reader
/// choosing. On a phone the system's share screen opens, on a
/// computer Folio's own dialog.
Future<void> shareAs(BuildContext context, String path, {String? name}) async {
  final file = EvrakFile.fromPath(path);
  final asPdf = switch (file.format) {
    EvrakFormat.udf ||
    EvrakFormat.docx ||
    EvrakFormat.odt ||
    EvrakFormat.rtf ||
    EvrakFormat.doc ||
    EvrakFormat.html ||
    EvrakFormat.markdown ||
    EvrakFormat.text => true,
    _ => false,
  };
  var chosen = path;
  if (file.format == EvrakFormat.tif) {
    try {
      chosen = await _pdfOf(file, name: name);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('PDF hazırlanamadı: $e')));
      }
      return;
    }
  } else if (asPdf) {
    final kind = p.extension(path).replaceFirst('.', '').toUpperCase();
    final pick = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('share-original'),
            leading: const Icon(Icons.description_outlined),
            title: Text('$kind olarak paylaş'),
            subtitle: const Text('Dosyanın kendisi, olduğu gibi'),
            onTap: () => Navigator.pop(context, false),
          ),
          ListTile(
            key: const ValueKey('share-pdf'),
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF olarak paylaş'),
            subtitle: const Text('Her telefonda ve bilgisayarda açılır'),
            onTap: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (pick == null) return;
    if (pick) {
      try {
        chosen = await _pdfOf(file, name: name);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(SnackBar(content: Text('PDF hazırlanamadı: $e')));
        }
        return;
      }
    }
  }
  if (!context.mounted) return;
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await FileActions.invoke('share', chosen);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('Paylaşılamadı: $e')));
      }
    }
    return;
  }
  await showDialog<String>(
    context: context,
    builder: (_) => ShareDocumentDialog(path: chosen),
  );
}

/// The document made a PDF in Folio's cache, under its own name: the
/// page the preview shows, or the TIFF's pages unchanged.
Future<String> _pdfOf(EvrakFile file, {String? name}) async {
  final bytes = file.format == EvrakFormat.tif
      ? await TiffService.tiffToPdf(await File(file.path).readAsBytes())
      : (await PreviewCache.load(file)).pdfBytes;
  final folder = Directory(
    p.join((await getTemporaryDirectory()).path, 'paylas'),
  );
  await folder.create(recursive: true);
  final base = (name ?? p.basenameWithoutExtension(file.path))
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .trim();
  final out = File(p.join(folder.path, '${base.isEmpty ? 'evrak' : base}.pdf'));
  await out.writeAsBytes(bytes, flush: true);
  return out.path;
}
