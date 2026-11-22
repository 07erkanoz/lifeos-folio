import 'dart:io';

import 'package:path/path.dart' as p;

/// On KDE's Wayland the palette asks KWin to put it in the middle of the
/// screen: no app may place its own window there, and it came up in a
/// corner (21 Kasım 2026). A window rule of Folio's own, matched by the
/// palette's title, added once to the lawyer's KWin rules; nothing else in
/// them is touched.
class KwinPaletteRule {
  static const group = 'lifeos-folio-hizli-arama';

  /// Not in the tests: they ran on KDE, waited on the lawyer's own
  /// kwinrulesrc and would have written it.
  static bool get applies =>
      Platform.isLinux &&
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '').contains('KDE');

  static Future<void> ensure(String title) async {
    if (!applies) return;
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return;
      final file = File(
        p.join(
          Platform.environment['XDG_CONFIG_HOME'] ?? p.join(home, '.config'),
          'kwinrulesrc',
        ),
      );
      final text = await file.exists() ? await file.readAsString() : '';
      final updated = withRule(text, title);
      if (updated == text) return;
      await file.parent.create(recursive: true);
      await file.writeAsString(updated, flush: true);
      await Process.run('dbus-send', [
        '--session',
        '--type=method_call',
        '--dest=org.kde.KWin',
        '/KWin',
        'org.kde.KWin.reconfigure',
      ]);
    } catch (_) {
      // Without the rule the palette is only not centred.
    }
  }

  /// [text] with Folio's rule in it, the [General] list naming it.
  static String withRule(String text, String title) {
    if (text.contains('[$group]')) return text;
    final lines = text.isEmpty ? <String>[] : text.split('\n');
    var start = lines.indexOf('[General]');
    if (start < 0) {
      lines.insertAll(0, ['[General]', '']);
      start = 0;
    }
    var end = lines.length;
    for (var i = start + 1; i < lines.length; i++) {
      if (lines[i].startsWith('[')) {
        end = i;
        break;
      }
    }
    final general = lines.sublist(start + 1, end);
    final names = [
      for (final l in general)
        if (l.startsWith('rules='))
          ...l.substring(6).split(',').where((n) => n.isNotEmpty),
      group,
    ];
    lines.replaceRange(start + 1, end, [
      for (final l in general)
        if (l.isNotEmpty && !l.startsWith('rules=') && !l.startsWith('count='))
          l,
      'count=${names.length}',
      'rules=${names.join(',')}',
      if (end < lines.length) '',
    ]);
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    lines.addAll([
      '',
      '[$group]',
      'Description=LifeOS Folio hızlı arama: ekranın ortasında',
      'title=$title',
      'titlematch=1',
      'types=1',
      'wmclassmatch=0',
      'placement=5',
      'placementrule=2',
      'above=true',
      'aboverule=2',
      '',
    ]);
    return lines.join('\n');
  }
}
