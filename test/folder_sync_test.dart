import 'dart:io';

import 'package:evrak_convert/services/office/office_identity.dart';
import 'package:evrak_convert/services/office/office_known.dart';
import 'package:evrak_convert/services/office/office_ledger.dart';
import 'package:evrak_convert/services/office/office_network.dart';
import 'package:evrak_convert/services/office/office_peer.dart';
import 'package:evrak_convert/services/office/office_task.dart';
import 'package:evrak_convert/services/office/office_chat.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:evrak_convert/services/sync/folder_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('folio_folders_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<OfficeNetwork> folio(String device) async {
    final net = OfficeNetwork(
      settings: () async => File('${dir.path}/$device/buro.json'),
      known: KnownDevices(file: () async => File('${dir.path}/$device/k.json')),
      ledger: OfficeLedger(
        file: () async => File('${dir.path}/$device/d.json'),
      ),
      tasks: OfficeTasks(file: () async => File('${dir.path}/$device/g.json')),
      chats: OfficeChats(file: () async => File('${dir.path}/$device/m.json')),
    );
    Directory('${dir.path}/$device/gelen').createSync(recursive: true);
    net.inbox = () async => Directory('${dir.path}/$device/gelen');
    final identity = await OfficeIdentity.load(store: _Store());
    await net.listenForTesting(
      identity,
      OfficePeer(
        deviceId: identity.deviceId,
        userId: identity.userId,
        name: 'Av. Erkan Öz',
        device: device,
        platform: OfficePlatform.linux,
      ),
    );
    return net;
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 1500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  FolderSync folders(OfficeNetwork net, String device) => FolderSync(
    network: net,
    file: () async => File('${dir.path}/$device/senkron.json'),
    bin: () async => Directory('${dir.path}/$device/cop'),
    root: () => '${dir.path}/$device/Senkron',
  );

  test(
    'a folder kept alike: new, changed, taken off, and changed on both',
    () async {
      final pc = await folio('masaustu'), phone = await folio('telefon');
      pc.seenForTesting(phone.self!);
      phone.seenForTesting(pc.self!);
      final asking = pc.pair(phone.self!)!;
      await until(
        () => phone.incoming.value?.code != null && asking.code != null,
      );
      phone.incoming.value!.confirm();
      asking.confirm();
      await until(() => pc.self!.userId == phone.self!.userId);
      pc.seenForTesting(phone.self!);
      phone.seenForTesting(pc.self!);
      final onPc = folders(pc, 'masaustu'), onPhone = folders(phone, 'telefon');
      await onPc.start();
      await onPhone.start();
      final shared = Directory('${dir.path}/Dilekçeler')..createSync();
      File('${shared.path}/İtiraz.pdf').writeAsStringSync('ilk');
      Directory('${shared.path}/2026').createSync();
      File('${shared.path}/2026/Cevap.udf').writeAsStringSync('cevap');
      File('${shared.path}/notlar.tmp').writeAsStringSync('alınmaz');
      final f = await onPc.share(shared.path);
      await pc.syncOwn();
      await until(() => onPhone.offered.containsKey(f.id));
      await onPhone.join(f.id);
      final there = onPhone.folders[f.id]!.path;
      await phone.syncOwn();
      await until(() => File('$there/2026/Cevap.udf').existsSync());
      await until(() => File('$there/İtiraz.pdf').existsSync());
      expect(File('$there/notlar.tmp').existsSync(), isFalse);
      // Changed on the phone: the computer's is replaced.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      File('$there/İtiraz.pdf').writeAsStringSync('telefonda düzeltildi');
      await phone.syncOwn();
      await until(
        () =>
            File('${shared.path}/İtiraz.pdf').readAsStringSync() ==
            'telefonda düzeltildi',
      );
      // Taken off on the computer: to the bin on the phone.
      File('${shared.path}/2026/Cevap.udf').deleteSync();
      await pc.syncOwn();
      await until(() => !File('$there/2026/Cevap.udf').existsSync());
      final bin = Directory('${dir.path}/telefon/cop');
      expect(
        bin
            .listSync(recursive: true)
            .whereType<File>()
            .map((e) => e.uri.pathSegments.last),
        contains('Cevap.udf'),
      );
      // Changed on both before they met: both kept.
      File('${shared.path}/İtiraz.pdf').writeAsStringSync('masaüstünde');
      File('$there/İtiraz.pdf').writeAsStringSync('telefonda');
      await pc.syncOwn();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await phone.syncOwn();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await pc.syncOwn();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      List<String> words(String folder) => [
        for (final e in Directory(folder).listSync())
          if (e is File && e.path.contains('İtiraz')) e.readAsStringSync(),
      ]..sort();
      await until(
        () => words(shared.path).length == 2 && words(there).length == 2,
      );
      expect(words(shared.path), ['masaüstünde', 'telefonda']);
      expect(words(there), words(shared.path));
    },
  );
}

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
