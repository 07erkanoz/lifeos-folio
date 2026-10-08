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
import 'deadline_choice.dart';
import 'envelope_directives.dart';
import 'notice_documents.dart';
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
      documents: db.noticeDocuments(n.message.id),
      choices: db.deadlineChoices(n.message.id),
      represented: n.caseKey == null ? const [] : db.representation(n.caseKey!),
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

  /// Its package's documents as read (see [readNoticeDocuments]).
  List<NoticeDocument> documents = const [],

  /// The deadlines the lawyer chose for it (see [DeadlineChoice]).
  List<DeadlineChoice> choices = const [],
  List<TarafKaydi> parties = const [],
  String? lawyer,

  /// Whom the lawyer said they act for in its case (see
  /// [PortalDatabase.representation]); before any guess by names.
  List<({String ad, String rol})> represented = const [],
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
  // The unit by the package's own description first (UYAP's name of it),
  // the subject's words after.
  final caseFile = documents
      .map((d) => d.caseFile)
      .whereType<NoticeCaseFile>()
      .firstOrNull;
  final category =
      TurkishLegalCalendar.kategoriFromMahkemeAdi(caseFile?.unitName) ??
      (subject == null
          ? null
          : TurkishLegalCalendar.kategoriFromMahkemeAdi(subject.unit));

  // The kinds of document, each with what told it: a document at a time,
  // so that two expert reports or two interim decisions in one package are
  // two documents, each with its own deadlines, not one.
  final kinds = <({BelgeTuru tur, Map<String, Object?> evidence})>[];
  final seenKinds = <BelgeTuru>{};
  final fromParts = <({BelgeTuru tur, String ad})>[];
  // The court's documents read, with their kinds, for their directives.
  final courtDocuments = <(NoticeDocument, BelgeTuru)>[];
  final docs = [
    for (final d in documents)
      if (d.state != 'ustveri') d,
  ];
  // The notice's list's parts; with no list, the package's documents, or
  // their names while they are not read yet (the audit's D16).
  final attached = envelope?.attachments ?? const [];
  final listedParts = manifest.parts.isNotEmpty
      ? [
          for (var i = 0; i < manifest.parts.length; i++)
            (
              id: manifest.parts[i].id,
              name: manifest.parts[i].name,
              seq: i,
              doc: docs
                  .where((d) => d.partId == manifest.parts[i].id)
                  .firstOrNull,
            ),
        ]
      : docs.isNotEmpty
      ? [
          for (final d in docs)
            (
              id: 'ek${d.seq}',
              name: d.name,
              seq: d.seq,
              doc: d as NoticeDocument?,
            ),
        ]
      : [
          for (var i = 0; i < attached.length; i++)
            if (!attached[i].name.toLowerCase().endsWith('.xml'))
              (
                id: 'ek$i',
                name: attached[i].name,
                seq: i,
                doc: null as NoticeDocument?,
              ),
        ];
  for (final part in listedParts) {
    final doc = part.doc;
    final byName = BelgeTuruTespit.ekTurleri([part.name]);
    // A name that tells nothing: what the document itself says it is,
    // by its heading.
    final byText = byName.isEmpty && doc != null && doc.hasText
        ? BelgeTuruTespit.tebligatTuru(const [], metin: doc.text)
        : null;
    final BelgeTuru tur;
    final String source;
    if (byName.isNotEmpty) {
      tur = byName.single.tur;
      source = 'ek';
      fromParts.add(byName.single);
    } else if (byText != null && !BelgeTuruTespit.belirsiz(byText)) {
      tur = byText;
      source = 'ekIcerik';
    } else {
      continue;
    }
    seenKinds.add(tur);
    kinds.add((
      tur: tur,
      evidence: {
        'kaynak': source,
        'ad': part.name,
        'parca': part.id,
        'sira': part.seq,
        'ozet': ?doc?.digest,
      },
    ));
    if (doc != null &&
        doc.hasText &&
        (_courtKinds.contains(tur) || _confirmingKinds.contains(tur))) {
      courtDocuments.add((doc, tur));
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

  /// Whose a duty of [yukumlu] is: by whom the lawyer said they act for in
  /// the case, else by the lawyer's name in its party list.
  ({AidiyetSinyali sinyal, String neden}) whose(Yukumlu yukumlu) =>
      represented.isNotEmpty
      ? aidiyetTemsilden(yukumlu: yukumlu, temsil: represented)
      : aidiyetSinyali(yukumlu: yukumlu, taraflar: parties, avukat: lawyer);

  /// One rule's record: its start, its day, why it is as it is.
  DeadlineRecord record(
    YasalSure rule, {
    required String ruleId,
    required BelgeTuru tur,
    required Map<String, Object?> evidence,
    required ({AidiyetSinyali sinyal, String neden}) sign,
    List<DeadlineReason> lead = const [],
    String? id,
    ({String event, LegalDay day})? startAt,
  }) {
    final reasons = <DeadlineReason>[
      ...lead,
      if (startAt == null)
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
      if (evidence['kaynak'] == 'ekIcerik')
        DeadlineReason(
          'turIcerikten',
          'Belge türü dosyanın adından değil, belgenin kendi başlığından '
              'anlaşıldı (${evidence['ad']}).',
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
    final LegalDay? start =
        startAt?.day ??
        switch (rule.baslangic) {
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
      // What the documents' contents were when it was reckoned (B24): one
      // read again, or changed, asks for the confirmation again.
      'belgeler': [
        for (final d in documents) [d.seq, d.digest, d.state, d.reader],
      ],
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
      id: id ?? 'uets:${m.id}:r:$ruleId',
      noticeId: m.id,
      caseKey: n.caseKey,
      ruleId: ruleId,
      title: rule.ad,
      law: rule.kanunMaddesi,
      startEvent:
          startAt?.event ??
          switch (rule.baslangic) {
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
      // The day of service too: a deadline with no day of its own goes by
      // its notice's age (see [KeptDeadline.expired]).
      evidence: {...evidence, 'teblig': served.key},
      engine: sureHesapSurumu,
      calendar: TurkishLegalCalendar.takvimSurumu,
      inputs: inputs,
      updated: at,
    );
  }

  final out = <DeadlineRecord>[];
  final catalogued = <(DeadlineRecord, YasalSure)>[];
  // A rule two documents of a kind bring in one notice (a report and its
  // annexes, two reports) starts on the same day and ends on the same day:
  // one deadline, which names every document it runs for (the audit's
  // B18: a repeated service's evidence joined). Notices of other days are
  // other deadlines.
  final made = <String, int>{};
  final alsoFor = <int, List<String>>{};
  for (final k in kinds) {
    for (final rule in surelerForBelgeTuru(k.tur, kategori)) {
      final info = kuralBilgisi(rule);
      final ruleId = info?.id ?? _slug(rule.ad);
      if (made[ruleId] case final at?) {
        (alsoFor[at] ??= []).add('${k.evidence['ad']}');
        continue;
      }
      // The old criminal regime's time from a pronouncement in presence:
      // the pronouncement came before 1 June 2024, so the time ran out
      // within weeks of it. A notice served long after cannot bring it.
      final until = DateTime.tryParse(rule.gecerliBitisIso ?? '');
      if (rule.baslangic == SureBaslangici.tefhim &&
          until != null &&
          inserted.isAfter(LegalDay.of(until).addDays(rule.gun + 60))) {
        continue;
      }
      made[ruleId] = catalogued.length;
      catalogued.add((
        record(
          rule,
          ruleId: ruleId,
          tur: k.tur,
          evidence: k.evidence,
          sign: whose(info?.yukumlu ?? Yukumlu.taraflar),
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

  for (final e in alsoFor.entries) {
    final (r, rule) = catalogued[e.key];
    catalogued[e.key] = (
      r.withState(
        r.state,
        reasons: [
          ...r.reasons,
          DeadlineReason(
            'birdenCokBelge',
            'Aynı süre bu tebligattaki başka belgeler için de işliyor: '
                '${e.value.join(', ')}.',
          ),
        ],
      ),
      rule,
    );
  }

  // The envelope's directives: one that gives a catalogued rule's own time
  // joins it, as its second source; one that gives another time is a
  // deadline of its own, both told of the other.
  // The directives: the envelope's, and those of the court's own documents
  // read (a tensip, an interim decision, a hearing's minutes, a decision):
  // not a party's petition, whose "iki hafta içinde" is no duty of anyone's.
  final sources = <_DirectiveSource>[
    if (envelopeText.isNotEmpty)
      _DirectiveSource(
        key: 'zarf',
        envelope: true,
        name: 'Tebligat zarfı',
        text: envelopeText,
        makes: true,
        evidence: const {'kaynak': 'zarf', 'ad': 'Tebligat zarfı'},
        tur: kinds.isEmpty ? BelgeTuru.diger : kinds.first.tur,
      ),
    for (final (d, tur) in courtDocuments)
      _DirectiveSource(
        key: 'ek${d.seq}',
        envelope: false,
        name: d.name,
        text: d.text,
        makes: _courtKinds.contains(tur),
        evidence: {
          'kaynak': 'ekTalimat',
          'ad': d.name,
          'parca': ?d.partId,
          'sira': d.seq,
          'ozet': d.digest,
        },
        tur: tur,
      ),
  ];
  final directives = [
    for (final source in sources)
      for (final d in envelopeDirectives(source.text)) (source, d),
  ];
  final joined = <int, List<(_DirectiveSource, EnvelopeDirective)>>{};
  final apart = <(_DirectiveSource, EnvelopeDirective)>[];
  for (final sd in directives) {
    final d = sd.$2;
    // The same time is not enough: the same act, the same start and the
    // same party first, then the time; else the two stay apart and each
    // says so.
    final fitting = [
      for (var j = 0; j < catalogued.length; j++)
        if (catalogued[j].$2.baslangic == SureBaslangici.teblig &&
            d.startsFrom == null &&
            _sameParty(d.party, kuralBilgisi(catalogued[j].$2)?.yukumlu) &&
            // A decision's words only bear a rule out: any act its clause
            // names will do; a time that makes a deadline goes by its own.
            (sd.$1.makes
                ? _fits(d.act, catalogued[j].$1.ruleId)
                : {
                    d.act,
                    ...d.acts,
                  }.any((a) => _fits(a, catalogued[j].$1.ruleId))) &&
            _spanOf(catalogued[j].$2) == d.span)
          j,
    ];
    // Two rules it could be: joined to neither, shown apart. The same rule
    // of two documents of a kind (two reports) is one rule: joined to both.
    final rules = {for (final j in fitting) catalogued[j].$1.ruleId};
    if (rules.length != 1) {
      if (sd.$1.makes) apart.add(sd);
    } else {
      for (final j in fitting) {
        (joined[j] ??= []).add(sd);
      }
    }
  }
  // The same directive in the envelope and in a document (the envelope
  // often repeats the tensip's warning) is one deadline, told of both: the
  // first source makes it, the envelope before the documents.
  final groups = <String, List<(_DirectiveSource, EnvelopeDirective)>>{};
  for (final sd in apart) {
    final d = sd.$2;
    (groups['${d.act}|${d.amount}|${d.unit.name}|${d.startsFrom}|${d.party}'] ??=
            [])
        .add(sd);
  }
  for (var i = 0; i < catalogued.length; i++) {
    final (r, rule) = catalogued[i];
    final with_ = joined[i] ?? const [];
    final others = [for (final g in groups.values) g.first];
    out.add(
      with_.isEmpty && others.isEmpty
          ? r
          : r.withState(
              r.state,
              reasons: [
                for (final (s, d) in with_)
                  DeadlineReason(
                    'zarfIleUyumlu',
                    s.envelope
                        ? 'Zarf da aynı süreyi veriyor (${d.text}): “${d.quote}”'
                        : 'Aynı süre ekte de yazıyor (${d.text}; ${s.name}): '
                              '“${d.quote}”',
                  ),
                for (final (s, d) in others)
                  DeadlineReason(
                    'zarfFarkli',
                    '${s.envelope ? 'Zarfta' : 'Ekte'} bununla eşleşmeyen bir '
                        'talimat var (${d.text}'
                        '${d.party == null ? '' : ', ${_partyTitle(d.party!)}'}'
                        '${d.startsFrom == null ? '' : ', ${_startTitle(d.startsFrom!)} başlayan'}'
                        '); o da ayrıca gösterildi.',
                  ),
                ...r.reasons,
              ],
            ),
    );
  }
  for (final group in groups.values) {
    final (s, d) = group.first;
    final rule = YasalSure(
      ad: '${s.envelope ? 'Zarftaki' : 'Ekteki'} süre · ${_actTitle(d.act)}',
      miktar: d.amount,
      birim: d.unit,
      kanunMaddesi: s.envelope ? 'Zarftaki ihtar' : 'Ekteki talimat',
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
          '${s.envelope ? 'zarf' : s.key}-${d.act}-${d.amount}${d.unit.name}',
          ?d.startsFrom,
          ?party,
        ].join('-'),
        tur: s.tur,
        evidence: s.evidence,
        // Spoken to its reader, the duty is the one served's; laid on a
        // party by name, it is that party's, whoever was served.
        sign: party == null && !d.toReader
            // Told of the service only, to no one: either side's, as a way
            // of appeal is.
            ? whose(Yukumlu.taraflar)
            : party == null
            ? (
                sinyal: AidiyetSinyali.olasiBizim,
                neden: s.envelope
                    ? 'Zarftaki talimat tebligatın muhatabına, yani size '
                          'yöneltilmiş.'
                    : 'Ekteki talimat belgeyi okuyana, yani size yöneltilmiş.',
              )
            : whose(switch (party) {
                'davaci' => Yukumlu.davaci,
                'davali' => Yukumlu.davali,
                'alacakli' => Yukumlu.alacakli,
                _ => Yukumlu.borclu,
              }),
        lead: [
          DeadlineReason(
            'zarfAlinti',
            s.envelope ? '“${d.quote}”' : '“${d.quote}” (${s.name})',
          ),
          if (d.otherAmount case final other?)
            DeadlineReason(
              'sayiCelisiyor',
              'Süre belgede iki türlü yazılmış (${d.amount} ve $other); '
                  'kısa olanı gösterildi. Belgeye bakıp doğrusunu seçin.',
            ),
          if (d.strict)
            const DeadlineReason(
              'kesinSure',
              'Mahkeme bunu kesin süre olarak verdi; süresinde yapılmayan '
                  'işlemin hakkı düşebilir (HMK m.94).',
            ),
          for (final (o, _) in group.skip(1))
            DeadlineReason(
              'zarfIleUyumlu',
              o.envelope
                  ? 'Zarf da aynı talimatı veriyor.'
                  : 'Aynı talimat ekte de yazıyor (${o.name}).',
            ),
          if (d.startsFrom == null && !d.fromService)
            DeadlineReason(
              'baslangicVarsayildi',
              '${s.envelope ? 'Zarf' : 'Belge'} sürenin neyden başladığını '
                  'söylemiyor; tebliğden başladığı kabul edildi.',
            ),
          if (catalogued.isNotEmpty)
            DeadlineReason(
              'zarfFarkli',
              'Kanunun süresi (${catalogued.map((c) => c.$2.sureMetni).toSet().join(', ')}) '
                  '${s.envelope ? 'zarftakinden' : 'ektekinden'} farklı; '
                  'ikisi de gösterildi.',
            ),
        ],
      ),
    );
  }
  // The lawyer's own: each the rule they chose, from the day they gave.
  for (final c in choices) {
    final rule = c.rule;
    if (rule == null) continue;
    final day = c.startDay == null ? null : DateTime.tryParse(c.startDay!);
    out.add(
      record(
        rule,
        id: c.deadlineId,
        ruleId: c.ruleId,
        tur: kinds.isEmpty ? BelgeTuru.diger : kinds.first.tur,
        evidence: {'kaynak': 'avukat', 'secim': c.id, 'yerine': ?c.replaces},
        sign: (
          sinyal: AidiyetSinyali.olasiBizim,
          neden: 'Bu süreyi siz eklediniz.',
        ),
        startAt: day == null && c.startEvent == 'teblig'
            ? null
            : (event: c.startEvent, day: LegalDay.of(day ?? sent)),
        lead: [
          DeadlineReason(
            'avukatSecti',
            c.replaces == null
                ? 'Bu süreyi siz seçtiniz.'
                : 'Bu süreyi Folio’nun önerdiği sürenin yerine siz seçtiniz.',
          ),
        ],
      ),
    );
  }
  return out;
}

/// Where a directive was read: the envelope, or a document of the court.
class _DirectiveSource {
  const _DirectiveSource({
    required this.key,
    required this.envelope,
    required this.name,
    required this.text,
    required this.makes,
    required this.evidence,
    required this.tur,
  });
  final String key;
  final bool envelope;

  /// Whether a directive of it that no rule holds is a deadline of its
  /// own; else it only bears a rule out.
  final bool makes;
  final String name;
  final String text;
  final Map<String, Object?> evidence;
  final BelgeTuru tur;
}

/// The court's own documents whose times are the judge's, not the law's:
/// their directives are read. Not a party's petition or an expert's report,
/// which only quote or propose; nor a decision or an order to pay, whose
/// times the catalogue holds and whose text repeats the law (measured on
/// the box's 116 documents, 8 October 2026: read, those gave a second,
/// noisier copy of the catalogue's own deadline).
const _courtKinds = {
  BelgeTuru.tensipZapti,
  BelgeTuru.araKarar,
  BelgeTuru.durusmaTutanagi,
  BelgeTuru.durusmaDavetiyesi,
  BelgeTuru.muzekkere,
};

/// A court's decisions and orders: their directives only bear out the
/// catalogue's deadline ("tebliğden itibaren iki hafta içinde istinaf"),
/// never make one of their own.
const _confirmingKinds = {
  BelgeTuru.gerekceliKarar,
  BelgeTuru.kararIlami,
  BelgeTuru.istinafKarari,
  BelgeTuru.temyizKarari,
  BelgeTuru.odemeEmri,
  BelgeTuru.odemeEmriKambiyo,
  BelgeTuru.icraEmri,
};

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
    'cevap' => any(['hmk127', 'iyuk16', 'hmk136', 'hmk347', 'cmk277']),
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
