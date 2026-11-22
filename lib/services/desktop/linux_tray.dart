import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';

/// One line of the tray's menu; none [key], a separator.
class LinuxTrayItem {
  const LinuxTrayItem(this.key, this.label);
  const LinuxTrayItem.separator() : key = null, label = '';
  final String? key;
  final String label;
}

/// Folio's tray icon on Linux, spoken to the desktop directly
/// (StatusNotifierItem, with its menu over dbusmenu): a left click is
/// Folio's own — the quick search — and a right click the menu.
/// tray_manager's appindicator gives a left click to the menu, and never
/// tells Folio of it (KDE, 21 Kasım 2026).
class LinuxTray {
  LinuxTray({required this.onActivate, required this.onMenu});

  final void Function() onActivate;
  final void Function(String key) onMenu;

  DBusClient? _bus;
  _Menu? _menu;

  bool get shown => _bus != null;

  /// Shows the icon ([asset], a PNG) with [tooltip] and [items].
  Future<void> show({
    required String asset,
    required String tooltip,
    required List<LinuxTrayItem> items,
  }) async {
    if (_bus != null) {
      _menu!.items = items;
      await _menu!.changed();
      return;
    }
    final pixmaps = await _pixmaps(asset);
    final bus = DBusClient.session();
    try {
      final name = 'org.kde.StatusNotifierItem-$pid-1';
      final menu = _Menu(items, onMenu);
      final item = _Item(
        tooltip: tooltip,
        pixmaps: pixmaps,
        onActivate: onActivate,
      );
      await bus.registerObject(menu);
      await bus.registerObject(item);
      await bus.requestName(name);
      await DBusRemoteObject(
        bus,
        name: 'org.kde.StatusNotifierWatcher',
        path: DBusObjectPath('/StatusNotifierWatcher'),
      ).callMethod(
        'org.kde.StatusNotifierWatcher',
        'RegisterStatusNotifierItem',
        [DBusString(name)],
        replySignature: DBusSignature(''),
      );
      _bus = bus;
      _menu = menu;
    } catch (_) {
      await bus.close();
      rethrow;
    }
  }

  Future<void> hide() async {
    final bus = _bus;
    _bus = null;
    _menu = null;
    await bus?.close();
  }

  /// The icon at a few sizes, as the specification wants it: ARGB32 in
  /// network byte order.
  static Future<List<(int, int, Uint8List)>> _pixmaps(String asset) async {
    final bytes = (await rootBundle.load(asset)).buffer.asUint8List();
    final out = <(int, int, Uint8List)>[];
    for (final size in [22, 32, 48, 64]) {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: size,
        targetHeight: size,
      );
      final image = (await codec.getNextFrame()).image;
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!.buffer.asUint8List();
      image.dispose();
      codec.dispose();
      final argb = Uint8List(rgba.length);
      for (var i = 0; i < rgba.length; i += 4) {
        argb[i] = rgba[i + 3];
        argb[i + 1] = rgba[i];
        argb[i + 2] = rgba[i + 1];
        argb[i + 3] = rgba[i + 2];
      }
      out.add((size, size, argb));
    }
    return out;
  }
}

const _sni = 'org.kde.StatusNotifierItem';
const _dbusmenu = 'com.canonical.dbusmenu';

class _Item extends DBusObject {
  _Item({
    required this.tooltip,
    required this.pixmaps,
    required this.onActivate,
  }) : super(DBusObjectPath('/StatusNotifierItem'));

  final String tooltip;
  final List<(int, int, Uint8List)> pixmaps;
  final void Function() onActivate;

  DBusValue get _pixmapValue => DBusArray(DBusSignature('(iiay)'), [
    for (final (w, h, data) in pixmaps)
      DBusStruct([DBusInt32(w), DBusInt32(h), DBusArray.byte(data)]),
  ]);

  Map<String, DBusValue> get _properties => {
    'Category': const DBusString('ApplicationStatus'),
    'Id': const DBusString('lifeos-folio'),
    'Title': const DBusString('LifeOS Folio'),
    'Status': const DBusString('Active'),
    'WindowId': const DBusInt32(0),
    'IconName': const DBusString(''),
    'IconPixmap': _pixmapValue,
    'OverlayIconName': const DBusString(''),
    'OverlayIconPixmap': DBusArray(DBusSignature('(iiay)'), const []),
    'AttentionIconName': const DBusString(''),
    'AttentionIconPixmap': DBusArray(DBusSignature('(iiay)'), const []),
    'AttentionMovieName': const DBusString(''),
    'ToolTip': DBusStruct([
      const DBusString(''),
      DBusArray(DBusSignature('(iiay)'), const []),
      const DBusString('LifeOS Folio'),
      DBusString(tooltip),
    ]),
    // A left click is Folio's own, not the menu's.
    'ItemIsMenu': const DBusBoolean(false),
    'Menu': DBusObjectPath('/MenuBar'),
  };

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      _sni,
      methods: [
        for (final m in ['Activate', 'SecondaryActivate', 'ContextMenu'])
          DBusIntrospectMethod(
            m,
            args: [
              DBusIntrospectArgument(
                DBusSignature('i'),
                DBusArgumentDirection.in_,
                name: 'x',
              ),
              DBusIntrospectArgument(
                DBusSignature('i'),
                DBusArgumentDirection.in_,
                name: 'y',
              ),
            ],
          ),
        DBusIntrospectMethod(
          'Scroll',
          args: [
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
              name: 'delta',
            ),
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.in_,
              name: 'orientation',
            ),
          ],
        ),
      ],
      properties: [
        for (final e in _properties.entries)
          DBusIntrospectProperty(
            e.key,
            e.value.signature,
            access: DBusPropertyAccess.read,
          ),
      ],
      signals: [
        for (final s in ['NewIcon', 'NewTitle', 'NewToolTip', 'NewMenu'])
          DBusIntrospectSignal(s),
        DBusIntrospectSignal(
          'NewStatus',
          args: [
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.out,
            ),
          ],
        ),
      ],
    ),
  ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != _sni) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (call.name) {
      case 'Activate':
      case 'SecondaryActivate':
        onActivate();
        return DBusMethodSuccessResponse();
      case 'ContextMenu':
      case 'Scroll':
        return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = interface == _sni ? _properties[name] : null;
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(interface == _sni ? _properties : {});
}

class _Menu extends DBusObject {
  _Menu(this.items, this.onMenu) : super(DBusObjectPath('/MenuBar'));

  List<LinuxTrayItem> items;
  final void Function(String key) onMenu;
  int _revision = 1;

  Future<void> changed() async {
    _revision++;
    await emitSignal(_dbusmenu, 'LayoutUpdated', [
      DBusUint32(_revision),
      const DBusInt32(0),
    ]);
  }

  Map<String, DBusValue> _props(int id) {
    if (id == 0) {
      return {'children-display': const DBusString('submenu')};
    }
    final item = items[id - 1];
    if (item.key == null) return {'type': const DBusString('separator')};
    return {
      'label': DBusString(item.label),
      'enabled': const DBusBoolean(true),
      'visible': const DBusBoolean(true),
    };
  }

  DBusValue _node(int id) => DBusStruct([
    DBusInt32(id),
    DBusDict.stringVariant(_props(id)),
    DBusArray(DBusSignature('v'), [
      if (id == 0)
        for (var i = 1; i <= items.length; i++) DBusVariant(_node(i)),
    ]),
  ]);

  static final _properties = <String, DBusValue>{
    'Version': const DBusUint32(3),
    'TextDirection': const DBusString('ltr'),
    'Status': const DBusString('normal'),
    'IconThemePath': DBusArray.string(const []),
  };

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != _dbusmenu) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final a = call.values;
    switch (call.name) {
      case 'GetLayout':
        final parent = a[0].asInt32();
        return DBusMethodSuccessResponse([
          DBusUint32(_revision),
          _node(parent == 0 ? 0 : parent.clamp(0, items.length)),
        ]);
      case 'GetGroupProperties':
        final ids = a[0].asInt32Array().toList();
        return DBusMethodSuccessResponse([
          DBusArray(DBusSignature('(ia{sv})'), [
            for (final id
                in ids.isEmpty
                    ? [for (var i = 0; i <= items.length; i++) i]
                    : ids)
              if (id >= 0 && id <= items.length)
                DBusStruct([DBusInt32(id), DBusDict.stringVariant(_props(id))]),
          ]),
        ]);
      case 'GetProperty':
        final value = _props(a[0].asInt32())[a[1].asString()];
        return value == null
            ? DBusMethodErrorResponse.invalidArgs()
            : DBusMethodSuccessResponse([DBusVariant(value)]);
      case 'Event':
        _event(a[0].asInt32(), a[1].asString());
        return DBusMethodSuccessResponse();
      case 'EventGroup':
        for (final e in a[0].asArray()) {
          final f = e.asStruct();
          _event(f[0].asInt32(), f[1].asString());
        }
        return DBusMethodSuccessResponse([DBusArray.int32(const [])]);
      case 'AboutToShow':
        return DBusMethodSuccessResponse([const DBusBoolean(false)]);
      case 'AboutToShowGroup':
        return DBusMethodSuccessResponse([
          DBusArray.int32(const []),
          DBusArray.int32(const []),
        ]);
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  void _event(int id, String event) {
    if (event != 'clicked' || id < 1 || id > items.length) return;
    final key = items[id - 1].key;
    // After the reply, not inside the call: the menu closes first.
    if (key != null) scheduleMicrotask(() => onMenu(key));
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = interface == _dbusmenu ? _properties[name] : null;
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(interface == _dbusmenu ? _properties : {});

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      _dbusmenu,
      methods: [
        DBusIntrospectMethod(
          'GetLayout',
          args: [
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('as'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('u'),
              DBusArgumentDirection.out,
            ),
            DBusIntrospectArgument(
              DBusSignature('(ia{sv}av)'),
              DBusArgumentDirection.out,
            ),
          ],
        ),
        DBusIntrospectMethod(
          'GetGroupProperties',
          args: [
            DBusIntrospectArgument(
              DBusSignature('ai'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('as'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('a(ia{sv})'),
              DBusArgumentDirection.out,
            ),
          ],
        ),
        DBusIntrospectMethod(
          'GetProperty',
          args: [
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('v'),
              DBusArgumentDirection.out,
            ),
          ],
        ),
        DBusIntrospectMethod(
          'Event',
          args: [
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('v'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('u'),
              DBusArgumentDirection.in_,
            ),
          ],
        ),
        DBusIntrospectMethod(
          'EventGroup',
          args: [
            DBusIntrospectArgument(
              DBusSignature('a(isvu)'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('ai'),
              DBusArgumentDirection.out,
            ),
          ],
        ),
        DBusIntrospectMethod(
          'AboutToShow',
          args: [
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('b'),
              DBusArgumentDirection.out,
            ),
          ],
        ),
        DBusIntrospectMethod(
          'AboutToShowGroup',
          args: [
            DBusIntrospectArgument(
              DBusSignature('ai'),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature('ai'),
              DBusArgumentDirection.out,
            ),
            DBusIntrospectArgument(
              DBusSignature('ai'),
              DBusArgumentDirection.out,
            ),
          ],
        ),
      ],
      properties: [
        for (final e in _properties.entries)
          DBusIntrospectProperty(
            e.key,
            e.value.signature,
            access: DBusPropertyAccess.read,
          ),
      ],
      signals: [
        DBusIntrospectSignal(
          'LayoutUpdated',
          args: [
            DBusIntrospectArgument(
              DBusSignature('u'),
              DBusArgumentDirection.out,
            ),
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.out,
            ),
          ],
        ),
        DBusIntrospectSignal(
          'ItemsPropertiesUpdated',
          args: [
            DBusIntrospectArgument(
              DBusSignature('a(ia{sv})'),
              DBusArgumentDirection.out,
            ),
            DBusIntrospectArgument(
              DBusSignature('a(ias)'),
              DBusArgumentDirection.out,
            ),
          ],
        ),
      ],
    ),
  ];
}
