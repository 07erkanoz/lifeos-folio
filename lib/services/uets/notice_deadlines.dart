import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../legal/deadlines/aidiyet.dart';
import '../legal/deadlines/belge_turu.dart';
import '../legal/deadlines/deadline_service.dart';
import '../legal/deadlines/kural_bilgisi.dart';
import '../legal/deadlines/legal_day.dart';
import '../legal/deadlines/mahkeme_kategori.dart';
import '../legal/deadlines/turkish_legal_calendar.dart';
import '../legal/deadlines/yasal_sure.dart';
import '../portal/portal_database.dart';
import '../portal/portal_deadline.dart';
import 'envelope_directives.dart';
import 'notice_matcher.dart';

/// What the notices' deadlines are made with beyond the database: each
/// case's parties by its key, and the lawyer's own name. [PortalSync]
/// fills it before every reckoning; empty, every deadline's owner is
/// "not known", which is shown, never taken for the lawyer's.
abstract final class NoticeDeadlineContext {
  static Map<String, List<TarafKaydi>> parties = const {};
  static String? lawyer;
}

/// The notices' deadlines, made again for every notice kept on this
/// computer: each rule a record of its own, never certain by itself (the
/// lawyer confirms it), with why it is as it is. What has not changed is
/// not written; the lawyer's decisions are never touched; the agenda rows
/// they were kept in before are carried over once, nothing of them lost.
///
/// [parties] gives a case's parties by its key, for the sign of whose
/// deadline it is; [lawyer] is the lawyer's own name.
///
/// [only], when given, makes those notices' alone again (one whose package
/// just came).
void refreshNoticeDeadlines(
  PortalDatabase db, {
  Map<String, List<TarafKaydi>> parties = const {},
  String? lawyer,
  DateTime? now,
  Set<String>? only,
}) {
  final at = now ?? DateTime.now();
  final legacy = <String, List<AgendaItem>>{};
  for (final old
      in only == null
          ? db.legacyNoticeDeadlines()
          : [
              for (final id in only) ...db.legacyNoticeDeadlines(noticeId: id),
            ]) {
    final notice = old.id.split(':').elementAtOrNull(1) ?? '';
    (legacy[notice] ??= []).add(old);
  }
  final seen = <String>{};
  // One notice whose package came reads that notice alone, not the box.
  final notices = only == null
      ? db.notices()
      : [for (final id in only) ?db.notice(id)];
  final manifests = only == null
      ? db.manifests()
      : {for (final id in only) id: db.manifest(id)};
  final envelopes = only == null
      ? db.envelopes()
      : {for (final id in only) id: ?db.envelope(id)};
  final users = {
    for (final d
        in only == null
            ? db.deadlines(decidedOnly: true)
            : [for (final id in only) ...db.deadlines(noticeId: id)])
      if (d.user != null) d.record.id: d.user!,
  };
  for (final n in notices) {
    seen.add(n.message.id);
    final fresh = noticeDeadlines(
      n,
      manifest:
          manifests[n.message.id] ??
          (state: 'alinmadi', fetchedAt: null, parts: const []),
      envelope: envelopes[n.message.id],
      takipTuru: switch (db.meta('takip:${n.message.id}')) {
        final v? when v.isNotEmpty => v,
        _ => null,
      },
      parties: n.caseKey == null ? const [] : parties[n.caseKey] ?? const [],
      lawyer: lawyer,
      now: at,
    );
    final carried = _carryOver(
      db,
      legacy[n.message.id] ?? const [],
      fresh,
      n,
      at,
    );
    db.replaceNoticeDeadlines(n.message.id, [
      for (final r in carried.records)
        _confirmationChanged(users[r.id], r) ?? r,
    ], now: at);
    for (final step in carried.after) {
      step();
    }
  }
  // Rows of notices no longer kept: carried over on their own, as they are.
  if (only != null) return;
  _carryOrphans(db, legacy, seen, at);
}

/// The same as [refreshNoticeDeadlines] for the whole box, a few notices
/// at a time with the window let breathe between them: a box of a
/// thousand notices reckoned at one go held it for seconds.
Future<void> refreshNoticeDeadlinesGently(
  PortalDatabase db, {
  Map<String, List<TarafKaydi>> parties = const {},
  String? lawyer,
  DateTime? now,
  int chunk = 25,
}) async {
  final at = now ?? DateTime.now();
  final ids = db.noticeIds();
  for (var i = 0; i < ids.length; i += chunk) {
    refreshNoticeDeadlines(
      db,
      parties: parties,
      lawyer: lawyer,
      now: at,
      only: ids.skip(i).take(chunk).toSet(),
    );
    await Future<void>.delayed(Duration.zero);
  }
  final legacy = <String, List<AgendaItem>>{};
  for (final old in db.legacyNoticeDeadlines()) {
    final notice = old.id.split(':').elementAtOrNull(1) ?? '';
    (legacy[notice] ??= []).add(old);
  }
  _carryOrphans(db, legacy, ids.toSet(), at);
}

/// The old agenda rows of notices no longer kept, carried over on their
/// own, as they are.
void _carryOrphans(
  PortalDatabase db,
  Map<String, List<AgendaItem>> legacy,
  Set<String> seen,
  DateTime at,
) {
  for (final e in legacy.entries) {
    if (seen.contains(e.key)) continue;
    for (final old in e.value) {
      final orphan = _orphan(old, e.key, at);
      db.replaceNoticeDeadlines(e.key, [
        ...[for (final d in db.deadlines(noticeId: e.key)) d.record],
        orphan,
      ], now: at);
      if (old.done) {
        db.saveDeadlineUser(DeadlineUser(deadlineId: orphan.id, done: true));
      }
      db.archiveLegacy(old, [orphan.id], now: at);
    }
  }
}

/// [n]'s deadlines as the engine makes them now (see
/// [refreshNoticeDeadlines]); pure, for the tests.
List<DeadlineRecord> noticeDeadlines(
  KeptNotice n, {
  required ({
    String state,
    String? fetchedAt,
    List<({String id, String name})> parts,
  })
  manifest,
  NoticeEnvelope? envelope,
  List<TarafKaydi> parties = const [],
  String? lawyer,
  DateTime? now,

  /// The lawyer's word on a payment order that does not say its kind of
  /// proceedings: 'genel' or 'kambiyo'; null while not said.
  String? takipTuru,
}) {
  final m = n.message;
  final sent = m.sent;
  if (sent == null) return const [];
  final at = now ?? DateTime.now();
  final subject = NoticeSubject.parse(m.subject);
  final category = subject == null
      ? null
      : TurkishLegalCalendar.kategoriFromMahkemeAdi(subject.unit);

  // The kinds of document, each with what told it: a document at a time,
  // so that two expert reports or two interim decisions in one package are
  // two documents, each with its own deadlines, not one.
  final kinds = <({BelgeTuru tur, Map<String, Object?> evidence})>[];
  final seenKinds = <BelgeTuru>{};
  final fromParts = <({BelgeTuru tur, String ad})>[];
  for (var i = 0; i < manifest.parts.length; i++) {
    final part = manifest.parts[i];
    for (final k in BelgeTuruTespit.ekTurleri([part.name])) {
      fromParts.add(k);
      seenKinds.add(k.tur);
      kinds.add((
        tur: k.tur,
        evidence: {'kaynak': 'ek', 'ad': k.ad, 'parca': part.id, 'sira': i},
      ));
    }
  }
  if (kinds.isEmpty && (envelope?.envelopeText ?? '').isNotEmpty) {
    final t = BelgeTuruTespit.tebligatTuru(
      const [],
      metin: envelope!.envelopeText,
    );
    if (!BelgeTuruTespit.belirsiz(t)) {
      kinds.add((tur: t, evidence: {'kaynak': 'zarf', 'ad': 'Tebligat zarfı'}));
    }
  }
  if (kinds.isEmpty) {
    final t = BelgeTuruTespit.tebligatTuru(const [], metin: m.subject);
    if (!BelgeTuruTespit.belirsiz(t)) {
      kinds.add((tur: t, evidence: {'kaynak': 'konu', 'ad': ''}));
    }
  }
  // A payment order that does not say its kind of proceedings: both the
  // general and the bills' deadlines, the lawyer to tell.
  // Once the lawyer said which, only that one.
  for (final k in [...kinds]) {
    if (k.tur != BelgeTuru.odemeEmri ||
        BelgeTuruTespit.odemeEmriTakipTuru('${k.evidence['ad']}') != null) {
      continue;
    }
    final said = {...k.evidence, 'avukat': takipTuru};
    if (takipTuru == 'kambiyo') {
      kinds.remove(k);
      if (seenKinds.add(BelgeTuru.odemeEmriKambiyo)) {
        kinds.add((tur: BelgeTuru.odemeEmriKambiyo, evidence: said));
      }
    } else if (takipTuru == 'genel') {
      kinds[kinds.indexOf(k)] = (tur: k.tur, evidence: said);
    } else if (seenKinds.add(BelgeTuru.odemeEmriKambiyo)) {
      kinds.add((tur: BelgeTuru.odemeEmriKambiyo, evidence: k.evidence));
    }
  }

  final inserted = turkeyDay(sent);
  final served = inserted.addDays(5);
  final read = m.read == null ? null : turkeyDay(m.read!);
  final kategori = category ?? MahkemeKategorisi.bilinmeyen;
  final envelopeText = envelope?.envelopeText ?? '';
  final envelopeDigest = envelopeText.isEmpty
      ? null
      : sha256.convert(utf8.encode(envelopeText)).toString();

  /// One rule's record: its start, its day, why it is as it is.
  DeadlineRecord record(
    YasalSure rule, {
    required String ruleId,
    required BelgeTuru tur,
    required Map<String, Object?> evidence,
    required ({AidiyetSinyali sinyal, String neden}) sign,
    List<DeadlineReason> lead = const [],
    String idSuffix = '',
  }) {
    final reasons = <DeadlineReason>[
      ...lead,
      const DeadlineReason(
        'besGunKurali',
        'Tebliğ, tebligatın elektronik adresinize ulaştığı (UETS kutusuna '
            'girdiği) günü izleyen 5. günün sonunda yapılmış sayıldı (Tebligat '
            'K. m.7/a). Okuma tarihi bunu değiştirmez.',
      ),
      if (!turkeyOffsetKnown(sent))
        const DeadlineReason(
          'eskiSaat',
          '2016 öncesi bir tebligat: o yılların yaz saati uygulaması '
              'hesaba katılmadı.',
        ),
      if (evidence['kaynak'] == 'konu')
        const DeadlineReason(
          'turKonudan',
          'Belge türü yalnız tebligatın konusundan anlaşıldı; ekleri '
              'görülmedi.',
        ),
      if (category == null)
        const DeadlineReason(
          'kategoriBelirsiz',
          'Mahkemenin yargı kolu adından anlaşılamadı; süre ve tatil '
              'kuralları buna göre değişir.',
        ),
      if (takipTuru == null &&
          tur == BelgeTuru.odemeEmriKambiyo &&
          fromParts.every((f) => f.tur != BelgeTuru.odemeEmriKambiyo))
        const DeadlineReason(
          'takipTuruBelirsiz',
          'Ödeme emrinin genel haciz mi kambiyo mu olduğu belgeden '
              'anlaşılamadı; ikisinin süreleri birlikte gösterildi.',
        ),
      if (takipTuru == null &&
          tur == BelgeTuru.odemeEmri &&
          BelgeTuruTespit.odemeEmriTakipTuru('${evidence['ad']}') == null)
        const DeadlineReason(
          'takipTuruBelirsiz',
          'Ödeme emrinin genel haciz mi kambiyo mu olduğu belgeden '
              'anlaşılamadı; ikisinin süreleri birlikte gösterildi.',
        ),
      if (rule.tariheBagli)
        DeadlineReason(
          'kararTarihiBilinmiyor',
          rule.gecerliBitisIso != null || rule.gecerliBaslangicIso == k7499
              ? 'Kararın tarihi bilinmiyor: 1 Haziran 2024’ten önceki ve '
                    'sonraki kararlarda kural farklı (7499 s.K.).'
              : 'Kararın tarihi bilinmiyor; kural karar tarihine bağlı.',
        ),
      DeadlineReason('aidiyet', sign.neden),
    ];

    // The event the rule starts from, never stood in for by another.
    final LegalDay? start = switch (rule.baslangic) {
      SureBaslangici.teblig => served,
      SureBaslangici.ogrenme => read,
      _ => null,
    };
    String? raw, due;
    var state = 'aday';
    if (start == null) {
      state = 'olayBekleniyor';
      reasons.add(
        DeadlineReason('olayBekleniyor', switch (rule.baslangic) {
          SureBaslangici.ogrenme =>
            'Süre öğrenmeden başlar; tebligatın açıldığı gün UETS’ten '
                'henüz gelmedi.',
          SureBaslangici.tefhim =>
            'Süre tefhimden başlar; tefhim günü bilinmiyor.',
          SureBaslangici.ilan => 'Süre ilandan başlar; ilan günü bilinmiyor.',
          _ => 'Süre karar tarihinden başlar; karar tarihi bilinmiyor.',
        }),
      );
    } else {
      final c = DeadlineService.computeFromUsuliTebligTarihi(
        usuliTebligTarihi: start.toLocal(),
        okunmaTarihi: read?.toLocal(),
        kategori: kategori,
        belgeTuru: tur,
        now: at,
        kurallar: [rule],
      );
      final item = c.items.single;
      raw = LegalDay.of(item.hamSonGun).key;
      due = LegalDay.of(item.etkiliSonGun).key;
      if (item.tatilBelirsiz) {
        reasons.add(
          const DeadlineReason(
            'tatilBelirsiz',
            'Son gün adli tatile denk geliyor; davanın tatile tabi olup '
                'olmadığı bilinmediğinden uzatma uygulanmadı. Tatile tabiyse '
                'son gün daha geçtir; ayrıntıdaki dayanağa bakın.',
          ),
        );
      }
      for (final note in item.dayanakNotlari) {
        reasons.add(DeadlineReason('dayanak', note));
      }
      final last = LegalDay.of(item.etkiliSonGun);
      if (TurkishLegalCalendar.isYarimGun(item.etkiliSonGun)) {
        reasons.add(
          const DeadlineReason(
            'yarimGun',
            'Son gün yarım gün; işlemi öğleden önce yapın ya da UYAP '
                'işlem saatini kontrol edin.',
          ),
        );
      }
      if (last.year < TurkishLegalCalendar.kDiniBayramTabloIlkYil ||
          last.year > TurkishLegalCalendar.kDiniBayramTabloSonYil) {
        reasons.add(
          DeadlineReason(
            'takvimDisi',
            '${last.year} yılının bayramları takvimde yok; son gün '
                'doğrulanamadı.',
          ),
        );
      }
      if (rule.maliTatildeDurur &&
          TurkishLegalCalendar.maliTatilBaslangiciKaydi(start.year)) {
        reasons.add(
          DeadlineReason(
            'maliTatilKaydi',
            '${start.year} yılında mali tatil 1 Temmuz’dan sonra başladı '
                '(5604 m.1/1); bitişi 20 Temmuz sayıldı.',
          ),
        );
      }
    }

    final inputs = _digest({
      'tebligat': m.id,
      'kutuyaGiris': sent.toUtc().toIso8601String(),
      'okunma': m.read?.toUtc().toIso8601String(),
      'manifest': manifest.state,
      'manifestZamani': manifest.fetchedAt,
      'zarf': envelope?.state,
      'zarfMetni': envelopeDigest,
      'kanit': evidence,
      'dosya': n.caseKey,
      'bag': n.link,
      'aidiyet': sign.sinyal.name,
      'aidiyetNedeni': sign.neden,
      'kategori': category?.name,
      'kural': ruleId,
      'kuralOlgu': [
        rule.miktar,
        rule.birim.name,
        rule.baslangic.name,
        rule.kanunMaddesi,
        rule.gecerliBaslangicIso,
        rule.gecerliBitisIso,
      ],
      'motor': sureHesapSurumu,
      'takvim': TurkishLegalCalendar.takvimSurumu,
    });
    return DeadlineRecord(
      id: 'uets:${m.id}:r:$ruleId$idSuffix',
      noticeId: m.id,
      caseKey: n.caseKey,
      ruleId: ruleId,
      title: rule.ad,
      law: rule.kanunMaddesi,
      startEvent: switch (rule.baslangic) {
        SureBaslangici.teblig => 'teblig',
        SureBaslangici.ogrenme => 'ogrenme',
        SureBaslangici.tefhim => 'tefhim',
        SureBaslangici.ilan => 'ilan',
        SureBaslangici.kararTarihi => 'karar',
      },
      startDay: start?.key,
      rawDay: raw,
      dueDay: due,
      state: state,
      ownership: sign.sinyal.name,
      reasons: reasons,
      evidence: evidence,
      engine: sureHesapSurumu,
      calendar: TurkishLegalCalendar.takvimSurumu,
      inputs: inputs,
      updated: at,
    );
  }

  final out = <DeadlineRecord>[];
  final catalogued = <(DeadlineRecord, YasalSure)>[];
  // A rule a second document of the same kind brings again is that
  // document's: its id says which, the first keeping the id it always had.
  final made = <String>{};
  for (final k in kinds) {
    for (final rule in surelerForBelgeTuru(k.tur, kategori)) {
      final info = kuralBilgisi(rule);
      final ruleId = info?.id ?? _slug(rule.ad);
      final again = !made.add(ruleId);
      catalogued.add((
        record(
          rule,
          ruleId: ruleId,
          idSuffix: again ? ':p:${k.evidence['parca']}' : '',
          tur: k.tur,
          evidence: k.evidence,
          sign: aidiyetSinyali(
            yukumlu: info?.yukumlu ?? Yukumlu.taraflar,
            taraflar: parties,
            avukat: lawyer,
          ),
          lead: [
            if (envelope == null)
              const DeadlineReason(
                'zarfBekleniyor',
                'Tebligat paketi henüz indirilmedi; zarftaki süre sonra '
                    'karşılaştırılacak.',
              )
            else if (envelopeText.isEmpty)
              const DeadlineReason(
                'zarfOkunamadi',
                'Tebligat zarfının metni okunamadı; zarfta başka bir süre '
                    'olup olmadığını kendiniz kontrol edin.',
              ),
          ],
        ),
        rule,
      ));
    }
  }

  // The envelope's directives: one that gives a catalogued rule's own time
  // joins it, as its second source; one that gives another time is a
  // deadline of its own, both told of the other.
  final directives = envelopeText.isEmpty
      ? const <EnvelopeDirective>[]
      : envelopeDirectives(envelopeText);
  final joined = <int, List<EnvelopeDirective>>{};
  final apart = <EnvelopeDirective>[];
  for (final d in directives) {
    // The same time is not enough: the same act, the same start and the
    // same party first, then the time; else the two stay apart and each
    // says so.
    final fitting = [
      for (var j = 0; j < catalogued.length; j++)
        if (catalogued[j].$2.baslangic == SureBaslangici.teblig &&
            d.startsFrom == null &&
            _sameParty(d.party, kuralBilgisi(catalogued[j].$2)?.yukumlu) &&
            _fits(d.act, catalogued[j].$1.ruleId) &&
            _spanOf(catalogued[j].$2) == d.span)
          j,
    ];
    // Two rules it could be: joined to neither, shown apart. The same rule
    // of two documents of a kind (two reports) is one rule: joined to both.
    final rules = {for (final j in fitting) catalogued[j].$1.ruleId};
    if (rules.length != 1) {
      apart.add(d);
    } else {
      for (final j in fitting) {
        (joined[j] ??= []).add(d);
      }
    }
  }
  for (var i = 0; i < catalogued.length; i++) {
    final (r, rule) = catalogued[i];
    final with_ = joined[i] ?? const [];
    final others = apart;
    out.add(
      with_.isEmpty && others.isEmpty
          ? r
          : r.withState(
              r.state,
              reasons: [
                for (final d in with_)
                  DeadlineReason(
                    'zarfIleUyumlu',
                    'Zarf da aynı süreyi veriyor (${d.text}): “${d.quote}”',
                  ),
                for (final d in others)
                  DeadlineReason(
                    'zarfFarkli',
                    'Zarfta bununla eşleşmeyen bir talimat var (${d.text}'
                        '${d.party == null ? '' : ', ${_partyTitle(d.party!)}'}'
                        '${d.startsFrom == null ? '' : ', ${_startTitle(d.startsFrom!)} başlayan'}'
                        '); o da ayrıca gösterildi.',
                  ),
                ...r.reasons,
              ],
            ),
    );
  }
  for (final d in apart) {
    final rule = YasalSure(
      ad: 'Zarftaki süre · ${_actTitle(d.act)}',
      miktar: d.amount,
      birim: d.unit,
      kanunMaddesi: 'Zarftaki ihtar',
      // The court's own time, not the law's: the recess does not extend it
      // as of course (HMK m.104).
      nitelik: SureNiteligi.hakim,
      // A time the envelope says runs from another event waits for that
      // event's day; the service never stands in for it.
      baslangic: switch (d.startsFrom) {
        'tefhim' => SureBaslangici.tefhim,
        'karar' => SureBaslangici.kararTarihi,
        'ilan' => SureBaslangici.ilan,
        'ogrenme' => SureBaslangici.ogrenme,
        _ => SureBaslangici.teblig,
      },
    );
    final party = d.party;
    out.add(
      record(
        rule,
        ruleId: [
          'zarf-${d.act}-${d.amount}${d.unit.name}',
          ?d.startsFrom,
          ?party,
        ].join('-'),
        tur: kinds.isEmpty ? BelgeTuru.diger : kinds.first.tur,
        evidence: {'kaynak': 'zarf', 'ad': 'Tebligat zarfı'},
        // Spoken to its reader, the duty is the one served's; laid on a
        // party by name, it is that party's, whoever was served.
        sign: party == null
            ? (
                sinyal: AidiyetSinyali.olasiBizim,
                neden:
                    'Zarftaki talimat tebligatın muhatabına, yani size '
                    'yöneltilmiş.',
              )
            : aidiyetSinyali(
                yukumlu: switch (party) {
                  'davaci' => Yukumlu.davaci,
                  'davali' => Yukumlu.davali,
                  'alacakli' => Yukumlu.alacakli,
                  _ => Yukumlu.borclu,
                },
                taraflar: parties,
                avukat: lawyer,
              ),
        lead: [
          DeadlineReason('zarfAlinti', '“${d.quote}”'),
          if (d.startsFrom == null && !d.fromService)
            const DeadlineReason(
              'baslangicVarsayildi',
              'Zarf sürenin neyden başladığını söylemiyor; tebliğden '
                  'başladığı kabul edildi.',
            ),
          if (catalogued.isNotEmpty)
            DeadlineReason(
              'zarfFarkli',
              'Kanunun süresi (${catalogued.map((c) => c.$2.sureMetni).toSet().join(', ')}) '
                  'zarftakinden farklı; ikisi de gösterildi.',
            ),
        ],
      ),
    );
  }
  return out;
}

/// Whether an envelope's directive laid on [party] (null: on its reader)
/// can be the catalogued rule whose duty is [holder]'s.
bool _sameParty(String? party, Yukumlu? holder) =>
    party == null ||
    holder == Yukumlu.taraflar ||
    switch (party) {
      'davaci' => holder == Yukumlu.davaci,
      'davali' => holder == Yukumlu.davali,
      'alacakli' => holder == Yukumlu.alacakli,
      _ => holder == Yukumlu.borclu,
    };

String _startTitle(String event) => switch (event) {
  'tefhim' => 'tefhimden',
  'karar' => 'karar tarihinden',
  'ilan' => 'ilandan',
  _ => 'öğrenmeden',
};

String _partyTitle(String party) => switch (party) {
  'davaci' => 'davacıya',
  'davali' => 'davalıya',
  'alacakli' => 'alacaklıya',
  _ => 'borçluya',
};

({int n, String unit}) _spanOf(YasalSure r) => switch (r.birim) {
  SureBirimi.hafta => (n: r.miktar * 7, unit: 'gun'),
  SureBirimi.gun => (n: r.miktar, unit: 'gun'),
  SureBirimi.isGunu => (n: r.miktar, unit: 'isGunu'),
  SureBirimi.ay => (n: r.miktar, unit: 'ay'),
  SureBirimi.yil => (n: r.miktar, unit: 'yil'),
};

/// Whether an envelope's [act] is the act of the catalogued rule [ruleId].
bool _fits(String act, String ruleId) {
  bool any(List<String> prefixes) => prefixes.any(ruleId.startsWith);
  return switch (act) {
    'itiraz' =>
      ruleId == 'iik89' ||
          any([
            'hmk281',
            'iik62',
            'iik168-5',
            'iik168-4',
            'iik168-3',
            'iik89-1',
            'iik89-2',
            'iik16',
          ]),
    'beyan' => any(['hmk281']),
    'cevap' => any(['hmk127', 'iyuk16']),
    'odeme' => any(['iik168-2', 'iik32']),
    'kanunYolu' => any(['hmk345', 'hmk361', 'cmk', 'iyuk45', 'iik363']),
    _ => false,
  };
}

String _actTitle(String act) => switch (act) {
  'kanunYolu' => 'kanun yolu',
  'itiraz' => 'itiraz',
  'cevap' => 'cevap ve savunma',
  'odeme' => 'ödeme',
  'delil' => 'delil ve tanık',
  'beyan' => 'beyan',
  _ => 'talimat',
};

/// SHA-256 of [inputs] as JSON, its keys in a fixed order.
String _digest(Map<String, Object?> inputs) {
  Object? canonical(Object? v) => v is Map
      ? {
          for (final k in (v.keys.map((k) => '$k').toList()..sort()))
            k: canonical(v[k]),
        }
      : v is List
      ? [for (final x in v) canonical(x)]
      : v;
  return sha256.convert(utf8.encode(jsonEncode(canonical(inputs)))).toString();
}

String _slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// The record with a reason added when the lawyer confirmed it on other
/// inputs than it now has: the confirmation no longer holds (see
/// [KeptDeadline.confirmed]), and the lawyer is told why.
DeadlineRecord? _confirmationChanged(DeadlineUser? user, DeadlineRecord r) {
  final confirmed = user?.confirmedInputs;
  if (confirmed == null || confirmed == r.inputs) return null;
  return r.withState(
    r.state,
    reasons: [
      const DeadlineReason(
        'onaySonrasiDegisti',
        'Onayınızdan sonra tebligatın ya da dosyanın bilgisi değişti; '
            'süreyi yeniden kontrol edip onaylayın.',
      ),
      ...r.reasons,
    ],
  );
}

/// The agenda rows [old] that [fresh]'s notice was kept in before, tied to
/// the new records: a row whose title names a single new record gives it
/// its done mark; one that names several gives none, each is told; one
/// that names none is kept as a record of its own. Returns the records to
/// keep and what to do once they are kept.
({List<DeadlineRecord> records, List<void Function()> after}) _carryOver(
  PortalDatabase db,
  List<AgendaItem> old,
  List<DeadlineRecord> fresh,
  KeptNotice n,
  DateTime at,
) {
  if (old.isEmpty) return (records: fresh, after: const []);
  final records = [...fresh];
  final after = <void Function()>[];
  for (final row in old) {
    final title = row.id.split(':').skip(2).join(':');
    final matches = [
      for (var i = 0; i < records.length; i++)
        if (records[i].title == title) i,
    ];
    final day = row.at == null ? null : LegalDay.of(row.at!).key;
    if (matches.isEmpty) {
      final orphan = _orphan(row, n.message.id, at, caseKey: n.caseKey);
      records.add(orphan);
      after.add(() {
        if (row.done) {
          db.saveDeadlineUser(DeadlineUser(deadlineId: orphan.id, done: true));
        }
        db.archiveLegacy(row, [orphan.id], now: at);
      });
      continue;
    }
    for (final i in matches) {
      final r = records[i];
      records[i] = r.withState(
        r.state,
        reasons: [
          ...r.reasons,
          if (day != null && day != r.dueDay)
            DeadlineReason(
              'eskiKayitFarkli',
              'Önceki kayıt: ${_tr(day)} · ${row.title}.',
            ),
          if (row.done && matches.length > 1)
            const DeadlineReason(
              'eskiTamamlandi',
              'Önceki kayıt tamamlandı olarak işaretlenmişti; hangi süreye '
                  'ait olduğunu seçin.',
            ),
        ],
      );
    }
    final ids = [for (final i in matches) records[i].id];
    after.add(() {
      if (row.done && ids.length == 1) {
        final user =
            db.deadline(ids.single)?.user ??
            DeadlineUser(deadlineId: ids.single);
        db.saveDeadlineUser(user.copyWith(done: true));
      }
      db.archiveLegacy(row, ids, now: at);
    });
  }
  return (records: records, after: after);
}

/// An old agenda row that no new record answers to, kept as it was.
DeadlineRecord _orphan(
  AgendaItem row,
  String noticeId,
  DateTime at, {
  String? caseKey,
}) => DeadlineRecord(
  id: 'uets:$noticeId:eski:${sha256.convert(utf8.encode(row.id)).toString().substring(0, 12)}',
  noticeId: noticeId,
  caseKey: caseKey ?? row.caseKey,
  ruleId: 'eski-kayit',
  title: row.title,
  law: '',
  startEvent: 'teblig',
  startDay: null,
  rawDay: null,
  dueDay: row.at == null ? null : LegalDay.of(row.at!).key,
  state: 'eski',
  ownership: AidiyetSinyali.belirsiz.name,
  reasons: [
    const DeadlineReason(
      'gocEslesmedi',
      'Bu, Folio’nun önceki sürümünün hesapladığı bir süre; yeni hesapta '
          'karşılığı yok. Kontrol edip gerekirse tamamlandı işaretleyin.',
    ),
  ],
  evidence: const {'kaynak': 'eskiKayit'},
  engine: 0,
  calendar: 0,
  inputs: sha256.convert(utf8.encode('eski|${row.id}')).toString(),
  updated: at,
);

String _tr(String key) {
  final p = key.split('-');
  return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : key;
}
