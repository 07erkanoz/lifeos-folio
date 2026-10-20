import 'dart:io';

/// Where the standalone editor starts: `--editor` on the command line, as
/// the LifeOS Editör program passes it.
const editorFlag = '--editor';

/// Where a document is only shown, in a window of its own.
const previewFlag = '--preview';

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
      editorFlag,
      ?path,
    ], mode: ProcessStartMode.detached);
  }
}
