// Karşılaştırma (paketin parçası değil): gerçek veritabanının KOPYASINDA,
// her tebligat için önceki ve yeni süreleri yan yana yazar; avukat kendi
// dosyalarını bilerek denetlesin diye. Rapor müvekkil bilgisi taşır: yalnız
// bu bilgisayarda kalır, depoya girmez.
//
//   OLCUM_DB=/kopya/portal.sqlite RAPOR=/yol/rapor.md \
//     flutter test tool/olcum/sure_karsilastirma_test.dart
import 'dart:io';

import 'package:evrak_convert/services/pdf/pdfium_setup.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_deadline.dart';
import 'package:evrak_convert/services/uets/notice_deadlines.dart';
import 'package:evrak_convert/services/uets/notice_documents.dart';
import 'package:evrak_convert/services/uets/notice_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/pdfium.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('karşılaştırma', () async {
    final path = Platform.environment['OLCUM_DB'];
    final out = Platform.environment['RAPOR'];
    if (path == null || out == null) return markTestSkipped('OLCUM_DB yok');
    PdfiumSetup.pathOverride = pdfiumLibrary();
    final db = PortalDatabase.open(path);
    String day(String? key) {
      if (key == null) return 'gün yok';
      final p = key.split('-');
      return '${p[2]}.${p[1]}.${p[0]}';
    }

    String line(DeadlineRecord r) =>
        '${r.title} · ${day(r.dueDay)}'
        '${r.state == 'olayBekleniyor' ? ' (olay bekleniyor)' : ''}';
    final before = <String, List<String>>{};
    for (final d in db.deadlines()) {
      if (d.record.state == 'eski') continue;
      (before[d.record.noticeId] ??= []).add(line(d.record));
    }
    await readNoticeDocuments(db, onRead: (id) => tieByCaseFile(db, id));
    refreshNoticeDeadlines(db);
    final now = DateTime.now();
    final b = StringBuffer()
      ..writeln('# Süre karşılaştırması · ${now.day}.${now.month}.${now.year}')
      ..writeln()
      ..writeln(
        'Gerçek tebligatların kopyası üzerinde, yeni motorla (ekler okunarak) '
        'yapıldı. Uygulamadaki kayıtlar değişmedi. Taraf listesi bu araçta '
        'yüklenmediği için “kimin süresi” sütunu yoktur. Yalnız son 120 günün '
        'tebligatları ve değişen ya da süresi olanlar listelenir.',
      )
      ..writeln();
    var shown = 0;
    final notices = db.notices()
      ..sort(
        (x, y) => (y.message.sent ?? DateTime(0)).compareTo(
          x.message.sent ?? DateTime(0),
        ),
      );
    for (final n in notices) {
      final sent = n.message.sent;
      if (sent == null || now.difference(sent).inDays > 120) continue;
      final id = n.message.id;
      final after = [
        for (final d in db.deadlines(noticeId: id))
          if (d.record.state != 'eski') d.record,
      ];
      final was = before[id] ?? const [];
      final now_ = [for (final r in after) line(r)];
      final docs = db.noticeDocuments(id);
      final unread = [
        for (final d in docs)
          if (!d.read) '${d.name} (${d.state})',
      ];
      if (was.isEmpty && now_.isEmpty && unread.isEmpty) continue;
      shown++;
      b
        ..writeln('## ${n.message.subject}')
        ..writeln()
        ..writeln(
          '- Kutuya giriş: ${sent.day}.${sent.month}.${sent.year}'
          '${n.caseKey == null ? ' · dosyaya bağlı değil' : ''}',
        )
        ..writeln(
          '- Belgeler: ${docs.where((d) => d.state != 'ustveri').length}'
          '${unread.isEmpty ? ', hepsi okundu' : '; okunamayan: ${unread.join(', ')}'}',
        )
        ..writeln('- Önce: ${was.isEmpty ? '—' : was.join('; ')}')
        ..writeln('- Şimdi:');
      if (after.isEmpty) b.writeln('  - —');
      for (final r in after) {
        final quote = r.reasons
            .where((x) => x.code == 'zarfAlinti' || x.code == 'zarfIleUyumlu')
            .map((x) => x.text)
            .firstOrNull;
        b.writeln(
          '  - ${line(r)} · ${r.law} · kaynak: ${r.evidence['kaynak']}'
          '${quote == null ? '' : '\n    - ${quote.length > 300 ? '${quote.substring(0, 300)}…' : quote}'}',
        );
      }
      b.writeln();
    }
    b.writeln('Listelenen tebligat: $shown');
    File(out).writeAsStringSync(b.toString());
    db.dispose();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
