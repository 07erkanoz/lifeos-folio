import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/platform/app_directories.dart';

class ThemeController extends ChangeNotifier {
  final String? settingsPath;
  ThemeMode mode;
  bool hoverPreview = true;

  /// Whether the library's panel folds to its icons on the UYAP pages,
  /// for the cases' and documents' room.
  bool foldPanelOnUyap = true;

  /// How large Folio's own words are, against the system's: the documents'
  /// pages keep their own size.
  double textScale = 1;

  /// The sizes offered, smallest first.
  static const textScales = [
    (0.85, 'Çok küçük'),
    (0.92, 'Küçük'),
    (1.0, 'Normal'),
    (1.1, 'Büyük'),
  ];
  bool _disposed = false;
  int _revision = 0;
  Future<void> _writing = Future.value();
  String? _path;
  ThemeController({this.settingsPath, this.mode = ThemeMode.system});

  Future<void> load() async {
    final revision = _revision;
    try {
      _path =
          settingsPath ??
          p.join((await folioSupportDirectory()).path, 'appearance.json');
      final file = File(_path!);
      if (await file.exists()) {
        final settings = jsonDecode(await file.readAsString());
        final value = settings['theme'];
        if (!_disposed && revision == _revision) {
          hoverPreview = settings['hoverPreview'] != false;
          foldPanelOnUyap = settings['foldPanelOnUyap'] != false;
          final scale = settings['textScale'];
          if (scale is num && scale >= 0.8 && scale <= 1.2) {
            textScale = scale.toDouble();
          }
          mode = ThemeMode.values.firstWhere(
            (m) => m.name == value,
            orElse: () => ThemeMode.system,
          );
          notifyListeners();
        }
      }
    } catch (_) {
      /* A missing preference must not prevent previewing files. */
    }
  }

  void setMode(ThemeMode next) {
    if (_disposed) return;
    _revision++;
    mode = next;
    notifyListeners();
    _persist();
  }

  void setHoverPreview(bool enabled) {
    if (_disposed) return;
    _revision++;
    hoverPreview = enabled;
    notifyListeners();
    _persist();
  }

  void setTextScale(double scale) {
    if (_disposed) return;
    _revision++;
    textScale = scale.clamp(0.8, 1.2).toDouble();
    notifyListeners();
    _persist();
  }

  void setFoldPanelOnUyap(bool fold) {
    if (_disposed) return;
    _revision++;
    foldPanelOnUyap = fold;
    notifyListeners();
    _persist();
  }

  void _persist() {
    final settings = {
      'theme': mode.name,
      'hoverPreview': hoverPreview,
      'foldPanelOnUyap': foldPanelOnUyap,
      'textScale': textScale,
    };
    _writing = _writing
        .then((_) async {
          _path ??=
              settingsPath ??
              p.join((await folioSupportDirectory()).path, 'appearance.json');
          final file = File(_path!);
          await file.parent.create(recursive: true);
          await file.writeAsString(jsonEncode(settings), flush: true);
        })
        .catchError((Object _) {});
  }

  Future<void> get saved => _writing;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
