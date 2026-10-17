import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:evrak_convert/services/udf/udf_reader.dart';
import 'package:evrak_convert/ui/widgets/signature_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A UDF of [content] with the fixtures' detached signature over theirs.
Uint8List _udf(List<int> content) {
  final signature = File('test/fixtures/signatures/rsa-valid.sgn')
      .readAsBytesSync();
  return Uint8List.fromList(
    ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile('content.xml', content.length, content))
        ..addFile(ArchiveFile('sign.sgn', signature.length, signature)),
    ),
  );
}

void main() {
  final content = File('test/fixtures/signatures/content.xml')
      .readAsBytesSync();

  test('a signature over the content as it came checks out; over changed '
      'content it does not', () async {
    final signed = UdfReader.readBytes(_udf(content))!;
    expect(await SignatureBanner.verified(signed), isTrue);
    final changed = UdfReader.readBytes(
      _udf([...content.sublist(0, content.length - 1), 0x20]),
    );
    // Changed past reading or not, never said to check out.
    if (changed != null) {
      expect(await SignatureBanner.verified(changed), isFalse);
    }
  });

  testWidgets('the banner says a signature checked out, and of one that did '
      'not says only, in its details, what that may mean', (tester) async {
    final signed = UdfReader.readBytes(_udf(content))!;
    await tester.runAsync(() => SignatureBanner.verified(signed)!);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SignatureBanner(model: signed)),
      ),
    );
    await tester.pump();
    expect(find.textContaining('İmza doğrulandı'), findsOneWidget);

    final other = UdfReader.readBytes(_udf(content))!;
    other.metadata['signedContentBytes'] = [...content, 0x20];
    await tester.runAsync(() => SignatureBanner.verified(other)!);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SignatureBanner(model: other)),
      ),
    );
    await tester.pump();
    expect(find.textContaining('İmza doğrulandı'), findsNothing);
    expect(find.text('E-İMZALI'), findsOneWidget);
    await tester.tap(find.text('Ayrıntılar'));
    await tester.pumpAndSettle();
    expect(find.text(SignatureBanner.notVerifiedNote), findsOneWidget);
  });
}
