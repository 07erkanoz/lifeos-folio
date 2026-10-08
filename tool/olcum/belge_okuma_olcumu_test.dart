// Ölçüm (paketin parçası değil): UETS paketlerinin belgeleri okununca ne
// değişiyor. Gerçek veritabanının KOPYASI üzerinde çalışır; yalnız sayı
// yazar, ad ya da içerik yazmaz.
//
//   OLCUM_DB=/kopya/portal.sqlite flutter test tool/olcum/belge_okuma_olcumu_test.dart
import 'dart:io';

import 'package:evrak_convert/services/pdf/pdfium_setup.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uets/notice_deadlines.dart';
import 'package:evrak_convert/services/uets/notice_documents.dart';
import 'package:evrak_convert/services/uets/notice_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/pdfium.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('ölçüm', () async {
    final path = Platform.environment['OLCUM_DB'];
    if (path == null) return markTestSkipped('OLCUM_DB yok');
    PdfiumSetup.pathOverride = pdfiumLibrary();
    final db = PortalDatabase.open(path);
    String count(Iterable<String> xs) {
      final m = <String, int>{};
      for (final x in xs) {
        m.update(x, (v) => v + 1, ifAbsent: () => 1);
      }
      return '$m';
    }

    final before = [for (final d in db.deadlines()) d.record];
    final untied = db.notices().where((n) => n.link == null).length;
    final watch = Stopwatch()..start();
    await readNoticeDocuments(
      db,
      onRead: (id) => tieByCaseFile(db, id),
    );
    final docs = [
      for (final e in db.envelopes().keys) ...db.noticeDocuments(e),
    ];
    stdout.writeln('okuma ${watch.elapsed.inSeconds} sn');
    stdout.writeln('belgeler ${docs.length} ${count(docs.map((d) => d.state))}');
    stdout.writeln(
      'bağlanmamış tebligat $untied → '
      '${db.notices().where((n) => n.link == null).length}',
    );
    refreshNoticeDeadlines(db);
    final after = [
      for (final d in db.deadlines())
        if (d.record.state != 'eski') d.record,
    ];
    stdout.writeln(
      'süre kaydı önce ${before.where((r) => r.state != 'eski').length} → '
      'sonra ${after.length}',
    );
    stdout.writeln(
      'türü içerikten ${after.where((r) => r.evidence['kaynak'] == 'ekIcerik').length}, '
      'ekteki talimattan ${after.where((r) => r.evidence['kaynak'] == 'ekTalimat').length}, '
      'zarftan ${after.where((r) => r.evidence['kaynak'] == 'zarf').length}',
    );
    stdout.writeln(
      'zarf/ek ile uyumlu ${after.where((r) => r.reasons.any((x) => x.code == 'zarfIleUyumlu')).length}',
    );
    stdout.writeln('durum ${count(after.map((r) => r.state))}');
    stdout.writeln('aidiyet ${count(after.map((r) => r.ownership))}');
    db.dispose();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
