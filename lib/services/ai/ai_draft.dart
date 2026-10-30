import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/document_model.dart';
import '../clients/client_documents.dart' show paperParagraph;
import '../udf/udf_writer.dart';
import '../uyap/uyap_case_store.dart';

/// A draft the AI program wrote, put in [record]'s folder as a UDF the
/// lawyer opens and edits: each line a paragraph, an empty line a space.
/// Being in the case's folder, it is the case's (its "Dilekçelerim").
/// Its path.
Future<String> writeAiDraft(
  UyapCaseStore store,
  UyapCaseRecord record,
  String title,
  String text,
) async {
  await store.settings.load();
  final folder = Directory(store.folderOf(record));
  await folder.create(recursive: true);
  final safe = title.trim().isEmpty
      ? 'Yapay zekâ taslağı'
      : title.trim().replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '-');
  var file = File(p.join(folder.path, '$safe.udf'));
  for (var i = 2; await file.exists(); i++) {
    file = File(p.join(folder.path, '$safe ($i).udf'));
  }
  final blocks = <DocBlock>[];
  var gap = false;
  for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
    final t = line.trimRight();
    if (t.trim().isEmpty) {
      gap = true;
      continue;
    }
    if (gap && blocks.isNotEmpty) blocks.add(paperParagraph('', after: 0));
    gap = false;
    blocks.add(paperParagraph(t.trim()));
  }
  await file.writeAsBytes(
    UdfWriter.writeBytes(DocModel(blocks: blocks)),
    flush: true,
  );
  return file.path;
}
