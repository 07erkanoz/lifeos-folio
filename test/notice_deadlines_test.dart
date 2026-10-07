import 'package:evrak_convert/services/legal/deadlines/aidiyet.dart';
import 'package:evrak_convert/services/legal/deadlines/belge_turu.dart';
import 'package:evrak_convert/services/legal/deadlines/kural_bilgisi.dart';
import 'package:evrak_convert/services/legal/deadlines/mahkeme_kategori.dart';
import 'package:evrak_convert/services/legal/deadlines/yasal_sure.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_deadline.dart';
import 'package:evrak_convert/services/uets/notice_deadlines.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:flutter_test/flutter_test.dart';

// The notices' deadlines (the report's B01, B03, B08, B13–B16): made rule
// by rule from the documents, candidates the lawyer confirms, made again
// when what they rest on changes, the old agenda rows carried over whole.
void main() {
  group('the kind of document', () {
    test('a payment order tells its proceedings, or does not (T49–T51)', () {
      expect(
        BelgeTuruTespit.ekTurleri(['(1)Odeme Emri Ornek 10.pdf']).single.tur,
        BelgeTuru.odemeEmriKambiyo,
      );
      expect(
        BelgeTuruTespit.ekTurleri(['Kambiyo Senetlerine Mahsus Ödeme Emri'])
            .single
            .tur,
        BelgeTuru.odemeEmriKambiyo,
      );
      expect(
        BelgeTuruTespit.ekTurleri(['Örnek 7 Ödeme Emri.pdf']).single.tur,
        BelgeTuru.odemeEmri,
      );
      expect(BelgeTuruTespit.odemeEmriTakipTuru('Ödeme Emri.pdf'), isNull);
      // "Örnek 10" is not "Örnek 100".
      expect(BelgeTuruTespit.odemeEmriTakipTuru('ornek 100'), isNull);
    });

    test('a garnishment notice tells its stage (T53)', () {
      BelgeTuru of(String name) => BelgeTuruTespit.ekTurleri([name]).single.tur;
      expect(
        of('Birinci Haciz İhbarnamesi.pdf'),
        BelgeTuru.hacizIhbarnamesiBirinci,
      );
      expect(of('89-2 Haciz Ihbarnamesi'), BelgeTuru.hacizIhbarnamesiIkinci);
      expect(of('3. Haciz İhbarnamesi'), BelgeTuru.hacizIhbarnamesiUcuncu);
      expect(of('Haciz İhbarnamesi'), BelgeTuru.hacizIhbarnamesi);
    });

    test('UETS’s run-together names are read word by word', () {
      // Not a statement of claim, so no answer period.
      expect(
        BelgeTuruTespit.ekTurleri(['(2)CevapDilekcesi.pdf']).single.tur,
        BelgeTuru.cevapDilekcesi,
      );
      expect(
        BelgeTuruTespit.ekTurleri(['(3)BilirkisiRaporu.pdf']).single.tur,
        BelgeTuru.bilirkisiRaporu,
      );
    });

    test('a party’s expert opinion or a health board report is not the '
        'court’s expert report (T59)', () {
      expect(BelgeTuruTespit.ekTurleri(['Uzman Görüşü.pdf']), isEmpty);
      expect(BelgeTuruTespit.ekTurleri(['Sağlık Kurulu Raporu.pdf']), isEmpty);
    });

    test('every document is a kind of its own (T23)', () {
      final kinds = BelgeTuruTespit.ekTurleri([
        '(1)dosyaBilgileriV1.xml',
        '(2)BilirkisiRaporu.pdf',
        '(3)AraKarar.pdf',
      ]).map((k) => k.tur);
      expect(kinds, [BelgeTuru.bilirkisiRaporu, BelgeTuru.araKarar]);
    });
  });

  group('the catalogue', () {
    test('every rule the engine can choose has an id and a duty holder', () {
      for (final tur in BelgeTuru.values) {
        for (final k in MahkemeKategorisi.values) {
          for (final rule in surelerForBelgeTuru(tur, k)) {
            expect(kuralBilgisi(rule), isNotNull, reason: '${rule.ad} ($tur)');
          }
        }
      }
    });

    test('an enforcement court’s decision is appealed under İİK m.363, '
        'not complained of (T52)', () {
      final rules = surelerForBelgeTuru(
        BelgeTuru.gerekceliKarar,
        MahkemeKategorisi.icra,
      );
      expect(rules.map((r) => kuralBilgisi(r)!.id), ['iik363']);
      // Only the regime 7499 wrote: a decision of May 2024 is not reckoned.
      expect(rules.single.gecerliMi(DateTime(2024, 5, 31)), isFalse);
      expect(rules.single.gecerliMi(DateTime(2024, 6, 1)), isTrue);
    });

    test('the third garnishment notice: fifteen and twenty days', () {
      final rules = surelerForBelgeTuru(
        BelgeTuru.hacizIhbarnamesiUcuncu,
        MahkemeKategorisi.icra,
      );
      expect(rules.map((r) => (r.miktar, r.kanunMaddesi)), [
        (15, 'İİK m.89/3'),
        (20, 'İİK m.89/3'),
      ]);
    });

    test(
      'a statement of claim and a report by jurisdiction (T55–T57, T22)',
      () {
        List<String> ids(BelgeTuru t, MahkemeKategorisi k) => [
          for (final r in surelerForBelgeTuru(t, k)) kuralBilgisi(r)!.id,
        ];
        expect(ids(BelgeTuru.davaDilekcesi, MahkemeKategorisi.hukuk), [
          'hmk127',
        ]);
        expect(ids(BelgeTuru.davaDilekcesi, MahkemeKategorisi.idare), [
          'iyuk16',
        ]);
        expect(ids(BelgeTuru.davaDilekcesi, MahkemeKategorisi.ceza), isEmpty);
        expect(ids(BelgeTuru.bilirkisiRaporu, MahkemeKategorisi.ceza), isEmpty);
        expect(ids(BelgeTuru.bilirkisiRaporu, MahkemeKategorisi.icra), [
          'hmk281',
        ]);
      },
    );
  });

  group('whose deadline it is', () {
    const lawyer = 'Ayşe Çelik';
    List<TarafKaydi> parties(String ourRole) => [
      (rol: ourRole, vekil: 'Av. AYŞE ÇELİK'),
      (rol: ourRole == 'Davacı' ? 'Davalı' : 'Davacı', vekil: 'Av. Can Er'),
    ];

    test('no role, no party list, no name: not known (T02)', () {
      expect(
        aidiyetSinyali(
          yukumlu: Yukumlu.davali,
          taraflar: const [],
          avukat: lawyer,
        ).sinyal,
        AidiyetSinyali.belirsiz,
      );
      expect(
        aidiyetSinyali(
          yukumlu: Yukumlu.davali,
          taraflar: parties('Davalı'),
          avukat: null,
        ).sinyal,
        AidiyetSinyali.belirsiz,
      );
    });

    test('the plaintiff’s lawyer is not given the answer period (T03)', () {
      expect(
        aidiyetSinyali(
          yukumlu: Yukumlu.davali,
          taraflar: parties('Davacı'),
          avukat: lawyer,
        ).sinyal,
        AidiyetSinyali.olasiKarsi,
      );
      expect(
        aidiyetSinyali(
          yukumlu: Yukumlu.davali,
          taraflar: parties('Davalı'),
          avukat: lawyer,
        ).sinyal,
        AidiyetSinyali.olasiBizim,
      );
    });

    test('the creditor’s lawyer is not given the debtor’s objection (T04)', () {
      expect(
        aidiyetSinyali(
          yukumlu: Yukumlu.borclu,
          taraflar: [(rol: 'Alacaklı', vekil: 'Av. Ayşe Çelik')],
          avukat: lawyer,
        ).sinyal,
        AidiyetSinyali.olasiKarsi,
      );
    });

    test('a lawyer on both sides, or an appeal, stays not known (T06)', () {
      expect(
        aidiyetSinyali(
          yukumlu: Yukumlu.davali,
          taraflar: [
            (rol: 'Davacı', vekil: 'Av. Ayşe Çelik'),
            (rol: 'Davalı', vekil: 'Av. Ayşe Çelik'),
          ],
          avukat: lawyer,
        ).sinyal,
        AidiyetSinyali.belirsiz,
      );
      expect(
        aidiyetSinyali(
          yukumlu: Yukumlu.taraflar,
          taraflar: parties('Davalı'),
          avukat: lawyer,
        ).sinyal,
        AidiyetSinyali.belirsiz,
      );
    });

    test('a name inside another is not the same lawyer', () {
      expect(
        aidiyetSinyali(
          yukumlu: Yukumlu.davali,
          taraflar: [(rol: 'Davalı', vekil: 'Av. Ayşegül Çelikkaya')],
          avukat: lawyer,
        ).sinyal,
        AidiyetSinyali.belirsiz,
      );
    });
  });

  group('the records', () {
    late PortalDatabase db;
    final now = DateTime(2026, 10, 6);
    setUp(() {
      db = PortalDatabase.memory();
      db.mergeCases([
        PortalCase.create(
          number: '2025/412',
          court: 'Antalya 3. Asliye Hukuk Mahkemesi',
        ),
      ]);
      db.mergeNotices([
        UetsMessage(
          id: 'm1',
          subject:
              'Antalya 3. Asliye Hukuk Mahkemesi [2025/412] [x-0-2025/412]',
          sent: DateTime.utc(2026, 9, 30, 9),
        ),
      ]);
    });
    tearDown(() => db.dispose());

    void parts(List<(String, String)> list) => db.saveManifest('m1', [
      for (final (id, name) in list) (id: id, name: name, mime: ''),
    ]);

    test('nothing is made before the documents are known', () {
      refreshNoticeDeadlines(db, now: now);
      expect(db.deadlines(), isEmpty);
      expect(db.manifest('m1').state, 'alinmadi');
    });

    test('a package of a report and a decision makes both kinds’ '
        'candidates, none on the agenda', () {
      parts([
        ('p1', '(1)BilirkisiRaporu.pdf'),
        ('p2', '(2)GerekceliKarar.pdf'),
      ]);
      refreshNoticeDeadlines(db, now: now);
      final rules = {for (final d in db.deadlines()) d.record.ruleId};
      expect(rules, {'hmk281', 'hmk345'});
      for (final d in db.deadlines()) {
        expect(d.record.state, 'aday');
        // In the box 30 September: served 5 October; two weeks: 19 October.
        expect(d.record.dueDay, '2026-10-19');
        expect(
          d.record.reasons.map((r) => r.code),
          containsAll(['besGunKurali', 'aidiyet']),
        );
        expect(d.record.evidence['kaynak'], 'ek');
      }
      expect(db.agenda(), isEmpty);
    });

    test('a payment order of unknown proceedings brings both regimes’ '
        'candidates, said so', () {
      parts([('p1', 'Ödeme Emri.pdf')]);
      refreshNoticeDeadlines(db, now: now);
      final rules = {for (final d in db.deadlines()) d.record.ruleId};
      expect(rules, containsAll(['iik62', 'iik168-5-borca', 'iik168-2-odeme']));
      expect(
        db.deadlines().first.record.reasons.map((r) => r.code),
        contains('takipTuruBelirsiz'),
      );
    });

    test('once the lawyer tells the proceedings, only theirs remain', () {
      parts([('p1', 'Ödeme Emri.pdf')]);
      db.setMeta('takip:m1', 'kambiyo');
      refreshNoticeDeadlines(db, now: now);
      final live = {
        for (final d in db.deadlines())
          if (d.record.state != 'eski') d.record.ruleId,
      };
      expect(live, contains('iik168-5-borca'));
      expect(live, isNot(contains('iik62')));
      expect(
        db.deadlines().expand((d) => d.record.reasons).map((r) => r.code),
        isNot(contains('takipTuruBelirsiz')),
      );
      db.setMeta('takip:m1', 'genel');
      refreshNoticeDeadlines(db, now: now);
      final general = {
        for (final d in db.deadlines())
          if (d.record.state != 'eski') d.record.ruleId,
      };
      expect(general, {'iik62'});
    });

    test('a confirmation holds while the inputs do, and falls when a '
        'document changes, even under the same name (T60, T67)', () {
      parts([('p1', '(1)GerekceliKarar.pdf')]);
      refreshNoticeDeadlines(db, now: now);
      final id = db.deadlines().single.record.id;
      expect(db.confirmDeadline(id, now: now), isTrue);
      expect(db.agenda().map((i) => i.id), [id]);
      refreshNoticeDeadlines(db, now: now);
      expect(db.deadline(id)!.confirmed, isTrue, reason: 'nothing changed');

      parts([('p9', '(1)GerekceliKarar.pdf')]);
      refreshNoticeDeadlines(db, now: now);
      final again = db.deadline(id)!;
      expect(again.confirmed, isFalse);
      expect(
        again.record.reasons.map((r) => r.code),
        contains('onaySonrasiDegisti'),
      );
      expect(db.agenda(), isEmpty);
    });

    test(
      'the lawyer’s done mark and own day survive a new reckoning (T68)',
      () {
        parts([('p1', '(1)GerekceliKarar.pdf')]);
        refreshNoticeDeadlines(db, now: now);
        final id = db.deadlines().single.record.id;
        db.saveDeadlineUser(
          DeadlineUser(deadlineId: id, manualDay: '2026-10-16'),
        );
        expect(db.agenda().single.at, DateTime(2026, 10, 16));
        db.saveAgenda(db.agenda().single.copyWith(done: true));
        parts([('p2', '(1)GerekceliKarar.pdf'), ('p3', 'Ek.pdf')]);
        refreshNoticeDeadlines(db, now: now);
        final kept = db.deadline(id)!;
        expect(kept.user!.done, isTrue);
        expect(kept.user!.manualDay, '2026-10-16');
        expect(
          kept.record.dueDay,
          '2026-10-19',
          reason: 'the engine’s, beside',
        );
      },
    );

    test('a deadline no longer made is kept as old, never deleted (T63)', () {
      parts([('p1', '(1)GerekceliKarar.pdf')]);
      refreshNoticeDeadlines(db, now: now);
      final id = db.deadlines().single.record.id;
      parts([('p1', '(1)AraKarar.pdf')]);
      refreshNoticeDeadlines(db, now: now);
      expect(db.deadline(id)!.record.state, 'eski');
      expect(db.deadlineHistory(id).map((h) => h.change), [
        'yeni',
        'artık üretilmiyor',
      ]);
    });

    test('taken off by the lawyer, a deadline leaves the agenda and the '
        'review, not its notice', () {
      parts([('p1', '(1)GerekceliKarar.pdf')]);
      refreshNoticeDeadlines(db, now: now);
      final id = db.deadlines().single.record.id;
      db.removeAgenda(id);
      final d = db.deadline(id)!;
      expect(d.toReview, isFalse);
      expect(d.onAgenda, isFalse);
      expect(db.deadlines(noticeId: 'm1'), hasLength(1));
    });

    group('the agenda rows of before', () {
      AgendaItem old(String title, {bool done = false, DateTime? at}) =>
          AgendaItem(
            id: 'uets:m1:$title',
            kind: 'deadline',
            title: title,
            body: 'UETS · …',
            at: at ?? DateTime(2026, 10, 19),
            allDay: true,
            done: done,
            updated: DateTime(2026, 10, 1),
          );

      test('one row, one new deadline: its done mark goes over; the row is '
          'kept and off the agenda', () {
        db.saveAgenda(old('İstinaf süresi', done: true));
        parts([('p1', '(1)GerekceliKarar.pdf')]);
        refreshNoticeDeadlines(db, now: now);
        final d = db.deadlines().single;
        expect(d.user!.done, isTrue);
        expect(db.legacyOf(d.record.id)!.title, 'İstinaf süresi');
        expect(db.agenda(), isEmpty);
        // Again: nothing more.
        refreshNoticeDeadlines(db, now: now);
        expect(db.deadlines(), hasLength(1));
      });

      test('an old row stays on the agenda, marked, until the lawyer '
          'decides on what it was carried over to', () {
        db.saveAgenda(old('İstinaf süresi'));
        parts([('p1', '(1)GerekceliKarar.pdf')]);
        refreshNoticeDeadlines(db, now: now);
        final shown = db.agenda().single;
        expect(shown.id, 'uets:m1:İstinaf süresi');
        expect(shown.body, contains('önceki hesap'));
        // Done on the agenda: kept on the old row, without the mark.
        db.saveAgenda(shown.copyWith(done: true));
        expect(db.agenda(), isEmpty);
        expect(db.legacyNoticeDeadlines(), isEmpty);
        db.saveAgenda(shown.copyWith(done: false));
        expect(
          db.agenda().single.body,
          isNot(contains('önceki hesap · önceki')),
        );
        // Confirmed: the new deadline takes its place.
        final id = db.deadlines().single.record.id;
        db.confirmDeadline(id, now: now);
        expect(db.agenda().map((i) => i.id), [id]);
      });

      test('a row whose day differs says so; one whose title answers to '
          'nothing stays, to be looked at', () {
        db.saveAgenda(old('İstinaf süresi', at: DateTime(2026, 10, 20)));
        db.saveAgenda(old('Eski bir süre', done: false));
        parts([('p1', '(1)GerekceliKarar.pdf')]);
        refreshNoticeDeadlines(db, now: now);
        final appeal = db.deadlines().firstWhere(
          (d) => d.record.ruleId == 'hmk345',
        );
        expect(
          appeal.record.reasons.map((r) => r.code),
          contains('eskiKayitFarkli'),
        );
        final orphan = db.deadlines().firstWhere(
          (d) => d.record.ruleId == 'eski-kayit',
        );
        expect(orphan.record.state, 'eski');
        expect(orphan.toReview, isTrue);
        expect(orphan.record.dueDay, '2026-10-19');
      });

      test('a row of a notice no longer kept is carried over on its own', () {
        db.saveAgenda(
          AgendaItem(
            id: 'uets:gone:Temyiz süresi',
            kind: 'deadline',
            title: 'Temyiz süresi',
            at: DateTime(2026, 11, 2),
            allDay: true,
            done: true,
            updated: DateTime(2026, 10, 1),
          ),
        );
        refreshNoticeDeadlines(db, now: now);
        final orphan = db.deadlines(noticeId: 'gone').single;
        expect(orphan.record.state, 'eski');
        expect(orphan.user!.done, isTrue);
        expect(db.agenda(), isEmpty);
      });
    });

    test('the lawyer’s own agenda deadlines stay as they are', () {
      db.saveAgenda(
        AgendaItem(
          id: 'own',
          kind: 'deadline',
          title: 'Islah',
          at: DateTime(2026, 10, 30),
          allDay: true,
          updated: now,
        ),
      );
      refreshNoticeDeadlines(db, now: now);
      expect(db.agenda().map((i) => i.id), ['own']);
    });
  });
}
