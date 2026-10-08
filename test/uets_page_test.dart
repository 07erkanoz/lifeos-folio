import 'dart:io';

import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_deadline.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/uets/notice_documents.dart';
import 'package:evrak_convert/services/uets/notice_deadlines.dart';
import 'package:evrak_convert/services/uets/notice_matcher.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/agenda/uets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 6, 9);

  Future<PortalDatabase> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    void Function(PortalDatabase db)? before,
    UyapCaseStore? store,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.mergeCases([
      PortalCase.create(
        number: '2025/412',
        court: 'Antalya 3. Asliye Hukuk Mahkemesi',
      ),
      PortalCase.create(number: '2026/77', court: 'Antalya 1. İcra Dairesi'),
    ]);
    db.mergeNotices([
      UetsMessage(
        id: 'm1',
        subject:
            'Antalya 3. Asliye Hukuk Mahkemesi [2025/412] [Gerekçeli Karar]',
        sent: DateTime(2026, 10, 1, 10),
      ),
      UetsMessage(
        id: 'm2',
        subject: 'İzmir 2. Sulh Hukuk Mahkemesi [2026/5] [Duruşma Davetiyesi]',
        sent: DateTime(2026, 9, 20, 10),
        read: DateTime(2026, 9, 21),
      ),
    ]);
    before?.call(db);
    matchNotices(db, now: now);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UetsPage(
            database: db,
            sync: PortalSync(
              web: UyapWebService.forTesting(),
              mobile: UyapMobileApi.forTesting(
                Uri.parse('http://127.0.0.1:9/'),
              ),
              uets: UetsApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
              database: () async => db,
            ),
            now: () => now,
            store: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets('the notices, their cases and the deadlines they started', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Antalya 3. Asliye Hukuk Mahkemesi · 2025/412'), findsOne);
    expect(find.text('Eşleşmedi'), findsOne);
    // The newest is selected: tied, with its deadline.
    expect(find.textContaining('otomatik eşleşti'), findsOne);
    // Its deadline, a candidate waiting for the lawyer.
    expect(find.textContaining('Onayınızı bekliyor'), findsWidgets);
    expect(find.text('20.10.2026'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('uets-filter-unread')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uets-row-m2')), findsNothing);
    expect(find.byKey(const ValueKey('uets-row-m1')), findsOne);
  });

  testWidgets('the lawyer ties a notice by hand', (tester) async {
    final db = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('uets-row-m2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uets-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026/77'));
    await tester.pumpAndSettle();
    final m2 = db.notices().firstWhere((n) => n.message.id == 'm2');
    expect(m2.link, 'manual');
    expect(m2.caseKey, caseKey('2026/77', 'Antalya 1. İcra Dairesi'));
    expect(find.textContaining('elle eşleştirildi'), findsOne);
  });

  testWidgets('on a phone a notice opens on a page of its own', (tester) async {
    for (final size in const [Size(360, 760), Size(390, 844)]) {
      await pump(tester, size: size);
      expect(find.byKey(const ValueKey('uets-row-m1')), findsOne);
      // No side panel on a phone.
      expect(find.textContaining('otomatik eşleşti'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('uets-row-m1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('otomatik eşleşti'), findsOne);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a notice whose package came shows its envelope’s time, its '
      'documents and its waiting deadline', (tester) async {
    await pump(
      tester,
      before: (db) {
        db.saveManifest('m1', [
          (id: 'p1', name: '(1)BilirkisiRaporu.pdf', mime: ''),
        ]);
        db.saveEnvelope(
          NoticeEnvelope(
            noticeId: 'm1',
            state: 'indirildi',
            folder: '/tmp/UETS/Antalya',
            envelopePath: '/tmp/UETS/Antalya/Tebligat zarfı.pdf',
            envelopeText:
                'Rapora karşı itirazlarınızı tebliğden itibaren iki hafta '
                'içinde bildirmeniz ihtar olunur.',
            attachments: const [
              (name: 'BilirkisiRaporu.pdf', path: '/tmp/UETS/Antalya/r.pdf'),
            ],
            fetchedAt: DateTime(2026, 10, 2),
          ),
        );
      },
    );
    expect(find.byKey(const ValueKey('uets-envelope')), findsOne);
    expect(find.textContaining('iki hafta', findRichText: true), findsWidgets);
    expect(
      find.byKey(const ValueKey('uets-file-BilirkisiRaporu.pdf')),
      findsOne,
    );
    expect(find.byKey(const ValueKey('uets-timeline')), findsOne);
    expect(find.textContaining('onay bekliyor'), findsWidgets);
    // The report's own deadline, joined by the envelope.
    expect(find.textContaining('Bilirkişi raporuna itiraz'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('uets-filter-pending')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uets-row-m1')), findsOne);
    expect(find.byKey(const ValueKey('uets-row-m2')), findsNothing);
  });

  testWidgets('the lawyer adds a deadline of their own: chosen, reckoned '
      'before it is kept, the notice’s record and confirmed', (tester) async {
    final db = await pump(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('uets-add-deadline')));
    await tester.tap(find.byKey(const ValueKey('uets-add-deadline')));
    await tester.pumpAndSettle();
    expect(find.text('Süre ekle'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('choice-hmk394')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('choice-result')),
        matching: find.textContaining('Son gün'),
      ),
      findsOne,
    );
    await tester.tap(find.byKey(const ValueKey('choice-save')));
    await tester.pumpAndSettle();
    final own = db
        .deadlines(noticeId: 'm1')
        .where((d) => d.record.ruleId == 'hmk394')
        .single;
    expect(own.record.id, startsWith('uets:m1:a:'));
    expect(own.record.evidence['kaynak'], 'avukat');
    expect(own.confirmed, isTrue);
    expect(db.agenda().map((i) => i.id), contains(own.record.id));
    // Made again, it stays: the lawyer's choice is kept, not a note.
    matchNotices(db, now: now);
    expect(db.deadline(own.record.id)!.confirmed, isTrue);
  });

  testWidgets('a deadline Folio made is changed for one the lawyer chooses; '
      'the first is taken off, not deleted', (tester) async {
    final db = await pump(tester);
    final made = db.deadlines(noticeId: 'm1').first;
    final change = find.byKey(ValueKey('review-change-${made.record.id}'));
    await tester.ensureVisible(change);
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(find.text('Süreyi değiştir'), findsWidgets);
    await tester.ensureVisible(find.byKey(const ValueKey('choice-ozel')));
    await tester.tap(find.byKey(const ValueKey('choice-ozel')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('choice-purpose')),
      'Kesin süre: tanık listesi',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choice-save')));
    await tester.pumpAndSettle();
    expect(db.deadline(made.record.id)!.user!.dismissed, isTrue);
    final own = db
        .deadlines(noticeId: 'm1')
        .where((d) => d.record.evidence['kaynak'] == 'avukat')
        .single;
    expect(own.record.title, 'Kesin süre: tanık listesi');
    expect(own.record.evidence['yerine'], made.record.id);
    expect(own.onAgenda, isTrue);
  });

  testWidgets('a package not wholly read says so, document by document, and '
      'no “no deadline” is told of it', (tester) async {
    await pump(
      tester,
      before: (db) {
        db.saveEnvelope(
          const NoticeEnvelope(
            noticeId: 'm2',
            state: 'indirildi',
            envelopeText: 'Duruşma davetiyesi.',
            attachments: [
              (name: 'Davetiye.pdf', path: '/sentetik/a.pdf'),
              (name: 'Ek-2.tif', path: '/sentetik/b.tif'),
            ],
          ),
        );
        db.saveNoticeDocuments('m2', [
          for (final (i, state) in const [(0, 'okundu'), (1, 'metinYok')])
            NoticeDocument(
              noticeId: 'm2',
              seq: i,
              name: i == 0 ? 'Davetiye.pdf' : 'Ek-2.tif',
              path: i == 0 ? '/sentetik/a.pdf' : '/sentetik/b.tif',
              digest: 'h$i',
              state: state,
              reader: noticeReaderVersion,
              readAt: DateTime(2026, 9, 21),
            ),
        ]);
      },
    );
    await tester.tap(find.byKey(const ValueKey('uets-row-m2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uets-files-unread')), findsOne);
    final files = find.byKey(const ValueKey('uets-files'));
    expect(
      find.descendant(of: files, matching: find.text('Okunamadı')),
      findsOne,
    );
    expect(find.descendant(of: files, matching: find.text('Okundu')), findsOne);
    expect(find.textContaining('2 belgeden 1 tanesi okunamadı'), findsOne);
    expect(find.textContaining('adından süre doğuran'), findsNothing);
  });

  testWidgets('asked once whom they act for, the lawyer’s word tells whose '
      'every deadline of the case is, and can be changed', (tester) async {
    final db = await pump(
      tester,
      before: (db) {
        db.saveEnvelope(
          const NoticeEnvelope(
            noticeId: 'm1',
            state: 'indirildi',
            envelopeText:
                'Davacıya tebliğden itibaren iki haftalık kesin süre içinde '
                'gider avansını yatırması ihtar olunur.',
            attachments: [
              (name: 'dosyaBilgileriV1.xml', path: '/sentetik/d.xml'),
            ],
          ),
        );
        db.saveNoticeDocuments('m1', [
          NoticeDocument(
            noticeId: 'm1',
            seq: 0,
            name: 'dosyaBilgileriV1.xml',
            path: '/sentetik/d.xml',
            digest: 'h',
            state: 'ustveri',
            text: const NoticeCaseFile(
              number: '2025/412',
              parties: [
                (name: 'AYŞE ÖRNEK', role: 'Davacı', institution: false),
                (name: 'ÖRNEK YAPI A.Ş.', role: 'Davalı', institution: true),
              ],
            ).toJson(),
            reader: noticeReaderVersion,
            readAt: DateTime(2026, 10, 2),
          ),
        ]);
      },
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final ask = find.byKey(const ValueKey('uets-represent-ask'));
    await tester.ensureVisible(ask);
    expect(ask, findsOne);
    final chip = find.byKey(const ValueKey('uets-represent-AYŞE ÖRNEK-Davacı'));
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(
      db.representation(
        caseKey('2025/412', 'Antalya 3. Asliye Hukuk Mahkemesi'),
      ),
      [(ad: 'AYŞE ÖRNEK', rol: 'Davacı')],
    );
    expect(find.byKey(const ValueKey('uets-represented')), findsOne);
    expect(find.textContaining('Ayşe Örnek (Davacı) vekilisiniz'), findsOne);
    final own = db
        .deadlines(noticeId: 'm1')
        .where((d) => d.record.ruleId.startsWith('zarf-odeme'))
        .single;
    expect(own.record.ownership, 'olasiBizim');
    await tester.tap(find.byKey(const ValueKey('uets-represented-change')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uets-represent-ask')), findsOne);
  });

  testWidgets('where UYAP names the lawyer on one side, it tells whom they '
      'act for, and the lawyer is not asked', (tester) async {
    final dir = Directory.systemTemp.createTempSync('folio_uets_rep_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = UyapCaseStore(
      directory: dir,
      settings: UyapSettings(directory: dir, home: '${dir.path}/ev'),
    );
    await tester.runAsync(
      () => store.keep(
        target: const UyapCase(
          '1',
          '2025/412',
          '',
          'Antalya 3. Asliye Hukuk Mahkemesi',
        ),
        details: const UyapCaseDetails(),
        parties: const [
          UyapParty('AYŞE ÖRNEK', 'Davacı', 'Av. Deniz Kaya', 'Kişi'),
          UyapParty('ÖRNEK YAPI A.Ş.', 'Davalı', 'Av. Murat Er', 'Kurum'),
        ],
        documents: const UyapCaseDocuments([]),
      ),
    );
    final lawyer = NoticeDeadlineContext.lawyer;
    NoticeDeadlineContext.lawyer = 'Av. Deniz Kaya';
    addTearDown(() => NoticeDeadlineContext.lawyer = lawyer);
    await pump(tester, store: store);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('uets-represent-ask')), findsNothing);
    expect(
      find.textContaining('UYAP’a göre bu dosyada Ayşe Örnek (Davacı)'),
      findsOne,
    );
  });
}
