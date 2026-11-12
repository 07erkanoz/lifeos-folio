import 'package:evrak_convert/services/ai/folio_mcp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a court written as a lawyer writes it, against the bank\'s name', () {
    expect(
      FolioMcp.courtMatches('Yargıtay 3. HD', 'Yargıtay Hukuk Genel Kurulu'),
      isFalse,
    );
    expect(
      FolioMcp.courtMatches('Yargıtay HGK', 'Yargıtay Hukuk Genel Kurulu'),
      isTrue,
    );
    expect(
      FolioMcp.courtMatches('Danıştay 13. D.', 'Danıştay 13. Daire'),
      isTrue,
    );
    expect(
      FolioMcp.courtMatches('Danıştay 4. D.', 'Danıştay 13. Daire'),
      isFalse,
    );
    expect(
      FolioMcp.courtMatches(
        'İstanbul BAM 54. HD',
        'İstanbul Bölge Adliye Mahkemesi 54. Hukuk Dairesi',
      ),
      isTrue,
    );
    expect(
      FolioMcp.courtMatches('Yargıtay 9. CD', 'Yargıtay 9. Hukuk Dairesi'),
      isFalse,
    );
  });
}
