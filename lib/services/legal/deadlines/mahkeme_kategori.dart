/// Mahkeme kategorisi — yasal süre eşleştirmesi ve adli tatil uzatması için.
///
/// UYAP/UETS modülünün hukuk çekirdeğinin ortak enum'u. (AvukatOS Hukuk
/// projesinden taşınan, kanıtlanmış sınıflandırma.)
enum MahkemeKategorisi {
  hukuk, // Aile, Asliye Hukuk, Ticaret, İş, Tüketici, Kadastro, Sulh Hukuk
  icra, // İcra Dairesi, İcra Hukuk, İcra Ceza
  ceza, // Ağır Ceza, Asliye Ceza, Sulh Ceza, Çocuk, Savcılık
  idare, // İdare, Bölge İdare, Danıştay
  vergi, // Vergi Mahkemesi
  bilinmeyen,
}
