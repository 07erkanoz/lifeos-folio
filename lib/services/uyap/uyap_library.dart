import 'dart:io';

import 'package:path/path.dart' as p;

import '../search/library_controller.dart';
import 'uyap_case_store.dart';

/// Makes the folder UYAP documents are saved in one of those Folio
/// searches, so a report or a petition is found by what it says. Asked
/// when a document is saved, and again whenever Folio starts: a document
/// saved from an editor window of its own, which keeps no archive, is
/// found from then on all the same. True when the folder was added.
Future<bool> searchUyapFolder(
  LibraryController library, {
  UyapSettings? settings,
}) async {
  final s = settings ?? UyapSettings.instance;
  await s.load();
  if (!s.saveDocuments) return false;
  final folder = s.folder;
  if (!await Directory(folder).exists()) return false;
  await library.initialize();
  if (library.sources.any(
    (source) =>
        p.equals(source.path, folder) || p.isWithin(source.path, folder),
  )) {
    return false;
  }
  await library.addPaths([folder]);
  return true;
}
