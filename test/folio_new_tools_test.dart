import 'package:evrak_convert/services/ai/ai_events.dart';
import 'package:evrak_convert/services/ai/ai_prompts.dart';
import 'package:evrak_convert/services/ai/folio_mcp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a document search drops the years a model adds', () {
    expect(
      FolioMcp.bareDocumentQuery('Avukatlık Asgari Ücret Tarifesi 2025-2026'),
      'Avukatlık Asgari Ücret Tarifesi',
    );
    expect(
      FolioMcp.bareDocumentQuery('2026 YILI güncel harç tarifesi'),
      'harç tarifesi',
    );
  });

  test('the program is told of the new tools', () {
    for (final n in [
      'mevzuat_toplu',
      'mevzuat_belge_ara',
      'mevzuat_belge_getir',
      'sure_hesapla',
    ]) {
      expect(FolioMcp.names, contains(n));
      expect(FolioMcp.instructions, contains(n));
    }
    expect(AiPrompts.core, contains('sure_hesapla'));
    expect(AiPrompts.core, contains('mevzuat_belge_ara'));
  });

  group('sure_hesapla', () {
    final now = DateTime(2026, 11, 12);
    test('İİK m.62: seven days from the service', () {
      final got = FolioMcp.deadline({
        'baslangic': '2026-11-02',
        'miktar': 7,
        'birim': 'gun',
        'yargi': 'icra',
        'madde': 'İİK m.62',
      }, now: now);
      expect(got['durum'], 'hesaplandi');
      expect(got['son_gun'], '2026-11-09');
    });

    test('a last day on a Sunday goes to Monday', () {
      // 2026-11-01 + 7 = Sunday 2026-11-08.
      final got = FolioMcp.deadline({
        'baslangic': '2026-11-01',
        'miktar': 7,
        'birim': 'gun',
        'yargi': 'hukuk',
        'madde': 'HMK m.345',
      }, now: now);
      expect(got['son_gun'], '2026-11-09');
      expect(got['takvimdeki_son_gun'], '2026-11-08');
    });

    test('two weeks into the recess are extended for a case subject to it', () {
      final got = FolioMcp.deadline({
        'baslangic': '2026-07-10',
        'miktar': 2,
        'birim': 'hafta',
        'yargi': 'hukuk',
        'madde': 'HMK m.345',
        'adli_tatile_tabi': true,
      }, now: now);
      // HMK m.104: the week counted from 1 September (Yargıtay HGK
      // 2017/20-2873 E., 2017/1449 K.): 8 September.
      expect(got['son_gun'], '2026-09-08');
    });

    test('nothing reckoned without its article', () {
      final got = FolioMcp.deadline({
        'baslangic': '2026-11-02',
        'miktar': 7,
        'birim': 'gun',
        'yargi': 'icra',
      });
      expect(got['durum'], 'yok');
    });
  });

  test('steps read as the lawyer sees them', () {
    expect(
      const AiStep(
        '1',
        'mevzuat_toplu',
        args: {
          'maddeler': [
            {'kanun': 'TBK', 'madde': '344'},
            {'kanun': 'İİK', 'madde': '62'},
          ],
        },
      ).label,
      'Kanun maddeleri okunuyor · TBK m.344, İİK m.62',
    );
    expect(const AiStep('1', 'mevzuat_belge_getir').kind, 'mevzuat');
  });
}
