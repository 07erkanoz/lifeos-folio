import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/ui/widgets/edevlet_phone_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the phone page takes the code only from its own return', () {
    final back = Uri.parse(
      'https://mobilws.uyap.gov.tr/portaldmz/avukat.html?code=abc&state=s1',
    );
    String? code(Uri u, {String? state = 's1'}) => EdevletPhonePage.codeOf(
      u,
      isReturn: UyapMobileApi.isReturn,
      state: state,
    );
    expect(code(back), 'abc');
    expect(code(back, state: 'other'), isNull, reason: 'another login');
    expect(
      code(Uri.parse('https://giris.turkiye.gov.tr/?code=abc&state=s1')),
      isNull,
    );
    expect(
      code(
        Uri.parse('https://mobilws.uyap.gov.tr/portaldmz/avukat.html?state=s1'),
      ),
      isNull,
    );
  });
}
