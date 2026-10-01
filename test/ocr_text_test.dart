import 'package:evrak_convert/services/ocr/ocr_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<String> paragraphs(String text) =>
      ocrDocModel(text).blocks.map((b) => b.plainText).toList();

  test('a justified paragraph is put back together; the parties stay one to '
      'a line; blocks stay apart', () {
    const read =
        'ANTALYA 5. SULH HUKUK MAHKEMESİ’NE\n'
        '\n'
        'DAVACILAR :1- AYŞE DENEME TC: 11111111110\n'
        '2-MEHMET DENEME TC:22222222220\n'
        '3- ALİ DENEME\n'
        'TEMSİLCİ :VELİ ÖRNEK TC: 33333333330\n'
        '\n'
        'AÇIKLAMALAR : Tereke temsilcisinin terekenin tespiti ve korunması\n'
        'açısından temel görevleri, murisin mal varlığının eksik-\n'
        'siz olarak belirlenmesini, belgelendirilmesini ve güvence altına\n'
        'alınmasını sağlamaktır.\n';
    expect(paragraphs(read), [
      'ANTALYA 5. SULH HUKUK MAHKEMESİ’NE',
      '',
      'DAVACILAR :1- AYŞE DENEME TC: 11111111110',
      '2-MEHMET DENEME TC:22222222220',
      '3- ALİ DENEME',
      'TEMSİLCİ :VELİ ÖRNEK TC: 33333333330',
      '',
      'AÇIKLAMALAR : Tereke temsilcisinin terekenin tespiti ve korunması '
          'açısından temel görevleri, murisin mal varlığının eksiksiz olarak '
          'belirlenmesini, belgelendirilmesini ve güvence altına alınmasını '
          'sağlamaktır.',
    ]);
  });

  test('a line that ends a sentence or a label ends its paragraph; an '
      'abbreviation or a line going on in lower case does not', () {
    const read =
        'Davalı işveren fesih bildiriminde bulunmamış, ücreti de ödememiştir.\n'
        'Bu nedenle alacağın faiziyle birlikte tahsiline karar verilmelidir\n'
        've yargılama giderleri davalıya yükletilmelidir.\n'
        // As wide as the page: the margin cut it, not the writer.
        'Antalya 5. Sulh Hukuk Mahkemesinin 2020/1532 E. ve 2021/309 K.\n'
        'Sayılı, 27.03.2024 tarihli ek kararı ile atanan temsilcinin değişti-\n'
        'rilmesi talebidir. Bildirilen tutar 86.224,00 TL.\n'
        'vergi gecikme cezası olarak tahakkuk ettirilmiştir.\n'
        'SONUÇ VE İSTEM:\n';
    expect(paragraphs(read), [
      'Davalı işveren fesih bildiriminde bulunmamış, ücreti de ödememiştir.',
      'Bu nedenle alacağın faiziyle birlikte tahsiline karar verilmelidir '
          've yargılama giderleri davalıya yükletilmelidir.',
      'Antalya 5. Sulh Hukuk Mahkemesinin 2020/1532 E. ve 2021/309 K. '
          'Sayılı, 27.03.2024 tarihli ek kararı ile atanan temsilcinin '
          'değiştirilmesi talebidir. '
          'Bildirilen tutar 86.224,00 TL. vergi gecikme cezası olarak tahakkuk '
          'ettirilmiştir.',
      'SONUÇ VE İSTEM:',
    ]);
  });

  test('what printing put on every page is left out, a misread colon is '
      'put right, and a paragraph broken across blocks is joined', () {
    const read =
        'dilekce ornek.udf\n'
        '\n'
        'VEKİLLERİ ! Av. Deneme Avukat\n'
        'TALEBİN KONUSU :! Temsilcinin değiştirilmesi talebidir.\n'
        '\n'
        'Temsilci görevini yapmak istemediğini açıkça belirtmiştir ancak\n'
        '\n'
        'Sayfa 1/2\n'
        'dilekce ornek.udf\n'
        '\n'
        'dosyaya herhangi bir beyanda bulunmamıştır.\n';
    expect(paragraphs(read), [
      'VEKİLLERİ : Av. Deneme Avukat',
      'TALEBİN KONUSU : Temsilcinin değiştirilmesi talebidir.',
      '',
      'Temsilci görevini yapmak istemediğini açıkça belirtmiştir ancak '
          'dosyaya herhangi bir beyanda bulunmamıştır.',
    ]);
  });

  test('nothing read is one empty paragraph', () {
    expect(paragraphs(' \n\n  \n'), ['']);
  });
}
