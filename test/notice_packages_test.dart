import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uets/eyp_package.dart';
import 'package:evrak_convert/services/uets/notice_deadlines.dart';
import 'package:evrak_convert/services/uets/notice_packages.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _zip(Map<String, List<int>> files) {
  final a = Archive();
  for (final e in files.entries) {
    a.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(a));
}

// Every notice's package comes down by itself: its envelope and documents
// kept on this computer, the envelope's directives in its deadlines.
void main() {
  late HttpServer server;
  late UetsApi api;
  late PortalDatabase db;
  late Directory root;
  var package = Uint8List(0);
  var busyOnce = false;
  final asked = <String>[];

  setUp(() async {
    asked.clear();
    busyOnce = false;
    root = Directory.systemTemp.createTempSync('folio-uets-');
    package = _zip({
      'UstYazi/ustyazi.pdf': utf8.encode('%PDF zarf'),
      'Ekler/EK-1.pdf': utf8.encode('%PDF rapor'),
      'Ustveri/Ustveri.xml': utf8.encode('<ustveri/>'),
      'Imzalar/ImzaCades.imz': [1, 2, 3],
    });
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      await utf8.decoder.bind(r).join();
      final path = r.uri.path.replaceFirst('/v1/', '');
      asked.add(path);
      if (path == 'messages/m1/_download') {
        if (busyOnce) {
          busyOnce = false;
          r.response.statusCode = 429;
          r.response.headers.set('Retry-After', '0');
        } else {
          r.response.add(package);
        }
      } else if (path.startsWith('auth/_mobil_imza') && r.method == 'POST') {
        r.response.statusCode = 201;
        r.response.write(
          jsonEncode({'transaction_id': 't', 'fingerprint': 'A'}),
        );
      } else if (path.startsWith('auth/_mobil_imza')) {
        r.response.write(jsonEncode({'status': 'ok'}));
      } else if (path == 'clients/_authentication') {
        r.response.write(
          jsonEncode({
            'access_token': 'k' * 40,
            'expire_time':
                DateTime.now()
                    .add(const Duration(minutes: 25))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
        );
      } else {
        r.response.write('[]');
      }
      await r.response.close();
    });
    api = UetsApi.forTesting(
      Uri.parse('http://127.0.0.1:${server.port}/v1/'),
      pollEvery: const Duration(milliseconds: 5),
    );
    final l = await api.startMobile(
      tckn: '10000000146',
      phone: '5321234567',
      operator: MobileOperator.turkcell,
    );
    await api.finishMobile(l);
    db = PortalDatabase.memory();
    db.mergeNotices([
      UetsMessage(
        id: 'm1',
        subject: 'Antalya 4. Asliye Hukuk Mahkemesi [2025/118] [x]',
        sent: DateTime.utc(2026, 9, 30, 9),
        barcode: '5003000000001',
      ),
    ]);
    db.saveManifest('m1', [
      (id: 'p1', name: '(1)dosyaBilgileriV1.xml', mime: ''),
      (id: 'p2', name: '(2)BilirkisiRaporu.pdf', mime: ''),
    ]);
  });
  tearDown(() async {
    db.dispose();
    await server.close(force: true);
    root.deleteSync(recursive: true);
  });

  Future<void> fetch(String envelopeText, {Set<String>? only}) =>
      fetchNoticePackages(
        api,
        db,
        root: root.path,
        gap: Duration.zero,
        readText: (_) async => envelopeText,
        now: DateTime(2026, 10, 6),
        only: only,
        recent: only == null ? autoPackageWindow : null,
      );

  test('the package is kept: the envelope, the documents under their own '
      'names, its text', () async {
    await fetch(
      'Rapora itirazlarınızı tebliğden itibaren iki hafta içinde '
      'bildirmeniz ihtar olunur.',
    );
    final e = db.envelope('m1')!;
    expect(e.state, 'indirildi');
    expect(File(e.envelopePath!).existsSync(), isTrue);
    expect(e.envelopePath, endsWith('Tebligat zarfı.pdf'));
    expect(e.attachments.map((a) => a.name), ['BilirkisiRaporu.pdf']);
    expect(File(e.attachments.single.path).readAsStringSync(), '%PDF rapor');
    expect(e.folder, contains('Antalya 4. Asliye Hukuk Mahkemesi 2025-118'));
    // Asked once; the next sync does not fetch it again.
    await fetch('x');
    expect(asked.where((a) => a.endsWith('_download')), hasLength(1));
  });

  test('the envelope’s time that is the law’s joins it as its second '
      'source', () async {
    await fetch(
      'Rapora itirazlarınızı tebliğden itibaren iki hafta içinde '
      'bildirmeniz ihtar olunur.',
    );
    refreshNoticeDeadlines(db, now: DateTime(2026, 10, 6));
    final d = db.deadlines(noticeId: 'm1');
    expect(d.map((x) => x.record.ruleId), ['hmk281']);
    expect(
      d.single.record.reasons.map((r) => r.code),
      contains('zarfIleUyumlu'),
    );
  });

  test(
    'a time of its own is a deadline of its own, each told of the other',
    () async {
      await fetch('Gider avansını bir hafta içinde yatırmanız ihtar olunur.');
      refreshNoticeDeadlines(db, now: DateTime(2026, 10, 6));
      final d = {
        for (final x in db.deadlines(noticeId: 'm1')) x.record.ruleId: x,
      };
      expect(d.keys, containsAll(['hmk281', 'zarf-odeme-1hafta']));
      final own = d['zarf-odeme-1hafta']!.record;
      // Served 5 October; a week: 12 October.
      expect(own.dueDay, '2026-10-12');
      expect(
        own.reasons.map((r) => r.code),
        containsAll(['zarfAlinti', 'zarfFarkli', 'baslangicVarsayildi']),
      );
      expect(
        d['hmk281']!.record.reasons.map((r) => r.code),
        contains('zarfFarkli'),
      );
    },
  );

  test('UETS’s "ask less often" is waited out', () async {
    busyOnce = true;
    await fetch('x');
    expect(db.envelope('m1')!.state, 'indirildi');
    expect(asked.where((a) => a.endsWith('_download')), hasLength(2));
  });

  test('a damaged package is kept as such, never as "no envelope"', () async {
    package = Uint8List.fromList(utf8.encode('not a zip'));
    await fetch('x');
    expect(db.envelope('m1')!.state, 'hata');
  });

  test('a package that would write outside its folder is refused', () {
    expect(
      () => EypPackage.read(
        _zip({
          '../../evil.pdf': [1],
        }),
      ),
      throwsFormatException,
    );
  });

  test('a notice older than forty days waits until it is asked for', () async {
    db.mergeNotices([
      UetsMessage(
        id: 'old',
        subject: 'Antalya 4. Asliye Hukuk Mahkemesi [2025/1] [x]',
        sent: DateTime.utc(2026, 7, 1, 9),
      ),
    ]);
    await fetch('x');
    expect(db.envelope('m1'), isNotNull);
    expect(db.envelope('old'), isNull);
    expect(asked, isNot(contains('messages/old/_download')));
    await fetch('x', only: {'old'});
    expect(asked, contains('messages/old/_download'));
  });
}
