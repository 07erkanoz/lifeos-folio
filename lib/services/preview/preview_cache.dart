import 'dart:io';
import 'dart:typed_data';

import '../../models/document_model.dart';
import '../../models/evrak_file.dart';
import '../convert/converter_service.dart';
import '../pdf/pdf_service.dart';

class DocumentPreview {
  final DocModel model;
  final Uint8List pdfBytes;
  const DocumentPreview(this.model, this.pdfBytes);
}

/// Small LRU of immutable source previews. Edits never enter this cache.
class PreviewCache {
  static const maxEntries = 5;
  static const maxBytes = 32 * 1024 * 1024;
  static final _entries = <String, DocumentPreview>{};
  static final _pending = <String, Future<DocumentPreview>>{};
  static int _size = 0;

  static Future<DocumentPreview> load(EvrakFile file) async {
    final stat = await File(file.path).stat();
    final key =
        '${file.path}:${stat.size}:${stat.modified.microsecondsSinceEpoch}:${stat.changed.microsecondsSinceEpoch}';
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached;
    }
    return _pending.putIfAbsent(key, () => _generate(file, key));
  }

  static Future<DocumentPreview> _generate(EvrakFile file, String key) async {
    try {
      final bytes = await File(file.path).readAsBytes();
      final model = await ConverterService.extractDocModel(bytes, file.format);
      if (model == null) {
        throw const FormatException('Belge okunamadı veya bozuk.');
      }
      final preview = DocumentPreview(
        model,
        await PdfService.modelToPdfBytes(model, title: file.baseName),
      );
      final cost = preview.pdfBytes.length + bytes.length;
      if (cost <= maxBytes) {
        // Bound both count and bytes; source size approximates retained model data.
        _entries[key] = preview;
        _costs[key] = cost;
        _size += cost;
        while (_entries.length > maxEntries || _size > maxBytes) {
          final oldest = _entries.keys.first;
          _entries.remove(oldest);
          _size -= _costs.remove(oldest)!;
        }
      }
      return preview;
    } finally {
      _pending.remove(key);
    }
  }

  static final _costs = <String, int>{};
}
