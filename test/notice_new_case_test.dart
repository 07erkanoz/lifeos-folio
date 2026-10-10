import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/uyap_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // As UYAP writes them (the form measured on live notifications; the
  // names invented).
  UyapNoticeRow row(String title, String body) => UyapNoticeRow(
    source: UyapNoticeSource.mobile,
    id: '1',
    title: title,
    body: body,
  );
  const court = 'Antalya 3. Asliye Ceza Mahkemesi';
  const body =
      'Antalya 3. Asliye Ceza Mahkemesi birimi, 2026/91 dosyasında , Sanık '
      'Deniz Yılmaz vekili olarak Vekil Kaydı yapıldı.';

  test('a Vekil Kaydı naming a case the portfolio lacks is a new case; one '
      'it holds, a Vekil Silinmesi or another kind is not', () {
    expect(uyapNoticeNamesNewCase(row('Vekil Kaydı', body), {}), isTrue);
    expect(
      uyapNoticeNamesNewCase(row('Vekil Kaydı', body), {
        caseKey('2026/91', court),
      }),
      isFalse,
    );
    expect(uyapNoticeNamesNewCase(row('Vekil Silinmesi', body), {}), isFalse);
    expect(
      uyapNoticeNamesNewCase(row('Bilirkişi Raporu Kaydedilmesi', body), {}),
      isFalse,
    );
    // A body that names no case for certain: nothing is guessed.
    expect(
      uyapNoticeNamesNewCase(row('Vekil Kaydı', 'Vekil kaydınız yapıldı.'), {}),
      isFalse,
    );
  });
}
