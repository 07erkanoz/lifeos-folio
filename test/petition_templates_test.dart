import 'package:evrak_convert/services/editor/petition_templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 10, 7);
  String text(String name, [PetitionCase? from]) => petitionTemplates
      .firstWhere((t) => t.name == name)
      .build(from, today)
      .toPlainText();

  test('every template builds, empty or from a case', () {
    const civil = PetitionCase(
      court: 'Antalya 3. Asliye Hukuk Mahkemesi',
      number: '2024/318',
      lawyer: 'Av. Deniz Kaya',
      parties: [('Davacı', 'Ayşe K.'), ('Davalı', 'B. İnşaat Ltd.')],
    );
    for (final t in petitionTemplates) {
      expect(t.build(null, today).blocks, isNotEmpty, reason: t.name);
      expect(t.build(civil, today).blocks, isNotEmpty, reason: t.name);
    }
    final answer = text('Cevap dilekçesi', civil);
    expect(answer, startsWith('ANTALYA 3. ASLİYE HUKUK MAHKEMESİ’NE'));
    expect(answer, contains('DOSYA NO\t: 2024/318 Esas'));
    expect(answer, contains('CEVAP VEREN\t: B. İnşaat Ltd. (Davalı)'));
    expect(answer, contains('Av. Deniz Kaya'));
  });

  test('civil and criminal appeals go to their own chambers', () {
    expect(
      text('İstinaf dilekçesi (Hukuk)'),
      contains('İLGİLİ HUKUK DAİRESİ’NE'),
    );
    final criminal = text(
      'İstinaf dilekçesi (Ceza)',
      const PetitionCase(
        court: 'Manavgat 1. Ağır Ceza Mahkemesi',
        number: '2026/295',
        parties: [('Sanık', 'K.H.')],
      ),
    );
    expect(criminal, contains('İLGİLİ CEZA DAİRESİ’NE'));
    expect(criminal, contains('MANAVGAT 1. AĞIR CEZA MAHKEMESİ’NE'));
    expect(criminal, contains('CMK m.272'));
    expect(criminal, contains('Sanık Müdafii'));
  });

  test('an objection to a payment order goes to the enforcement office', () {
    expect(
      text('Ödeme emrine itiraz'),
      startsWith('[…] İCRA DAİRESİ MÜDÜRLÜĞÜ’NE'),
    );
    expect(
      text(
        'Ödeme emrine itiraz',
        const PetitionCase(court: 'Antalya 5. İcra Dairesi', number: '2026/41'),
      ),
      startsWith('ANTALYA 5. İCRA DAİRESİ MÜDÜRLÜĞÜ’NE'),
    );
  });

  test('a hearing petition names the hearing, and a criminal one the '
      'defence', () {
    final excuse = text(
      'Mazeret dilekçesi (mesleki)',
      PetitionCase(
        court: 'Manavgat 1. Ağır Ceza Mahkemesi',
        number: '2026/295',
        hearing: DateTime(2026, 10, 9, 10, 15),
      ),
    );
    expect(excuse, contains('09.10.2026 günü saat 10:15'));
    expect(excuse, contains('Sanık Müdafii'));
    expect(text('E-duruşma talebi'), contains('HMK m.149'));
  });
}
