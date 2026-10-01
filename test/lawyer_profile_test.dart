import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_path_provider.dart';

const _office = LawyerProfile(
  lawyers: [
    Lawyer(
      name: 'DENEME AVUKAT',
      bar: 'Antalya',
      barNumber: '1234',
      tbbNumber: '56789',
      idNumber: '11111111110',
    ),
    Lawyer(name: 'İKİNCİ AVUKAT', bar: 'İstanbul Barosu'),
  ],
  address: 'Deneme Mah. 1. Sk. No: 1 Muratpaşa/Antalya',
  phone: '0242 000 00 00',
  email: 'buro@example.com',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => LawyerProfile.use(null));

  test('the blanks a profile answers, and only those', () {
    final blanks = _office.blanks(today: DateTime(2026, 9, 26));
    expect(blanks['AVUKAT'], 'Av. DENEME AVUKAT');
    expect(blanks['VEKİLLER'], 'Av. DENEME AVUKAT - Av. İKİNCİ AVUKAT');
    // "Antalya" typed, "Antalya Barosu" meant.
    expect(blanks['BARO'], 'Antalya Barosu');
    expect(blanks['BARO SİCİL NO'], '1234');
    expect(blanks['TBB SİCİL NO'], '56789');
    // The lawyer's number, never a client's [TC].
    expect(blanks['AVUKAT TC'], '11111111110');
    expect(blanks.containsKey('TC'), isFalse);
    expect(blanks['BÜRO ADRESİ'], startsWith('Deneme Mah.'));
    expect(blanks['BÜRO TELEFONU'], '0242 000 00 00');
    expect(blanks['EPOSTA'], 'buro@example.com');
    expect(blanks['BUGÜN'], '26.09.2026');
    // Nothing typed, nothing claimed: the blank is asked instead.
    expect(blanks.containsKey('KEP'), isFalse);
    for (final name in blanks.keys) {
      expect(LawyerProfile.known, contains(name));
    }
  });

  test('the main lawyer is the one chosen, or the first named when the '
      'chosen one is blank', () {
    expect(
      const LawyerProfile(
        lawyers: [
          Lawyer(name: 'DENEME AVUKAT'),
          Lawyer(name: 'İKİNCİ AVUKAT', bar: 'İstanbul Barosu'),
        ],
        main: 1,
      ).blanks()['AVUKAT'],
      'Av. İKİNCİ AVUKAT',
    );
    expect(
      const LawyerProfile(
        lawyers: [
          Lawyer(),
          Lawyer(name: 'DENEME AVUKAT'),
        ],
      ).blanks()['AVUKAT'],
      'Av. DENEME AVUKAT',
    );
    expect(const LawyerProfile().blanks().keys, ['BUGÜN']);
    expect(const LawyerProfile().isEmpty, isTrue);
  });

  test('a profile is kept on this computer and read back whole', () async {
    useFakePathProvider();
    await _office.save();
    LawyerProfile.use(null);
    final read = await LawyerProfile.load();
    expect(read.toJson(), _office.toJson());
  });
}
