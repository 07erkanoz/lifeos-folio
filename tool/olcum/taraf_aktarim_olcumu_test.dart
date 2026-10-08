// Ölçüm (paketin parçası değil): kaydedilmiş UYAP dosyalarının taraflarını
// veritabanının KOPYASINA yazar; kaç dosya, kaç taraf, kaç müvekkil. Yalnız
// sayı yazar.
//
//   OLCUM_DB=/kopya/portal.sqlite OLCUM_DESTEK=/kopya/destek \
//     OLCUM_AVUKAT='Ad Soyad' flutter test tool/olcum/taraf_aktarim_olcumu_test.dart
import 'dart:io';

import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ölçüm', () async {
    final path = Platform.environment['OLCUM_DB'];
    final support = Platform.environment['OLCUM_DESTEK'];
    if (path == null || support == null) return markTestSkipped('yok');
    final db = PortalDatabase.open(path);
    final store = UyapCaseStore(directory: Directory(support));
    var parties = 0;
    final keys = <String>[];
    for (final (record, _) in await store.cases()) {
      if (record.parties.isEmpty) continue;
      final key = caseKey(record.number, record.court);
      db.saveCaseParties(key, record.parties, source: 'uyap');
      keys.add(key);
      parties += record.parties.length;
    }
    final lawyer = Platform.environment['OLCUM_AVUKAT'];
    final withClients = keys
        .where((k) => db.clientsOf(k, lawyer: lawyer).isNotEmpty)
        .length;
    final clients = {
      for (final k in keys)
        for (final c in db.clientsOf(k, lawyer: lawyer)) c.ad,
    };
    stdout.writeln(
      'dosya ${keys.length}, taraf satırı $parties, '
      'müvekkili belli dosya $withClients, ayrı müvekkil ${clients.length}',
    );
    // Written again unchanged: nothing written.
    for (final (record, _) in await store.cases()) {
      if (record.parties.isEmpty) continue;
      db.saveCaseParties(
        caseKey(record.number, record.court),
        record.parties,
        source: 'uyap',
      );
    }
    db.dispose();
  });
}
