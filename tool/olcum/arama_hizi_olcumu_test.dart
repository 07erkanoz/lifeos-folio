// Ölçüm (paketin parçası değil): ana sayfa aramasının hızı, gerçek
// verinin KOPYASINDA. Yalnız süre ve sayı yazar. "pencere" sütunu,
// arama sürerken pencerenin en uzun takıldığı süredir: bir kare 16 ms.
//
//   OLCUM_DB=/kopya/portal.sqlite OLCUM_DESTEK=/kopya/destek \
//     flutter test tool/olcum/arama_hizi_olcumu_test.dart
import 'dart:async';
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
      inline: false,
    );

    /// [work]'s time, and the longest the event loop went unanswered.
    Future<(int, int)> timed(Future<void> Function() work) async {
      final watch = Stopwatch()..start();
      var last = 0, longest = 0;
      final tick = Timer.periodic(const Duration(milliseconds: 1), (_) {
        final now = watch.elapsedMilliseconds;
        if (now - last > longest) longest = now - last;
        last = now;
      });
      await work();
      final now = watch.elapsedMilliseconds;
      if (now - last > longest) longest = now - last;
      tick.cancel();
      return (now, longest);
    }

    final (ready, readyHeld) = await timed(search.prepare);
    stdout.writeln('hazırlık $ready ms · pencere en çok $readyHeld ms');
    for (final q in ['al', 'ali', 'ali v', 'ali va', 'ali var', 'ali varo']) {
      late GlobalSearchResults r;
      final (took, held) = await timed(() async => r = await search.find(q));
      stdout.writeln(
        '"${q.length} harf" $took ms · pencere en çok $held ms · '
        '${r.cases.total} dosya, ${r.documents.total} evrak',
      );
    }
    search.dispose();
    db.dispose();
  });
}
