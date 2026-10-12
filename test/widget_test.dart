import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:evrak_convert/main.dart';

void main() {
  testWidgets('EvrakConvertApp baslangic duman testi', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const EvrakConvertApp());
    await tester.pump();
    expect(find.text('EVRAK KÜTÜPHANENİZ'), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Dosya Aç'), findsOneWidget);
    // A folder is added from the square beside it, named by its tooltip.
    expect(find.byTooltip('Klasör Ekle'), findsWidgets);
  });
}
