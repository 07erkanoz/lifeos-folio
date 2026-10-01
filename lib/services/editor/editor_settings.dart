import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

/// The editor's own switches: whether it suggests as the reader types, and
/// what it may learn from. All on unless the reader turns them off; what is
/// learned never leaves this computer.
class EditorSettings extends ChangeNotifier {
  EditorSettings({
    @visibleForTesting Directory? directory,
    // ignore: prefer_initializing_formals
  }) : _directory = directory;

  final Directory? _directory;

  /// Offer completions under the caret.
  bool suggestions = true;

  /// Learn from the documents saved in the editor.
  bool learnSaved = true;

  /// Learn from the documents in the archive's index.
  bool learnArchive = true;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// The one the app uses. Replaced in tests.
  static EditorSettings instance = EditorSettings();

  Future<File> _file() async => File(
    p.join((_directory ?? await folioSupportDirectory()).path, 'editor.json'),
  );

  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map) {
          suggestions = data['oneri'] != false;
          learnSaved = data['kaydedilenlerden'] != false;
          learnArchive = data['arsivden'] != false;
        }
      }
    } on Object {
      // Defaults stand.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setSuggestions(bool value) => _set(() => suggestions = value);
  Future<void> setLearnSaved(bool value) => _set(() => learnSaved = value);
  Future<void> setLearnArchive(bool value) => _set(() => learnArchive = value);

  Future<void> _set(void Function() change) async {
    change();
    notifyListeners();
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'oneri': suggestions,
          'kaydedilenlerden': learnSaved,
          'arsivden': learnArchive,
        }),
      );
    } on Object {
      // The setting holds for this run either way.
    }
  }
}
