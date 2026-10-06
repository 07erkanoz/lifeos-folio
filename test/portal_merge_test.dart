import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_case.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const web = PortalChannel.uyapWeb;
  const mobile = PortalChannel.uyapMobile;
  final monday = DateTime.utc(2026, 10, 5, 9);
  final tuesday = DateTime.utc(2026, 10, 6, 9);

  group('a field', () {
    test('an empty answer keeps what there is', () {
      final had = Observed(['Ayşe K.', 'B. Ltd.'], web, monday);
      expect(mergeObserved(had, Observed(<String>[], mobile, tuesday)), had);
      expect(mergeObserved(had, Observed<List<String>>([], web, tuesday)), had);
      expect(mergeObserved(had, null), had);
    });

    test('an empty field takes the mobile API’s shorter answer', () {
      final short = Observed(['Ayşe K.'], mobile, monday, complete: false);
      expect(mergeObserved(null, short), short);
    });

    test(
      'the mobile API’s newer but partial answer does not cut the web’s',
      () {
        final full = Observed(['Ayşe K.', 'B. Ltd.', 'C. Vekil'], web, monday);
        final short = Observed(['Ayşe K.'], mobile, tuesday, complete: false);
        expect(mergeObserved(full, short), full);
        // And the web's complete answer replaces an older partial one.
        expect(mergeObserved(short, full), full);
      },
    );

    test(
      'among complete answers the newer wins; a tie keeps what there is',
      () {
        final old = Observed('açık', web, monday);
        final now = Observed('kapalı', mobile, tuesday);
        expect(mergeObserved(old, now), now);
        expect(mergeObserved(now, old), now);
        expect(mergeObserved(old, Observed('kapalı', mobile, monday)), old);
      },
    );
  });

  group('a case', () {
    test('the two portals meet on the folded number and court', () {
      expect(
        caseKey('2025/412', 'Antalya 3. Asliye Hukuk Mahkemesi'),
        caseKey('2025 / 412', 'ANTALYA 3. ASLİYE HUKUK MAHKEMESİ'),
      );
      expect(
        caseKey('2026/77 - 2', 'Antalya 6. İcra Dairesi'),
        caseKey('2026/77', 'Antalya 6. İcra Dairesi'),
      );
      expect(
        caseKey('2025/412', 'Antalya 3. Asliye Hukuk Mahkemesi'),
        isNot(caseKey('2025/412', 'Antalya 4. Asliye Hukuk Mahkemesi')),
      );
    });

    test('the web and the mobile fill each other’s gaps', () {
      final fromWeb = PortalCase(
        key: caseKey('2025/412', 'Antalya 3. Asliye Hukuk Mahkemesi'),
        number: '2025/412',
        court: 'Antalya 3. Asliye Hukuk Mahkemesi',
        ids: const {web: '991'},
        parties: Observed(
          [
            {'ad': 'Ayşe K.', 'rol': 'Davacı'},
            {'ad': 'B. Ltd.', 'rol': 'Davalı'},
          ],
          web,
          monday,
        ),
        details: Observed({'tur': 'Alacak'}, web, monday),
      );
      final fromMobile = PortalCase(
        key: fromWeb.key,
        number: '2025/412',
        court: 'ANTALYA 3. ASLİYE HUKUK MAHKEMESİ',
        ids: const {mobile: 'x7'},
        status: Observed('açık', mobile, tuesday),
        parties: Observed(
          [
            {'ad': 'Ayşe K.'},
          ],
          mobile,
          tuesday,
          complete: false,
        ),
        documents: Observed(
          [
            {'no': '41', 'ad': 'Bilirkişi raporu'},
          ],
          mobile,
          tuesday,
          complete: false,
        ),
      );
      for (final merged in [
        fromWeb.merge(fromMobile),
        fromMobile.merge(fromWeb),
      ]) {
        expect(merged.parties!.value, hasLength(2));
        expect(merged.parties!.source, web);
        expect(merged.details!.value['tur'], 'Alacak');
        expect(merged.status!.value, 'açık');
        expect(merged.documents!.source, mobile);
        expect(merged.ids, {web: '991', mobile: 'x7'});
      }
    });

    test('a case one answer leaves out stays in the portfolio', () {
      final a = PortalCase.create(number: '2025/1', court: 'Kepez 1. Sulh');
      final b = PortalCase.create(number: '2025/2', court: 'Kepez 1. Sulh');
      final portfolio = mergePortfolio({a.key: a, b.key: b}, [a]);
      expect(portfolio.keys, containsAll([a.key, b.key]));
    });
  });
}
