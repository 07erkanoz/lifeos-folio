import 'kural_bilgisi.dart';

/// Whether a deadline seems to be the lawyer's own. Only a sign: a name in
/// a party's lawyer field may be another lawyer's of the same name, an
/// office may be written instead of a person, the representation may have
/// ended. So it never makes a deadline certain, nor hides one; it labels.
enum AidiyetSinyali {
  /// The lawyer acts, by the case's party list, for the side that must act.
  olasiBizim,

  /// The lawyer acts for the other side: the duty is the other side's.
  olasiKarsi,

  /// Not to be told from what is known.
  belirsiz,
}

/// A party as the case's list gives it: its role and its lawyers' names.
typedef TarafKaydi = ({String rol, String vekil});

/// The sign for a rule whose duty is [yukumlu], from the case's [taraflar]
/// and the lawyer's own name [avukat]; with the reason, in a sentence for
/// the lawyer.
({AidiyetSinyali sinyal, String neden}) aidiyetSinyali({
  required Yukumlu yukumlu,
  required List<TarafKaydi> taraflar,
  required String? avukat,
}) {
  ({AidiyetSinyali sinyal, String neden}) belirsiz(String neden) =>
      (sinyal: AidiyetSinyali.belirsiz, neden: neden);
  final ad = _kelimeler(avukat ?? '')..removeWhere((w) => w == 'av');
  if (ad.length < 2) {
    return belirsiz(
      'Avukat adınız bilinmiyor; sürenin kime ait olduğu '
      'denetlenemedi.',
    );
  }
  if (taraflar.isEmpty) {
    return belirsiz(
      'Dosyanın tarafları Folio’da yok; sürenin kime ait '
      'olduğu denetlenemedi.',
    );
  }
  final bizimRoller = <String>{
    for (final t in taraflar)
      if (_kelimeler(t.vekil).toSet().containsAll(ad)) t.rol,
  };
  if (bizimRoller.isEmpty) {
    return belirsiz(
      'Dosyanın taraf listesinde vekil olarak adınız '
      'bulunamadı.',
    );
  }
  final yanlar = {for (final r in bizimRoller) _yan(r)};
  if (yanlar.length > 1 || yanlar.contains(_Yan.bilinmiyor)) {
    return belirsiz(
      'Dosyada birden fazla ya da tanınmayan sıfatta '
      'görünüyorsunuz (${bizimRoller.join(', ')}).',
    );
  }
  final yan = yanlar.single;
  final rol = bizimRoller.join(', ');
  ({AidiyetSinyali sinyal, String neden}) bizim() => (
    sinyal: AidiyetSinyali.olasiBizim,
    neden: 'Taraf listesine göre $rol vekilisiniz.',
  );
  ({AidiyetSinyali sinyal, String neden}) karsi(String kimin) => (
    sinyal: AidiyetSinyali.olasiKarsi,
    neden: 'Taraf listesine göre $rol vekilisiniz; bu süre $kimin.',
  );
  return switch (yukumlu) {
    // Either side may act; whether the decision went against the lawyer's
    // side is not known here.
    Yukumlu.taraflar => belirsiz(
      'Bu süre her iki taraf için işler; $rol vekilisiniz. Karar ya da '
      'işlem aleyhinizse sizin süreniz.',
    ),
    Yukumlu.davali => yan == _Yan.pasif ? bizim() : karsi('davalının'),
    Yukumlu.borclu => yan == _Yan.pasif ? bizim() : karsi('borçlunun'),
    Yukumlu.alacakli => yan == _Yan.aktif ? bizim() : karsi('alacaklının'),
    Yukumlu.ucuncuKisi =>
      yan == _Yan.ucuncu ? bizim() : karsi('üçüncü kişinin'),
  };
}

enum _Yan { aktif, pasif, ucuncu, bilinmiyor }

/// The side a role is on: the one who sues or claims, the one sued or
/// pursued, or a third person.
_Yan _yan(String rol) {
  final r = _kelimeler(rol).join(' ');
  bool has(String k) => r.contains(k);
  if (has('ucuncu') || has('3 kisi') || has('muhatap')) return _Yan.ucuncu;
  if (has('davaci') ||
      has('alacakli') ||
      has('musteki') ||
      has('katilan') ||
      has('magdur') ||
      has('basvuran')) {
    return _Yan.aktif;
  }
  if (has('davali') ||
      has('borclu') ||
      has('sanik') ||
      has('supheli') ||
      has('karsi taraf')) {
    return _Yan.pasif;
  }
  return _Yan.bilinmiyor;
}

/// Words, Turkish letters folded, case dropped: "Av. Ayşe ÇELİK" and
/// "AYSE CELIK" are the same two words.
List<String> _kelimeler(String s) {
  var x = s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('û', 'u');
  x = x.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  return x.isEmpty ? <String>[] : x.split(' ');
}
