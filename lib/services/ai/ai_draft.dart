import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;

import '../../models/document_model.dart';
import '../../models/evrak_file.dart';
import '../clients/client_documents.dart' show paperParagraph;
import '../docx/docx_bridge.dart';
import '../pdf/pdf_service.dart';
import '../udf/udf_writer.dart';
import '../uyap/uyap_case_store.dart';

/// A document the AI program wrote, as a document: each line a paragraph,
/// an empty line a space; a Markdown heading bold, its marks gone.
DocModel aiDraftModel(String text) {
  final blocks = <DocBlock>[];
  var gap = false;
  for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
    var t = line.trim();
    if (t.isEmpty) {
      gap = true;
      continue;
    }
    if (gap && blocks.isNotEmpty) blocks.add(paperParagraph('', after: 0));
    gap = false;
    final heading = RegExp(r'^#{1,6}\s+').firstMatch(t);
    if (heading != null) {
      t = '**${t.substring(heading.end).replaceAll('**', '')}**';
    }
    blocks.add(paperParagraph(t));
  }
  return DocModel(blocks: blocks);
}

/// [text] as a file of [format]: UDF, Word or PDF.
Future<Uint8List> aiDraftBytes(
  String title,
  String text,
  EvrakFormat format,
) async {
  final model = aiDraftModel(text);
  return switch (format) {
    EvrakFormat.docx => await compute(DocxBridge.writeBytes, model),
    EvrakFormat.pdf => await PdfService.modelToPdfBytes(model, title: title),
    _ => Uint8List.fromList(UdfWriter.writeBytes(model)),
  };
}

/// A name a file may have of [title].
String aiDraftName(String title) {
  final safe = title
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '-')
      // A name ending in a dot or a space is not one every system keeps:
      // "… E." would be "… E..udf".
      .replaceAll(RegExp(r'[. ]+$'), '');
  return safe.isEmpty ? 'Yapay zekâ taslağı' : safe;
}

/// A draft the AI program wrote, put as a UDF the lawyer opens and edits:
/// in [record]'s folder, so that it is the case's ("Dilekçelerim"), or
/// with no case in Folio's "Yapay zekâ" folder beside the UYAP one. Its
/// path.
Future<String> writeAiDraft(
  UyapCaseStore store,
  UyapCaseRecord? record,
  String title,
  String text,
) async {
  await store.settings.load();
  final folder = Directory(
    record != null
        ? store.folderOf(record)
        : p.join(p.dirname(store.settings.folder), 'Yapay zekâ'),
  );
  await folder.create(recursive: true);
  final name = aiDraftName(title);
  var file = File(p.join(folder.path, '$name.udf'));
  for (var i = 2; await file.exists(); i++) {
    file = File(p.join(folder.path, '$name ($i).udf'));
  }
  await file.writeAsBytes(
    UdfWriter.writeBytes(aiDraftModel(text)),
    flush: true,
  );
  return file.path;
}
