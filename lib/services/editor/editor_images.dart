import 'dart:typed_data';

import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'doc_delta_map.dart';

/// Putting a picture into a document.
///
/// The bytes travel inside the document rather than as a link to a file on
/// disk: a document is mailed, signed and archived on its own, and a picture
/// that lived beside it would arrive missing.
class EditorImages {
  /// What a picture may be printed at. An A4 page is 595 pt wide and the
  /// template's margins take about 145 pt of that, so this is the text column:
  /// a photograph from a phone would otherwise arrive ten pages wide.
  static const columnWidth = 450.0;

  /// A picture larger than this makes the document slow to save and, once
  /// base64'd into UDF, roughly a third larger again on disk.
  static const maxBytes = 12 * 1024 * 1024;

  /// What Leptonica, the PDF writer and Word all understand between them.
  static const extensions = [
    'png',
    'jpg',
    'jpeg',
    'gif',
    'bmp',
    'webp',
    'tif',
    'tiff',
  ];

  static String mimeFor(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'tif' || 'tiff' => 'image/tiff',
      'gif' => 'image/gif',
      'bmp' => 'image/bmp',
      'webp' => 'image/webp',
      _ => 'image/png',
    };
  }

  /// Printed size in points for a picture [pixelWidth] by [pixelHeight],
  /// scaled down to fit the column but never scaled up: a small scanned seal
  /// blown up to page width would only look worse.
  static ({double width, double height}) fit(
    int pixelWidth,
    int pixelHeight, {
    double column = columnWidth,
  }) {
    // Screen pixels at 96 dpi against the 72 pt inch the document is measured
    // in; this is the size the picture has on screen, which is what someone
    // choosing it expects to see on the page.
    final width = pixelWidth * 72 / 96;
    final height = pixelHeight * 72 / 96;
    if (width <= column || width <= 0) {
      return (width: width, height: height);
    }
    return (width: column, height: height * column / width);
  }

  /// Size of the picture in [bytes], or null when nothing can decode it.
  /// Reads the header only — a scan can be tens of megabytes.
  static ({double width, double height})? measure(Uint8List bytes) {
    try {
      final info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info == null || info.width <= 0 || info.height <= 0) return null;
      return fit(info.width, info.height);
    } catch (_) {
      return null;
    }
  }

  /// Places the picture at the cursor, on a line of its own.
  ///
  /// Its own line because that is what the document formats underneath can
  /// hold: UDF and DOCX each give an image a paragraph. Inserting it inside a
  /// sentence would look right until the document was saved and reopened.
  static void insert(
    QuillController controller, {
    required String base64Data,
    required String mime,
    required ({double width, double height}) size,
  }) => EditorEmbeds.insertOnOwnLine(
    controller,
    BlockEmbed.image(DocDeltaMap.imageUri(base64Data, mime)),
    lineAttribute: Attribute(DocDeltaMap.kImageAttr, AttributeScope.block, {
      'w': size.width,
      'h': size.height,
    }),
  );
}

/// Putting something that is not text into a document.
class EditorEmbeds {
  /// Places [embed] at the cursor, on a line of its own, and leaves the cursor
  /// after it.
  ///
  /// Its own line because that is what the document formats underneath can
  /// hold: UDF and DOCX each give a picture or a table a paragraph. Inserting
  /// one inside a sentence would look right until the document was saved and
  /// reopened.
  static void insertOnOwnLine(
    QuillController controller,
    Embeddable embed, {
    Attribute? lineAttribute,
  }) {
    final selection = controller.selection;
    var index = selection.baseOffset;
    final length = selection.extentOffset - index;
    if (index < 0) index = controller.document.length - 1;

    final text = controller.document.toPlainText();
    // Break the line first when the cursor sits in the middle of a sentence.
    if (index > 0 && index <= text.length && text[index - 1] != '\n') {
      controller.replaceText(index, length, '\n', null);
      index += 1;
      controller.replaceText(index, 0, embed, null);
    } else {
      controller.replaceText(index, length, embed, null);
    }

    // The line has to end after it, or whatever follows shares a line with it
    // and the save turns that into two blocks.
    controller.replaceText(index + 1, 0, '\n', null);
    if (lineAttribute != null) {
      controller.formatText(index, 1, lineAttribute);
    }
    controller.updateSelection(
      TextSelection.collapsed(offset: index + 2),
      ChangeSource.local,
    );
  }
}
