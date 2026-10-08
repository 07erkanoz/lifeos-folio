// Ölçüm (paketin parçası değil): zarflarda ve mahkeme belgelerinde süre
// geçen cümlelerin kaçından talimat çıktığı, çıkmayanların ne olduğu.
// Gerçek veritabanının KOPYASINDA çalışır; sayı yazar, ÖRNEK dosyası
// verilirse kaçanların maskeli örneklerini oraya (yalnız bu bilgisayarda).
//
//   OLCUM_DB=/kopya/portal.sqlite [ORNEK=/yol/ornek.txt] \
//     flutter test tool/olcum/kacan_sure_olcumu_test.dart
import 'dart:io';

import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/uets/envelope_directives.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ölçüm', () {
    final path = Platform.environment['OLCUM_DB'];
    if (path == null) return markTestSkipped('OLCUM_DB yok');
    final db = PortalDatabase.open(path);
    final texts = <(String, String)>[
      for (final e in db.envelopes().values)
        if ((e.envelopeText ?? '').isNotEmpty) ('zarf', e.envelopeText!),
      for (final id in db.envelopes().keys)
        for (final d in db.noticeDocuments(id))
          if (d.hasText) ('belge', d.text),
    ];
    final loose = RegExp(
      r'(?<![\p{L}\d])(\d{1,3}|bir|iki|üç|dört|beş|altı|yedi|sekiz|dokuz|on|'
      r'onbeş|on beş|yirmi|otuz|altmış|doksan)\s*(\([^)]{1,15}\))?\s+'
      r'(iş\s+günü|gün|hafta|ay|yıl)',
      caseSensitive: false,
      unicode: true,
    );
    final kinds = <String, int>{};
    final samples = StringBuffer();
    var sentences = 0, caught = 0;
    for (final (source, text) in texts) {
      final flat = text.replaceAll(RegExp(r'\s+'), ' ');
      for (final s in flat.split(RegExp(r'(?<=[.!?;])\s+'))) {
        if (!loose.hasMatch(s)) continue;
        sentences++;
        if (envelopeDirectives(s).isNotEmpty) {
          caught++;
          continue;
        }
        final l = s.toLowerCase();
        final kind = RegExp(r'hapis|adli para|hürriyeti|cezası|ceza ile')
                .hasMatch(l)
            ? 'ceza miktarı'
            : RegExp(r'\d{1,2}[./]\d{1,2}[./]\d{4}').hasMatch(l) &&
                  !l.contains('itibaren')
            ? 'tarihli anlatım'
            : RegExp(r'önce|sonra|evvel').hasMatch(l)
            ? 'olaya göre (önce/sonra)'
            : RegExp(r'madde|kanun|k\.|hmk|iik|cmk|tbk|tmk').hasMatch(l)
            ? 'kanun anlatımı'
            : RegExp(r'faiz|kira|aylık|yıllık|maaş|ücret').hasMatch(l)
            ? 'para ve dönem'
            : 'diğer';
        kinds.update('$source · $kind', (v) => v + 1, ifAbsent: () => 1);
        if (kind == 'diğer' || kind == 'olaya göre (önce/sonra)') {
          final masked = s
              .replaceAll(RegExp(r'\b[A-ZÇĞİÖŞÜ]{2,}\b'), 'X')
              .replaceAll(RegExp(r'\d{4}/\d+'), 'N/N');
          samples.writeln(
            '[$source · $kind] ${masked.length > 260 ? masked.substring(0, 260) : masked}\n',
          );
        }
      }
    }
    stdout.writeln('süre geçen cümle $sentences, talimat çıkan $caught');
    for (final e in (kinds.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)))) {
      stdout.writeln('  ${e.key}: ${e.value}');
    }
    final out = Platform.environment['ORNEK'];
    if (out != null) File(out).writeAsStringSync(samples.toString());
    db.dispose();
  });
}
