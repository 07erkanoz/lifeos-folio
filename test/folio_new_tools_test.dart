import 'package:evrak_convert/services/ai/ai_events.dart';
import 'package:evrak_convert/services/ai/ai_prompts.dart';
import 'package:evrak_convert/services/ai/folio_mcp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ceza_hesapla', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    test('the summary gives the law that favours the accused', () async {
      final r = await FolioMcp().call('ceza_hesapla', {
        'suc': 'TCK 86/1',
        'olay_tarihi': '2025-03-10',
        'fail_yas_grubu': 'yetiskin',
      });
      final sum = '${r['sonuc']}';
      expect(sum, contains('Kanundaki aralık: 1 yıl – 3 yıl'));
      expect(sum, contains('olay tarihindeki metin'));
      expect(sum, contains('HAGB (CMK 231/5, kurulan hüküm ≤ 2 yıl): mümkün'));
      expect(sum, contains('10.03.2033'));
    });

    test('a minor\'s sentence after the reduction', () async {
      final r = await FolioMcp().call('ceza_hesapla', {
        'suc': 'TCK 142/1-b',
        'olay_tarihi': '2024-01-05',
        'fail_yas_grubu': '15-18',
      });
      expect('${r['sonuc']}', contains('en az 3 yıl 4 ay, en çok 6 yıl 8 ay'));
    });

    test('the crime by its name or under another key', () async {
      for (final args in [
        {'suc': 'Kasten yaralama', 'olay_tarihi': '2025-03-10'},
        {'suç': 'TCK 86/1', 'olay_tarihi': '2025-03-10'},
        {'suc': '86/1', 'olay_tarihi': '2025-03-10'},
      ]) {
        final r = await FolioMcp().call('ceza_hesapla', args);
        expect(r['durum'], 'hesaplandi', reason: '$args');
        expect('${r['suc']}', endsWith('86/1'));
      }
    });
  });

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
