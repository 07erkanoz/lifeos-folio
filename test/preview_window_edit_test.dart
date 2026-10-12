import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/preview_app.dart';

void main() {
  testWidgets('a document opened from the file manager can be taken to '
      'editing from its preview window; a picture cannot', (tester) async {
    final dir = Directory.systemTemp.createTempSync('folio-preview-edit-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final text = File('${dir.path}/not.txt')..writeAsStringSync('Not');
    await tester.pumpWidget(PreviewApp(path: text.path));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('preview-window-edit')),
      Platform.isLinux || Platform.isWindows || Platform.isMacOS
          ? findsOneWidget
          : findsNothing,
    );

    final picture = File('${dir.path}/resim.png')..writeAsBytesSync([0]);
    // A window of its own each: not the text's window changed.
    await tester.pumpWidget(PreviewApp(key: UniqueKey(), path: picture.path));
    await tester.pump();
    expect(find.byKey(const ValueKey('preview-window-edit')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
