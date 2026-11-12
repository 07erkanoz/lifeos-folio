import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/legal/criminal_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Dart calculator must give Python's answer (banaozel
/// server/ceza_hesap.py) for every golden case: the whole `hesapla` output
/// and the `metin` text. The goldens are Python's own output
/// (tool/ceza/altin_uret.py); when one differs the Dart is wrong.
void main() {
  late CriminalCalculator calc;
  final today = DateTime.utc(2026, 10, 1);

  setUpAll(() async {
    calc = await CriminalCalculator.load();
  });

  group('golden cases from Python', () {
    late List<Map<String, Object?>> cases;
    setUpAll(() {
      final raw = File('test/fixtures/ceza_altin.json.gz').readAsBytesSync();
      cases = [
        for (final c in jsonDecode(utf8.decode(gzip.decode(raw))) as List) (c as Map).cast<String, Object?>(),
      ];
    });

    test('every case matches', () {
      expect(cases.length, greaterThan(5000));
      final failures = <String>[];
      var passed = 0;
      for (final c in cases) {
        final input = (c['girdi'] as Map).cast<String, Object?>();
        final day = DateTime.parse(c['bugun'] as String);
        final want = c['cikti'] as Map;
        String? why;
        if (want.containsKey('istisna')) {
          try {
            calc.compute(input, today: day);
            why = 'Python raised ${want['istisna']}, Dart did not';
          } on FormatException {
            // as Python
          }
        } else {
          final got = calc.compute(input, today: day);
          final diff = _diff(got, want, r'$');
          if (diff != null) {
            why = diff;
          } else {
            final text = calc.text(input, today: day);
            if (text != c['metin']) why = 'text differs:\n${_firstLineDiff(text, c['metin'] as String)}';
          }
        }
        if (why == null) {
          passed++;
        } else if (failures.length < 10) {
          failures.add('${jsonEncode(input)}\n  $why');
        }
      }
      // ignore: avoid_print
      print('criminal calculator goldens: $passed / ${cases.length} pass');
      expect(failures, isEmpty, reason: failures.join('\n\n'));
      expect(passed, cases.length);
    });
  });

  group('ported from test_ceza_hesap.py', () {
    Map<String, Object?> h(Map<String, Object?> kw) =>
        calc.compute({'karar_tarihi': '01.10.2026', ...kw}, today: today);
    String metin(Map<String, Object?> g) => calc.text(g, today: today);
    Rational ay(int n) => Rational(n * 30);
    Rational yil(int n) => Rational(n * 360);
    Rational frac(Object? v) => Rational.fromJson(v);
    Map<String, Object?> m(Object? v) => (v as Map).cast<String, Object?>();
    List<Map<String, Object?>> surumler(Map<String, Object?> r) => [for (final x in r['surumler'] as List) m(x)];
    Rational sen(Map<String, Object?> r, String ad, [int? surum]) {
      final x = surum == null ? m(r['lehe']) : surumler(r)[surum];
      return frac(m(m(x['senaryolar'])[ad])['deger']);
    }

    List<String> uyari(Map<String, Object?> r) => [for (final u in r['uyari'] as List) u as String];
    bool anyWarn(Map<String, Object?> r, String s) => uyari(r).any((u) => u.contains(s));
    Map<String, Object?> lehe(Map<String, Object?> r) => m(r['lehe']);
    Map<String, Object?> zaman(Map<String, Object?> r) => m(r['zamanasimi']);

    test('2023/282: favourable law, HAGB and limitation', () {
      final r = h({
        'olay_tarihi': '05.08.2022', 'suc': 'TCK 86/1', 'nitelikli': ['TCK 86/3-e', 'TCK 87/3'], //
        'takdiri_indirim': true,
      });
      expect(m(lehe(r)['surum'])['bas'], isNull);
      expect(frac(lehe(r)['alt']), ay(12));
      expect(sen(r, 'alt_artirim_en_cok'), ay(12) * Rational(3, 2) * Rational(3, 2) * Rational(5, 6));
      expect(CriminalCalculator.formatDays(sen(r, 'alt_artirim_en_cok')), '1 yıl 10 ay 15 gün');
      expect(CriminalCalculator.formatDays(sen(r, 'alt_indirimsiz')), '2 yıl 3 ay');
      expect(CriminalCalculator.formatDays(sen(r, 'en_cok')), '6 yıl 9 ay');
      expect(r['hagb'] as String, contains('takdire bağlı indirimler'));
      expect([zaman(r)['madde'], zaman(r)['sure_yil']], ['66/1-d', 15]);
      expect([zaman(r)['olagan_bitis'], zaman(r)['uzamis_bitis']], ['2037-08-05', '2045-02-05']);
      expect(r['uzlastirma'], isFalse);
      expect(r['sikayet'], isFalse);
    });

    test('87/1 floors are dated', () {
      expect(sen(h({'olay_tarihi': '01.01.2024', 'karar_tarihi': '01.01.2025', 'suc': 'TCK 86/1', 'nitelikli': ['TCK 87/1']}), 'en_az'),
          ay(36));
      expect(sen(h({'olay_tarihi': '01.07.2025', 'suc': 'TCK 86/1', 'nitelikli': ['TCK 87/1']}), 'en_az'), ay(48));
      expect(sen(h({'olay_tarihi': '01.07.2025', 'suc': 'TCK 86/1', 'nitelikli': ['TCK 86/3-e', 'TCK 87/1']}), 'en_az'),
          ay(72));
      final gecis = h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 86/1', 'nitelikli': ['TCK 87/1']});
      expect(surumler(gecis), hasLength(2));
      expect(sen(gecis, 'en_az'), ay(36));
    });

    test('86/2 against a woman in three periods', () {
      expect(frac(lehe(h({'olay_tarihi': '01.05.2022', 'karar_tarihi': '20.05.2022', 'suc': 'TCK 86/2', 'kadina_karsi': true}))['alt']),
          ay(4));
      expect(frac(lehe(h({'olay_tarihi': '01.06.2022', 'karar_tarihi': '01.06.2023', 'suc': 'TCK 86/2', 'kadina_karsi': true}))['alt']),
          ay(6));
      final son = h({'olay_tarihi': '01.07.2025', 'suc': 'TCK 86/2', 'kadina_karsi': true});
      expect(frac(lehe(son)['alt']), ay(9));
      expect(son['tutuklama_yasagi'], isFalse);
    });

    test('mediation with other crimes against the same victim (CMK 253/3)', () {
      final tek = h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 86/2'});
      expect([tek['uzlastirma'], tek['sikayet']], [true, true]);
      expect(h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 86/2', 'ayni_magdura_diger_suclar': ['TCK 106/2']})['uzlastirma'],
          isFalse);
      expect(h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 86/2', 'ayni_magdura_diger_suclar': ['TCK 125/1']})['uzlastirma'],
          isTrue);
      expect(h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 86/2', 'ayni_magdura_diger_suclar': ['TCK 125/3-a']})['uzlastirma'],
          isFalse);
      expect(h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 86/1', 'nitelikli': ['TCK 86/3-e']})['uzlastirma'], isFalse);
    });

    test('age and the chain-offence ban', () {
      final r = h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 86/1', 'fail_yas_grubu': '15-18'});
      expect(sen(r, 'en_az'), ay(12) * Rational(2, 3));
      expect(frac(zaman(r)['oran']), Rational(2, 3));
      final z = h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 86/1', 'zincirleme': true});
      expect(anyWarn(z, '43/3'), isTrue);
      expect(m(z['genel'])['zincirleme'], isFalse);
    });

    test('code spellings', () {
      expect(calc.normalCode('tck 86/3-e'), 'TCK 86/3-e');
      expect(calc.normalCode('TCK m.86/3 e'), 'TCK 86/3-e');
      expect(calc.normalCode('86/1'), 'TCK 86/1');
      expect(calc.normalCode('125/3-a'), 'TCK 125/3-a');
      expect(calc.normalCode('6136 sayılı Kanun m.13/1'), '6136 13/1');
      for (final s in ['5237 sayılı TCK 102/1', '5237 s.K. 102/1', 'Türk Ceza Kanunu 102/1']) {
        expect(calc.normalCode(s), 'TCK 102/1', reason: s);
      }
      for (final s in ['6136 13-1', '6136 SK 13/1', '6136/13-1']) {
        expect(calc.normalCode(s), '6136 13/1', reason: s);
      }
    });

    test('unknown crime and missing date', () {
      expect(metin({'olay_tarihi': '01.01.2024', 'suc': 'TCK 302'}), contains('tabloda yok'));
      expect(metin({'suc': 'TCK 86/1'}), contains('olay_tarihi gerekli'));
    });

    test('night theft, 158 bents and 158/4', () {
      final r = h({'olay_tarihi': '01.03.2024', 'suc': 'TCK 142/2-h', 'nitelikli': ['TCK 143']});
      expect(r['bent'], 'h');
      expect(sen(r, 'en_az'), ay(90));
      expect(r['agir_ceza'], isFalse);
      final i = h({'olay_tarihi': '01.03.2026', 'suc': 'TCK 158/1-f', 'nitelikli': ['TCK 158/4']});
      expect(lehe(i)['gun'], '2026-07-31');
      expect(sen(i, 'alt_indirimsiz'), ay(24));
      expect(zaman(i)['sure_yil'], 8);
      final bentsiz = h({'olay_tarihi': '01.03.2026', 'suc': 'TCK 158/1'});
      expect(frac(lehe(bentsiz)['alt']), ay(36));
      expect(anyWarn(bentsiz, 'bent'), isTrue);
    });

    test('effective remorse', () {
      final r = h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 141/1', 'etkin_pismanlik': 'kovusturma_oncesi'});
      expect([sen(r, 'en_az'), sen(r, 'alt_indirimsiz')], [ay(4), ay(12)]);
      final y = h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 86/1', 'etkin_pismanlik': 'kovusturma_oncesi'});
      expect(y['etkin'], isNull);
      expect(anyWarn(y, '168'), isTrue);
      final z = h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 247/1', 'etkin_pismanlik': 'sorusturma_oncesi'});
      expect([sen(z, 'en_az'), sen(z, 'alt_indirimsiz')], [ay(20), ay(20)]);
      final e = h({'olay_tarihi': '01.01.2026', 'suc': 'TCK 220/2', 'etkin_pismanlik': 'yakalandiktan_sonra_bilgi'});
      expect([sen(e, 'en_az'), sen(e, 'alt_indirimsiz')], [ay(6), ay(16)]);
      final mm = metin({'olay_tarihi': '01.01.2024', 'suc': 'TCK 148/1', 'etkin_pismanlik': 'kovusturmada'});
      expect(mm.split('\n')[1], contains('168/3'));
      expect(mm, isNot(contains('168/1')));
    });

    test('life sentences convert by the general rules', () {
      final eski = h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 81', 'tesebbus': true});
      expect([for (final x in surumler(eski)) x['gun']], ['2024-01-01', '2025-06-04']);
      expect([sen(eski, 'en_az'), sen(eski, 'en_cok')], [yil(9), yil(15)]);
      final yeni = h({'olay_tarihi': '01.07.2025', 'suc': 'TCK 82/1', 'tesebbus': true});
      expect([sen(yeni, 'en_az'), sen(yeni, 'en_cok')], [yil(14), yil(21)]);
      expect([zaman(eski)['madde'], zaman(yeni)['madde']], ['66/1-b', '66/1-a']);
      final t = h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 82/1', 'takdiri_indirim': true});
      expect([sen(t, 'en_az'), sen(t, 'en_cok')], [Rational(10000000), Rational(20000000)]);
      final hk = h({
        'olay_tarihi': '01.01.2024', 'suc': 'TCK 81', 'haksiz_tahrik': true, 'fail_yas_grubu': '15-18', //
        'takdiri_indirim': true,
      });
      expect(sen(hk, 'en_az'), yil(12) * Rational(2, 3) * Rational(5, 6));
      expect(sen(hk, 'en_cok'), yil(12));
      final y = h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 81', 'yardim_eden': true});
      expect([sen(y, 'en_az'), sen(y, 'en_cok')], [yil(10), yil(15)]);
      expect(metin({'olay_tarihi': '01.01.2024', 'suc': 'TCK 81'}), contains('müebbet hapis'));
    });

    test('thirty-year cap and the 2005 cap day', () {
      final r = h({'olay_tarihi': '01.01.2024', 'suc': 'TCK 188/1', 'nitelikli': ['TCK 188/5-2']});
      expect([sen(r, 'en_az'), sen(r, 'en_cok')], [yil(30), yil(30)]);
      expect([r['agir_ceza'], r['zorunlu_mudafi'], zaman(r)['sure_yil']], [true, true, 20]);
      final e = h({'olay_tarihi': '15.06.2005', 'suc': 'TCK 188/1', 'nitelikli': ['TCK 188/4-a', 'TCK 188/5-2']});
      expect(sen(e, 'en_cok') <= yil(30), isTrue);
      expect(surumler(e).any((x) => x['gun'] == '2005-07-08'), isTrue);
    });

    test('order of circumstances does not change the result', () {
      expect(sen(h({'olay_tarihi': '01.07.2025', 'suc': 'TCK 86/1', 'nitelikli': ['TCK 87/1', 'TCK 86/3-e']}), 'en_az'),
          ay(72));
      expect(sen(h({'olay_tarihi': '01.07.2025', 'suc': 'TCK 125/1', 'nitelikli': ['TCK 125/4', 'TCK 125/3-a']}), 'en_az'),
          ay(14));
      final tek = h({'olay_tarihi': '01.07.2025', 'suc': 'TCK 86/1', 'nitelikli': ['TCK 86/3-a']});
      final iki = h({'olay_tarihi': '01.07.2025', 'suc': 'TCK 86/1', 'nitelikli': ['TCK 86/3-a', 'TCK 86/3-e']});
      expect([sen(iki, 'en_az'), sen(tek, 'en_az')], [ay(27), ay(27)]);
      expect(sen(iki, 'en_cok'), ay(54));
      expect(zaman(iki)['sure_yil'], 8);
      expect(anyWarn(iki, 'bir kez artırım'), isTrue);
      expect(sen(h({'olay_tarihi': '01.07.2025', 'suc': 'TCK 86/1', 'nitelikli': ['TCK 86/3-a', 'TCK 86/3-f']}), 'en_az'),
          ay(36));
    });

    test('jurisdiction ignores rate increases (5235 m.14)', () {
      for (final (suc, nit) in [('TCK 158/1', 'TCK 158/3'), ('TCK 155/2', 'TCK 155/3'), ('TCK 142/1', 'TCK 143')]) {
        expect(h({'olay_tarihi': '01.01.2026', 'suc': suc, 'nitelikli': [nit]})['agir_ceza'], isFalse, reason: suc);
      }
      expect(h({'olay_tarihi': '01.01.2026', 'suc': 'TCK 188/3'})['agir_ceza'], isTrue);
      expect(h({'olay_tarihi': '01.01.2026', 'suc': 'TCK 148/1'})['agir_ceza'], isTrue);
    });

    test('repealed bents redirect, 82/1 bents', () {
      final r = h({'olay_tarihi': '15.03.2024', 'suc': 'TCK 142/1', 'bent': 'b', 'nitelikli': ['TCK 143']});
      expect([r['suc'], r['bent']], ['TCK 142/2', 'h']);
      expect(metin({'olay_tarihi': '01.01.2024', 'suc': 'TCK 142/1-f'}), contains('163/3'));
      final b = h({'olay_tarihi': '01.03.2020', 'suc': 'TCK 82/1-d-bosanmis'});
      expect(b['bent'], 'd-bosanmis');
      expect(frac(lehe(b)['alt']), Rational(10000000));
      final k = h({'olay_tarihi': '01.03.2020', 'suc': 'TCK 82/1', 'kadina_karsi': true});
      expect(k['bent'], 'f');
    });

    test('5607 periods and the 3/10 own range', () {
      (Rational, Rational) ara(String t) {
        final r = h({'olay_tarihi': t, 'karar_tarihi': t, 'suc': '5607 3/1', 'nitelikli': ['5607 3/10']});
        return (sen(r, 'en_az'), sen(r, 'en_cok'));
      }

      expect(ara('10.04.2013'), (ay(12), ay(60)));
      expect(ara('11.04.2013'), (ay(24), ay(60)));
      expect(ara('27.06.2014'), (ay(24), ay(60)));
      expect(ara('28.06.2014'), (ay(36), ay(180)));
      final k = h({'olay_tarihi': '01.01.2024', 'suc': '5607 3/5', 'nitelikli': ['5607 3/10'], 'tesebbus': true});
      expect(sen(k, 'en_az'), ay(36));
      expect(anyWarn(k, '3/22'), isTrue);
    });

    test('crossing versions are flagged', () {
      expect(anyWarn(h({'olay_tarihi': '01.01.2014', 'suc': '5607 3/5', 'nitelikli': ['5607 3/23-3']}), 'kesişiyor'),
          isTrue);
      expect(anyWarn(h({'olay_tarihi': '01.03.2006', 'suc': 'TCK 86/1', 'nitelikli': ['TCK 87/3']}), 'kesişiyor'),
          isTrue);
    });

    test('text notes', () {
      expect(metin({'olay_tarihi': '01.03.2026', 'suc': 'TCK 158/1-f'}), contains('5235 geçici m.7'));
      expect(metin({'olay_tarihi': '01.01.2024', 'suc': 'TCK 235/1'}), contains('DMK m.48/A-5): ihaleye fesat'));
      expect(metin({'olay_tarihi': '01.01.2024', 'suc': 'TCK 125/1'}), contains('Seçimlik adlî para'));
      expect(metin({'olay_tarihi': '01.01.2024', 'suc': 'TCK 86/1'}), isNot(contains('Seçimlik adlî para')));
      final varr = metin({'karar_tarihi': '01.10.2026', 'olay_tarihi': '01.09.2026', 'suc': 'TCK 142/3', 'nitelikli': ['TCK 142/3-2']});
      expect(varr, contains('on bin güne kadar adlî para'));
      expect(metin({'olay_tarihi': '01.01.2024', 'suc': 'TCK 141/1'}), contains('denetimi kaydı yok'));
    });

    test('a date that does not exist throws, as Python raises', () {
      expect(() => h({'olay_tarihi': '31.02.2024', 'suc': 'TCK 86/1'}), throwsFormatException);
    });

    test('the tool lists its crimes', () {
      expect(calc.crimeCodes, containsAll(['TCK 86/1', 'TCK 158/1', '6136 13/1', '5607 3/18']));
      expect(calc.circumstanceCodes.first, 'TCK 86/3-a');
    });
  });
}

/// The first place where [got] and [want] differ, as a JSON path; null when equal.
String? _diff(Object? got, Object? want, String path) {
  if (want is Map) {
    if (got is! Map) return '$path: expected a map, got $got';
    for (final k in {...want.keys, ...got.keys}) {
      if (!want.containsKey(k)) return '$path.$k: unexpected ${jsonEncode(got[k])}';
      if (!got.containsKey(k)) return '$path.$k: missing (expected ${jsonEncode(want[k])})';
      final d = _diff(got[k], want[k], '$path.$k');
      if (d != null) return d;
    }
    return null;
  }
  if (want is List) {
    if (got is! List) return '$path: expected a list, got $got';
    if (got.length != want.length) return '$path: length ${got.length} != ${want.length}: ${jsonEncode(got)} vs ${jsonEncode(want)}';
    for (var i = 0; i < want.length; i++) {
      final d = _diff(got[i], want[i], '$path[$i]');
      if (d != null) return d;
    }
    return null;
  }
  return got == want ? null : '$path: ${jsonEncode(got)} != ${jsonEncode(want)}';
}

String _firstLineDiff(String got, String want) {
  final a = got.split('\n'), b = want.split('\n');
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : '<none>', y = i < b.length ? b[i] : '<none>';
    if (x != y) return '  line $i dart:   $x\n  line $i python: $y';
  }
  return '';
}
