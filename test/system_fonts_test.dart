import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/fonts/document_fonts.dart';
import 'package:evrak_convert/services/fonts/system_font_catalog.dart';
import 'package:evrak_convert/services/pdf/pdf_service.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMessageHandler('flutter/assets', null));

  test('font catalog reads all bundled family and style names', () {
    for (final family in ['Serif', 'Sans', 'Mono']) {
      for (final style in DocumentFonts.faces) {
        expect(readFontName(File('fonts/pdf/Liberation$family-$style.ttf')), (
          'Liberation $family',
          style,
        ));
      }
    }
  });

  test(
    'installed font bytes are used exactly in preference to bundled substitute',
    () async {
      final catalog = await SystemFontCatalog.load();
      if (catalog.isEmpty) return;
      final family = catalog.entries.firstWhere(
        (entry) => entry.value.containsKey('Regular'),
      );
      final actual = await DocumentFonts.loadFace(family.key, 'Regular');
      expect(
        actual.buffer.asUint8List(actual.offsetInBytes, actual.lengthInBytes),
        await File(family.value['Regular']!).readAsBytes(),
      );
    },
  );

  test('missing asset falls back to installed Turkish font and still generates PDF', () async {
    if (!Platform.isLinux && !Platform.isWindows) return;
    var missingAssets = 0;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(
        message!.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        ),
      );
      if (key.startsWith('fonts/pdf/')) missingAssets++;
      return null;
    });
    final data = await DocumentFonts.loadFace(
      'Missing asset test serif',
      'Regular',
    );
    expect(data.lengthInBytes, greaterThan(1000));
    expect(missingAssets, greaterThan(0));
    final bytes = await PdfService.modelToPdfBytes(
      DocModel(
        blocks: [
          DocBlock(
            plainText: 'Türkçe: İı Şş Ğğ Çç Öö Üü',
            spans: [
              DocSpan(
                startOffset: 0,
                length: 'Türkçe: İı Şş Ğğ Çç Öö Üü'.length,
                fontFamily: 'Missing asset test serif',
              ),
            ],
          ),
        ],
      ),
    );
    expect(ascii.decode(bytes.sublist(0, 4)), '%PDF');
  });

  test(
    'failed font load is evicted so a later successful load can recover',
    () async {
      var attempts = 0;
      final bytes = await File('fonts/pdf/LiberationSerif-Regular.ttf')
          .readAsBytes();
      messenger.setMockMessageHandler('flutter/assets', (_) async {
        attempts++;
        return attempts == 1 ? null : ByteData.sublistView(bytes);
      });
      await expectLater(
        DocumentFonts.loadFace('Recovery test family', 'TestStyle'),
        throwsA(anything),
      );
      final recovered = await DocumentFonts.loadFace(
        'Recovery test family',
        'TestStyle',
      );
      expect(recovered.lengthInBytes, bytes.length);
      expect(attempts, 2);
    },
  );
}
