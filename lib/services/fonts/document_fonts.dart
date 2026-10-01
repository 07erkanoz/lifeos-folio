import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../models/document_model.dart';
import '../layout/page_numbers.dart';
import 'font_line_metrics.dart';
import 'system_font_catalog.dart';

/// Original family names are retained in saved document data.
class DocumentFonts {
  static const faces = ['Regular', 'Bold', 'Italic', 'BoldItalic'];
  static final _data = <String, Future<ByteData>>{};
  static final _registered = <String, String>{};
  static final _registering = <String, Future<void>>{};
  static Map<String, Map<String, String>> _catalog = {};
  static final _metrics = <String, FontLineMetrics>{};

  /// Row height of [name] as the page draws it, read from the font that was
  /// actually loaded for it — a fallback has its own. Known once any of its
  /// faces has loaded; until then the common Times/Arial value.
  static FontLineMetrics lineMetrics(String? name) =>
      _metrics[fontKey(name ?? 'Times New Roman')] ?? FontLineMetrics.common;

  static Future<void> prepare() async {
    _catalog = await SystemFontCatalog.load();
  }

  static List<String> get families =>
      ({'Times New Roman', 'Arial', 'Courier New', ..._catalog.keys}.toList()
        ..sort());
  static Set<String> modelFamilies(DocModel model) {
    final names = <String>{'Times New Roman'};
    void collect(List<DocBlock> blocks) {
      for (final block in blocks) {
        for (final span in block.spans) {
          if (span.fontFamily != null) names.add(span.fontFamily!);
        }
        if (block.table != null) {
          for (final row in block.table!.rows) {
            for (final cell in row.cells) {
              collect(cell.blocks);
            }
          }
        }
      }
    }

    for (final style in model.styles) {
      names.add(style.family);
    }
    collect(model.blocks);
    for (final blocks in model.pageRegions.values) {
      collect(blocks);
    }
    // The page numbers' own font, which nothing in the text may use.
    final regionAttrs = model.metadata['pageRegionAttrs'];
    if (regionAttrs is Map) {
      for (final attrs in regionAttrs.values) {
        final numbering = PageNumbering.parse(attrs is Map ? attrs : null);
        if (numbering != null) names.add(numbering.fontFace);
      }
    }
    return names;
  }

  static Future<ByteData> loadFace(String name, String style) async {
    final key = '${fontKey(name)}-$style';
    try {
      final data = await _data.putIfAbsent(key, () => _load(name, style));
      if (style == 'Regular' || !_metrics.containsKey(fontKey(name))) {
        final metrics = FontLineMetrics.read(data);
        if (metrics != null) _metrics[fontKey(name)] = metrics;
      }
      return data;
    } catch (_) {
      _data.remove(key);
      rethrow;
    }
  }

  static Future<ByteData> _load(String name, String style) async {
    await prepare();
    Future<ByteData?> fromSystem(String family) async {
      final entry = _catalog.entries
          .where((e) => fontKey(e.key) == fontKey(family))
          .firstOrNull;
      final path = entry?.value[style];
      if (path == null) return null;
      try {
        return ByteData.sublistView(await File(path).readAsBytes());
      } on FileSystemException {
        return null;
      }
    }

    final exact = await fromSystem(name);
    if (exact != null) return exact;
    final fallback = fallbackFamily(name);
    final asset = 'fonts/pdf/$fallback-$style.ttf';
    try {
      return await rootBundle.load(asset);
    } catch (_) {
      // A damaged/moved asset bundle must not hide installed system fonts.
      for (final substitute in [
        fallback.replaceAll('Liberation', 'Liberation '),
        if (fallback == 'LiberationSerif') ...[
          'Times New Roman',
          'DejaVu Serif',
        ],
        if (fallback == 'LiberationSans') ...['Arial', 'DejaVu Sans', 'Roboto'],
        if (fallback == 'LiberationMono') ...[
          'Courier New',
          'DejaVu Sans Mono',
        ],
      ]) {
        final bytes = await fromSystem(substitute);
        if (bytes != null) return bytes;
      }
      // Also allow a valid desktop bundle when the engine asset lookup failed.
      final path = p.join(
        p.dirname(Platform.resolvedExecutable),
        'data',
        'flutter_assets',
        asset,
      );
      if (await File(path).exists()) {
        return ByteData.sublistView(await File(path).readAsBytes());
      }
      rethrow;
    }
  }

  static Future<void> loadEditorFamilies(Iterable<String> names) async {
    await Future.wait(
      names.map((name) async {
        final key = fontKey(name);
        if (_registered.containsKey(key)) return;
        try {
          await _registering.putIfAbsent(key, () async {
            final alias = 'LifeOS/$key';
            final loader = FontLoader(alias);
            for (final face in faces) {
              loader.addFont(loadFace(name, face));
            }
            await loader.load();
            _registered[key] = alias;
          });
        } finally {
          _registering.remove(key);
        }
      }),
    );
  }

  static String family(String? name) =>
      _registered[fontKey(name ?? 'Times New Roman')] ?? fallbackFamily(name);

  static String fallbackFamily(String? name) {
    final value = (name ?? '').toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    if (['courier', 'consolas', 'mono'].any(value.contains)) {
      return 'LiberationMono';
    }
    if ([
      'arial',
      'helvetica',
      'calibri',
      'sans',
      'segoe',
      'verdana',
      'tahoma',
      'dialog',
    ].any(value.contains)) {
      return 'LiberationSans';
    }
    return 'LiberationSerif';
  }
}
