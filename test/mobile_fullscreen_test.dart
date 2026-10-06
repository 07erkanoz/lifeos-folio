import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/main.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/search/library_controller.dart';
import 'package:evrak_convert/services/udf/udf_writer.dart';
import 'package:evrak_convert/ui/theme/theme_controller.dart';

void main() {
  testWidgets('a phone can read a document with nothing else on screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('folio-fullscreen-'),
    ))!;
    final file = File('${dir.path}/tutanak.udf');
    await tester.runAsync(
      () => file.writeAsBytes(
        UdfWriter.writeBytes(
          DocModel(blocks: [DocBlock(plainText: 'Duruşma tutanağı')]),
        ),
      ),
    );
    final library = LibraryController(
      databasePath: ':memory:',
      watchFolders: false,
    );
    final appearance = ThemeController(settingsPath: '${dir.path}/theme.json');
    await tester.runAsync(library.initialize);

    await tester.pumpWidget(
      EvrakConvertApp(
        library: library,
        appearance: appearance,
        initialPaths: [file.path],
      ),
    );
    for (
      var i = 0;
      i < 100 &&
          find.byKey(const ValueKey('preview-header')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final header = find.byKey(const ValueKey('preview-header'));
    expect(header, findsOneWidget);

    // How much of the phone the document gets before and after.
    final chrome = tester.getSize(header).height;
    expect(chrome, greaterThan(0));

    expect(find.byTooltip('Tam ekran'), findsOneWidget);
    await tester.tap(find.byTooltip('Tam ekran'));
    await tester.pump();

    // The header and the action row step aside; the way back stays.
    expect(header, findsNothing);
    expect(find.byTooltip('Paylaş'), findsNothing);
    expect(
      find.byKey(const ValueKey('preview-exit-fullscreen')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('preview-exit-fullscreen')));
    await tester.pump();
    expect(header, findsOneWidget);
    expect(find.byTooltip('Paylaş'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      library.dispose();
      appearance.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
