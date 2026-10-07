import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hash;
import 'package:evrak_convert/services/office/office_identity.dart';
import 'package:evrak_convert/services/office/office_known.dart';
import 'package:evrak_convert/services/office/office_link.dart';
import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/services/office/office_pairing.dart';
import 'package:evrak_convert/services/office/office_peer.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:evrak_convert/ui/office/office_network_page.dart';
import 'package:evrak_convert/ui/office/office_pairing_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends SecretStore {
  final kept = <String, Map<String, Object?>>{};
  @override
  Future<bool> write(String name, Map<String, Object?> value) async {
    kept[name] = value;
    return true;
  }

  @override
  Future<Map<String, Object?>?> read(String name) async => kept[name];
}

/// Two Folios on this machine, speaking over real sockets on loopback, as
/// two devices of an office would.
void main() {
  late Directory dir;
  late OfficeNetwork a, b;

  Future<OfficeNetwork> folio(String name, String device) async {
    final net = OfficeNetwork(
      settings: () async => File('${dir.path}/$device.json'),
      known: KnownDevices(file: () async => File('${dir.path}/$device-k.json')),
    );
    final identity = await OfficeIdentity.load(store: _Store());
    await net.listenForTesting(
      identity,
      OfficePeer(
        deviceId: identity.deviceId,
        userId: identity.userId,
        name: name,
        device: device,
        platform: OfficePlatform.linux,
      ),
    );
    return net;
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('folio_pair_');
    a = await folio('Av. Deniz Kaya', 'deniz-pc');
    b = await folio('Av. Mert Yıldız', 'mert-pc');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'the same code on both screens, both say so: each knows the other',
    () async {
      final asking = a.pair(b.self!)!;
      await until(() => b.incoming.value != null);
      final asked = b.incoming.value!;
      await until(() => asking.code != null && asked.code != null);
      expect(asking.code, asked.code);
      expect(asking.code, matches(RegExp(r'^\d{3} \d{3}$')));
      expect(asked.other!.name, 'Av. Deniz Kaya');
      asked.confirm();
      // One side's word is not enough.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(a.isKnown(b.self!.deviceId), isFalse);
      expect(b.isKnown(a.self!.deviceId), isFalse);
      asking.confirm();
      await until(() => asking.state == PairingState.done);
      await until(() => asked.state == PairingState.done);
      expect(a.isKnown(b.self!.deviceId), isTrue);
      expect(b.isKnown(a.self!.deviceId), isTrue);
      // The key kept is the other's own.
      final kept = a.known.single;
      expect(
        OfficeIdentity.idOf(base64Decode(kept.publicKey)),
        b.self!.deviceId,
      );
      expect(kept.name, 'Av. Mert Yıldız');
      // Kept on disk; forgotten when asked.
      final again = await KnownDevices(
        file: () async => File('${dir.path}/deniz-pc-k.json'),
      ).all();
      expect(again.single.deviceId, b.self!.deviceId);
      await a.forget(b.self!.deviceId);
      expect(a.isKnown(b.self!.deviceId), isFalse);
    },
  );

  test('one says no: neither knows the other', () async {
    final asking = a.pair(b.self!)!;
    await until(() => b.incoming.value?.code != null);
    b.incoming.value!.reject();
    await until(() => asking.state == PairingState.rejected);
    expect(a.known, isEmpty);
    expect(b.known, isEmpty);
  });

  test('one between who changes its number is found out', () async {
    // Commits to one number, then shows another, as someone choosing a
    // number after hearing the other's would have to.
    final identity = await OfficeIdentity.load(store: _Store());
    final link = await OfficeLink.connect('127.0.0.1', b.self!.port);
    final key = identity.devicePublic.bytes;
    final committed = List<int>.filled(32, 1), shown = List<int>.filled(32, 2);
    link.send({
      't': 'pair',
      'v': 1,
      'id': identity.deviceId,
      'dk': base64Encode(key),
      'u': identity.userId,
      'n': 'Av. Aracı',
      'c': 'arada',
      'p': 'linux',
      'commit': base64Encode(hash.sha256.convert([...key, ...committed]).bytes),
    });
    final answered = Completer<void>();
    link.messages.listen((m) {
      if (m['t'] == 'pair-ok' && !answered.isCompleted) {
        answered.complete();
        link.send({'t': 'reveal', 'nonce': base64Encode(shown)});
      }
    });
    await answered.future;
    await until(() => b.incoming.value?.finished ?? false);
    expect(b.incoming.value!.state, PairingState.failed);
    expect(b.incoming.value!.code, isNull);
    expect(b.known, isEmpty);
    await link.close();
  });

  test('a device that says it is another is not listened to', () async {
    final identity = await OfficeIdentity.load(store: _Store());
    final link = await OfficeLink.connect('127.0.0.1', b.self!.port);
    link.send({
      't': 'pair',
      'v': 1,
      'id': 'aaaaaaaaaaaaaaaa',
      'dk': base64Encode(identity.devicePublic.bytes),
      'u': identity.userId,
      'commit': base64Encode(List<int>.filled(32, 0)),
    });
    await until(() => b.incoming.value == null || b.incoming.value!.finished);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(b.incoming.value?.state ?? PairingState.failed, PairingState.failed);
    await link.close();
  });

  test('while one is being known, another is told to wait', () async {
    final first = a.pair(b.self!)!;
    await until(() => b.incoming.value?.code != null);
    final c = await folio('Av. Selin Aksoy', 'selin-pc');
    final second = c.pair(b.self!)!;
    await until(() => second.finished);
    expect(second.state, PairingState.failed);
    expect(second.reason, contains('başka bir cihazı'));
    expect(first.finished, isFalse);
    first.reject();
  });

  test(
    'the code is the same whoever reckons it, and changes with any part',
    () {
      final k1 = List<int>.filled(32, 7), k2 = List<int>.filled(32, 8);
      final n1 = List<int>.filled(32, 1), n2 = List<int>.filled(32, 2);
      final code = OfficePairing.codeOf(k1, k2, n1, n2);
      expect(OfficePairing.codeOf(k1, k2, n1, n2), code);
      expect(OfficePairing.codeOf(k2, k1, n1, n2), isNot(code));
      expect(OfficePairing.codeOf(k1, k2, n2, n1), isNot(code));
    },
  );

  testWidgets('the page offers to know a device, shows the known, forgets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final asking = a.pair(b.self!)!;
      await until(() => b.incoming.value?.code != null);
      b.incoming.value!.confirm();
      asking.confirm();
      await until(() => a.isKnown(b.self!.deviceId));
    });
    final c = OfficePeer(
      deviceId: 'cccccccccccccccc',
      userId: 'uc',
      name: 'Av. Selin Aksoy',
      device: 'selin-pc',
      platform: OfficePlatform.windows,
      host: '127.0.0.1',
      port: 9,
    );
    a.seenForTesting(c);
    a.seenForTesting(b.self!);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OfficeNetworkPage(network: a)),
      ),
    );
    await tester.pump();
    // The unknown one can be known; the known one is marked, not offered.
    expect(find.byKey(ValueKey('office-pair-${c.deviceId}')), findsOneWidget);
    expect(
      find.byKey(ValueKey('office-pair-${b.self!.deviceId}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('office-known-${b.self!.deviceId}')),
      findsOneWidget,
    );
    await tester.runAsync(() async {
      await a.forget(b.self!.deviceId);
    });
    await tester.pump();
    expect(
      find.byKey(ValueKey('office-pair-${b.self!.deviceId}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dialog shows the code and takes the user\'s word', (
    tester,
  ) async {
    late OfficePairing asking;
    await tester.runAsync(() async {
      asking = a.pair(b.self!)!;
      await until(() => b.incoming.value?.code != null && asking.code != null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OfficePairingDialog(pairing: b.incoming.value!)),
      ),
    );
    expect(find.text(asking.code!), findsOneWidget);
    expect(find.textContaining('Av. Deniz Kaya'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pairing-confirm')));
    await tester.pump();
    expect(find.text('Karşı tarafın onayı bekleniyor…'), findsOneWidget);
    await tester.runAsync(() async {
      asking.confirm();
      await until(() => b.incoming.value!.state == PairingState.done);
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('pairing-close')), findsOneWidget);
    expect(find.textContaining('tanındı'), findsOneWidget);
  });
}
