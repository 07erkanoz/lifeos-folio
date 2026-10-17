import 'dart:io';

import 'package:evrak_convert/services/legal/citation.dart';
import 'package:evrak_convert/services/legal/decision.dart';
import 'package:evrak_convert/services/legal/decision_anatomy.dart';
import 'package:evrak_convert/services/legal/decision_sentences.dart';
import 'package:flutter_test/flutter_test.dart';

final _laws = CitationScanner.parse(
  File('assets/mevzuat/laws.json').readAsStringSync(),
);
final _courts = DecisionScanner.parse(
  File('assets/mevzuat/courts.json').readAsStringSync(),
);

DecisionAnatomy _read(String text, {String query = '', Set<String>? stock}) =>
    DecisionAnatomy.of(
      text,
      query: query,
      laws: _laws,
      decisions: _courts,
      boilerplate: stock == null ? null : DecisionBoilerplate(stock),
    );

/// Every quotation is the decision's own words, at the place it gives.
void _verbatim(String text, DecisionAnatomy anatomy) {
  final quotes = <Quote>[
    for (final step in anatomy.chain) step.court,
    ?anatomy.subjectHeading,
    ?anatomy.subject,
    if (anatomy.outcome case final o?) ...[
      o.region,
      for (final v in o.verbs) ...[v.verb, v.clause],
    ],
    for (final s in anatomy.sections) s.heading,
    for (final h in anatomy.highlights) h.quote,
  ];
  for (final q in quotes) {
    expect(text.substring(q.start, q.end), q.text);
  }
}

const _yargitay = '''
9. Hukuk Dairesi 2025/9394 E. , 2026/696 K.
"İçtihat Metni"MAHKEMESİ : Trabzon Bölge Adliye Mahkemesi 5. Hukuk Dairesi
SAYISI : 2024/1375 E., 2025/1715 K.
İLK DERECE MAHKEMESİ : Trabzon 2. İş Mahkemesi
SAYISI : 2022/269 E., 2024/87 K.
Bölge Adliye Mahkemesi kararı davacı vekili tarafından temyiz edilmekle; kesinlik, süre, temyiz şartı ve diğer usul eksiklikleri yönünden yapılan ön inceleme sonucunda, temyiz dilekçesinin kabulüne karar verildikten ve Tetkik Hâkimi tarafından hazırlanan rapor dinlendikten sonra dosyadaki belgeler incelenip gereği düşünüldü:
I. DAVA
Davacı vekili dava dilekçesinde; müvekkilinin kıdem tazminatının ödenmediğini ileri sürerek tahsilini talep etmiştir.
II. CEVAP
Davalı vekili cevap dilekçesinde; davanın reddini istemiştir.
III. İLK DERECE MAHKEMESİ KARARI
İlk Derece Mahkemesinin kararı ile davanın kısmen kabulüne karar verilmiştir.
IV. İSTİNAF
Bölge Adliye Mahkemesince davacı vekilinin istinaf başvurusunun esastan reddine karar verilmiştir.
V. TEMYİZ
A. Temyiz Sebepleri
Davacı vekili temyiz dilekçesinde; kararın bozulmasını istemiştir.
B. Değerlendirme ve Gerekçe
1. Uyuşmazlık ve Hukuki Nitelendirme
Uyuşmazlık, kıdem tazminatı alacağının hesaplanmasına ilişkindir.
2. İlgili Hukuk
Mülga 1475 sayılı İş Kanunu'nun 14/2 hükmü işçinin aynı işverene bağlı olarak çalıştığı sürelerin kıdem hesabı yönünden birleştirileceğini hükme bağlamıştır.
3. Değerlendirme
Dosyadaki yazılara, kararın dayandığı delillerle gerektirici sebeplere göre davacı vekilinin aşağıdaki paragrafın kapsamı dışındaki temyiz itirazları yerinde görülmemiştir.
Fasılalı çalışmada bir döneme ilişkin kıdem tazminatının eksik ödendiği belirlendiği takdirde o dönem bakımından tasfiyeden söz edilmesi mümkün değildir.
Davacı ... vekili tarafından ödenen tutarın mahsubu gerekirken bu husus gözetilmeden yazılı şekilde hüküm kurulması hatalı olup bozmayı gerektirmiştir.
VI. KARAR
Açıklanan sebeplerle;
1. Temyiz olunan, İlk Derece Mahkemesi kararına karşı istinaf başvurusunun esastan reddine ilişkin Bölge Adliye Mahkemesi kararının ORTADAN KALDIRILMASINA,
2. İlk Derece Mahkemesi kararının BOZULMASINA,
Dosyanın kararı veren İlk Derece Mahkemesine, bozma kararının bir örneğinin kararı veren Bölge Adliye Mahkemesine gönderilmesine,
02.02.2026 tarihinde oy birliğiyle karar verildi.''';

const _bam = '''
T.C.
İSTANBUL
BÖLGE ADLİYE MAHKEMESİ
17. HUKUK DAİRESİ
DOSYA NO: 2025/953 Esas
KARAR NO : 2025/1320
T Ü R K M İ L L E T İ A D I N A
İ S T İ N A F K A R A R I
İNCELENEN KARARIN
MAHKEMESİ: İstanbul Anadolu 2. Asliye Ticaret Mahkemesi
TARİHİ: 14/05/2025
NUMARASI : 2022/272 Esas, 2025/354 Karar
DAVANIN KONUSU : Alacak (Kira Sözleşmesinden Kaynaklanan)
KARAR TARİHİ: 16/10/2025
GEREĞİ DÜŞÜNÜLDÜ:
DAVACI : ... Ltd. Şti.
Davacı vekili dava dilekçesinde özetle; kira bedellerinin ödenmediğini belirterek alacağın tahsilini talep etmiştir.
CEVAP: Davalı vekili davanın reddini istemiştir.
DELİLLERİN TARTIŞILMASI VE GEREKÇE: Dava, kira sözleşmesinden kaynaklanan alacağın tahsili istemine ilişkindir.Mahkemece davanın reddine karar verilmiştir.
Bu durumda ilk derece mahkemesince anılan dosyaların kesinleşip kesinleşmediğinin belirlenmesi, kesinleşmiş ise verilen kararların bu davada değerlendirilmesi gerekir.
H Ü K Ü M : Gerekçesi yukarıda izah edildiği üzere;
1-Davacı vekilinin istinaf başvurusunun KABULÜNE,2-İstanbul Anadolu 2. Asliye Ticaret Mahkemesinin 2022/272 Esas, 2025/354 Karar sayılı kararının HMK'nın 353/1-a-6 maddesi uyarınca KALDIRILMASINA,3-Dosyanın yeniden karar verilmek üzere mahal Mahkemesine İADESİNE,
Dosya üzerinden kesin olmak üzere oybirliği ile karar verildi.''';

void main() {
  group('sentences', () {
    test('the bank\'s anonymising ellipsis does not end a sentence', () {
      const text =
          'Davacı ... vekili tarafından ödenen tutar mahsup edilmelidir. '
          'Sonraki cümle burada başlar.';
      final found = DecisionSentences.of(text);
      expect(found.map((q) => q.text), [
        'Davacı ... vekili tarafından ödenen tutar mahsup edilmelidir.',
        'Sonraki cümle burada başlar.',
      ]);
    });

    test('ordinals, dates, sums and citation marks do not either', () {
      const text =
          'Yargıtay 3. Hukuk Dairesinin E. 2019/1 K. 2020/2 sayılı ve '
          '12.03.2024 tarihli kararında 1.250,00 TL için TBK m. 49 uyarınca '
          'Av. Ali Veli dinlenmiştir. İkinci cümle.';
      expect(DecisionSentences.of(text), hasLength(2));
    });

    test('two sentences run together without a space are two', () {
      const text =
          'Dava, alacak istemine ilişkindir.Mahkemece davanın reddine karar '
          'verilmiştir.';
      expect(DecisionSentences.of(text).map((q) => q.text), [
        'Dava, alacak istemine ilişkindir.',
        'Mahkemece davanın reddine karar verilmiştir.',
      ]);
    });

    test('every sentence is a quotation at its place', () {
      for (final q in DecisionSentences.of(_yargitay)) {
        expect(_yargitay.substring(q.start, q.end), q.text);
      }
    });
  });

  group('the chain of courts', () {
    test('the Court of Cassation\'s heading names both courts below', () {
      final a = _read(_yargitay);
      expect(a.chain.map((s) => (s.role, s.court.text)), [
        (CourtRole.appeal, 'Trabzon Bölge Adliye Mahkemesi 5. Hukuk Dairesi'),
        (CourtRole.firstInstance, 'Trabzon 2. İş Mahkemesi'),
      ]);
      expect(a.chain.first.numbers?.text, '2024/1375 E., 2025/1715 K.');
      expect(a.chain.last.filed, ('2022/269', '2024/87'));
    });

    test('a regional court\'s heading names the court of first instance', () {
      final a = _read(_bam);
      expect(a.chain, hasLength(1));
      expect(a.chain.single.role, CourtRole.firstInstance);
      expect(
        a.chain.single.court.text,
        'İstanbul Anadolu 2. Asliye Ticaret Mahkemesi',
      );
      expect(a.chain.single.date?.text, '14/05/2025');
    });

    test('a regional court that tried the case itself is first instance', () {
      const text = '''
11. Hukuk Dairesi 2025/330 E. , 2025/1795 K.
"İçtihat Metni"MAHKEMESİ : İstanbul Bölge Adliye Mahkemesi 14. Hukuk Dairesi
(İlk Derece sıfatıyla)
SAYISI : 2024/5 E., 2024/7 K.''';
      expect(_read(text).chain.single.role, CourtRole.firstInstance);
    });

    test('a General Assembly names the chamber that was resisted', () {
      const text = '''
Hukuk Genel Kurulu 2024/41 E. , 2025/523 K.
"İçtihat Metni"MAHKEMESİ :Ticaret Mahkemesi
SAYISI : 2021/1115 E., 2022/274 K.
ÖZEL DAİRE KARARI : Yargıtay (Kapatılan) 17. Hukuk Dairesinin 15.02.2021 tarihli ve
2020/724 Esas, 2021/1336 Karar sayılı BOZMA kararı
1. Taraflar arasındaki maddi ve manevi tazminat davasından dolayı yapılan yargılama sonunda, Ankara Batı Asliye Ticaret Mahkemesince verilen davanın kısmen kabulüne ilişkin kararın davalı vekili tarafından temyiz edilmesi üzerine Yargıtay 4. Hukuk Dairesince yapılan inceleme sonunda bozulmuştur.''';
      final a = _read(text);
      expect(a.chain.map((s) => s.role), [
        CourtRole.firstInstance,
        CourtRole.chamber,
      ]);
      expect(a.chain.last.court.text, contains('17. Hukuk Dairesinin'));
      expect(a.chain.last.numbers?.text, startsWith('2020/724 Esas'));
    });

    test('the Council of State names the court below in its request', () {
      const text = '''
Danıştay 2. Daire Başkanlığı 2021/17740 E. , 2025/6404 K.
"İçtihat Metni" T.C.
D A N I Ş T A Y
İKİNCİ DAİRE
Esas No : 2021/17740
Karar No : 2025/6404
TEMYİZ EDEN (DAVALI) : ... Genel Müdürlüğü
VEKİLİ : Av. ...
İSTEMİN KONUSU : ... Bölge İdare Mahkemesi ... İdari Dava Dairesince verilen ... günlü kararın bozulması isteminden ibarettir.
YARGILAMA SÜRECİ :
Dava Konusu İstem : Dava; polis memuru olan davacının meslekten çıkarılma cezasıyla cezalandırılmasına ilişkin işlemin iptali istemiyle açılmıştır.''';
      final a = _read(text);
      expect(a.chain.single.role, CourtRole.appeal);
      expect(
        a.chain.single.court.text,
        'Bölge İdare Mahkemesi ... İdari Dava Dairesi',
      );
      // What the case is about is the claim, not the request for review.
      expect(a.subjectHeading?.text, startsWith('Dava; polis memuru'));
      expect(a.subject, isNull);
      _verbatim(text, a);
    });
  });

  group('what the case is about', () {
    test('the sentence that says so, and the heading', () {
      final a = _read(_bam);
      expect(
        a.subject?.text,
        'Dava, kira sözleşmesinden kaynaklanan alacağın tahsili istemine '
        'ilişkindir.',
      );
      expect(
        a.subjectHeading?.text,
        'Alacak (Kira Sözleşmesinden Kaynaklanan)',
      );
    });

    test('"Uyuşmazlık, … ilişkindir." when there is no "Dava,"', () {
      expect(
        _read(_yargitay).subject?.text,
        'Uyuşmazlık, kıdem tazminatı alacağının hesaplanmasına ilişkindir.',
      );
    });

    test('an older decision\'s opening names the case', () {
      const text = '''
3. Hukuk Dairesi 2017/1502 E. , 2017/1318 K.
"İçtihat Metni"MAHKEMESİ :SULH HUKUK MAHKEMESİ
Taraflar arasındaki kira bedelinin tespiti davasının mahkemece yapılan yargılaması sonucunda verilen hüküm temyiz edilmiştir.''';
      expect(_read(text).subject?.text, 'kira bedelinin tespiti');
    });
  });

  group('the outcome, from the operative part alone', () {
    test('a reversal that also sets the regional court aside', () {
      final o = _read(_yargitay).outcome!;
      expect(o.primary, OutcomeKind.bozma);
      // "istinaf başvurusunun esastan reddine ilişkin" names the decision
      // set aside; it decides nothing.
      expect(o.kinds, [OutcomeKind.bozma, OutcomeKind.kaldirma]);
      expect(o.region.text, startsWith('VI. KARAR'));
    });

    test('an appeal allowed is not the claim allowed', () {
      final o = _read(_bam).outcome!;
      expect(o.kinds, [OutcomeKind.kaldirma, OutcomeKind.gonderme]);
      expect(o.region.text, startsWith('H Ü K Ü M'));
    });

    test('a file returned is not a dismissal, whatever the text quotes', () {
      const text = '''
Hukuk Genel Kurulu 2023/1 E. , 2024/2 K.
"İçtihat Metni"MAHKEMESİ : Asliye Hukuk Mahkemesi
I. YARGILAMA SÜRECİ
Mahkemece davanın reddine karar verilmiş, karar davacı vekilince temyiz edilmiştir.
II. KARAR
Açıklanan sebeplerle;
Dosyanın ilgili belgelerin eklenmesi için mahalline GERİ ÇEVRİLMESİNE, 01.01.2024 tarihinde oy birliğiyle karar verildi.''';
      final o = _read(text).outcome!;
      expect(o.kinds, [OutcomeKind.geriCevirme]);
    });

    test('the Council of State upholding says the appeal is refused', () {
      const text = '''
Danıştay 9. Daire 2024/1 E. , 2024/2 K.
"İçtihat Metni"T.C.
Esas No : 2024/1
Karar No : 2024/2
TEMYİZ EDENİN İDDİALARI: Kararın bozulması istenilmektedir.
İleri sürülen iddialar kararın bozulmasını sağlayacak durumda bulunmadığından, temyiz isteminin reddine ve kararın onanmasına, 16/10/2024 tarihinde oybirliğiyle karar verildi.''';
      expect(_read(text).outcome!.kinds, [OutcomeKind.onama]);
    });

    test('a petition refused for its amount is said apart', () {
      const text = '''
VI. KARAR
1. Davalılar vekilinin temyiz dilekçesinin miktardan REDDİNE,
2. Temyiz olunan Bölge Adliye Mahkemesi kararının ONANMASINA,''';
      expect(_read(text).outcome!.kinds, [
        OutcomeKind.onama,
        OutcomeKind.temyizReddi,
      ]);
    });

    test('a court of first instance dismissing on procedure dismissed', () {
      const text = '''
HÜKÜM : Yukarıda açıklanan nedenlerle ;
1-Davanın hukuki yarar yokluğundan usulden reddine,
2-Davalı tarafından yapılan yargılama gideri bulunmadığından karar verilmesine yer olmadığına,''';
      expect(_read(text).outcome!.kinds, [OutcomeKind.ret]);
    });

    test('lack of jurisdiction over the subject', () {
      const text = '''
HÜKÜM: Gerekçesi yukarıda açıklandığı üzere;
1-Davanın HMK'nın 114/1-c ve 115/2. maddeleri uyarınca görev yönünden usulden reddine,''';
      expect(_read(text).outcome!.kinds, [OutcomeKind.gorevsizlik]);
    });

    test('a dissent below the decision is not the decision', () {
      const text = '''
KARAR SONUCU :
Açıklanan nedenlerle; kararın ONANMASINA, oyçokluğuyla karar verildi.
(X)KARŞI OY : Kararın bozulmasına karar verilmesi gerektiği oyuyla katılmıyorum.''';
      final a = _read(text);
      expect(a.outcome!.kinds, [OutcomeKind.onama]);
      expect(a.outcome!.region.text, isNot(contains('KARŞI OY')));
    });
  });

  group('the parts', () {
    test('the sectioned form, with its numbered sub-parts', () {
      final a = _read(_yargitay);
      expect(
        [
          for (final s in a.sections)
            if (s.level == 1) s.title,
        ],
        [
          'DAVA',
          'CEVAP',
          'İLK DERECE MAHKEMESİ KARARI',
          'İSTİNAF',
          'TEMYİZ',
          'KARAR',
        ],
      );
      expect(
        [
          for (final s in a.sections)
            if (s.level == 3) s.title,
        ],
        ['Uyuşmazlık ve Hukuki Nitelendirme', 'İlgili Hukuk', 'Değerlendirme'],
      );
      _verbatim(_yargitay, a);
    });

    test('a regional court\'s parts written with their text after a colon', () {
      final a = _read(_bam);
      expect(
        [for (final s in a.sections) s.heading.text],
        [
          'GEREĞİ DÜŞÜNÜLDÜ:',
          'CEVAP:',
          'DELİLLERİN TARTIŞILMASI VE GEREKÇE:',
          'H Ü K Ü M :',
        ],
      );
      // The party list and the document's own spaced-out title are not
      // parts of it.
      expect(a.sections.map((s) => s.title), isNot(contains('DAVACI')));
      _verbatim(_bam, a);
    });

    test('a title in dashes is the document\'s, not a part', () {
      const text = '''
17. Hukuk Dairesi 2016/4174 E. , 2019/442 K.
"İçtihat Metni"MAHKEMESİ :Ticaret Mahkemesi
Taraflar arasındaki maddi tazminat davası üzerine yapılan yargılama sonunda verilen hüküm temyiz edilmekle, dosya incelendi, gereği düşünüldü:
-K A R A R-
Davacı vekili tazminat istemiştir.
SONUÇ: Yukarıda açıklanan nedenlerle hükmün BOZULMASINA, oybirliğiyle karar verildi.''';
      final a = _read(text);
      expect(a.sections.map((s) => s.heading.text), ['SONUÇ:']);
      expect(a.outcome!.primary, OutcomeKind.bozma);
    });
  });

  group('what it cites', () {
    test('the closing line of an upheld decision cites HMK 370/1', () {
      const text = '''
VI. KARAR
Temyiz olunan Bölge Adliye Mahkemesi kararının 6100 sayılı Kanun'un 370/1 hükmü uyarınca ONANMASINA,''';
      final laws = _read(text).laws;
      expect(laws.map((c) => (c.law.number, c.article, c.paragraph)), [
        (6100, 370, 1),
      ]);
    });

    test('a decision\'s own numbers and the one under review are not '
        'precedents', () {
      final a = _read(_bam);
      expect(a.decisions, isEmpty);
    });

    test('a precedent in the reasoning is', () {
      const text = '''
MAHKEMESİ : Asliye Hukuk Mahkemesi
SAYISI : 2021/1 E., 2022/2 K.
I. GEREKÇE
Nitekim, aynı ilkeler Yargıtay Hukuk Genel Kurulunun 07.05.2014 gün ve 2013/4-1121 Esas, 2014/626 Karar sayılı kararında da vurgulanmıştır.''';
      final cited = _read(text).decisions;
      expect(cited.map((d) => (d.esas, d.karar)), [
        ('2013/4-1121', '2014/626'),
      ]);
    });
  });

  group('what stands out', () {
    test('taken from the court\'s own reasons, never the parties\'', () {
      final a = _read(_yargitay, query: 'kıdem tazminatı');
      final reasons = a.sections.firstWhere((s) => s.title == 'Değerlendirme');
      expect(a.highlights, isNotEmpty);
      for (final h in a.highlights) {
        expect(h.quote.start, greaterThanOrEqualTo(reasons.start));
        expect(h.quote.end, lessThanOrEqualTo(reasons.end));
      }
      expect(
        a.highlights.first.quote.text,
        startsWith('Fasılalı çalışmada bir döneme'),
      );
      expect(a.highlights.first.matched, ['kıdem', 'tazminatı']);
    });

    test('a sentence many decisions say is never shown', () {
      const stockSentence =
          'Dosyadaki yazılara, kararın dayandığı delillerle gerektirici '
          'sebeplere göre davacı vekilinin aşağıdaki paragrafın kapsamı '
          'dışındaki temyiz itirazları yerinde görülmemiştir.';
      final without = _read(_yargitay);
      final withStock = _read(
        _yargitay,
        stock: {DecisionBoilerplate.keyOf(stockSentence)},
      );
      expect(
        withStock.highlights.map((h) => h.quote.text),
        isNot(contains(stockSentence)),
      );
      // The mark ignores figures, so the same form for another file and
      // another date is the same sentence.
      expect(
        DecisionBoilerplate.keyOf(
          '2. Temyizen incelenen karar, 12.03.2024 '
          'tarihli rapora göre usul ve kanuna uygundur.',
        ),
        DecisionBoilerplate.keyOf(
          '1. Temyizen incelenen karar, 01.01.2020 '
          'tarihli rapora göre usul ve kanuna uygundur.',
        ),
      );
      expect(without.highlights, isNotEmpty);
    });

    test('marks are counted over decisions, once per decision', () {
      const repeated =
          'Temyizen incelenen karar usul ve kanuna uygun olup temyiz '
          'itirazları yerinde görülmemiştir.';
      final keys = DecisionBoilerplate.repeatedIn([
        '$repeated Birinci karar.',
        '$repeated $repeated İkinci karar.',
        'Başka bir şey söyleyen üçüncü karar burada yazılıdır.',
      ], inAtLeast: 2);
      expect(keys, {DecisionBoilerplate.keyOf(repeated)});
    });

    test('an older decision\'s reasons begin after its "-KARAR-"', () {
      const text = '''
1. Hukuk Dairesi 2015/7397 E. , 2018/1002 K.
"İçtihat Metni"MAHKEMESİ :ASLİYE HUKUK MAHKEMESİ
DAVA TÜRÜ : TAPU İPTALİ VE TESCİL
Davacı, temliklerin muvazaalı olduğunu ileri sürerek tapu kayıtlarının iptali ile tescilini istemiştir.
Davalılar, davanın reddini savunmuşlardır.
Mahkemece, muvazaa olgusunun ispatlandığı gerekçesiyle davanın kabulüne karar verilmiştir.
Karar, davalılar vekili tarafından süresinde temyiz edilmiş olmakla dosya incelendi, gereği görüşülüp düşünüldü.
-KARAR-
Bilindiği üzere, 6100 sayılı HMK'nun 26. maddesi hükmü gereğince hakim, kural olarak tarafların talep sonuçlarıyla bağlıdır.
Davacının miras payı oranında tapu kaydının iptali ile tescile karar verilmesi gerekirken kalan paylar yönünden hüküm kurulması doğru değildir.
SONUÇ: Yukarıda açıklanan nedenlerle hükmün BOZULMASINA, oybirliğiyle karar verildi.''';
      final a = _read(text, query: 'tapu iptal tescil');
      expect(a.highlights, isNotEmpty);
      final turn = text.indexOf('-KARAR-');
      for (final h in a.highlights) {
        expect(h.quote.start, greaterThan(turn));
      }
      _verbatim(text, a);
    });

    test('a court\'s whole reasoning in one long sentence is kept', () {
      final long =
          'Somut olayın incelemesinde; davaya konu uyuşmazlığın kooperatif '
          'üyeliğinden kaynaklı tapu iptal ve tescil talebi olduğu, ${'davacıların '
                  'kooperatif üyesi olduğu ve akçeli yükümlülüklerini yerine '
                  'getirdiği, ' * 12}bu nedenle davanın kabulüne karar vermek '
          'gerektiği kanaatine varılarak aşağıdaki şekilde hüküm kuruldu';
      final text =
          'DAVA : Tapu İptali\nGEREĞİ DÜŞÜNÜLDÜ:\n'
          'Davacı vekili dava dilekçesinde tescil talep etmiştir.\n'
          'DELİLLERİN DEĞERLENDİRİLMESİ VE GEREKÇE\n$long\n'
          'HÜKÜM : Gerekçesi yukarıda açıklandığı üzere;\n'
          '1- Davanın KABULÜNE,';
      expect(long.length, greaterThan(900));
      final a = _read(text, query: 'tapu iptal');
      expect(a.highlights.single.quote.text, long);
    });

    test('what the case is about, said again, is not what stands out', () {
      const text = '''
I. GEREKÇE
Uyuşmazlık, temel olarak davacı tapu malikleri ile davalı idare arasındaki kamulaştırmasız el atılan taşınmaz bedeli istemine yöneliktir.
Kamulaştırmasız el atma hâlinde taşınmazın bedeli dava tarihindeki değerine göre belirlenmelidir ve bu kural olarak böyle uygulanır.
II. KARAR
Açıklanan sebeplerle kararın ONANMASINA,''';
      final a = _read(text, query: 'kamulaştırmasız el atma');
      expect(
        a.highlights.map((h) => h.quote.text),
        isNot(contains(startsWith('Uyuşmazlık,'))),
      );
      expect(a.highlights.first.quote.text, startsWith('Kamulaştırmasız el'));
    });

    test('a statute set out word for word gives way to the court\'s own '
        'sentence', () {
      const text = '''
I. GEREKÇE
2577 sayılı Kanun'un "Tam yargı davalarında yetki" başlıklı 36. maddesinin birinci fıkrasında ise; "İdari sözleşmelerden doğanlar dışında kalan tam yargı davaları, idari işlemin yapıldığı yerin idare mahkemesinde görülür" hükmüne yer verilmiştir.
Bu durumda; iptal kararına dayalı olarak açılan tam yargı davasının görüm ve çözümünde işlemi tesis eden idarenin bulunduğu yer idare mahkemesinin yetkili olduğu sonucuna varılmaktadır.
II. KARAR
Açıklanan nedenlerle; davanın görüm ve çözümünde Ankara İdare Mahkemesinin yetkili olduğuna karar verildi.''';
      final a = _read(text, query: 'tam yargı');
      expect(a.highlights.first.quote.text, startsWith('Bu durumda;'));
    });

    test('a quoted sentence is never cut at an ellipsis', () {
      final a = _read(_yargitay, query: 'tutarın mahsubu');
      final cut = a.highlights.where((h) => h.quote.text.contains('mahsubu'));
      expect(cut.single.quote.text, startsWith('Davacı ... vekili'));
      expect(cut.single.quote.text, endsWith('bozmayı gerektirmiştir.'));
    });
  });
}
