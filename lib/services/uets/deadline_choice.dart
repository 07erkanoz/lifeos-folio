import '../legal/deadlines/kural_bilgisi.dart';
import '../legal/deadlines/mahkeme_kategori.dart';
import '../legal/deadlines/yasal_sure.dart';

/// A deadline the lawyer chose for a notice: a rule of the catalogue, or a
/// time of their own, from the notice's service or another event's day.
/// Added by the lawyer, it is confirmed by that; one put in place of a
/// deadline Folio made takes that one off (the audit's B26: the lawyer's
/// own deadline is the notice's record, with its source, not a note
/// beside it).
class DeadlineChoice {
  final String id;
  final String noticeId;

  /// The catalogue's id of the rule ('hmk345'), or 'ozel' for a time of
  /// the lawyer's own.
  final String ruleId;

  /// For 'ozel': the time and what it is for.
  final int amount;
  final SureBirimi unit;
  final String purpose;

  /// 'teblig', 'tefhim', 'karar', 'ilan' or 'ogrenme'; and its day
  /// ('yyyy-mm-dd'), null for the notice's own service.
  final String startEvent;
  final String? startDay;

  /// The deadline it was put in place of, if any.
  final String? replaces;
  final DateTime created;

  const DeadlineChoice({
    required this.id,
    required this.noticeId,
    required this.ruleId,
    this.amount = 0,
    this.unit = SureBirimi.gun,
    this.purpose = '',
    this.startEvent = 'teblig',
    this.startDay,
    this.replaces,
    required this.created,
  });

  /// The record a choice makes is known by this id.
  String get deadlineId => 'uets:$noticeId:a:$id';

  /// The rule it stands for: the catalogue's, or one made of the lawyer's
  /// own time; null when the catalogue no longer has it.
  YasalSure? get rule {
    if (ruleId == 'ozel') {
      return YasalSure(
        ad: purpose.trim().isEmpty ? 'Sizin süreniz' : purpose.trim(),
        miktar: amount,
        birim: unit,
        kanunMaddesi: 'Sizin girdiğiniz süre',
        // Not a time the law sets, as far as Folio knows: the recess does
        // not extend it as of course; the day is shown before it is kept.
        nitelik: SureNiteligi.hakim,
      );
    }
    for (final r in choosableRules.expand((g) => g.rules)) {
      if (kuralBilgisi(r)?.id == ruleId) return r;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'tebligat': noticeId,
    'kural': ruleId,
    'miktar': amount,
    'birim': unit.name,
    'neIcin': purpose,
    'baslangic': startEvent,
    'baslangicGunu': startDay,
    'yerine': replaces,
    'eklendi': created.toIso8601String(),
  };

  static DeadlineChoice fromJson(Map json) => DeadlineChoice(
    id: '${json['id']}',
    noticeId: '${json['tebligat']}',
    ruleId: '${json['kural']}',
    amount: json['miktar'] as int? ?? 0,
    unit: SureBirimi.values.asNameMap()[json['birim']] ?? SureBirimi.gun,
    purpose: '${json['neIcin'] ?? ''}',
    startEvent: '${json['baslangic'] ?? 'teblig'}',
    startDay: json['baslangicGunu'] as String?,
    replaces: json['yerine'] as String?,
    created: DateTime.parse('${json['eklendi']}'),
  );
}

/// The rules the lawyer chooses from, a group at a time, with the
/// jurisdictions each is for. Only rules the catalogue holds.
const choosableRules =
    <({String title, Set<MahkemeKategorisi> for_, List<YasalSure> rules})>[
      (
        title: 'KANUN YOLU',
        for_: {MahkemeKategorisi.hukuk, MahkemeKategorisi.bilinmeyen},
        rules: [sIstinafHukuk, sTemyizHukuk],
      ),
      (
        title: 'İTİRAZ, CEVAP VE BEYAN',
        for_: {MahkemeKategorisi.hukuk, MahkemeKategorisi.bilinmeyen},
        rules: [sTedbirItiraz, sBilirkisiRaporu, sCevapHmk127],
      ),
      (
        title: 'İCRA',
        for_: {MahkemeKategorisi.icra, MahkemeKategorisi.bilinmeyen},
        rules: [
          sIcraMahkemesiIstinaf,
          sIcraSikayet,
          sOdemeEmriIik62,
          sKambiyoBorcaItiraz,
          sKambiyoImzayaItiraz,
          sIcraEmriOdeme,
          sHacizIhbarnamesi,
          sItirazinIptali,
        ],
      ),
      (
        title: 'CEZA',
        for_: {MahkemeKategorisi.ceza},
        rules: [
          sCezaIstinafYeni,
          sCezaTemyizYeni,
          sCezaIstinafEski,
          sCezaTemyizEski,
        ],
      ),
      (
        title: 'İDARİ VE VERGİ YARGISI',
        for_: {MahkemeKategorisi.idare, MahkemeKategorisi.vergi},
        rules: [sIdariKanunYolu, sIyukSavunma, sIdariDava, sVergiDava],
      ),
    ];
