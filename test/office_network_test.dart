import 'dart:io';

import 'package:evrak_convert/services/office/office_identity.dart';
import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/services/office/office_peer.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:evrak_convert/ui/office/office_network_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A safe store in memory; or one that keeps nothing, as a Linux without a
/// keyring does.
class _Store extends SecretStore {
  _Store({this.keeps = true});
  final bool keeps;
  final kept = <String, Map<String, Object?>>{};

  @override
  Future<bool> write(String name, Map<String, Object?> value) async {
    if (!keeps) return false;
    kept[name] = value;
    return true;
  }

  @override
  Future<Map<String, Object?>?> read(String name) async => kept[name];
}

OfficePeer peer(
  String id,
  String name, {
  String user = 'u',
  OfficePlatform platform = OfficePlatform.windows,
  bool online = true,
}) => OfficePeer(
  deviceId: id,
  userId: user + id,
  name: name,
  device: 'cihaz-$id',
  platform: platform,
  online: online,
  lastSeen: DateTime(2026, 10, 8, 9, 30),
);

void main() {
  test('the keys are made once and read back the same', () async {
    final store = _Store();
    final first = await OfficeIdentity.load(store: store);
    final again = await OfficeIdentity.load(store: store);
    expect(first.kept, isTrue);
    expect(again.deviceId, first.deviceId);
    expect(again.userId, first.userId);
    expect(first.deviceId, isNot(first.userId));
    expect(first.deviceId, hasLength(16));
  });

  test('without a safe store the keys last only this run', () async {
    final store = _Store(keeps: false);
    final first = await OfficeIdentity.load(store: store);
    final again = await OfficeIdentity.load(store: store);
    expect(first.kept, isFalse);
    expect(again.deviceId, isNot(first.deviceId));
  });

  test('an announcement carries who and what, and is read back', () {
    final mine = peer('a1', 'Av. Deniz Yılmaz', platform: OfficePlatform.linux);
    final back = OfficePeer.fromAnnouncement(
      mine.attributes,
      host: '192.168.1.20',
      port: 4040,
    )!;
    expect(back.deviceId, 'a1');
    expect(back.name, 'Av. Deniz Yılmaz');
    expect(back.platform, OfficePlatform.linux);
    expect(back.host, '192.168.1.20');
    expect(back.port, 4040);
    // Nothing but these: no file, no client.
    expect(
      mine.attributes.keys,
      unorderedEquals(['v', 'id', 'u', 'n', 'c', 'p']),
    );
    // Not a Folio's, or of a protocol to come.
    expect(OfficePeer.fromAnnouncement(const {'n': 'x'}), isNull);
    expect(
      OfficePeer.fromAnnouncement(const {'id': 'a', 'u': 'b', 'v': '0'}),
      isNull,
    );
  });

  test('words heard before the address do not lose it', () {
    final placed = OfficePeer.fromAnnouncement(
      peer('a', 'Av. Deniz Kaya').attributes,
      host: '192.168.1.9',
      port: 4040,
    )!;
    final words = OfficePeer.fromAnnouncement(
      peer('a', 'Av. Deniz Kaya').attributes,
    )!;
    final kept = words.keepingPlaceOf(placed);
    expect(kept.host, '192.168.1.9');
    expect(kept.port, 4040);
    expect(placed.keepingPlaceOf(null).port, 4040);
    // An IPv6 address heard after an IPv4 one does not replace it.
    final v6 = OfficePeer.fromAnnouncement(
      peer('a', 'Av. Deniz Kaya').attributes,
      host: 'fd8d::1',
      port: 4040,
    )!;
    expect(v6.keepingPlaceOf(placed).host, '192.168.1.9');
    expect(placed.keepingPlaceOf(v6).host, '192.168.1.9');
  });

  test('devices are put under their people, the user first', () {
    final self = peer('s', 'Av. Deniz Yılmaz', platform: OfficePlatform.linux);
    final people = groupPeople([
      peer('p1', 'Av. Mert Yıldız', online: false),
      // The same lawyer's phone, its key not yet shared: by the name.
      peer('p2', 'AV. DENİZ YILMAZ', platform: OfficePlatform.android),
      peer('p3', 'Av. Deniz Kaya'),
      peer('p4', 'Av. Deniz Kaya', platform: OfficePlatform.ios),
      // This device's own announcement, heard back.
      self,
    ], self: self);
    expect(people.map((p) => p.name), [
      'Av. Deniz Yılmaz',
      'Av. Deniz Kaya',
      'Av. Mert Yıldız',
    ]);
    expect(people.first.self, isTrue);
    expect(people.first.devices.map((d) => d.deviceId), ['s', 'p2']);
    expect(people[1].devices, hasLength(2));
    expect(people.last.online, isFalse);
  });

  testWidgets('the page asks before joining, then lists the people', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('folio_office_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final net = OfficeNetwork(settings: () async => File('${dir.path}/b.json'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OfficeNetworkPage(network: net)),
      ),
    );
    await tester.pump();
    expect(find.text('Büro ağına katılın'), findsOneWidget);
    expect(find.byKey(const ValueKey('office-join')), findsOneWidget);
    net.seenForTesting(
      peer('p3', 'Av. Deniz Kaya'),
      self: peer('s', 'Av. Deniz Yılmaz', platform: OfficePlatform.linux),
    );
    net.seenForTesting(peer('p1', 'Av. Mert Yıldız', online: false));
    await tester.pump();
    expect(find.text('Kişiler ve cihazlar'), findsOneWidget);
    expect(find.textContaining('Aynı ağda 3 kişi, 3 cihaz'), findsOneWidget);
    expect(find.textContaining('(siz)', findRichText: true), findsOneWidget);
    expect(find.textContaining('kapalı', findRichText: true), findsOneWidget);
    expect(find.byKey(const ValueKey('office-leave')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lawyer keeping only their own devices alike is no office: '
      'the page asks to join it, and another\'s nameless device is on no '
      'list', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('folio_office_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final net = OfficeNetwork(settings: () async => File('${dir.path}/b.json'));
    net.seenForTesting(
      peer('p3', ''),
      self: peer('s', '', platform: OfficePlatform.linux),
      office: false,
    );
    expect(net.officeOpen, isFalse);
    expect(net.people.expand((p) => p.devices).map((d) => d.deviceId), ['s']);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OfficeNetworkPage(network: net)),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('office-join')), findsOneWidget);
  });

  testWidgets('the page fits a phone', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('folio_office_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final net = OfficeNetwork(settings: () async => File('${dir.path}/b.json'));
    net.seenForTesting(
      peer('p3', 'Av. Deniz Kaya Yılmazoğulları'),
      self: peer('s', 'Av. Deniz Yılmaz', platform: OfficePlatform.android),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OfficeNetworkPage(network: net)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Av. Deniz Kaya Yılmazoğulları'), findsOneWidget);
  });
}
