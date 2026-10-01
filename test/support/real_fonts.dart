import 'dart:io';

import 'package:flutter/services.dart';

/// Draws text in Liberation Sans and icons in Material's own font, rather
/// than in the test's Ahem, whose square letters are a fifth wider than any
/// real face: a width measured in Ahem says the toolbar does not fit when
/// it does.
Future<void> loadRealFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  for (final name in ['FlutterTest', 'Ahem', 'Roboto']) {
    await family(name, [
      for (final style in ['Regular', 'Bold'])
        'fonts/pdf/LiberationSans-$style.ttf',
    ]);
  }
  final flutter = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  await family('MaterialIcons', [
    '${flutter.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}
