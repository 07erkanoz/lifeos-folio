import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/editor/profile_autofill.dart';
import 'package:flutter_test/flutter_test.dart';

// What a portal tells of the lawyer fills the profile's blanks; what the
// lawyer typed stays.
void main() {
  test('an empty profile is filled from UYAP', () {
    final p = fillProfileBlanks(
      const LawyerProfile(),
      name: 'DENİZ KAYA',
      bar: 'ANTALYA BAROSU',
      barNumber: '1234',
      tckn: '12345678901',
      phone: '05321234567',
      email: 'deniz@ornek.com',
    );
    expect(p.lawyer!.name, 'Deniz Kaya');
    expect(p.lawyer!.bar, 'Antalya Barosu');
    expect(p.lawyer!.barNumber, '1234');
    expect(p.lawyer!.idNumber, '12345678901');
    expect(p.phone, '05321234567');
    expect(p.email, 'deniz@ornek.com');
  });

  test('what was typed is never written over; only blanks are filled', () {
    const typed = LawyerProfile(
      lawyers: [Lawyer(name: 'Av. Deniz Kaya Yılmaz', barNumber: '99')],
      phone: '05550000000',
    );
    final p = fillProfileBlanks(
      typed,
      name: 'DENİZ KAYA',
      barNumber: '1234',
      tckn: '12345678901',
      phone: '05321234567',
    );
    expect(p.lawyer!.name, 'Av. Deniz Kaya Yılmaz');
    expect(p.lawyer!.barNumber, '99');
    expect(p.lawyer!.idNumber, '12345678901');
    expect(p.phone, '05550000000');
  });

  test('a number that is not a TC number is not kept as one', () {
    final p = fillProfileBlanks(
      const LawyerProfile(lawyers: [Lawyer(name: 'Deniz Kaya')]),
      tckn: '123',
    );
    expect(p.lawyer!.idNumber, isEmpty);
  });
}
