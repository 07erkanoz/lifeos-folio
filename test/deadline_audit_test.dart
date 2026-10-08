import 'package:evrak_convert/services/legal/deadlines/aidiyet.dart';
import 'package:evrak_convert/services/legal/deadlines/belge_turu.dart';
import 'package:evrak_convert/services/legal/deadlines/deadline_service.dart';
import 'package:evrak_convert/services/legal/deadlines/kural_bilgisi.dart';
import 'package:evrak_convert/services/legal/deadlines/legal_day.dart';
import 'package:evrak_convert/services/legal/deadlines/mahkeme_kategori.dart';
import 'package:evrak_convert/services/legal/deadlines/tebligat_parser.dart';
import 'package:evrak_convert/services/legal/deadlines/turkish_legal_calendar.dart';
import 'package:evrak_convert/services/legal/deadlines/yasal_sure.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_deadline.dart';
import 'package:evrak_convert/services/uets/envelope_directives.dart';
import 'package:evrak_convert/services/uets/notice_deadlines.dart';
import 'package:evrak_convert/services/uets/notice_matcher.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

// What the audit of 8 October 2026 found wrong in the deadline engine
// (docs/audits/2026-10-08: the report's B-numbers, its probes' D-numbers),
// each kept as a test once fixed: stage A of its plan.
void main() {
  late PortalDatabase db;
  setUp(() {
    db = PortalDatabase.memory();
    db.mergeNotices([
      UetsMessage(
        id: 'audit',
        subject: 'Ankara 1. Asliye Hukuk Mahkemesi [2026/100]',
        sent: DateTime.utc(2026, 9, 1, 9),
      ),
    ]);
  });
  tearDown(() => db.dispose());

  List<DeadlineRecord> records(
    String text, {
    List<TarafKaydi> parties = const [],
    String? lawyer,
  }) => noticeDeadlines(
    db.notice('audit')!,
    manifest: (state: 'alindi', fetchedAt: null, parts: const []),
    envelope: NoticeEnvelope(
      noticeId: 'audit',
      state: 'indirildi',
      envelopeText: text,
    ),
    parties: parties,
    lawyer: lawyer,
    now: DateTime(2026, 10, 8),
  );

  String day(DateTime d) => LegalDay.of(d).key;

  test('B06/D06: a time the envelope says runs from the pronouncement waits '
      'for its day; the service never stands in for it', () {
    final r = records(
      'Tefhimden itibaren iki hafta içinde beyanlarınızı sununuz.',
    ).single;
    expect(r.startEvent, 'tefhim');
    expect(r.state, 'olayBekleniyor');
    expect(r.dueDay, isNull);
    expect(
      r.reasons.map((x) => x.code),
      isNot(contains('baslangicVarsayildi')),
    );
  });

  test('B07/D07: a duty the envelope lays on the other party by name is not '
      'made the lawyer’s because the notice came to the lawyer', () {
    const text =
        'Davalı tarafa tebliğden itibaren iki hafta içinde delil sunması '
        'ihtar olunur.';
    expect(envelopeDirectives(text).single.party, 'davali');
    expect(records(text).single.ownership, AidiyetSinyali.belirsiz.name);
    // The party list tells whose: the plaintiff's lawyer, the other side's.
    final theirs = records(
      text,
      parties: [(rol: 'Davacı', vekil: 'Av. Ayşe Çelik')],
      lawyer: 'Av. Ayşe Çelik',
    ).single;
    expect(theirs.ownership, AidiyetSinyali.olasiKarsi.name);
    // Spoken to its reader, it stays the reader's.
    expect(
      records('Tebliğden itibaren iki hafta içinde delillerinizi sununuz.')
          .single
          .ownership,
      AidiyetSinyali.olasiBizim.name,
    );
  });

  test('B08/D08: a defendant who counter-sues is on neither side as such', () {
    expect(
      aidiyetSinyali(
        yukumlu: Yukumlu.davali,
        taraflar: [(rol: 'Davalı-Karşı Davacı', vekil: 'Av. Ayşe Çelik')],
        avukat: 'Ayşe Çelik',
      ).sinyal,
      AidiyetSinyali.belirsiz,
    );
  });

  test('B09/D09: the same place and number do not tie another court; a '
      'bureau still ties to its office', () {
    final labour = PortalCase.create(
      number: '2026/100',
      court: 'Ankara 8. İş Mahkemesi',
    );
    expect(
      matchSubject('Ankara 1. Asliye Hukuk Mahkemesi [2026/100]', [labour]),
      isNull,
    );
    final office = PortalCase.create(
      number: '2026/1500',
      court: 'Antalya Cumhuriyet Başsavcılığı',
    );
    expect(
      matchSubject('Antalya Soruşturma Bürosu [2026/1500]', [office]),
      office.key,
    );
  });

  test('B10/D12: the core gives no day for a rule whose event’s day is '
      'missing, and keeps it as waiting', () {
    const s = YasalSure(
      ad: 'ilan deneyi',
      miktar: 7,
      kanunMaddesi: 'deney',
      baslangic: SureBaslangici.ilan,
    );
    final c = DeadlineService.computeFromUsuliTebligTarihi(
      usuliTebligTarihi: DateTime(2026, 9, 6),
      kategori: MahkemeKategorisi.hukuk,
      kurallar: [s],
    );
    expect(c.items, isEmpty);
    expect(c.olayBekleyenler.single.sure, s);
    expect(c.olayBekleyenler.single.eksikOlay, 'ilan');
    // Given, it is its own day, not the decision's.
    final given = DeadlineService.computeFromUsuliTebligTarihi(
      usuliTebligTarihi: DateTime(2026, 9, 6),
      ilanTarihi: DateTime(2026, 9, 1),
      kararTarihi: DateTime(2026, 6, 1),
      kategori: MahkemeKategorisi.hukuk,
      kurallar: [s],
    );
    expect(day(given.items.single.baslangicTarihi), '2026-09-01');
  });

  test('B11/D19: HMK’s recess ends on 8 September, İYUK’s on 7', () {
    DateTime last(MahkemeKategorisi k) => TurkishLegalCalendar.adjustDeadline(
      DateTime(2026, 8, 10),
      kategori: k,
      adliTatileTabi: true,
    ).effectiveDate;
    // Yargıtay 2. HD 2021/2526 E., 2021/3729 K., after HGK 2017/1449 K.
    expect(day(last(MahkemeKategorisi.hukuk)), '2026-09-08');
    // Danıştay İDDK: İYUK m.8/3 counts from 1 September, its first day.
    expect(day(last(MahkemeKategorisi.idare)), '2026-09-07');
  });

  test('B12: a judge’s time and a time of substantive law are not extended '
      'by the recess as of course', () {
    const judge = YasalSure(
      ad: 'Tanık listesi',
      miktar: 2,
      birim: SureBirimi.hafta,
      kanunMaddesi: 'Ara karar',
      nitelik: SureNiteligi.hakim,
    );
    final c = DeadlineService.computeFromUsuliTebligTarihi(
      usuliTebligTarihi: DateTime(2026, 8, 3),
      kategori: MahkemeKategorisi.hukuk,
      adliTatileTabi: true,
      kurallar: [judge],
    );
    expect(day(c.items.single.etkiliSonGun), '2026-08-17');
    expect(c.items.single.guven, isNot(SureGuveni.yuksek));
    expect(c.items.single.dayanakNotlari.join(), contains('hâkim'));
    expect(sItirazinIptali.nitelik, SureNiteligi.maddi);
    // An envelope’s time is the court’s.
    expect(
      records('Tebliğden itibaren iki hafta içinde beyanlarınızı sununuz.')
          .single
          .law,
      'Zarftaki ihtar',
    );
  });

  test('B13/D13: not knowing whether the recess applies is not certain', () {
    final c = DeadlineService.computeFromUsuliTebligTarihi(
      usuliTebligTarihi: DateTime(2026, 7, 20),
      kategori: MahkemeKategorisi.hukuk,
      belgeTuru: BelgeTuru.gerekceliKarar,
    );
    expect(c.items.single.guven, isNot(SureGuveni.yuksek));
    expect(c.items.single.tatilBelirsiz, isTrue);
  });

  test('B14/D14: a year before the holiday table is not certain either', () {
    final c = DeadlineService.computeFromUsuliTebligTarihi(
      usuliTebligTarihi: DateTime(2023, 4, 10),
      kategori: MahkemeKategorisi.hukuk,
      belgeTuru: BelgeTuru.gerekceliKarar,
    );
    expect(c.items.single.guven, SureGuveni.dusuk);
  });

  test('B16/D11: the old criminal regime’s two starts are two rows; the '
      'pronouncement’s waits for its day', () {
    final rules = surelerForBelgeTuru(
      BelgeTuru.gerekceliKarar,
      MahkemeKategorisi.ceza,
    );
    expect(rules, contains(sCezaIstinafEski));
    expect(rules, contains(sCezaIstinafEskiTefhim));
    expect(sCezaIstinafEski.baslangic, SureBaslangici.teblig);
    expect(sCezaIstinafEskiTefhim.baslangic, SureBaslangici.tefhim);
    expect(sCezaTemyizEskiTefhim.baslangic, SureBaslangici.tefhim);
    final c = DeadlineService.computeFromUsuliTebligTarihi(
      usuliTebligTarihi: DateTime(2024, 3, 4),
      kategori: MahkemeKategorisi.ceza,
      belgeTuru: BelgeTuru.gerekceliKarar,
      kararTarihi: DateTime(2024, 2, 20),
    );
    expect(c.items.map((i) => i.sureAdi), ['İstinaf süresi (eski hüküm)']);
    expect(c.olayBekleyenler.single.sure, sCezaIstinafEskiTefhim);
  });

  test('B17/D17: a regional court’s criminal chamber is criminal for every '
      'classifier', () {
    const name = 'Ankara Bölge Adliye Mahkemesi 5. Ceza Dairesi';
    expect(
      TebligatParser.parse('$name [2026/100]').kategori,
      MahkemeKategorisi.ceza,
    );
    expect(
      TurkishLegalCalendar.kategoriFromMahkemeAdi(name),
      MahkemeKategorisi.ceza,
    );
  });

  test('B18: two documents of a kind in one package (a report and its '
      'annex) run one time from one day: one deadline naming both, not two '
      'that say the same', () {
    final made = noticeDeadlines(
      db.notice('audit')!,
      manifest: (
        state: 'alindi',
        fetchedAt: null,
        parts: const [
          (id: 'p1', name: '(1)BilirkisiRaporu.pdf'),
          (id: 'p2', name: '(2)BilirkisiRaporu.pdf'),
        ],
      ),
      now: DateTime(2026, 10, 8),
    );
    final r = made.single;
    expect(r.id, 'uets:audit:r:${r.ruleId}');
    expect(
      r.reasons.firstWhere((x) => x.code == 'birdenCokBelge').text,
      contains('(2)BilirkisiRaporu.pdf'),
    );
  });

  test('B19: an envelope’s time joins the rule of the same act, party and '
      'start; laid on another party, it stays apart', () {
    final kept = noticeDeadlines(
      db.notice('audit')!,
      manifest: (
        state: 'alindi',
        fetchedAt: null,
        parts: const [(id: 'p1', name: '(1)BilirkisiRaporu.pdf')],
      ),
      envelope: const NoticeEnvelope(
        noticeId: 'audit',
        state: 'indirildi',
        envelopeText:
            'Rapora karşı itirazlarınızı tebliğden itibaren iki hafta '
            'içinde bildiriniz.',
      ),
      now: DateTime(2026, 10, 8),
    );
    expect(kept, hasLength(1));
    expect(kept.single.reasons.map((r) => r.code), contains('zarfIleUyumlu'));
  });

  test('B20/D15: a long time limit still to run is not hidden because its '
      'notice is more than forty days old', () {
    final r = records(
      'Tebliğden itibaren doksan gün içinde beyanlarınızı sununuz.',
    ).single;
    expect(r.dueDay, isNotNull);
    expect(KeptDeadline(r, null).expired(DateTime(2026, 10, 20)), isFalse);
    final last = DateTime.parse(r.dueDay!);
    expect(
      KeptDeadline(r, null).expired(last.add(const Duration(days: 8))),
      isTrue,
    );
  });

  test('B22 and stage A’s measure: a deadline the lawyer confirmed stays on '
      'the agenda when the engine changes, to be confirmed again', () {
    final r = records(
      'Tebliğden itibaren iki hafta içinde beyanlarınızı sununuz.',
    ).single;
    // The ids of what an envelope gave before stay as they were.
    expect(r.id, 'uets:audit:r:zarf-beyan-2hafta');
    final before = KeptDeadline(
      r,
      DeadlineUser(deadlineId: r.id, confirmedInputs: 'an older reckoning'),
    );
    expect(before.confirmed, isFalse);
    expect(before.reconfirm, isTrue);
    expect(before.onAgenda, isTrue);
    expect(before.toReview, isTrue);
  });

  group('stage C: a directive at a time', () {
    test(
      'B03/D01–D03: the court’s “kesin süre” and an OCR’s plain letters',
      () {
        final d1 = envelopeDirectives(
          'Davacıya tanık listesini sunması için tebliğden itibaren iki '
          'haftalık kesin süre verilmesine.',
        ).single;
        expect(
          (d1.amount, d1.unit, d1.act, d1.party, d1.strict),
          (2, SureBirimi.hafta, 'delil', 'davaci', true),
        );
        expect(
          envelopeDirectives(
            'Tebliğden itibaren iki hafta kesin süre verilmesine.',
          ),
          hasLength(1),
        );
        final ocr = envelopeDirectives(
          'Tebligden itibaren iki hafta icinde itirazlarinizi bildiriniz.',
        ).single;
        expect(
          (ocr.act, ocr.toReader, ocr.fromService),
          ('itiraz', true, true),
        );
      },
    );

    test('B04/D04: a warning the court quotes is a directive; a law it '
        'quotes is not', () {
      expect(
        envelopeDirectives(
          'İHTAR: “Tebliğden itibaren iki hafta içinde itirazlarınızı '
          'bildiriniz.”',
        ),
        hasLength(1),
      );
      expect(
        envelopeDirectives(
          'Kanun şöyle der: “işveren kazadan sonraki 3 iş günü içinde '
          'bildirimde bulunur.” Bilgilerinize sunulur.',
        ),
        isEmpty,
      );
    });

    test('B05/D05, D18, D20: two times in a sentence, two parties with one '
        'time, each its own', () {
      expect(
        envelopeDirectives(
          'Tebliğden itibaren beş gün içinde itirazlarınızı bildirmeniz ve '
          'on gün içinde borcunuzu ödemeniz ihtar olunur.',
        ).map((d) => (d.amount, d.act)),
        [(5, 'itiraz'), (10, 'odeme')],
      );
      expect(
        envelopeDirectives(
          'Tebliğden itibaren iki hafta içinde tanık listenizi sununuz. '
          'Tebliğden itibaren iki hafta içinde delil avansınızı yatırınız.',
        ),
        hasLength(2),
      );
      expect(
        envelopeDirectives(
          'Davacıya tebliğden itibaren iki hafta içinde tanık listesini '
          'sunması ihtar olunur. Davalıya tebliğden itibaren iki hafta '
          'içinde belgelerini delil olarak sunması ihtar olunur.',
        ).map((d) => d.party),
        ['davaci', 'davali'],
      );
    });

    test('the report’s example: four obligations, “aynı sürede” the one '
        'before, one with no start to count from', () {
      final ds = envelopeDirectives(
        'Davacıya, tebliğden itibaren iki haftalık kesin sürede tanık '
        'listesini sunması; davalıya aynı sürede delil avansını yatırması; '
        'taraflara bilirkişi raporuna karşı iki hafta içinde beyanda '
        'bulunmaları; vekillere duruşmadan bir hafta önce mazeretlerini '
        'bildirmeleri ihtar olunur.',
      );
      expect(ds.map((d) => (d.party, d.act, d.amount)), [
        ('davaci', 'delil', 2),
        ('davali', 'odeme', 2),
        (null, 'beyan', 2),
      ]);
      expect(ds[1].strict, isTrue);
    });

    test('“iki (3) hafta”: the two are not chosen between silently', () {
      final d = envelopeDirectives(
        'Tebliğden itibaren iki (3) hafta içinde beyanlarınızı sununuz.',
      ).single;
      expect((d.amount, d.otherAmount), (2, 3));
      final r = records(
        'Tebliğden itibaren iki (3) hafta içinde beyanlarınızı sununuz.',
      ).single;
      expect(r.reasons.map((x) => x.code), contains('sayiCelisiyor'));
    });

    test('D16: with no list and nothing read yet, the documents’ names', () {
      final r = noticeDeadlines(
        db.notice('audit')!,
        manifest: (state: 'hata', fetchedAt: null, parts: const []),
        envelope: const NoticeEnvelope(
          noticeId: 'audit',
          state: 'zarfYok',
          attachments: [
            (name: 'Gerekçeli Karar.pdf', path: '/sentetik/karar.pdf'),
          ],
        ),
      );
      expect(r, isNotEmpty);
    });
  });

  group('§7: whom the lawyer acts for', () {
    test('said once, it tells whose a duty is, before any name', () {
      const plaintiff = [(ad: 'Ayşe Örnek', rol: 'Davacı')];
      expect(
        aidiyetTemsilden(yukumlu: Yukumlu.davaci, temsil: plaintiff).sinyal,
        AidiyetSinyali.olasiBizim,
      );
      expect(
        aidiyetTemsilden(yukumlu: Yukumlu.davali, temsil: plaintiff).sinyal,
        AidiyetSinyali.olasiKarsi,
      );
      expect(
        aidiyetTemsilden(yukumlu: Yukumlu.taraflar, temsil: plaintiff).sinyal,
        AidiyetSinyali.belirsiz,
      );
      // A defendant who counter-sues: which suit the duty is in, not told.
      expect(
        aidiyetTemsilden(
          yukumlu: Yukumlu.davali,
          temsil: const [(ad: 'Örnek A.Ş.', rol: 'Davalı-Karşı Davacı')],
        ).sinyal,
        AidiyetSinyali.belirsiz,
      );
    });

    test('a lawyer named among a party’s lawyers; “Talep Eden” is the one '
        'who asks', () {
      expect(
        vekilOlarakGeciyor('AYSE CELIK, MEHMET ER', 'Av. Ayşe Çelik'),
        isTrue,
      );
      expect(vekilOlarakGeciyor('AYSE CELIKBAS', 'Av. Ayşe Çelik'), isFalse);
      expect(tekYanda(['Talep Eden']), isTrue);
      expect(tekYanda(['Davacı', 'Davalı']), isFalse);
    });

    test('the engine goes by it for a duty laid on a party', () {
      const text =
          'Davacıya tebliğden itibaren iki haftalık kesin süre içinde gider '
          'avansını yatırması ihtar olunur.';
      final r = noticeDeadlines(
        db.notice('audit')!,
        manifest: (state: 'alindi', fetchedAt: null, parts: const []),
        envelope: const NoticeEnvelope(
          noticeId: 'audit',
          state: 'indirildi',
          envelopeText: text,
        ),
        represented: const [(ad: 'Ayşe Örnek', rol: 'Davacı')],
        now: DateTime(2026, 10, 8),
      ).single;
      expect(r.ownership, AidiyetSinyali.olasiBizim.name);
      expect(r.reasons.map((x) => x.text).join(), contains('siz belirttiniz'));
    });
  });

  group('the cases’ parties, kept in the database', () {
    test('a row a party; a better source replaces a poorer one, never the '
        'other way; the same parties are not written again', () {
      const k = 'k';
      db.saveCaseParties(k, const [
        UyapParty('AYŞE ÖRNEK', 'Davacı', '', 'Kişi'),
      ], source: 'paket');
      db.saveCaseParties(k, const [
        UyapParty('AYŞE ÖRNEK', 'Davacı', 'Av. Deniz Kaya', 'Kişi'),
        UyapParty('ÖRNEK A.Ş.', 'Davalı', 'Av. Murat Er', 'Kurum'),
      ], source: 'uyap');
      db.saveCaseParties(k, const [
        UyapParty('YANLIŞ', 'Davacı', '', 'Kişi'),
      ], source: 'paket');
      final kept = db.caseParties(caseKey: k)[k]!;
      expect(kept.map((t) => (t.name, t.lawyer)), [
        ('AYŞE ÖRNEK', 'Av. Deniz Kaya'),
        ('ÖRNEK A.Ş.', 'Av. Murat Er'),
      ]);
    });

    test('the lawyer’s clients: their word, else UYAP’s lawyers', () {
      const k = 'k';
      db.saveCaseParties(k, const [
        UyapParty('AYŞE ÖRNEK', 'Davacı', 'Av. Deniz Kaya', 'Kişi'),
        UyapParty('ÖRNEK A.Ş.', 'Davalı', 'Av. Murat Er', 'Kurum'),
      ], source: 'uyap');
      expect(db.clientsOf(k, lawyer: 'Av. Deniz Kaya'), [
        (ad: 'AYŞE ÖRNEK', rol: 'Davacı'),
      ]);
      db.setRepresentation(k, const [(ad: 'ÖRNEK A.Ş.', rol: 'Davalı')]);
      expect(db.clientsOf(k, lawyer: 'Av. Deniz Kaya'), [
        (ad: 'ÖRNEK A.Ş.', rol: 'Davalı'),
      ]);
    });

    test('heirs, a guardian and a child pushed into crime stand on their '
        'sides', () {
      expect(tekYanda(['Mirasçı', 'Vasi Adayı']), isTrue);
      expect(tekYanda(['Suça Sürüklenen Çocuk']), isTrue);
      expect(tekYanda(['Davacı-Karşı Davalı']), isFalse);
    });
  });
}
