/// İcra süreçlerine ait dar, yapılandırılmış takvim sözleşmesi.
/// Durma, eski rejim ve belirsiz başlangıçta tarih üretilmez.
library;

import 'mahkeme_kategori.dart';
import 'turkish_legal_calendar.dart';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
Map<String, Object?> icraSureHesapla(Map<String, Object?> g) {
  final k = g['kural'];
  final s = g['baslangic'];
  final d = s is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)
      ? DateTime.tryParse(s)
      : null;
  final missing = <String>[];
  if (d == null || _iso(d) != s) missing.add('Usulüne uygun başlangıç tarihi');
  if (g['durma'] != 'yok') {
    missing.add(
      'İtiraz, taksit, geri bırakma veya diğer durmanın süreye etkisi',
    );
  }
  if (g['rejim'] != 'guncel') {
    missing.add('Olay tarihinde uygulanacak geçiş rejimi');
  }
  if (k == 'haciz_isteme' && g['takip_yolu'] != 'genel_ilamsiz') {
    missing.add('Genel haciz yoluyla ilamsız takip');
  }
  if (!['haciz_isteme', 'satis_isteme', 'gider_tamamlama'].contains(k)) {
    missing.add('Desteklenen süre türü');
  }
  if (g['avukat_onayi'] != true) {
    missing.add('Başlangıç ve hukuki koşulların avukat doğrulaması');
  }
  if (missing.isNotEmpty) {
    return {'ok': false, 'icra_surumu': 1, 'eksikler': missing};
  }
  // İİK m.19: karşılık gelen gün; bulunmazsa o ayın son günü.
  final last = DateTime(d!.year + 1, d.month + 1, 0).day;
  final raw = k == 'gider_tamamlama'
      ? d.add(const Duration(days: 15))
      : DateTime(d.year + 1, d.month, d.day > last ? last : d.day);
  final adj = TurkishLegalCalendar.adjustDeadline(
    raw,
    kategori: MahkemeKategorisi.icra,
    adliTatileTabi: false,
  );
  final projection = TurkishLegalCalendar.diniBayramProjeksiyonYili(
    adj.effectiveDate.year,
  );
  return {
    'ok': true,
    'icra_surumu': 1,
    'kural': k,
    'baslangic': s,
    'ham_son_gun': _iso(raw),
    'son_gun': projection ? null : _iso(adj.effectiveDate),
    'takvim_teyidi_gerekli': projection,
    'takvim_son_guncelleme': TurkishLegalCalendar.kTakvimSonGuncelleme,
    'dayanak': k == 'haciz_isteme' ? 'İİK m.78 ve 19' : 'İİK m.106 ve 19',
    'notlar': [
      ...adj.notes,
      if (projection) 'Hedef yılın tatil takvimi proje içinde doğrulanmadı; kesin son gün gösterilmez.',
      'Bu tarih tek başına takibin veya haczin düştüğünü göstermez. Talep, gider, durma ve geçiş koşulları ayrıca izlenir.',
    ],
  };
}
