/// Tebligat konu ayrıştırıcı.
///
/// UETS tebligat konusundan mahkeme adı, dosya numarası ve mahkeme
/// kategorisini çıkarır. (AvukatOS Hukuk projesinden taşınmıştır.)
library;

import 'mahkeme_kategori.dart';
import 'turkish_legal_calendar.dart';

/// Parse edilmiş tebligat bilgileri.
class TebligatParsed {
  final String mahkemeAdi; // "Manavgat 1. Aile Mahkemesi"
  final String dosyaNo; // "2025/465"
  final String mahkemeTuru; // "Aile", "Asliye Hukuk", "İcra" vs.
  final MahkemeKategorisi kategori;

  const TebligatParsed({
    required this.mahkemeAdi,
    required this.dosyaNo,
    required this.mahkemeTuru,
    required this.kategori,
  });

  static const empty = TebligatParsed(
    mahkemeAdi: '',
    dosyaNo: '',
    mahkemeTuru: '',
    kategori: MahkemeKategorisi.bilinmeyen,
  );

  bool get isEmpty => mahkemeAdi.isEmpty && dosyaNo.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

/// Tebligat konu metnini ayrıştırır.
///
/// Beklenen format: `"Manavgat 1. Aile Mahkemesi [2025/465] [detay]"`.
/// İlk `[...]` → dosya numarası, öncesi → mahkeme adı.
class TebligatParser {
  TebligatParser._();

  static TebligatParsed parse(String konu) {
    if (konu.isEmpty) return TebligatParsed.empty;

    final bracketMatch = RegExp(r'^(.+?)\s*\[(\d{4}/\d+)\]').firstMatch(konu);

    String mahkemeAdi;
    String dosyaNo;

    if (bracketMatch != null) {
      mahkemeAdi = bracketMatch.group(1)!.trim();
      dosyaNo = bracketMatch.group(2)!;
    } else {
      final altMatch = RegExp(r'^(.+?)\s*\[').firstMatch(konu);
      mahkemeAdi = altMatch?.group(1)?.trim() ?? konu.trim();
      dosyaNo = '';
    }

    final mahkemeTuru = _detectMahkemeTuru(mahkemeAdi);
    // Folio: the one classifier the UETS deadlines use too; two that
    // disagreed gave "Bölge Adliye Mahkemesi 5. Ceza Dairesi" the civil
    // courts' rules here and the criminal ones there.
    final kategori =
        TurkishLegalCalendar.kategoriFromMahkemeAdi(mahkemeAdi) ??
        MahkemeKategorisi.bilinmeyen;

    return TebligatParsed(
      mahkemeAdi: mahkemeAdi,
      dosyaNo: dosyaNo,
      mahkemeTuru: mahkemeTuru,
      kategori: kategori,
    );
  }

  /// Mahkeme adından tür çıkar (örn. "Manavgat 1. Aile Mahkemesi" → "Aile").
  static String _detectMahkemeTuru(String ad) {
    final lower = ad.toLowerCase();

    // Sıralama önemli — spesifik olanlar önce.
    if (lower.contains('icra ceza')) return 'İcra Ceza';
    if (lower.contains('icra hukuk')) return 'İcra Hukuk';
    if (lower.contains('icra dairesi') || lower.contains('icra müdürlüğü')) {
      return 'İcra';
    }
    if (lower.contains('çocuk ağır ceza')) return 'Çocuk Ağır Ceza';
    if (lower.contains('ağır ceza')) return 'Ağır Ceza';
    if (lower.contains('asliye ceza')) return 'Asliye Ceza';
    if (lower.contains('sulh ceza')) return 'Sulh Ceza';
    if (lower.contains('çocuk')) return 'Çocuk';
    if (lower.contains('aile')) return 'Aile';
    if (lower.contains('asliye hukuk')) return 'Asliye Hukuk';
    if (lower.contains('asliye ticaret') || lower.contains('ticaret')) {
      return 'Ticaret';
    }
    if (lower.contains('iş mahkemesi') || lower.contains('iş ')) return 'İş';
    if (lower.contains('tüketici')) return 'Tüketici';
    if (lower.contains('kadastro')) return 'Kadastro';
    if (lower.contains('sulh hukuk')) return 'Sulh Hukuk';
    if (lower.contains('fikri ve sınai')) return 'Fikri Sınai';
    if (lower.contains('vergi')) return 'Vergi';
    if (lower.contains('bölge idare')) return 'Bölge İdare';
    if (lower.contains('idare')) return 'İdare';
    if (lower.contains('bölge adliye')) return 'Bölge Adliye';
    if (lower.contains('anayasa')) return 'Anayasa';
    if (lower.contains('yargıtay')) return 'Yargıtay';
    if (lower.contains('danıştay')) return 'Danıştay';
    if (lower.contains('savcılık') || lower.contains('savcılığı')) {
      return 'Savcılık';
    }
    if (lower.contains('noter')) return 'Noter';
    if (lower.contains('icra')) return 'İcra'; // Genel icra

    return '';
  }
}
