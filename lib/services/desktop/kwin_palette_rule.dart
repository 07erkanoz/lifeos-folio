import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/painting.dart' show Size;
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

  /// The palette put in the middle of the screen now, by a script KWin
  /// runs. The rule places a window as it is mapped; a hidden window's size
  /// is not changed on Wayland, so the palette was mapped at the main
  /// window's size, centred for that, then made small from its corner
  /// (22 Kasım 2026).
  static Future<void> center(String title, {required Size size}) async {
    if (!applies) return;
    final client = DBusClient.session();
    try {
      final file = File(
        p.join(Directory.systemTemp.path, 'lifeos-folio-palet-orta.js'),
      );
      final script = centerScript(title, size: size);
      if (!await file.exists() || await file.readAsString() != script) {
        await file.writeAsString(script, flush: true);
      }
      final kwin = DBusRemoteObject(
        client,
        name: 'org.kde.KWin',
        path: DBusObjectPath('/Scripting'),
      );
      const name = 'lifeos-folio-palet-orta';
      await kwin.callMethod('org.kde.kwin.Scripting', 'unloadScript', [
        const DBusString(name),
      ], replySignature: DBusSignature('b'));
      final loaded = await kwin.callMethod(
        'org.kde.kwin.Scripting',
        'loadScript',
        [DBusString(file.path), const DBusString(name)],
        replySignature: DBusSignature('i'),
      );
      if (loaded.values.first.asInt32() < 0) return;
      // Started by the scripting itself: the script's own object, named by
      // its number, can be one unloaded before under the same number, and
      // running that ran nothing (22 Kasım 2026).
      await kwin.callMethod(
        'org.kde.kwin.Scripting',
        'start',
        const [],
        replySignature: DBusSignature(''),
      );
    } catch (_) {
      // Not KWin 6, or no session bus: the palette is only not centred.
    } finally {
      await client.close();
    }
  }

  /// KWin's script centring Folio's window titled [title] in the screen's
  /// work area once it is [size]: the size asked for comes a moment after
  /// the window is shown, and centred before it, the palette was centred
  /// for the main window's size.
  static String centerScript(
    String title, {
    Size size = const Size(720, 540),
  }) =>
      '''
const title = ${jsonEncode(title)};
const width = ${size.width.round()}, height = ${size.height.round()};
function centre(w) {
  const g = w.frameGeometry;
  if (Math.abs(g.width - width) > 2 || Math.abs(g.height - height) > 2) return false;
  const area = workspace.clientArea(KWin.PlacementArea, w);
  const x = Math.round(area.x + (area.width - g.width) / 2);
  const y = Math.round(area.y + (area.height - g.height) / 2);
  if (g.x !== x || g.y !== y) w.frameGeometry = {x: x, y: y, width: g.width, height: g.height};
  return true;
}
function follow(w) {
  if (w.resourceClass !== "com.erkanoz.evrak_convert") return;
  // Kept while it is the palette: KWin places a window shown again after
  // this script has run, and its size comes later still.
  const keep = function () {
    if (w.caption === title) centre(w);
  };
  keep();
  w.frameGeometryChanged.connect(keep);
  w.captionChanged.connect(keep);
}
// Shown again on Wayland the palette is a new window: it may come after
// this script.
for (const w of workspace.windowList()) follow(w);
workspace.windowAdded.connect(follow);
''';
}
