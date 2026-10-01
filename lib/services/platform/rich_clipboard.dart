import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/document_model.dart';
import '../editor/doc_model_json.dart';
import '../html/html_writer.dart';
import '../preview/structured_reader.dart';
import '../rtf/rtf_reader.dart';
import '../rtf/rtf_writer.dart';
import 'uyap_clipboard.dart';

import 'package:flutter/services.dart';
import 'package:quill_native_bridge/quill_native_bridge.dart';

/// Reads the rich representation applications such as Word and LibreOffice
/// place beside plain text on the system clipboard, and writes Folio's own.
abstract final class RichClipboard {
  static const _desktop = MethodChannel('lifeos_evrak/rich_clipboard');
  static final _bridge = QuillNativeBridge();

  /// The copy still on its way to the clipboard, which a paste waits for:
  /// Ctrl+C then Ctrl+V pressed quickly would otherwise read what was there
  /// before.
  static Future<void>? _writing;

  static bool get _native =>
      Platform.isLinux ||
      Platform.isWindows ||
      Platform.isMacOS ||
      Platform.isAndroid;

  static Future<DocModel?> model() async {
    await _writing;
    if (_native) {
      try {
        final data = await _desktopData();
        debugPrint(
          'Folio paste: native clipboard returned, '
          'representations=${(data?['candidates'] as List?)?.length ?? (data == null ? 0 : 1)}',
        );
        if (data != null) return await compute(decode, data);
        if (Platform.isAndroid) return null;
      } on MissingPluginException {
        // Older runners still have the HTML-only channel.
      }
    }
    final source = await html();
    if (source == null) return null;
    return compute(decode, {
      'format': 'html',
      'data': Uint8List.fromList(utf8.encode(source)),
    });
  }

  /// Puts [model] on the clipboard as HTML, RTF and [text], with Folio's own
  /// copy of it inside the HTML (see [HtmlWriter.folioMeta]).
  ///
  /// Each program takes the richest form it reads: Word and LibreOffice the
  /// RTF or the HTML, a browser or a mail the HTML, a terminal the text, and
  /// Folio itself the model, with nothing lost.
  static Future<void> write(DocModel model, String text) {
    final future = _write(model, text);
    _writing = future.catchError((Object _) {});
    return future;
  }

  static Future<void> _write(DocModel model, String text) async {
    if (!_native) {
      await Clipboard.setData(ClipboardData(text: text));
      return;
    }
    try {
      final representations = await compute(encode, (model: model, text: text));
      await _desktop.invokeMethod<void>('setRichData', representations);
    } catch (error) {
      // An older runner, or a clipboard another program holds: the text at
      // least still gets there.
      debugPrint('Rich clipboard write failed: $error');
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  /// What [write] hands the platform, built away from the UI isolate: a
  /// whole document's HTML and RTF take a moment.
  static Map<String, Object> encode(({DocModel model, String text}) request) {
    final folio = base64Encode(
      utf8.encode(jsonEncode(DocModelJson.encode(request.model))),
    );
    final html = HtmlWriter.document(request.model, folio: folio);
    return {
      'text': request.text,
      'html': Platform.isWindows
          ? HtmlWriter.cfHtml(html)
          : Uint8List.fromList(utf8.encode(html)),
      'rtf': Uint8List.fromList(RtfWriter.writeBytes(request.model)),
    };
  }

  static Future<Map<String, dynamic>?> _desktopData() async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _desktop.invokeMapMethod<String, dynamic>('getRichData');
      } on PlatformException catch (error) {
        if (error.code != 'clipboard_busy' || attempt >= 4) rethrow;
        // Word may still be finishing its delayed clipboard rendering.
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  }

  static DocModel? decode(Map<String, dynamic> data) {
    final candidates = [
      for (final candidate in data['candidates'] as List? ?? [data])
        Map<String, dynamic>.from(candidate as Map),
    ];
    // Folio's own copy first: it is the model itself. Then UYAP's, which
    // carries everything UYAP holds. Then RTF, which Word and LibreOffice
    // write with tab stops, exact indents, line spacing and list numbering;
    // measured against 40 documents copied out of LibreOffice, their HTML
    // lost line spacing on 8% of paragraphs and spacing after on 10%, the
    // RTF on 2%. HTML last, from what gives nothing else: a browser, Google
    // Docs.
    int rank(Map<String, dynamic> candidate) => switch (candidate['format']) {
      'html' when _carriesFolio(candidate['data']) => 0,
      'uyap' => 1,
      'rtf' => 2,
      'html' => 3,
      _ => 4,
    };
    final ordered = [for (final (i, c) in candidates.indexed) (rank(c), i, c)]
      ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    for (final (_, _, candidate) in ordered) {
      try {
        final model = _decodeRepresentation(candidate);
        if (model != null &&
            model.blocks.any(
              (block) =>
                  block.plainText.trim().isNotEmpty ||
                  block.table != null ||
                  block.imageBase64 != null,
            )) {
          return model;
        }
      } catch (error) {
        debugPrint('Clipboard representation rejected: $error');
      }
    }
    return null;
  }

  static DocModel? _decodeRepresentation(Map<String, dynamic> data) {
    final bytes = data['data'] as Uint8List;
    switch (data['format']) {
      case 'uyap':
        return UyapClipboard.read(bytes);
      case 'rtf':
        if (!RtfReader.looksLikeRtf(bytes)) return null;
        var end = bytes.length;
        while (end > 0 && bytes[end - 1] == 0) {
          end--;
        }
        return RtfReader.readClipboard(Uint8List.sublistView(bytes, 0, end));
      case 'html':
        var source = _cfHtml(bytes) ?? '';
        if (source.isNotEmpty) {
          // CF_HTML uses byte offsets, not Dart string offsets.
        } else if (bytes.length >= 2 &&
            ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
                (bytes[0] == 0xfe && bytes[1] == 0xff) ||
                bytes[1] == 0)) {
          final bigEndian = bytes[0] == 0xfe;
          final offset = bytes[0] == 0xff || bytes[0] == 0xfe ? 2 : 0;
          final view = ByteData.sublistView(bytes);
          source = String.fromCharCodes([
            for (var i = offset; i + 1 < bytes.length; i += 2)
              view.getUint16(i, bigEndian ? Endian.big : Endian.little),
          ]);
        } else {
          source = utf8.decode(bytes, allowMalformed: true);
        }
        source = source.replaceAll('\u0000', '');
        // Windows CF_HTML wraps the HTML document with byte-offset headers.
        if (source.startsWith('Version:')) {
          final start = source.indexOf('<');
          if (start >= 0) source = source.substring(start);
        }
        return folio(source) ?? StructuredReader.clipboardHtml(source);
      default:
        return null;
    }
  }

  /// Whether an HTML representation holds Folio's own copy, looked for in
  /// its raw bytes before anything is decoded.
  static bool _carriesFolio(Object? data) {
    if (data is! Uint8List) return false;
    final head = latin1.decode(
      data.length > 8192 ? Uint8List.sublistView(data, 0, 8192) : data,
      allowInvalid: true,
    );
    return head.contains('name="${HtmlWriter.folioMeta}"');
  }

  static final _folioMeta = RegExp(
    '<meta\\s+name="${HtmlWriter.folioMeta}"\\s+content="([A-Za-z0-9+/=]+)"',
  );

  /// Folio's own copy of what was copied, when Folio copied it.
  static DocModel? folio(String html) {
    final match = _folioMeta.firstMatch(html);
    if (match == null) return null;
    try {
      return DocModelJson.decode(
        jsonDecode(utf8.decode(base64Decode(match.group(1)!))),
      );
    } on FormatException {
      return null;
    }
  }

  static String? _cfHtml(Uint8List bytes) {
    final header = latin1.decode(bytes.take(4096).toList());
    if (!header.startsWith('Version:')) return null;
    int? offset(String key) => int.tryParse(
      RegExp('(?:^|[\\r\\n])$key:[ \\t]*(-?[0-9]+)')
              .firstMatch(header)
              ?.group(1) ??
          '',
    );
    final start = offset('StartFragment');
    final end = offset('EndFragment');
    if (start == null ||
        end == null ||
        start < 0 ||
        end < start ||
        end > bytes.length) {
      return null;
    }
    final htmlStart = offset('StartHTML');
    final htmlEnd = offset('EndHTML');
    String part(int from, int to) => utf8
        .decode(bytes.sublist(from, to), allowMalformed: true)
        .replaceAll(RegExp(r'<!--\s*(?:Start|End)Fragment\s*-->'), '');
    final context =
        htmlStart != null &&
        htmlEnd != null &&
        htmlStart >= 0 &&
        htmlStart <= start &&
        htmlEnd >= end &&
        htmlEnd <= bytes.length;
    return '${context ? part(htmlStart, start) : ''}'
        '<!--StartFragment-->${part(start, end)}<!--EndFragment-->'
        '${context ? part(end, htmlEnd) : ''}';
  }

  static Future<String?> html() async {
    try {
      final value = Platform.isLinux
          ? await _desktop.invokeMethod<String>('getHtml')
          : await _nativeHtml();
      if (value == null || value.trim().isEmpty) return null;
      return value;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<String?> _nativeHtml() async {
    if (!await _bridge.isSupported(QuillNativeBridgeFeature.getClipboardHtml)) {
      return null;
    }
    return _bridge.getClipboardHtml();
  }
}
