// Ölçüm (paketin parçası değil): ana sayfa aramasının hızı, gerçek
// verinin KOPYASINDA. Yalnız süre ve sayı yazar.
//
//   OLCUM_DB=/kopya/portal.sqlite OLCUM_DESTEK=/kopya/destek \
//     flutter test tool/olcum/arama_hizi_olcumu_test.dart
import 'dart:io';

import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/ui/search/global_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ölçüm', () async {
    final path = Platform.environment['OLCUM_DB'];
    final support = Platform.environment['OLCUM_DESTEK'];
    if (path == null || support == null) return markTestSkipped('yok');
    final db = PortalDatabase.open(path);
    final search = GlobalSearch(
      lawyer: 'Av. Deneme',
      database: db,
      store: UyapCaseStore(directory: Directory(support)),
    );
    for (final q in ['al', 'ali', 'ali v', 'ali va', 'ali var', 'ali varo']) {
      final watch = Stopwatch()..start();
      final r = await search.find(q);
      stdout.writeln(
        '"${q.length} harf" ${watch.elapsedMilliseconds} ms · '
        '${r.cases.total} dosya, ${r.documents.total} evrak',
      );
    }
    db.dispose();
  });
}
