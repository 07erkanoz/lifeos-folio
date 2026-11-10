import 'dart:ui' as ui;

import 'package:evrak_convert/l10n/gen/app_localizations.dart';
import 'package:evrak_convert/ui/widgets/tiff_viewer_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A scan's pages listed as small pictures beside the one read: made by a
// decoder of their own, as each comes into view, and a press goes to the
// page pressed.
void main() {
  testWidgets('the small pages of a TIFF open beside it and lead to their '
      'page', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: const Scaffold(
          body: TiffViewerWidget(filePath: 'test/fixtures/ocr_cok_sayfali.tif'),
        ),
      ),
    );
    Future<void> until(bool Function() ready) async {
      for (var i = 0; i < 300 && !ready(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(ready(), isTrue);
    }

    final toggle = find.byKey(const ValueKey('tiff-thumbnails'));
    await until(() => toggle.evaluate().isNotEmpty);
    await until(() => find.textContaining('Sayfa 1 / ').evaluate().isNotEmpty);
    expect(find.byKey(const ValueKey('tiff-thumbnail-panel')), findsNothing);

    await tester.tap(toggle);
    await tester.pump();
    final panel = find.byKey(const ValueKey('tiff-thumbnail-panel'));
    expect(panel, findsOneWidget);
    // Each small page is drawn once it is decoded, and is small.
    Iterable<ui.Image?> drawn() => tester
        .widgetList<RawImage>(
          find.descendant(of: panel, matching: find.byType(RawImage)),
        )
        .map((w) => w.image);
    await until(() => drawn().length >= 2);
    for (final image in drawn()) {
      expect(image!.width, lessThanOrEqualTo(328));
      expect(image.height, lessThanOrEqualTo(328));
    }

    await tester.tap(find.byKey(const ValueKey('tiff-thumbnail-2')));
    await until(() => find.textContaining('Sayfa 2 / ').evaluate().isNotEmpty);

    await tester.tap(toggle);
    await tester.pump();
    expect(panel, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
