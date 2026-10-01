import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/legal/citation.dart';
import 'package:evrak_convert/services/speech/reading_text.dart';

/// A filing is written for the eye; the voice is given it in words.
void main() {
  final reading = ReadingText.parse(
    File('assets/ses/okuma.json').readAsStringSync(),
    {
      for (final law in CitationScanner.parse(
        File('assets/mevzuat/laws.json').readAsStringSync(),
      ).laws)
        for (final short in law.abbreviations)
          if (short != 'Anayasa') short: law.name,
    },
  );

  test('numbers, and numbers that count', () {
    expect(sayiYazi(0), 'sıfır');
    expect(sayiYazi(1000), 'bin');
    expect(sayiYazi(2025), 'iki bin yirmi beş');
    expect(sayiYazi(15000), 'on beş bin');
    expect(sayiYazi(1100000), 'bir milyon yüz bin');
    expect(siraYazi(3), 'üçüncü');
    expect(siraYazi(4), 'dördüncü');
    expect(siraYazi(119), 'yüz on dokuzuncu');
    expect(siraYazi(20), 'yirminci');
    expect(siraYazi(60), 'altmışıncı');
  });

  test('a name takes the case the sentence gave its short form', () {
    expect(
      inflect('Hukuk Muhakemeleri Kanunu', 'nın'),
      "Hukuk Muhakemeleri Kanunu'nun",
    );
    expect(
      inflect('Hukuk Muhakemeleri Kanunu', 'ya'),
      "Hukuk Muhakemeleri Kanunu'na",
    );
    expect(
      inflect('Sosyal Güvenlik Kurumu', 'dan'),
      "Sosyal Güvenlik Kurumu'ndan",
    );
    expect(inflect('Türk Medeni Kanunu', 'daki'), "Türk Medeni Kanunu'ndaki");
    expect(inflect('Anayasa', 'ya'), "Anayasa'ya");
    expect(inflect('Türk lirası', 'nin', proper: false), 'Türk lirasının');
  });

  test('the sentence that was read out badly as written', () {
    expect(
      reading.spoken(
        "Davacı vekili, Ankara 3. Asliye Hukuk Mahkemesi'nin 2025/417 Esas "
        'sayılı dosyasına sunduğu dilekçede, HMK m. 119 uyarınca 15.000 TL '
        'alacağın faiziyle birlikte tahsilini talep etmiştir.',
      ),
      "Davacı vekili, Ankara üçüncü Asliye Hukuk Mahkemesi'nin iki bin "
      'yirmi beş, dört yüz on yedi Esas sayılı dosyasına sunduğu dilekçede, '
      "Hukuk Muhakemeleri Kanunu'nun yüz on dokuzuncu maddesi uyarınca on "
      'beş bin Türk lirası alacağın faiziyle birlikte tahsilini talep '
      'etmiştir.',
    );
  });

  test('what a filing is thick with', () {
    expect(
      reading.spoken('TMK m. 166/1'),
      "Türk Medeni Kanunu'nun yüz altmış altıncı maddesinin birinci fıkrası",
    );
    expect(
      reading.spoken("HMK'nın 297. maddesi"),
      "Hukuk Muhakemeleri Kanunu'nun iki yüz doksan yedinci maddesi",
    );
    expect(
      reading.spoken('6100 s. HMK'),
      'altı bin yüz sayılı Hukuk Muhakemeleri Kanunu',
    );
    expect(
      reading.spoken('Yargıtay 3. HD. 2024/1234 E., 2025/56 K.'),
      'Yargıtay üçüncü Hukuk Dairesi iki bin yirmi dört, bin iki yüz otuz '
      'dört Esas, iki bin yirmi beş, elli altı Karar',
    );
    expect(
      reading.spoken('01.02.2025 tarihli'),
      'bir Şubat iki bin yirmi beş tarihli',
    );
    expect(
      reading.spoken("1.250,50 TL'nin %18'i"),
      'bin iki yüz elli Türk lirasının elli kuruş yüzde on sekiz\'i',
    );
    expect(
      reading.spoken('Av. Ayşe Kaya, SGK\'ya'),
      "Avukat Ayşe Kaya, Sosyal Güvenlik Kurumu'na",
    );
    expect(reading.spoken('AÇIKLAMALAR'), 'açıklamalar');
    expect(reading.spoken('KLM Ltd. Şti.'), 'ke le me Limited Şirketi');
    expect(reading.spoken('TÜRK MİLLETİ ADINA'), 'türk milleti adına');
    expect(
      reading.spoken('Tel: 0532 123 45 67'),
      'telefon sıfır beş yüz otuz iki yüz yirmi üç kırk beş altmış yedi',
    );
  });

  test('sentences end at a full stop, not at an abbreviation or ordinal', () {
    const text =
        'Av. Ayşe Kaya 3. Asliye Hukuk Mahkemesine başvurdu. '
        'HMK m. 119 uyarınca talepte bulundu!\n'
        'SONUÇ VE İSTEM\n\n  Kabulü gerekir';
    final sentences = reading.sentences(text);
    expect(sentences.map((s) => s.text).toList(), [
      'Av. Ayşe Kaya 3. Asliye Hukuk Mahkemesine başvurdu.',
      'HMK m. 119 uyarınca talepte bulundu!',
      'SONUÇ VE İSTEM',
      'Kabulü gerekir',
    ]);
    for (final s in sentences) {
      expect(text.substring(s.start, s.end), s.text);
    }
  });

  test('a sentence too long to say in a breath is parted at a comma', () {
    final long = List.filled(40, 'uzun bir cümle parçası').join(', ');
    final sentences = reading.sentences('$long.');
    expect(sentences.length, greaterThan(1));
    expect(sentences.every((s) => s.text.length <= 330), isTrue);
  });
}
