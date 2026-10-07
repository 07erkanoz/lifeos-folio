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
void refreshNoticeDeadlines(
  PortalDatabase db, {
  Map<String, List<TarafKaydi>> parties = const {},
  String? lawyer,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final legacy = <String, List<AgendaItem>>{};
  for (final old in db.legacyNoticeDeadlines()) {
    final notice = old.id.split(':').elementAtOrNull(1) ?? '';
    (legacy[notice] ??= []).add(old);
  }
  final seen = <String>{};
  final manifests = db.manifests();
  final users = {
    for (final d in db.deadlines())
      if (d.user != null) d.record.id: d.user!,
  };
  for (final n in db.notices()) {
    seen.add(n.message.id);
    final fresh = noticeDeadlines(
      n,
      manifest:
          manifests[n.message.id] ??
          (state: 'alinmadi', fetchedAt: null, parts: const []),
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
  List<TarafKaydi> parties = const [],
  String? lawyer,
  DateTime? now,
}) {
  final m = n.message;
  final sent = m.sent;
  if (sent == null) return const [];
  final at = now ?? DateTime.now();
  final subject = NoticeSubject.parse(m.subject);
  final category = subject == null
      ? null
      : TurkishLegalCalendar.kategoriFromMahkemeAdi(subject.unit);

  // The kinds of document, each with what told it.
  final kinds = <({BelgeTuru tur, Map<String, Object?> evidence})>[];
  final seenKinds = <BelgeTuru>{};
  final names = [for (final p in manifest.parts) p.name];
  final fromParts = BelgeTuruTespit.ekTurleri(names);
  for (final k in fromParts) {
    if (!seenKinds.add(k.tur)) continue;
    final part = manifest.parts.firstWhere((p) => p.name == k.ad);
    kinds.add((
      tur: k.tur,
      evidence: {
        'kaynak': 'ek',
        'ad': k.ad,
        'parca': part.id,
        'sira': manifest.parts.indexOf(part),
      },
    ));
  }
  if (kinds.isEmpty) {
    final t = BelgeTuruTespit.tebligatTuru(const [], metin: m.subject);
    if (!BelgeTuruTespit.belirsiz(t)) {
      kinds.add((tur: t, evidence: {'kaynak': 'konu', 'ad': ''}));
    }
  }
  // A payment order that does not say its kind of proceedings: both the
  // general and the bills' deadlines, the lawyer to tell.
  for (final k in [...kinds]) {
    if (k.tur == BelgeTuru.odemeEmri &&
        BelgeTuruTespit.odemeEmriTakipTuru('${k.evidence['ad']}') == null &&
        seenKinds.add(BelgeTuru.odemeEmriKambiyo)) {
      kinds.add((tur: BelgeTuru.odemeEmriKambiyo, evidence: k.evidence));
    }
  }

  final inserted = turkeyDay(sent);
  final served = inserted.addDays(5);
  final read = m.read == null ? null : turkeyDay(m.read!);
  final out = <DeadlineRecord>[];
  for (final k in kinds) {
    final kategori = category ?? MahkemeKategorisi.bilinmeyen;
    for (final rule in surelerForBelgeTuru(k.tur, kategori)) {
      final info = kuralBilgisi(rule);
      final ruleId = info?.id ?? _slug(rule.ad);
      final reasons = <DeadlineReason>[
        const DeadlineReason(
          'ulasmaDogrulanmadi',
          'Tebliğ günü, UETS’in tebligatı kutuya koyduğu andan beş gün '
              'sonra sayıldı; ulaşma deliliyle doğrulanmadı.',
        ),
        if (!turkeyOffsetKnown(sent))
          const DeadlineReason(
            'eskiSaat',
            '2016 öncesi bir tebligat: o yılların yaz saati uygulaması '
                'hesaba katılmadı.',
          ),
        if (k.evidence['kaynak'] == 'konu')
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
        if (k.tur == BelgeTuru.odemeEmriKambiyo &&
            fromParts.every((f) => f.tur != BelgeTuru.odemeEmriKambiyo))
          const DeadlineReason(
            'takipTuruBelirsiz',
            'Ödeme emrinin genel haciz mi kambiyo mu olduğu belgeden '
                'anlaşılamadı; ikisinin süreleri birlikte gösterildi.',
          ),
        if (k.tur == BelgeTuru.odemeEmri &&
            BelgeTuruTespit.odemeEmriTakipTuru('${k.evidence['ad']}') == null)
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
      ];
      final sign = aidiyetSinyali(
        yukumlu: info?.yukumlu ?? Yukumlu.taraflar,
        taraflar: parties,
        avukat: lawyer,
      );
      reasons.add(DeadlineReason('aidiyet', sign.neden));

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
          belgeTuru: k.tur,
          now: at,
          kurallar: [rule],
        );
        final item = c.items.single;
        raw = LegalDay.of(item.hamSonGun).key;
        due = LegalDay.of(item.etkiliSonGun).key;
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
        'kanit': k.evidence,
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
      out.add(
        DeadlineRecord(
          id: 'uets:${m.id}:r:$ruleId',
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
          evidence: k.evidence,
          engine: sureHesapSurumu,
          calendar: TurkishLegalCalendar.takvimSurumu,
          inputs: inputs,
          updated: at,
        ),
      );
    }
  }
  return out;
}

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
