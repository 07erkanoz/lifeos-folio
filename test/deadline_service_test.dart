import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/legal/deadlines/belge_turu.dart';
import 'package:evrak_convert/services/legal/deadlines/deadline_service.dart';
import 'package:evrak_convert/services/legal/deadlines/mahkeme_kategori.dart';
import 'package:evrak_convert/services/legal/deadlines/turkish_legal_calendar.dart';
import 'package:evrak_convert/services/legal/deadlines/yasal_sure.dart';

DateTime d(String iso) => DateTime.parse(iso);
String iso(DateTime tarih) =>
    '${tarih.year.toString().padLeft(4, '0')}-'
    '${tarih.month.toString().padLeft(2, '0')}-'
    '${tarih.day.toString().padLeft(2, '0')}';

DeadlineComputation ceza({
  required String teblig,
  String? karar,
  BelgeTuru belge = BelgeTuru.gerekceliKarar,
}) => DeadlineService.computeFromUsuliTebligTarihi(
  usuliTebligTarihi: d(teblig),
  kategori: MahkemeKategorisi.ceza,
  belgeTuru: belge,
  kararTarihi: karar == null ? null : d(karar),
  now: d('2026-08-03'),
);

void main() {
  group('Arka plan adli tatil sorgusu eleme', () {
    test('Tatil dışı ve icra sorgulanmaz, etkili hukuk tarihi sorgulanır', () {
      bool gerekli(DateTime tarih, MahkemeKategorisi kategori) =>
          DeadlineService.adliTatilKarariGerekli(
            gonderimTarihi: tarih,
            kategori: kategori,
            belgeTuru: BelgeTuru.gerekceliKarar,
          );
      expect(gerekli(d('2026-01-10'), MahkemeKategorisi.hukuk), isFalse);
      expect(gerekli(d('2026-07-20'), MahkemeKategorisi.hukuk), isTrue);
      expect(gerekli(d('2026-07-20'), MahkemeKategorisi.icra), isFalse);
    });
    test('Atlanan sorgu bütün kategori ve türlerde kayıt sonucunu korur', () {
      var atlanan = 0;
      var gerekli = 0;
      for (final kategori in MahkemeKategorisi.values) {
        for (final tur in BelgeTuru.values) {
          // Kış, mali tatil, adli tatilin iki sınırı ve yıl geçişi.
          for (final gun in [
            '2026-01-10',
            '2026-06-20',
            '2026-07-01',
            '2026-07-15',
            '2026-07-20',
            '2026-08-15',
            '2026-08-31',
            '2026-09-01',
            '2026-12-25',
          ]) {
            final tarih = d(gun);
            if (DeadlineService.adliTatilKarariGerekli(
              gonderimTarihi: tarih,
              okunmaTarihi: tarih,
              kategori: kategori,
              belgeTuru: tur,
            )) {
              gerekli++;
              continue;
            }
            atlanan++;
            List<Map<String, Object>> hesap(bool? tabi) => [
              for (final x in DeadlineService.compute(
                gonderimTarihi: tarih,
                okunmaTarihi: tarih,
                kategori: kategori,
                belgeTuru: tur,
                adliTatileTabi: tabi,
                now: d('2026-09-13'),
              ).items)
                {
                  'baslik': x.sureAdi,
                  'kanun': x.kanun,
                  'sureMetni': x.sureMetni,
                  'sonGun': x.etkiliSonGun.millisecondsSinceEpoch,
                },
            ];
            expect(hesap(null), hesap(true), reason: '$kategori/$tur/$gun');
            expect(hesap(null), hesap(false), reason: '$kategori/$tur/$gun');
          }
        }
      }
      expect(atlanan, greaterThan(0));
      expect(gerekli, greaterThan(0));
    });
  });

  /// REGRESYON TOHUMU — Türkçe katlama.
  ///
  /// `kategoriFromMahkemeAdi` içinde düz `toLowerCase()` kullanılıyordu.
  /// Dart'ın küçültmesi İ'yi birleşik i̇ (i + combining dot) yapıyor ve bu,
  /// koddaki düz 'iş mahkemesi' dizesiyle EŞLEŞMİYOR. Sonuç: İş Mahkemesi
  /// dosyalarında kategori hiç çözülemiyor, dolayısıyla süre de üretilemiyordu
  /// — sessizce, hata vermeden. Türkçe büyükler artık ÖNCE elle çevriliyor.
  group('Mahkeme adından kategori', () {
    test('İş Mahkemesi tanınır (İ katlaması)', () {
      expect(
        TurkishLegalCalendar.kategoriFromMahkemeAdi('Antalya 2. İş Mahkemesi'),
        MahkemeKategorisi.hukuk,
      );
    });

    test('büyük harfli ad da tanınır', () {
      expect(
        TurkishLegalCalendar.kategoriFromMahkemeAdi(
          'ALANYA 1. ASLİYE CEZA MAHKEMESİ',
        ),
        MahkemeKategorisi.ceza,
      );
      expect(
        TurkishLegalCalendar.kategoriFromMahkemeAdi('İSTANBUL VERGİ MAHKEMESİ'),
        MahkemeKategorisi.vergi,
      );
    });

    test('tanınmayan adda null — yanlış uzatma üretmektense hesap yapma', () {
      expect(
        TurkishLegalCalendar.kategoriFromMahkemeAdi('Bilinmeyen Kurum'),
        isNull,
      );
      expect(TurkishLegalCalendar.kategoriFromMahkemeAdi(''), isNull);
      expect(TurkishLegalCalendar.kategoriFromMahkemeAdi(null), isNull);
    });
  });

  /// REGRESYON TOHUMU — 2026-08-27, kanundan doğrulandı.
  ///
  /// Motor her "hukuk" dosyasını adli tatile TABİ sayıp HMK m.104 uzatmasını
  /// koşulsuz uyguluyordu. Oysa m.104 uzatmayı yalnız "adli tatile tabi olan
  /// dava ve işlerde" verir; m.103 tatilde görülenleri sayar (İŞÇİNİN açtığı
  /// iş davaları, nafaka/soybağı/velayet/vesayet, nüfus, iflas-konkordato,
  /// çekişmesiz yargı, ivedi işler, ihtiyati tedbir/haciz) ve onlarda uzatma
  /// YOKTUR. Bir iş davasında motor 8 Ağustos yerine 7 Eylül diyordu: bir ay
  /// hayalî süre, üstelik hak kaybettiren yönde.
  group('HMK m.103 — adli tatile tabi olmayan işler', () {
    DeadlineComputation hukuk({bool? tabi}) =>
        DeadlineService.computeFromUsuliTebligTarihi(
          usuliTebligTarihi: d('2026-07-25'),
          kategori: MahkemeKategorisi.hukuk,
          belgeTuru: BelgeTuru.gerekceliKarar,
          now: d('2026-07-26'),
          adliTatileTabi: tabi,
        );

    test('tabi olduğu BİLİNİYORSA m.104 uzatması uygulanır', () {
      // Yargıtay HGK 2017/20-2873 E., 2017/1449 K.; 2. HD 2021/2526 E.,
      // 2021/3729 K.: hafta 1 Eylül'den sayılır, son gün 8 Eylül.
      final s = hukuk(tabi: true).items.single;
      expect(iso(s.hamSonGun), '2026-08-08');
      expect(iso(s.etkiliSonGun), '2026-09-08');
      expect(s.dayanakNotlari.join(' '), contains('HMK m.104'));
    });

    test('tabi DEĞİLSE uzatma uygulanmaz, son gün tatil içinde kalır', () {
      final s = hukuk(tabi: false).items.single;
      expect(iso(s.hamSonGun), '2026-08-08');
      // 8 Ağustos 2026 cumartesi — iş günü kaydırması ayrıca çalışır.
      expect(iso(s.etkiliSonGun), '2026-08-10');
      expect(s.dayanakNotlari.join(' '), contains('HMK m.103'));
    });

    test('BİLİNMİYORSA uzatma uygulanmaz — belirsizlik güvenli yöne düşer', () {
      // Uzatmak son günü İLERİ atar; yanlış ileri tarih hak kaybettirir,
      // yanlış erken tarih yalnız erken çalıştırır.
      final s = hukuk().items.single;
      expect(iso(s.etkiliSonGun), '2026-08-10');
      expect(s.dayanakNotlari.join(' '), contains('belirlenemedi'));
      // Uyarı, tabi olsaydı çıkacak tarihi de söylemeli.
      expect(s.dayanakNotlari.join(' '), contains('08.09.2026'));
    });
  });

  /// REGRESYON TOHUMU — İYUK m.8/3 ile HMK m.104 AYNI ÇAPAYI KULLANMAZ.
  ///
  /// İYUK m.8/3 çapası 1 Eylül'dür ve o gün BİRİNCİ gündür; yedinci gün
  /// 7 Eylül. Kaydırma sayımın içinde olduğu için ayrıca +1 EKLENMEZ —
  /// eklenince 8 Eylül çıkıyor ve bu hak kaybettiren yönde bir hatadır
  /// (Danıştay İDDK somut olayda son günü 7 Eylül kabul ediyor). HMK m.104'ün
  /// 8 Eylül'ü ayrı kuraldır; İYUK ona göre değiştirilmez. Dayanak atfı da
  /// düzeltildi: uzatmayı m.61 değil m.8/3 verir.
  group('İYUK m.8/3 — idari yargıda uzatma dayanağı', () {
    test('uzatma 7 Eylüldür ve dayanak m.8/3 olarak yazılır', () {
      final s = DeadlineService.computeFromUsuliTebligTarihi(
        usuliTebligTarihi: d('2026-07-25'),
        kategori: MahkemeKategorisi.idare,
        belgeTuru: BelgeTuru.gerekceliKarar,
        now: d('2026-07-26'),
        adliTatileTabi: true,
      ).items.single;
      expect(iso(s.etkiliSonGun), '2026-09-07');
      final notlar = s.dayanakNotlari.join(' ');
      expect(notlar, contains('İYUK m.8/3'));
      expect(notlar, isNot(contains('İYUK m.61)')));
    });
  });

  group('CMK adli tatil', () {
    test('tatilden önce başlayıp ham sonu tatile gelen süre 3 Eylüle uzar', () {
      final sonuc = ceza(teblig: '2026-07-10', karar: '2026-07-10');
      expect(iso(sonuc.items.single.hamSonGun), '2026-07-24');
      expect(iso(sonuc.items.single.etkiliSonGun), '2026-09-03');
    });

    test(
      '20 Temmuzda doğan iki haftalık süre 1 Eylülde başlayıp 15 Eylülde biter',
      () {
        final sonuc = ceza(teblig: '2026-07-20', karar: '2026-07-20');
        expect(iso(sonuc.items.single.baslangicTarihi), '2026-09-01');
        expect(iso(sonuc.items.single.etkiliSonGun), '2026-09-15');
        expect(
          sonuc.items.single.dayanakNotlari.join(' '),
          contains('47/1 İBK'),
        );
      },
    );

    test('31 Ağustosta doğan süre de 1 Eylülde başlar', () {
      final sonuc = ceza(teblig: '2026-08-31', karar: '2026-08-31');
      expect(iso(sonuc.items.single.baslangicTarihi), '2026-09-01');
      expect(iso(sonuc.items.single.etkiliSonGun), '2026-09-15');
    });

    test('1 Eylül tebliğinde ayrıca adli tatil uzaması uygulanmaz', () {
      final sonuc = ceza(teblig: '2026-09-01', karar: '2026-09-01');
      expect(iso(sonuc.items.single.etkiliSonGun), '2026-09-15');
      expect(
        sonuc.items.single.dayanakNotlari.join(' '),
        isNot(contains('47/1 İBK')),
      );
    });
  });

  group('7499 geçişi', () {
    test('31 Mayıs 2024 kararı eski yedi günlük istinaf süresidir', () {
      final sonuc = ceza(teblig: '2024-05-31', karar: '2024-05-31');
      expect(sonuc.items.single.sureMetni, '7 gün');
      expect(sonuc.items.single.kanun, 'CMK m.273');
    });

    test('1 Haziran 2024 kararı iki haftalık istinaf süresidir', () {
      final sonuc = ceza(teblig: '2024-06-01', karar: '2024-06-01');
      expect(sonuc.items.single.sureMetni, '2 hafta');
    });

    test('karar tarihi yoksa eski ve yeni iki senaryo görünür kalır', () {
      final sonuc = ceza(teblig: '2026-06-01');
      expect(sonuc.items, hasLength(2));
      expect(sonuc.items.map((x) => x.sureMetni).toSet(), {'7 gün', '2 hafta'});
    });

    test('ceza BAM kararı yeni rejimde CMK 291 iki haftadır', () {
      final sonuc = ceza(
        teblig: '2026-06-01',
        karar: '2026-05-30',
        belge: BelgeTuru.istinafKarari,
      );
      expect(sonuc.items.single.kanun, 'CMK m.291');
      expect(sonuc.items.single.sureMetni, '2 hafta');
    });

    test('ceza BAM kararı eski rejimde CMK 291 on beş gündür', () {
      final sonuc = ceza(
        teblig: '2024-05-01',
        karar: '2024-05-31',
        belge: BelgeTuru.istinafKarari,
      );
      expect(sonuc.items.single.kanun, 'CMK m.291');
      expect(sonuc.items.single.sureMetni, '15 gün');
    });
  });

  group('duruşmada verilen süre (katalog dışı)', () {
    // Süre KATALOGDAN gelmez, zabıttan okunur: "tanık listesi için iki hafta
    // kesin süre". UETS bunu asla göremez — yüze karşı tefhim edilir, zarf
    // yoktur. Takvim hesabı yine motorda kalır; modele aritmetik sorulmaz.
    YasalSure tanikListesi() => const YasalSure(
      ad: 'Tanık listesi bildirme',
      miktar: 2,
      birim: SureBirimi.hafta,
      kanunMaddesi: 'HMK m.94 (kesin süre)',
      baslangic: SureBaslangici.tefhim,
      guven: SureGuveni.orta,
      nitelik: SureNiteligi.hakim,
    );

    test('başlangıç TEFHİM tarihidir, tebliğ beklenmez', () {
      // 12 Mart duruşması + 2 hafta = 26 Mart. Adli tatil yok, uzatma yok.
      final sonuc = DeadlineService.computeFromOzelSure(
        baslangic: d('2026-03-12'),
        sure: tanikListesi(),
        kategori: MahkemeKategorisi.hukuk,
        now: d('2026-03-13'),
      );
      expect(iso(sonuc.items.single.etkiliSonGun), '2026-03-26');
      expect(sonuc.items.single.kanun, 'HMK m.94 (kesin süre)');
      expect(sonuc.items.single.sureMetni, '2 hafta');
    });

    test('adli tatile tabi işte de hâkimin süresi kendiliğinden UZAMAZ', () {
      // 12 Ağustos duruşması + 2 hafta = 26 Ağustos, adli tatilin İÇİNDE
      // bitiyor. HMK m.104 yalnız "kanunda belirtilen" süreleri uzatır;
      // hâkimin verdiği süre için uzatma varsayılmaz, avukata kontrol
      // etmesi söylenir (denetim raporu B12).
      final sonuc = DeadlineService.computeFromOzelSure(
        baslangic: d('2026-08-12'),
        sure: tanikListesi(),
        kategori: MahkemeKategorisi.hukuk,
        now: d('2026-08-13'),
        adliTatileTabi: true,
      );
      expect(iso(sonuc.items.single.etkiliSonGun), '2026-08-26');
      expect(sonuc.items.single.uzadi, isFalse);
      expect(sonuc.items.single.dayanakNotlari.join(' '), contains('hâkim'));
    });

    test('m.103 kapsamındaki işte uzatma YOKTUR', () {
      // REGRESYON TOHUMU: işçinin açtığı iş davası m.103/1-ç kapsamındadır,
      // m.104 uzatması uygulanmaz. Uzatmak son günü 12 gün ileri atar ve
      // avukata dolmuş bir süreyi "hâlâ var" diye gösterir.
      final sonuc = DeadlineService.computeFromOzelSure(
        baslangic: d('2026-08-12'),
        sure: tanikListesi(),
        kategori: MahkemeKategorisi.hukuk,
        now: d('2026-08-13'),
        adliTatileTabi: false,
      );
      expect(iso(sonuc.items.single.etkiliSonGun), '2026-08-26');
      expect(sonuc.items.single.uzadi, isFalse);
    });

    test('kapsam bilinmiyorsa uzatma uygulanmaz (güvenli yön)', () {
      final sonuc = DeadlineService.computeFromOzelSure(
        baslangic: d('2026-08-12'),
        sure: tanikListesi(),
        kategori: MahkemeKategorisi.hukuk,
        now: d('2026-08-13'),
      );
      expect(iso(sonuc.items.single.etkiliSonGun), '2026-08-26');
    });

    test('katalog HİÇ sorgulanmaz — yalnız verilen kural üretilir', () {
      // Belge türü `diger` ile katalog boş döner; ham süre yolu buna rağmen
      // tek bir sonuç üretmeli. Katalog sızarsa sayı 1'den büyük olurdu.
      final sonuc = DeadlineService.computeFromOzelSure(
        baslangic: d('2026-03-12'),
        sure: tanikListesi(),
        kategori: MahkemeKategorisi.hukuk,
        now: d('2026-03-13'),
      );
      expect(sonuc.items, hasLength(1));
    });
  });
}
