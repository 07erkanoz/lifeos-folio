import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/ui/mobile/lawyer_profile_page.dart';
import 'package:evrak_convert/ui/mobile/mobile_settings_page.dart';
import 'package:evrak_convert/ui/mobile/profile_from_uyap.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UYAP Mobil fills the default lawyer and what the office lacks', () {
    final session = MobileSession(
      user: 'DENİZ YILMAZ',
      since: DateTime(2026),
      expires: DateTime(2026, 2),
      bar: 'ANTALYA BAROSU',
      barNumber: '2758',
      tbbNumber: '51234',
      tckn: '10000000146',
      phones: const ['0532 000 00 00'],
      emails: const ['deniz@ornek.av.tr'],
    );
    final filled = fillFromSession(
      const LawyerProfile(address: 'Muratpaşa', kep: 'k@kep.tr'),
      session,
    );
    final l = filled.lawyer!;
    expect(l.titled, 'Av. Deniz Yılmaz');
    expect(l.barName, 'Antalya Barosu');
    expect(l.barNumber, '2758');
    expect(l.tbbNumber, '51234');
    expect(l.idNumber, '10000000146');
    expect(filled.phone, '0532 000 00 00');
    expect(filled.email, 'deniz@ornek.av.tr');
    expect(filled.address, 'Muratpaşa');
  });

  for (final size in const [Size(360, 760), Size(390, 844)]) {
    testWidgets('settings and the profile fit a ${size.width} px phone', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      LawyerProfile.use(
        const LawyerProfile(
          lawyers: [
            Lawyer(name: 'Deniz Yılmaz', bar: 'Antalya', barNumber: '2758'),
          ],
        ),
      );
      addTearDown(() => LawyerProfile.use(null));
      final library = LibraryController(watchFolders: false);
      addTearDown(library.dispose);
      final appearance = ThemeController();
      addTearDown(appearance.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MobileSettingsPage(library: library, appearance: appearance),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('BAĞLANTILAR'), findsOne);
      expect(find.text('UYAP Mobil'), findsOne);
      await tester.pumpWidget(const MaterialApp(home: LawyerProfilePage()));
      await tester.pumpAndSettle();
      expect(find.text('UYAP Mobil’den güncelle'), findsOne);
      expect(find.text('VARSAYILAN'), findsOne);
      expect(find.text('Deniz Yılmaz'), findsOne);
      await tester.tap(find.byKey(const ValueKey('profile-add-lawyer')));
      await tester.pumpAndSettle();
      expect(find.text('Varsayılan yap'), findsOne);
    });
  }
}
