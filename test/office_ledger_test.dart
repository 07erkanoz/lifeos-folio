import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/office/office_identity.dart';
import 'package:evrak_convert/services/office/office_known.dart';
import 'package:evrak_convert/services/office/office_ledger.dart';
import 'package:evrak_convert/services/office/office_peer.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
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

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('folio_ledger_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<(OfficeIdentity, OfficePeer, KnownDevice)> device(String name) async {
    final id = await OfficeIdentity.load(store: _Store());
    final peer = OfficePeer(
      deviceId: id.deviceId,
      userId: id.userId,
      name: name,
      device: '$name-pc',
      platform: OfficePlatform.windows,
    );
    final known = KnownDevice(
      deviceId: id.deviceId,
      userId: id.userId,
      publicKey: base64Encode(id.devicePublic.bytes),
      name: name,
      device: '$name-pc',
      platform: OfficePlatform.windows,
      knownAt: DateTime.now(),
    );
    return (id, peer, known);
  }

  OfficeLedger ledger(String n) =>
      OfficeLedger(file: () async => File('${dir.path}/$n.json'));

  test(
    'the founder manages; members are taken in, given roles, let go',
    () async {
      final (deniz, denizPeer, _) = await device('Av. Deniz Kaya');
      final (mert, _, mertKnown) = await device('Stj. Av. Mert Yıldız');
      final (_, _, selinKnown) = await device('Av. Selin Aksoy');
      final l = ledger('a');
      await l.found(deniz, denizPeer, 'Kaya Hukuk Bürosu');
      expect(l.officeName, 'Kaya Hukuk Bürosu');
      expect(l.isManager(deniz.deviceId), isTrue);
      expect(await l.admit(deniz, mertKnown, OfficeRole.trainee), isNull);
      expect(await l.admit(deniz, selinKnown, OfficeRole.lawyer), isNull);
      expect(l.members, hasLength(3));
      // A trainee signs nothing that counts.
      expect(
        await l.setRole(mert, mert.deviceId, OfficeRole.manager),
        isNotNull,
      );
      expect(l.member(mert.deviceId)!.role, OfficeRole.trainee);
      // The only manager is not demoted or let go.
      expect(
        await l.setRole(deniz, deniz.deviceId, OfficeRole.lawyer),
        isNotNull,
      );
      expect(await l.remove(deniz, deniz.deviceId), isNotNull);
      expect(l.isManager(deniz.deviceId), isTrue);
      // A second manager, who then lets someone go.
      expect(
        await l.setRole(deniz, selinKnown.deviceId, OfficeRole.manager),
        isNull,
      );
      expect(await l.remove(deniz, mert.deviceId), isNull);
      expect(l.member(mert.deviceId), isNull);
      // Kept on disk as it was.
      final again = ledger('a');
      await again.load();
      expect(
        again.members.map((m) => m.name),
        unorderedEquals(['Av. Deniz Kaya', 'Av. Selin Aksoy']),
      );
      expect(again.officeId, l.officeId);
    },
  );

  test(
    'another member takes the ledger; a forged or changed record is not',
    () async {
      final (deniz, denizPeer, _) = await device('Av. Deniz Kaya');
      final (mert, _, mertKnown) = await device('Stj. Av. Mert Yıldız');
      final a = ledger('a');
      await a.found(deniz, denizPeer, 'Kaya Hukuk Bürosu');
      await a.admit(deniz, mertKnown, OfficeRole.trainee);
      final b = ledger('b');
      expect(await b.merge(a.records), isTrue);
      expect(b.officeId, a.officeId);
      expect(b.member(mert.deviceId)!.role, OfficeRole.trainee);
      // Changed after signing: a trainee made manager by editing the record.
      final changed = Map<String, Object?>.from(a.records.last)
        ..['rol'] = 'manager';
      final c = ledger('c');
      await c.merge([a.records.first, changed]);
      expect(c.member(mert.deviceId), isNull);
      // Another office's founding does not move a member to it.
      final (other, otherPeer, _) = await device('Av. Okan Tekin');
      final o = ledger('o');
      await o.found(other, otherPeer, 'Başka Büro');
      await b.merge(o.records);
      expect(b.officeId, a.officeId);
    },
  );

  test('no other manager demotes or lets go the founder', () async {
    final (deniz, denizPeer, denizKnown) = await device('Av. Deniz Kaya');
    final (murat, _, muratKnown) = await device('Av. Murat Er');
    final l = ledger('f');
    await l.found(deniz, denizPeer, 'Kaya Hukuk Bürosu');
    await l.admit(deniz, muratKnown, OfficeRole.manager);
    expect(await l.remove(murat, denizKnown.deviceId), isNotNull);
    expect(
      await l.setRole(murat, denizKnown.deviceId, OfficeRole.trainee),
      isNotNull,
    );
    expect(l.member(deniz.deviceId)!.role, OfficeRole.manager);
    // The founder can let the other manager go.
    expect(await l.remove(deniz, murat.deviceId), isNull);
  });
}
