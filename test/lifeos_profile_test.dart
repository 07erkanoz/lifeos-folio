import 'dart:io';

import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/platform/lifeos_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the file is in LifeOS settings folder, as the installer writes it', () {
    expect(
      LifeosProfile.file({'HOME': '/home/deniz'})!.path,
      '/home/deniz/.config/lifeos/folio-profil.json',
    );
    expect(
      LifeosProfile.file({'HOME': '/home/deniz', 'XDG_CONFIG_HOME': '/ayar'})!
          .path,
      '/ayar/lifeos/folio-profil.json',
    );
    // A relative XDG_CONFIG_HOME does not count.
    expect(
      LifeosProfile.file({'HOME': '/home/deniz', 'XDG_CONFIG_HOME': 'ayar'})!
          .path,
      '/home/deniz/.config/lifeos/folio-profil.json',
    );
    expect(LifeosProfile.file({}), isNull);
  });

  test('every key the installer writes lands where Folio keeps it', () {
    final profile = LifeosProfile.parse('''{
      "kaynak": "kurulum",
      "ad": " Deniz Yılmaz ",
      "baro": "Antalya",
      "sicil": "1234",
      "tbb": "56789",
      "buro": "Yılmaz Hukuk Bürosu",
      "tel": "0242 000 00 00",
      "eposta": "deniz@example.com",
      "kep": "deniz.yilmaz@hs01.kep.tr",
      "adres": "Deneme Mah. 1. Sk. No: 1 Muratpaşa/Antalya"
    }''')!;
    final lawyer = profile.lawyer!;
    expect(lawyer.name, 'Deniz Yılmaz');
    expect(lawyer.barName, 'Antalya Barosu');
    expect(lawyer.barNumber, '1234');
    expect(lawyer.tbbNumber, '56789');
    expect(lawyer.idNumber, '');
    expect(profile.officeName, 'Yılmaz Hukuk Bürosu');
    expect(profile.phone, '0242 000 00 00');
    expect(profile.email, 'deniz@example.com');
    expect(profile.kep, 'deniz.yilmaz@hs01.kep.tr');
    expect(profile.address, 'Deneme Mah. 1. Sk. No: 1 Muratpaşa/Antalya');
  });

  test('a broken or empty file is no profile', () {
    expect(LifeosProfile.parse('{bozuk'), isNull);
    expect(LifeosProfile.parse('[]'), isNull);
    expect(LifeosProfile.parse('{"kaynak": "karsilama"}'), isNull);
    expect(LifeosProfile.parse('{"ad": 5, "baro": null}'), isNull);
    // Only the office is still something to offer.
    expect(
      LifeosProfile.parse('{"buro": "Kaya Hukuk"}')!.officeName,
      'Kaya Hukuk',
    );
  });

  test('read: a missing or broken file is quietly nothing', () async {
    final dir = await Directory.systemTemp.createTemp('folio-lifeos-profile-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/folio-profil.json');
    expect(await LifeosProfile.read(file), isNull);
    await file.writeAsString('{"ad": "Deniz');
    expect(await LifeosProfile.read(file), isNull);
    await file.writeAsString('{"ad": "Deniz Yılmaz", "baro": "İzmir"}');
    expect((await LifeosProfile.read(file))!.lawyer!.barName, 'İzmir Barosu');
  });

  test('Folio\'s own lawyer wins; its other details are not overwritten', () {
    const lifeos = LawyerProfile(
      lawyers: [Lawyer(name: 'Deniz Yılmaz')],
      phone: '0242 000 00 00',
      kep: 'deniz@hs01.kep.tr',
    );
    const kept = LawyerProfile(lawyers: [Lawyer(name: 'Ece Kaya')]);
    expect(identical(LifeosProfile.fill(kept, lifeos), kept), isTrue);
    final filled = LifeosProfile.fill(
      const LawyerProfile(phone: '0532 111 11 11'),
      lifeos,
    );
    expect(filled.lawyer!.name, 'Deniz Yılmaz');
    expect(filled.phone, '0532 111 11 11');
    expect(filled.kep, 'deniz@hs01.kep.tr');
  });

  group('at every start', () {
    const lifeos = LawyerProfile(
      lawyers: [Lawyer(name: 'Deniz Yılmaz', bar: 'Antalya')],
      kep: 'deniz@hs01.kep.tr',
    );
    late LawyerProfile kept;
    late List<LawyerProfile> saved;
    late bool taken;
    Future<bool> start({LawyerProfile? given, bool asGiven = true}) =>
        LifeosProfile.fillAtStart(
          load: () async => kept,
          save: (p) async => saved.add(p),
          lifeos: () async => asGiven ? given ?? lifeos : null,
          taken: () async => taken,
          markTaken: () async => taken = true,
        );
    setUp(() {
      kept = const LawyerProfile(phone: '0532 111 11 11');
      saved = [];
      taken = false;
    });

    test('no lawyer and LifeOS\'s file: filled, kept, told once', () async {
      expect(await start(), isTrue);
      final one = saved.single;
      expect(one.lawyer!.name, 'Deniz Yılmaz');
      expect(one.kep, 'deniz@hs01.kep.tr');
      expect(one.phone, '0532 111 11 11');
      expect(taken, isTrue);
      // The next start: offered already, nothing again.
      kept = const LawyerProfile();
      expect(await start(), isFalse);
      expect(saved, hasLength(1));
    });

    test('a lawyer of Folio\'s own: nothing changes', () async {
      kept = const LawyerProfile(lawyers: [Lawyer(name: 'Ece Kaya')]);
      expect(await start(), isFalse);
      expect(saved, isEmpty);
      expect(taken, isFalse);
    });

    test('no file, or a broken one: as before, nothing kept', () async {
      expect(await start(asGiven: false), isFalse);
      expect(saved, isEmpty);
      expect(taken, isFalse);
      final dir = await Directory.systemTemp.createTemp('folio-lifeos-start-');
      addTearDown(() => dir.delete(recursive: true));
      final broken = File('${dir.path}/folio-profil.json');
      await broken.writeAsString('{"ad": "Deniz');
      expect(
        await LifeosProfile.fillAtStart(
          load: () async => kept,
          save: (p) async => saved.add(p),
          lifeos: () => LifeosProfile.read(broken),
          taken: () async => false,
          markTaken: () async => taken = true,
        ),
        isFalse,
      );
      expect(saved, isEmpty);
    });

    test('a file with no lawyer in it fills nothing', () async {
      expect(
        await start(given: const LawyerProfile(officeName: 'Kaya Hukuk')),
        isFalse,
      );
      expect(saved, isEmpty);
    });

    test('the step at the first start was passed: not offered again', () async {
      taken = true;
      kept = const LawyerProfile();
      expect(await start(), isFalse);
      expect(saved, isEmpty);
    });
  });
}
