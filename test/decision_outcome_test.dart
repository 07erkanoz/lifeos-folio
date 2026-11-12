import 'package:evrak_convert/services/ai/folio_mcp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('by majority, with the dissent after it saying "oybirliği"', () {
    final got = FolioMcp.outcomeOf(
      'GEREKÇE ... HMK 440/III-3 maddesine göre karar düzeltme yolu kapalı '
      'olmak üzere 07.02.2019 tarihinde oy çokluğuyla kesin olarak karar '
      'verildi. KARŞI OY 6502 sayılı Kanun ... Dairenin oybirliği ile verdiği '
      'karar ...',
    );
    expect(got['oy'], 'oy çokluğu');
    expect(got['karsi_oy'], isTrue);
    expect(got['hukum_cumlesi'], contains('oy çokluğuyla'));
  });

  test('unanimous, and nothing said', () {
    expect(
      FolioMcp.outcomeOf(
        '… tebliğine, 23/03/2021 tarihinde oybirliğiyle karar verildi.',
      )['oy'],
      'oybirliği',
    );
    expect(FolioMcp.outcomeOf('Gerekçe metni.')['oy'], 'metinde yazmıyor');
  });
}
