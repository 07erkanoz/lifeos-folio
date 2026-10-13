import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/portfolio/portfolio_rows.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a court of first instance and an enforcement office need no word; '
      'the higher courts and an investigation say where they stand', () {
    expect(courtLevel('Manavgat İcra Dairesi'), isNull);
    expect(courtLevel('Antalya 3. Asliye Hukuk Mahkemesi'), isNull);
    expect(
      courtLevel('Antalya Bölge Adliye Mahkemesi 4. Hukuk Dairesi'),
      'İstinaf',
    );
    expect(courtLevel('Yargıtay 9. Hukuk Dairesi'), 'Yargıtay');
    expect(courtLevel('Danıştay 10. Daire'), 'Danıştay');
    expect(courtLevel('Manavgat Cumhuriyet Başsavcılığı'), 'Soruşturma');
  });

  test('the high courts sit in no courthouse', () {
    expect(courthouseOf('Yargıtay 9. Hukuk Dairesi'), 'Yargıtay');
    expect(courthouseOf('Danıştay 10. Daire'), 'Danıştay');
    expect(
      courthouseOf('Antalya Bölge Adliye Mahkemesi 4. Hukuk Dairesi'),
      'Antalya Bölge Adliye Mahkemesi',
    );
    expect(courthouseOf('Manavgat İcra Dairesi'), 'Manavgat Adliyesi');
    expect(
      courthouseOf('İstanbul Anadolu 5. Asliye Ticaret Mahkemesi'),
      'İstanbul Anadolu Adliyesi',
    );
    expect(courthouseOf(''), 'Diğer');
  });

  group('our side of an enforcement file', () {
    const creditor = UyapParty('ACME A.Ş.', 'Alacaklı', 'DENİZ KAYA', 'Kurum');
    // The debtor's counsel shares the lawyer's surname.
    const debtor = UyapParty('AHMET YILMAZ', 'Borçlu', 'MERVE KAYA', 'Kişi');

    test('is the party whose counsel is the lawyer in full, not one whose '
        'counsel only shares the surname', () {
      final (ours, others) = splitParties([debtor, creditor], 'Av. Deniz Kaya');
      expect(ours, [creditor]);
      expect(others, [debtor]);
    });

    test('a surname alone found on both sides decides nothing', () {
      final (ours, _) = splitParties([debtor, creditor], 'Av. Ali Kaya');
      expect(ours, isEmpty);
    });

    test('what the lawyer said they act for comes before UYAP', () {
      final (ours, _) = splitParties(
        [debtor, creditor],
        'Av. Deniz Kaya',
        said: const [(ad: 'Ahmet Yılmaz', rol: 'Borçlu')],
      );
      expect(ours, [debtor]);
    });
  });
}
