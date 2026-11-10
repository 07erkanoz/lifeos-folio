import 'dart:io';

import 'app_edition.dart';

/// Where the standalone editor starts: `--editor` on the command line, as
/// the LifeOS Editör program passes it.
const editorFlag = '--editor';

/// Where a document is only shown, in a window of its own.
const previewFlag = '--preview';

/// Where a document named on the command line is shown in Folio's own
/// window, not in a preview window of its own: a preview's "Folio'da aç".
const folioFlag = '--folio';

/// Where LifeOS Ofis starts: its launcher passes it (lib/ofis_app.dart).
const ofisFlag = '--ofis';

/// A document in an editor window of its own: Folio started again as
/// LifeOS Editör, which takes no single-instance lock, so each one is a
/// window the system can put beside another or on a second screen.
abstract final class EditorWindow {
  static bool get available =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// Opens [path], or a new document when there is none; replaced under
  /// test, where no window is started.
  static Future<void> Function([String? path]) open = _open;

  /// [path] handed to Folio's own window, to be edited there: the running
  /// one takes it (DesktopInstance), or Folio starts. Replaced under test.
  static Future<void> Function(String path) inFolio = _inFolio;

  static Future<void> _inFolio(String path) async {
    if (!available) return;
    await Process.start(Platform.resolvedExecutable, [
      '--edit',
      '--',
      path,
    ], mode: ProcessStartMode.detached);
  }

  static Future<void> _open([String? path]) async {
    if (!available) return;
    await Process.start(Platform.resolvedExecutable, [
      // LifeOS Ofis's new window is Ofis's, not LifeOS Editör's.
      if (AppEdition.isOfis) ...[ofisFlag, '--edit'] else editorFlag,
      ?path,
    ], mode: ProcessStartMode.detached);
  }
}

/// A document in a preview window of its own, only to be read.
abstract final class PreviewWindow {
  /// Opens [path]; replaced under test, where no window is started.
  static Future<void> Function(String path) open = _open;

  /// [path] shown in Folio's own window, with its library beside it: the
  /// running Folio takes it, or Folio starts.
  static Future<void> Function(String path) inFolio = _inFolio;

  static Future<void> _open(String path) async {
    if (!EditorWindow.available) return;
    await Process.start(Platform.resolvedExecutable, [
      // LifeOS Ofis shows a document in a window of its own, not Folio's.
      AppEdition.isOfis ? ofisFlag : previewFlag,
      path,
    ], mode: ProcessStartMode.detached);
  }

  static Future<void> _inFolio(String path) async {
    if (!EditorWindow.available) return;
    await Process.start(Platform.resolvedExecutable, [
      folioFlag,
      '--',
      path,
    ], mode: ProcessStartMode.detached);
  }
}
