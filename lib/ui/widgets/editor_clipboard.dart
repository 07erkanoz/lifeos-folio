import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../models/document_model.dart';
import '../../services/editor/doc_delta_map.dart';
import '../../services/platform/rich_clipboard.dart';

/// What a pasted table or picture can become where it lands.
enum PasteTarget {
  /// The document itself: a table stays a table, a picture a picture.
  body,

  /// A header or footer: it draws pictures; a table is set as lines of text.
  band,

  /// A table cell: text only.
  cell,
}

/// Copy and paste that keep what the text looks like, for every editor on
/// the page: the document, its header and footer, and each table cell.
///
/// UYAP's own editor pastes what comes from Word or a web page as bare text.
/// Here a paste reads the richest thing on the clipboard — UYAP's own copy,
/// then HTML or RTF, then Folio's own — through the readers that open files,
/// so fonts, sizes, colours, alignment, indents, tab stops and tables arrive
/// as they were. A copy puts the same on the clipboard for other programs:
/// HTML and RTF for Word, LibreOffice and a browser, the model itself for
/// Folio (see [RichClipboard.write]).
mixin EditorClipboard on QuillController {
  PasteTarget pasteTarget = PasteTarget.body;

  /// The tables the document keeps beside its delta, which the embeds in a
  /// copied selection point into.
  List<DocBlock> Function()? tables;

  /// Keeps the tables a paste brings and returns the index the first one got.
  int Function(List<DocBlock> tables)? keepTables;

  /// The document's own settings a copy carries along: whose tab rules its
  /// paragraphs follow, and whether a line break inside one is UYAP's.
  Map<String, dynamic> Function()? documentMetadata;

  /// Called once a rich paste is in, with what came in.
  void Function(DocModel pasted)? onPasted;

  // Quill marks these experimental; they are the one route both the keyboard
  // and the context menu take.
  @override
  // ignore: experimental_member_use
  bool clipboardSelection(bool copy) {
    if (!selection.isValid || selection.isCollapsed) return false;
    // Read before a cut takes it out.
    final model = copiedModel();
    unawaited(RichClipboard.write(model, plainText(model)));
    if (!copy) {
      if (readOnly) return false;
      final cut = selection;
      replaceText(
        cut.start,
        cut.end - cut.start,
        '',
        TextSelection.collapsed(offset: cut.start),
      );
    }
    return true;
  }

  @override
  // ignore: experimental_member_use
  Future<bool> clipboardPaste({void Function()? updateEditor}) async {
    if (readOnly || !selection.isValid) return true;
    try {
      final model = await RichClipboard.model();
      if (model != null && pasteModel(model)) {
        updateEditor?.call();
        return true;
      }
    } catch (error, stack) {
      // What cannot be read rich is still pasted, as text.
      debugPrint('Rich paste failed: $error\n$stack');
    }
    // ignore: experimental_member_use
    return super.clipboardPaste(updateEditor: updateEditor);
  }

  /// The selection as a document: the paragraphs it covers with their own
  /// layout, the tables it holds, and whether it stops short of the last
  /// paragraph's end.
  DocModel copiedModel() {
    final start = selection.start, end = selection.end;
    final whole = document.toDelta();
    final slice = whole.slice(start, end);
    final openEnd = !_endsWithBreak(slice);
    if (openEnd) {
      // The paragraph the selection stops in still has its layout, carried
      // by the line end the selection did not reach.
      slice.insert('\n', _lineAttributes(whole, end));
    }
    final source = documentMetadata?.call() ?? const {};
    return DocDeltaMap.deltadanModel(
      slice,
      korunanlar: tables?.call() ?? const [],
      metadata: {
        for (final key in const ['formatId', 'tabRules', 'defaultTabStop'])
          if (source[key] != null) key: source[key],
        'openEnd': openEnd,
      },
    );
  }

  /// What a program that takes only text gets: a table as rows of cells
  /// separated by tabs, as Word gives it, rather than the object replacement
  /// character Quill writes for anything that is not text.
  static String plainText(DocModel model) {
    final lines = <String>[];
    void add(List<DocBlock> blocks) {
      for (final block in blocks) {
        if (block.type == DocBlockType.table && block.table != null) {
          for (final row in block.table!.rows) {
            lines.add(
              [
                for (final cell in row.cells)
                  cell.blocks
                      .where((b) => b.type != DocBlockType.image)
                      .map((b) => b.plainText)
                      .join(' '),
              ].join('\t'),
            );
          }
        } else if (block.type != DocBlockType.image) {
          lines.add(block.plainText);
        }
      }
    }

    add(model.blocks);
    final text = lines.join('\n');
    return model.metadata['openEnd'] == true ? text : '$text\n';
  }

  /// Puts [model] where the selection is. Returns false when there is
  /// nothing in it to paste.
  bool pasteModel(DocModel model) {
    final blocks = pasteTarget == PasteTarget.body
        ? model.blocks
        : _flatten(model.blocks, pictures: pasteTarget == PasteTarget.band);
    if (blocks.isEmpty ||
        (blocks.length == 1 &&
            blocks.single.plainText.isEmpty &&
            blocks.single.table == null &&
            blocks.single.imageBase64 == null)) {
      return false;
    }
    final mapped = DocDeltaMap.modeldenDelta(
      DocModel(blocks: blocks, metadata: model.metadata, styles: model.styles),
    );
    var operations = mapped.delta.toList();
    if (mapped.korunanlar.isNotEmpty) {
      final keep = keepTables;
      if (keep == null) return false;
      final base = keep(mapped.korunanlar);
      operations = [
        for (final op in operations)
          if (op.data case {DocDeltaMap.kTableEmbed: final int index})
            Operation.insert({
              DocDeltaMap.kTableEmbed: index + base,
            }, op.attributes)
          else
            op,
      ];
    }
    _insert(operations, model.metadata['openEnd']);
    onPasted?.call(model);
    return true;
  }

  /// Inserts [operations], which end with a paragraph's end, in place of the
  /// selection, as one change the user can undo in one step.
  ///
  /// Whether the pasted content's last paragraph end comes along depends on
  /// whether it was copied: [openEnd] false keeps it, as Word does when the
  /// whole paragraph was selected; true drops it, so the last pasted text
  /// carries on into the paragraph it lands in. When the source cannot say —
  /// HTML from a browser — it is dropped too, so a sentence pasted into a
  /// sentence does not break it, and a paragraph pasted onto an empty line
  /// keeps its own alignment and indents there.
  void _insert(List<Operation> operations, Object? openEnd) {
    final start = selection.start, end = selection.end;
    final whole = document.toDelta();
    final lineEnd = _lineEnd(whole, end);
    final atLineStart = start == 0 || _charAt(whole, start - 1) == '\n';
    final restEmpty = end == lineEnd;

    final pasted = Delta();
    for (final op in operations) {
      pasted.push(op);
    }
    final ops = pasted.toList();
    final last = ops.isEmpty ? null : ops.last;
    final lastAttributes = last?.attributes;
    final endsWithEmbed =
        ops.length >= 2 &&
        ops[ops.length - 2].data is Map &&
        last?.data == '\n';
    final drop =
        openEnd != false &&
        !endsWithEmbed &&
        last != null &&
        last.data is String &&
        (last.data as String).endsWith('\n');
    final body = Delta();
    // A table or a picture needs a line of its own.
    if (ops.isNotEmpty && ops.first.data is Map && !atLineStart) {
      body.insert('\n', _lineAttributes(whole, start));
    }
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      if (drop && i == ops.length - 1) {
        final text = op.data as String;
        if (text.length > 1) {
          body.insert(text.substring(0, text.length - 1), op.attributes);
        }
      } else {
        body.push(op);
      }
    }
    final breaks = body.toList().any(
      (op) => op.data is String && (op.data as String).contains('\n'),
    );
    final change = Delta()..retain(start);
    if (end > start) change.delete(end - start);
    for (final op in body.toList()) {
      change.push(op);
    }
    if (drop && openEnd == null && restEmpty && (atLineStart || breaks)) {
      // The last pasted paragraph has the line to itself: its layout wins.
      final current = _lineAttributes(whole, end) ?? const {};
      final layout = <String, dynamic>{
        for (final key in {...current.keys, ...?lastAttributes?.keys})
          if (_blockKeys.contains(key)) key: lastAttributes?[key],
      };
      if (layout.isNotEmpty) change.retain(1, layout);
    }
    compose(change, selection, ChangeSource.local);
    // After what went in. Delta.length counts operations, not characters.
    final inserted = body.toList().fold<int>(
      0,
      (sum, op) => sum + (op.length ?? 0),
    );
    updateSelection(
      TextSelection.collapsed(offset: start + inserted),
      ChangeSource.local,
    );
  }

  static final _blockKeys = {...Attribute.blockKeys, 'doc-layout'};

  static bool _endsWithBreak(Delta delta) {
    final ops = delta.toList();
    if (ops.isEmpty) return false;
    final data = ops.last.data;
    return data is String && data.endsWith('\n');
  }

  static String? _charAt(Delta delta, int offset) {
    var at = 0;
    for (final op in delta.toList()) {
      final length = op.length ?? 0;
      if (offset < at + length) {
        final data = op.data;
        return data is String ? data[offset - at] : null;
      }
      at += length;
    }
    return null;
  }

  /// Where the line holding [offset] ends: the offset of its line break.
  static int _lineEnd(Delta delta, int offset) {
    var at = 0;
    for (final op in delta.toList()) {
      final length = op.length ?? 0;
      final data = op.data;
      if (at + length > offset && data is String) {
        final found = data.indexOf('\n', offset > at ? offset - at : 0);
        if (found >= 0) return at + found;
      }
      at += length;
    }
    return at - 1;
  }

  /// The attributes of the line break ending the line that holds [offset],
  /// which is where Quill keeps a paragraph's layout.
  static Map<String, dynamic>? _lineAttributes(Delta delta, int offset) {
    var at = 0;
    for (final op in delta.toList()) {
      final length = op.length ?? 0;
      final data = op.data;
      if (at + length > offset && data is String) {
        final found = data.indexOf('\n', offset > at ? offset - at : 0);
        if (found >= 0) {
          final attributes = op.attributes;
          return attributes == null ? null : Map.of(attributes);
        }
      }
      at += length;
    }
    return null;
  }

  /// A table as the lines a header or a cell can hold — one per row, its
  /// cells separated by tabs and keeping their runs — and pictures dropped
  /// where they cannot be drawn.
  static List<DocBlock> _flatten(
    List<DocBlock> blocks, {
    required bool pictures,
  }) => [
    for (final block in blocks)
      if (block.type == DocBlockType.table && block.table != null)
        for (final row in block.table!.rows) _row(row)
      else if (block.type == DocBlockType.image ||
          block.imageBase64 != null) ...[if (pictures) block] else
        block,
  ];

  static DocBlock _row(DocTableRow row) {
    final text = StringBuffer();
    final spans = <DocSpan>[];
    for (final (i, cell) in row.cells.indexed) {
      if (i > 0) text.write('\t');
      final flat = _flatten(cell.blocks, pictures: false);
      for (final (j, block) in flat.indexed) {
        if (j > 0) text.write(' ');
        final offset = text.length;
        text.write(block.plainText);
        for (final s in block.spans) {
          spans.add(
            DocSpan(
              startOffset: s.startOffset + offset,
              length: s.length,
              bold: s.bold,
              italic: s.italic,
              underline: s.underline,
              strikethrough: s.strikethrough,
              superscript: s.superscript,
              subscript: s.subscript,
              fontFamily: s.fontFamily,
              fontSize: s.fontSize,
              color: s.color,
              background: s.background,
            ),
          );
        }
      }
    }
    return DocBlock(plainText: text.toString(), spans: spans);
  }
}

/// A controller with [EditorClipboard], for the editors that need nothing
/// else: the header and the footer.
class ClipboardController extends QuillController with EditorClipboard {
  ClipboardController({PasteTarget target = PasteTarget.body})
    : super(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
      ) {
    pasteTarget = target;
  }
}
