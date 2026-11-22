// Puts the tray icon on the real desktop for a few seconds and asks it
// back over D-Bus. Run on purpose: FOLIO_TRAY_PROBE=1.
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/desktop/linux_tray.dart';

void main() {
  testWidgets('tray', (tester) async {
    await tester.runAsync(() async {
      var clicks = 0;
      final menu = <String>[];
      final tray = LinuxTray(onActivate: () => clicks++, onMenu: menu.add);
      await tray.show(
        asset: 'assets/branding/lifeos_folio.png',
        tooltip: 'deneme',
        items: const [
          LinuxTrayItem('search', 'Hızlı arama ve ajan'),
          LinuxTrayItem.separator(),
          LinuxTrayItem('quit', 'Tamamen çık'),
        ],
      );
      final bus = DBusClient.session();
      final name = 'org.kde.StatusNotifierItem-$pid-1';
      final watcher = DBusRemoteObject(
        bus,
        name: 'org.kde.StatusNotifierWatcher',
        path: DBusObjectPath('/StatusNotifierWatcher'),
      );
      final items = (await watcher.getProperty(
        'org.kde.StatusNotifierWatcher',
        'RegisteredStatusNotifierItems',
      )).asStringArray().toList();
      debugPrint('KAYITLI: ${items.where((i) => i.contains('$pid')).toList()}');
      final item = DBusRemoteObject(
        bus,
        name: name,
        path: DBusObjectPath('/StatusNotifierItem'),
      );
      debugPrint(
        'ItemIsMenu: ${(await item.getProperty('org.kde.StatusNotifierItem', 'ItemIsMenu')).asBoolean()}',
      );
      await item.callMethod('org.kde.StatusNotifierItem', 'Activate', [
        const DBusInt32(0),
        const DBusInt32(0),
      ]);
      final m = DBusRemoteObject(
        bus,
        name: name,
        path: DBusObjectPath('/MenuBar'),
      );
      final layout = await m.callMethod('com.canonical.dbusmenu', 'GetLayout', [
        const DBusInt32(0),
        const DBusInt32(-1),
        DBusArray.string(const []),
      ]);
      debugPrint(
        'MENU: ${layout.values[1].asStruct()[2].asArray().length} öğe',
      );
      await m.callMethod('com.canonical.dbusmenu', 'Event', [
        const DBusInt32(1),
        const DBusString('clicked'),
        DBusVariant(const DBusInt32(0)),
        const DBusUint32(0),
      ]);
      await Future<void>.delayed(const Duration(seconds: 3));
      debugPrint('TIKLAMA: $clicks MENÜ: $menu');
      await bus.close();
      await tray.hide();
    });
  }, skip: Platform.environment['FOLIO_TRAY_PROBE'] == null);
}
