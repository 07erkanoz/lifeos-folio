import 'dart:io';

import 'package:evrak_convert/ui/widgets/share_as.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A UDF asks how it goes: as it is, or as a PDF; a PDF goes as it is and
// a TIFF as a PDF, neither asking.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('folio_share_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester, String path) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => shareAs(context, path),
            child: const Text('paylaş'),
          ),
        ),
      ),
    ),
  );

  testWidgets('a UDF is offered as itself or as a PDF', (tester) async {
    final udf = File('${dir.path}/Ara Karar.udf')..writeAsBytesSync([0]);
    await pump(tester, udf.path);
    await tester.tap(find.text('paylaş'));
    await tester.pumpAndSettle();
    expect(find.text('UDF olarak paylaş'), findsOneWidget);
    expect(find.text('PDF olarak paylaş'), findsOneWidget);
    // As it is: on a computer, Folio's own dialog for the file itself.
    await tester.tap(find.byKey(const ValueKey('share-original')));
    await tester.pumpAndSettle();
    expect(find.text('Ara Karar.udf'), findsOneWidget);
  });

  testWidgets('a PDF is shared without asking', (tester) async {
    final pdf = File('${dir.path}/Karar.pdf')..writeAsBytesSync([0]);
    await pump(tester, pdf.path);
    await tester.tap(find.text('paylaş'));
    await tester.pumpAndSettle();
    expect(find.text('PDF olarak paylaş'), findsNothing);
    expect(find.text('Karar.pdf'), findsOneWidget);
  });
}
