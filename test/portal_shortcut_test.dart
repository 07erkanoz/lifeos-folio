@TestOn('linux')
// The global shortcut goes through the XDG desktop portal, and this test
// registers real objects on a D-Bus session bus to answer it. There is no such
// bus on Windows or macOS, so the test does not fail there — it waits for one
// that never appears and times out after thirty seconds, twice.
library;

import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/desktop/global_shortcut.dart';

const interface = 'org.freedesktop.portal.GlobalShortcuts';

class _Session extends DBusObject {
  bool closed = false;
  _Session()
    : super(
        DBusObjectPath('/org/freedesktop/portal/desktop/session/test/folio'),
      );
  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.name == 'Close') {
      closed = true;
      return DBusMethodSuccessResponse([]);
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

class _Portal extends DBusObject {
  final DBusClient owner;
  final _Session session;
  final bool reject;
  String? trigger;
  String? registeredApp;
  bool configured = false;
  _Portal(this.owner, this.session, {this.reject = false})
    : super(DBusObjectPath('/org/freedesktop/portal/desktop'));
  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async =>
      DBusGetPropertyResponse(const DBusUint32(2));
  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.name == 'Register') {
      registeredApp = call.values.first.asString();
      return DBusMethodSuccessResponse([]);
    }
    if (call.name == 'ConfigureShortcuts') {
      configured = true;
      return DBusMethodSuccessResponse([]);
    }
    if (registeredApp == null) {
      return DBusMethodErrorResponse.failed('Application identity missing');
    }
    final options = call.values.last.asStringVariantDict();
    final token = options['handle_token']!.asString();
    final sender = call.sender!.substring(1).replaceAll('.', '_');
    final request = DBusObject(
      DBusObjectPath('/org/freedesktop/portal/desktop/request/$sender/$token'),
    );
    await owner.registerObject(request);
    Map<String, DBusValue> result;
    if (call.name == 'CreateSession') {
      result = {'session_handle': DBusString(session.path.value)};
    } else if (call.name == 'BindShortcuts') {
      final shortcut = call.values[1].asArray().single.asStruct();
      trigger = shortcut[1]
          .asStringVariantDict()['preferred_trigger']!
          .asString();
      result = {
        'shortcuts': DBusArray(DBusSignature('(sa{sv})'), [
          DBusStruct([
            const DBusString('search'),
            DBusDict.stringVariant({
              'trigger_description': const DBusString('Ctrl+Alt+Space'),
            }),
          ]),
        ]),
      };
    } else {
      return DBusMethodErrorResponse.unknownMethod();
    }
    Timer(
      const Duration(milliseconds: 1),
      () => request.emitSignal('org.freedesktop.portal.Request', 'Response', [
        DBusUint32(reject && call.name == 'BindShortcuts' ? 1 : 0),
        DBusDict.stringVariant(result),
      ]),
    );
    return DBusMethodSuccessResponse([request.path]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final reject in [false, true]) {
    test(
      'portal ${reject ? 'denial cleans session' : 'binds, receives activation token and releases session'}',
      () async {
        final server = DBusServer();
        final dir = await Directory.systemTemp.createTemp('folio-portal-');
        final address = await server.listenAddress(DBusAddress.unix(dir: dir));
        final owner = DBusClient(address);
        final session = _Session();
        final portal = _Portal(owner, session, reject: reject);
        await owner.requestName('org.freedesktop.portal.Desktop');
        await owner.registerObject(session);
        await owner.registerObject(portal);
        final activation = Completer<String?>();
        final shortcut = GlobalShortcut(
          activation.complete,
          usePortal: true,
          busFactory: () => DBusClient(address),
        );
        try {
          if (reject) {
            await expectLater(
              shortcut.register(const FolioShortcut()),
              throwsStateError,
            );
            expect(session.closed, isTrue);
          } else {
            expect(
              await shortcut.register(const FolioShortcut()),
              'Ctrl+Alt+Space',
            );
            expect(portal.trigger, 'CTRL+ALT+space');
            expect(portal.registeredApp, 'com.erkanoz.evrak_convert');
            await shortcut.configure();
            expect(portal.configured, isTrue);
            await portal.emitSignal(interface, 'Activated', [
              session.path,
              const DBusString('search'),
              const DBusUint64(1),
              DBusDict.stringVariant({
                'activation_token': const DBusString('synthetic-token'),
              }),
            ]);
            expect(
              await activation.future.timeout(const Duration(seconds: 2)),
              'synthetic-token',
            );
            await shortcut.unregister();
            expect(session.closed, isTrue);
          }
        } finally {
          await shortcut.dispose();
          await owner.close();
          await server.close();
          await dir.delete(recursive: true);
        }
      },
    );
  }
}
