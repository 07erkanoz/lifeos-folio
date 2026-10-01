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

  /// Opens [path], or a new document when there is none.
  static Future<void> open([String? path]) async {
    if (!available) return;
    await Process.start(Platform.resolvedExecutable, [
      editorFlag,
      ?path,
    ], mode: ProcessStartMode.detached);
  }
}
