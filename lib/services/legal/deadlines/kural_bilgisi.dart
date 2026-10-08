import 'sure_katalogu.dart';

/// Whose duty a deadline is: the side of the case that must act in it. A
/// deadline is the lawyer's only when the lawyer acts for that side.
enum Yukumlu {
  /// The defendant (an answer to a statement of claim).
  davali,

  /// The debtor (objections to a payment order, an order to pay).
  borclu,

  /// The third person a garnishment notice is sent to.
  ucuncuKisi,

  /// The creditor (the suit against a debtor's objection).
  alacakli,

  /// The plaintiff (a time the court gives the one who sued).
  davaci,

  /// Either side of the case may act (an appeal, an objection to a report);
  /// which one is the lawyer's is not told by the rule.
  taraflar,
}

/// A rule's lasting name, for the records and their history: the Turkish
/// title of a rule may be reworded, its id is not. And whose duty it is.
class KuralBilgisi {
  final String id;
  final Yukumlu yukumlu;
  const KuralBilgisi(this.id, this.yukumlu);
}

const _kurallar = <YasalSure, KuralBilgisi>{
  sIstinafHukuk: KuralBilgisi('hmk345', Yukumlu.taraflar),
  sTemyizHukuk: KuralBilgisi('hmk361', Yukumlu.taraflar),
  sCevapHmk127: KuralBilgisi('hmk127', Yukumlu.davali),
  sBilirkisiRaporu: KuralBilgisi('hmk281', Yukumlu.taraflar),
  sIcraSikayet: KuralBilgisi('iik16', Yukumlu.taraflar),
  sItirazinIptali: KuralBilgisi('iik67', Yukumlu.alacakli),
  sOdemeEmriIik62: KuralBilgisi('iik62', Yukumlu.borclu),
  sKambiyoBorcaItiraz: KuralBilgisi('iik168-5-borca', Yukumlu.borclu),
  sKambiyoImzayaItiraz: KuralBilgisi('iik168-4-imza', Yukumlu.borclu),
  sKambiyoVasifSikayeti: KuralBilgisi('iik168-3-sikayet', Yukumlu.borclu),
  sKambiyoOdeme: KuralBilgisi('iik168-2-odeme', Yukumlu.borclu),
  sIcraEmriOdeme: KuralBilgisi('iik32', Yukumlu.borclu),
  sIcraEmriGeriBirakma: KuralBilgisi('iik33', Yukumlu.borclu),
  sHacizIhbarnamesi: KuralBilgisi('iik89', Yukumlu.ucuncuKisi),
  sHaciz891: KuralBilgisi('iik89-1', Yukumlu.ucuncuKisi),
  sHaciz892: KuralBilgisi('iik89-2', Yukumlu.ucuncuKisi),
  sHaciz893Dava: KuralBilgisi('iik89-3-dava', Yukumlu.ucuncuKisi),
  sHaciz893Belge: KuralBilgisi('iik89-3-belge', Yukumlu.ucuncuKisi),
  sIcraMahkemesiIstinaf: KuralBilgisi('iik363', Yukumlu.taraflar),
  sCezaIstinafEski: KuralBilgisi('cmk273-eski', Yukumlu.taraflar),
  sCezaIstinafEskiTefhim: KuralBilgisi('cmk273-eski-tefhim', Yukumlu.taraflar),
  sCezaIstinafYeni: KuralBilgisi('cmk273', Yukumlu.taraflar),
  sCezaTemyizEski: KuralBilgisi('cmk291-eski', Yukumlu.taraflar),
  sCezaTemyizEskiTefhim: KuralBilgisi('cmk291-eski-tefhim', Yukumlu.taraflar),
  sCezaTemyizYeni: KuralBilgisi('cmk291', Yukumlu.taraflar),
  sIdariDava: KuralBilgisi('iyuk7-idari', Yukumlu.taraflar),
  sVergiDava: KuralBilgisi('iyuk7-vergi', Yukumlu.taraflar),
  sIyukSavunma: KuralBilgisi('iyuk16', Yukumlu.davali),
  sIdariKanunYolu: KuralBilgisi('iyuk45-46', Yukumlu.taraflar),
  sIstinafBilinmeyen: KuralBilgisi('hmk345-belirsiz', Yukumlu.taraflar),
  sTemyizBilinmeyen: KuralBilgisi('hmk361-belirsiz', Yukumlu.taraflar),
};

/// [sure]'s id and duty holder. A rule added to the catalogue without an
/// entry here fails the catalogue's test, never silently.
KuralBilgisi? kuralBilgisi(YasalSure sure) => _kurallar[sure];

/// Every rule that has an entry, for that test.
Iterable<YasalSure> get bilinenKurallar => _kurallar.keys;
