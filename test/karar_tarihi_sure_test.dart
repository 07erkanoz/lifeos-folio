// KARAR TARİHİ SÜRE BAŞLANGICI DEĞİLDİR.
//
// `uyapweb.md` §21.4 bu alanı "temyiz/karar düzeltme sürelerinin başlangıcı"
// diye yazmıştı; kullanıcı (avukat) düzeltti: kanun yolu süreleri TEBLİĞDEN
// işler (HMK m.345/1, m.361/1), cezada yüze karşı kararda TEFHİMDEN
// (CMK m.273/1). Bu test o yanlışın koda geri sızmasını engeller.
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/legal/deadlines/sure_katalogu.dart';

void main() {
  test('kararTarihi KURAL SÜRÜMÜ seçer — süreyi başlatmaz', () {
    // Tarih-etkin bir kural: yalnız belirli bir dönemde verilen kararlara
    // uygulanır. `gecerliMi` bunu sorar; süre hesabı yapmaz.
    const k = YasalSure(
      ad: 'test',
      miktar: 2,
      kanunMaddesi: 'test m.1',
      birim: SureBirimi.hafta,
      baslangic: SureBaslangici.teblig,
      gecerliBaslangicIso: '2020-01-01',
      gecerliBitisIso: '2024-01-01',
    );
    expect(k.tariheBagli, isTrue);
    expect(k.gecerliMi(DateTime(2022, 6, 1)), isTrue);
    expect(k.gecerliMi(DateTime(2019, 12, 31)), isFalse);
    expect(k.gecerliMi(DateTime(2024, 1, 1)), isFalse, reason: '[from, to)');
    // BİLİNMİYORSA KURAL ELENMEZ — engine güveni düşürür, kuralı atmaz.
    expect(k.gecerliMi(null), isTrue);
  });

  test('sürenin BAŞLANGICI ayrı bir kavramdır (tebliğ/tefhim)', () {
    // Katalogda başlangıç türü kuralın kendi alanıdır; karar tarihi değil.
    const teblig = YasalSure(
      ad: 'istinaf',
      miktar: 2,
      kanunMaddesi: 'HMK m.345/1',
      birim: SureBirimi.hafta,
      baslangic: SureBaslangici.teblig,
    );
    const tefhim = YasalSure(
      ad: 'ceza istinaf',
      miktar: 7,
      kanunMaddesi: 'CMK m.273/1',
      birim: SureBirimi.gun,
      baslangic: SureBaslangici.tefhim,
    );
    expect(teblig.baslangic, SureBaslangici.teblig);
    expect(tefhim.baslangic, SureBaslangici.tefhim);
    // `kararTarihi` bir başlangıç TÜRÜ olarak katalogda var ama kanun yolu
    // süreleri için kullanılmaz — bu iki kural onu seçmiyor.
    expect(teblig.baslangic, isNot(SureBaslangici.kararTarihi));
    expect(tefhim.baslangic, isNot(SureBaslangici.kararTarihi));
  });
}
