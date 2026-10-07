import 'package:evrak_convert/services/legal/deadlines/sure_katalogu.dart';
import 'package:evrak_convert/services/uets/envelope_directives.dart';
import 'package:flutter_test/flutter_test.dart';

// The times an envelope gives its reader, read by rule (the report's B03,
// B17; T39–T41). The texts are made up, after the shape of real ones.
void main() {
  test('a court’s summons: two weeks for the answer', () {
    final d = envelopeDirectives(
      'DAVETİYE. Dava dilekçesi ekte gönderilmiştir. HMK 122-129 maddeleri '
      'gereğince 2 hafta içinde iddia ve savunmalarınızı delilleriniz ile '
      'birlikte vermeniz, aksi halde dava dilekçesinde ileri sürülen '
      'vakıaların tamamını inkar etmiş sayılacağınız hususu ihtar ve tebliğ '
      'olunur.',
    );
    expect(d, hasLength(1));
    expect((d.single.amount, d.single.unit), (2, SureBirimi.hafta));
    expect(d.single.act, 'cevap');
    // "ihtar ve tebliğ olunur" at the sentence's end is the serving, not
    // the time's start: the start is taken, and said to be.
    expect(d.single.fromService, isFalse);
    expect(d.single.span, (n: 14, unit: 'gun'));
  });

  test('an office’s decision: thirty days to object, its past omissions '
      'and a quoted law left out', () {
    final d = envelopeDirectives(
      'İşe giriş bildirgesi yasal süresi içinde verilmediğinden idari para '
      'cezası uygulanmıştır. Kanunun 14 üncü maddesinde "İşveren, iş '
      'kazalarını kazadan sonraki 3 iş günü içinde Kuruma bildirir." '
      'denilmektedir. İş kazası yasal süresi içerisinde bildirilmediğinden '
      'ceza uygulanmıştır. Söz konusu cezaya karşı kararın tarafınıza '
      'tebliğinden itibaren (30) gün içinde yetkili mahkemeye itiraz '
      'hakkınız vardır.',
    );
    expect(d, hasLength(1));
    expect((d.single.amount, d.single.unit), (30, SureBirimi.gun));
    expect(d.single.act, 'itiraz');
  });

  test('a short, plain directive is not missed (T39)', () {
    final d = envelopeDirectives(
      'Gider avansını bir hafta içinde yatırmanız ihtar olunur.',
    );
    expect(d.single.amount, 1);
    expect(d.single.unit, SureBirimi.hafta);
    expect(d.single.act, 'odeme');
    expect(d.single.fromService, isFalse);
  });

  test('a directive in the middle of a long letter is found (T40)', () {
    final filler = List.filled(200, 'Dosya incelenmiştir.').join(' ');
    final d = envelopeDirectives(
      '$filler Tanık listenizi on beş (15) gün içerisinde sunmanız '
      'gerekmektedir. $filler',
    );
    expect(d.single.amount, 15);
    expect(d.single.act, 'delil');
  });

  test('words and figures, and working days', () {
    expect(
      envelopeDirectives(
        'Beyanlarınızı iki (2) hafta içinde bildirmeniz gerekir.',
      ).single.amount,
      2,
    );
    final d = envelopeDirectives(
      'Eksikliği tebliğden itibaren 3 iş günü içinde tamamlamanız gerekir.',
    ).single;
    expect(d.unit, SureBirimi.isGunu);
  });

  test('a sentence that speaks to no one and not of service gives nothing', () {
    expect(
      envelopeDirectives('Bilirkişi raporunu 2 hafta içinde dosyaya sunar.'),
      isEmpty,
    );
    expect(
      envelopeDirectives('Duruşma 12.11.2026 günü saat 10.30’dadır.'),
      isEmpty,
    );
  });

  test('a time that runs from another event is not taken', () {
    final d = envelopeDirectives(
      'Karar tarafınıza tebliğ edilmiş olup dosyanın incelenmesi sonucunda '
      'eksikliklerin giderilmesi için gereken işlemlerin yapılması, harç ve '
      'masrafların karşılanması ve diğer hususların değerlendirilmesi ile '
      'ilgili olarak bilirkişi incelemesine karar verilmiştir; buna göre '
      'beyanlarınızı duruşmadan sonraki iki hafta içinde sununuz.',
    );
    // "duruşmadan sonraki": another event's time, not a directive from service.
    expect(d, isEmpty);
  });

  test('an appeal’s time is told apart', () {
    final d = envelopeDirectives(
      'Karara karşı tebliğden itibaren iki hafta içinde istinaf yoluna '
      'başvurabilirsiniz.',
    ).single;
    expect(d.act, 'kanunYolu');
    expect(d.fromService, isTrue);
  });

  test('a past omission in another clause does not drop the time', () {
    final d = envelopeDirectives(
      'Bildirim zamanında verilmediğinden ceza verildi; tarafınıza '
      'tebliğden itibaren 30 gün içinde itiraz hakkınız vardır.',
    ).single;
    expect((d.amount, d.unit, d.act), (30, SureBirimi.gun, 'itiraz'));
  });

  test('an act and a service in another clause are not this time’s', () {
    final d = envelopeDirectives(
      'İstinaf başvurusu reddedildi; iki hafta içinde cevaplarınızı sununuz.',
    ).single;
    expect(d.act, 'cevap');
    expect(d.fromService, isFalse);
  });
}
