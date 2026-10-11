import 'dart:io';

import 'package:evrak_convert/services/platform/data_reset.dart';
import 'package:evrak_convert/ui/settings/clear_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Tüm verileri temizle says what goes and what stays, clears '
      'only once ticked, and closes Folio', (tester) async {
    var cleared = 0, closed = 0;
    final root = Directory.systemTemp.createTempSync('folio-temizle-');
    addTearDown(() => root.deleteSync(recursive: true));
    DataReset.marker = () => File('${root.path}/isaret');
    DataReset.folders = () async {
      cleared++;
      return const [];
    };
    DataReset.keychain = () async {};
    closeFolio = () async => closed++;
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => clearAllData(context),
            child: const Text('temizle'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('temizle'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Müvekkiller'), findsOneWidget);
    expect(find.textContaining('silinmez'), findsOneWidget);
    // Not before it is ticked.
    final yes = find.byKey(const ValueKey('clear-all-yes'));
    expect(tester.widget<FilledButton>(yes).onPressed, isNull);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(cleared, 0);
    expect(closed, 0);

    await tester.tap(find.text('temizle'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-all-sure')));
    await tester.pump();
    await tester.tap(yes);
    for (var i = 0; i < 20 && closed == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(cleared, 1);
    expect(closed, 1);
  });
}
