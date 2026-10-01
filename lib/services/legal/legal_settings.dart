import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

/// Whether the two legal aids are wanted, and remembering the answer.
///
/// Both put marks on a document the reader did not write, and one of them
/// reaches the network, so neither is something to impose. They are kept
/// apart because the reasons to turn them off are different: the dictionary
/// is a matter of taste, the articles a matter of whether this machine
/// should be talking to mevzuat.gov.tr at all.
class LegalSettings extends ChangeNotifier {
  /// The directory is a seam for tests; the app passes none.
  LegalSettings({
    @visibleForTesting Directory? directory,
    // `this._directory` is what the analyser would rather see, but a named
    // argument may not begin with an underscore, so it cannot be called.
    // ignore: prefer_initializing_formals
  }) : _directory = directory;

  final Directory? _directory;

  /// Underline the laws a document cites, and fetch the article when one is
  /// pressed. This is the one that uses the network.
  bool articles = true;

  /// Offer the meaning of a term of art from the right-click menu. Local; it
  /// never reaches anything.
  bool dictionary = true;

  /// Underline the decisions a document cites, and fetch the text when one
  /// is pressed. Uses the network, like the articles, and is kept apart from
  /// them because the case bank holds only a selection: about a third of the
  /// citations in a working archive can be found, so a reader who tires of
  /// being told "not found" can turn this off alone.
  bool decisions = true;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// The one the app uses. Replaced in tests.
  static LegalSettings instance = LegalSettings();

  Future<File> _file() async => File(
    p.join((_directory ?? await folioSupportDirectory()).path, 'hukuk.json'),
  );

  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map) {
          articles = data['maddeler'] != false;
          dictionary = data['sozluk'] != false;
          decisions = data['kararlar'] != false;
        }
      }
    } on Object {
      // A missing or damaged file means the settled defaults, not a failure
      // the reader has to be told about.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setArticles(bool value) async {
    if (articles == value) return;
    articles = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDictionary(bool value) async {
    if (dictionary == value) return;
    dictionary = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDecisions(bool value) async {
    if (decisions == value) return;
    decisions = value;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'maddeler': articles,
          'sozluk': dictionary,
          'kararlar': decisions,
        }),
      );
    } on Object {
      // The setting holds for this run either way.
    }
  }
}
