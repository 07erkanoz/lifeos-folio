import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../services/editor/doc_delta_map.dart';
import '../../services/layout/image_box.dart';

/// Draws pictures inside the editor.
///
/// Images used to reach the editor as `〔Görsel 1 — kaydetmede korunur〕`: the
/// bytes were carried through a save untouched, but the writer could not see
/// what they were placing it around. Rendering them costs nothing extra — the
/// data is already in the document — and lets a picture be positioned like any
/// other paragraph.
///
/// A picture is drawn at the size the document gives it, as the preview and
/// UYAP draw it (see [ImageBox]), so a letterhead's logo is the size on the
/// screen that it prints at. Clicked, it offers the sizes a picture is
/// usually given: a share of the text column.
///
/// The value is a data URI, so nothing is read from disk while typing and the
/// document stays self-contained.
class EditorImageEmbed extends EmbedBuilder {
  @override
  String get key => BlockEmbed.imageType;

  /// Pictures sit on their own line, like a paragraph.
  @override
  bool get expanded => false;

  static Uint8List? decode(String value) {
    final comma = value.indexOf(',');
    if (!value.startsWith('data:') || comma < 0) return null;
    try {
      return base64Decode(value.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  static String encode(Uint8List bytes, String mimeType) =>
      'data:$mimeType;base64,${base64Encode(bytes)}';

  /// Each picture's pixel size, read once from its header.
  static final _pixels = Expando<({int width, int height})>();

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final bytes = decode(embedContext.node.value.data as String? ?? '');
    if (bytes == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '〔Görsel okunamadı — kaydetmede korunur〕',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }
    final node = embedContext.node;
    final pixels = _pixels[node] ??= ImageBox.pixels(bytes);
    final given = node.parent?.style.attributes[DocDeltaMap.kImageAttr]?.value;
    double? number(Object? v) => v is num ? v.toDouble() : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final column = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 450.0;
        final size = ImageBox.size(
          width: given is Map ? number(given['w']) : null,
          height: given is Map ? number(given['h']) : null,
          pixels: pixels,
          available: column,
        );
        final picture = Padding(
          padding: const EdgeInsets.only(bottom: ImageBox.border),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Image.memory(
              bytes,
              fit: BoxFit.fill,
              // A picture that cannot be decoded must not take the editor
              // down with it; the bytes are still written back on save.
              errorBuilder: (context, _, _) => const Text(
                '〔Görsel çizilemedi — kaydetmede korunur〕',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          ),
        );
        if (embedContext.readOnly || pixels == null) return picture;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTapDown: (details) => _sizeMenu(
              context,
              embedContext,
              details.globalPosition,
              pixels,
              column,
            ),
            child: picture,
          ),
        );
      },
    );
  }

  /// The sizes a picture is usually given: a share of the text column, or
  /// the size it has, a pixel to the point.
  static Future<void> _sizeMenu(
    BuildContext context,
    EmbedContext embedContext,
    Offset at,
    ({int width, int height}) pixels,
    double column,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlay.globalToLocal(at);
    final share = await showMenu<double>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        overlay.size.width - local.dx,
        overlay.size.height - local.dy,
      ),
      items: [
        const PopupMenuItem(enabled: false, child: Text('Görsel genişliği')),
        for (final (label, value) in const [
          ('Sütun genişliği', 1.0),
          ('Sütunun %75\'i', .75),
          ('Yarım sütun', .5),
          ('Sütunun %33\'ü', 1 / 3),
          ('Sütunun %25\'i', .25),
          ('Özgün boyut', 0.0),
        ])
          PopupMenuItem(value: value, child: Text(label)),
      ],
    );
    if (share == null) return;
    final natural = ImageBox.size(pixels: pixels, available: column);
    final width = share == 0 ? natural.width : column * share;
    final height = width * pixels.height / pixels.width;
    embedContext.controller.formatText(
      embedContext.node.documentOffset,
      1,
      Attribute(DocDeltaMap.kImageAttr, AttributeScope.block, {
        'w': double.parse(width.toStringAsFixed(1)),
        'h': double.parse(height.toStringAsFixed(1)),
      }),
    );
  }
}
