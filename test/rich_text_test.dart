import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/legal/rich_text.dart';

List<String> _lines(List<RichParagraph> paragraphs) => [
  for (final p in paragraphs) p.text,
];

List<String> _bold(List<RichParagraph> paragraphs) => [
  for (final p in paragraphs)
    for (final run in p.runs)
      if (run.bold) run.text,
];

void main() {
  group('the little formatting the official pages carry', () {
    test('bold is kept, and it is the words the source marked', () {
      // Bedesten kararın künyesini ve hükmünü kalın yazıyor; kalın olan yer
      // hükmün bulunduğu yerdir, düz metne çevirmek onu kaybettiriyordu.
      final read = richParagraphsOf(
        '<p><b>HÜKÜM</b>: Davanın <strong>kabulüne</strong>, masrafların '
        'davalıya yükletilmesine</p>',
      );
      expect(_lines(read), [
        'HÜKÜM: Davanın kabulüne, masrafların davalıya yükletilmesine',
      ]);
      expect(_bold(read), ['HÜKÜM', 'kabulüne']);
    });

    test('a line break is a paragraph, and blank lines go', () {
      // Ölçüldü: Bedesten kararı tek bir <p> içinde 88 <br> ile geliyor.
      final read = richParagraphsOf(
        '<p align="justify">bir<br><br><br><br>iki<br>üç</p>',
      );
      expect(_lines(read), ['bir', 'iki', 'üç']);
      expect(read.every((p) => p.alignment == DocAlignment.justify), isTrue);
    });

    test('Word wraps its source mid-sentence; the text does not', () {
      final read = richParagraphsOf(
        '<p>Davacı vekili,\nkamulaştırmasız\n  el atma iddiasıyla</p>',
      );
      expect(_lines(read), [
        'Davacı vekili, kamulaştırmasız el atma iddiasıyla',
      ]);
    });

    test('entities are read, named or numbered', () {
      final read = richParagraphsOf(
        '<p>&quot;a&quot; &amp; b &#304;&#351; &ccedil;&ouml;z &nbsp;x</p>',
      );
      expect(_lines(read), ['"a" & b İş çöz x']);
    });

    test('what is not text is not shown: styles, scripts, comments', () {
      final read = richParagraphsOf(
        '<html><head><style>p.MsoNormal { font-size: 12pt; }</style></head>'
        '<body><!-- yorum --><script>var x = 1;</script>'
        '<p class="MsoNormal">Metin</p></body></html>',
      );
      expect(_lines(read), ['Metin']);
    });

    test('an empty page is empty', () {
      expect(richParagraphsOf(''), isEmpty);
      expect(richParagraphsOf('<html><body></body></html>'), isEmpty);
    });

    test('emphasis given by a style counts, and ends with its tag', () {
      final read = richParagraphsOf(
        '<p><span style="font-weight:bold">kalın</span> düz '
        '<span style="font-style: italic">eğik</span></p>',
      );
      expect(read.single.runs, [
        const RichRun('kalın', bold: true),
        const RichRun(' düz '),
        const RichRun('eğik', italic: true),
      ]);
    });

    test('where a paragraph is set is kept', () {
      final read = richParagraphsOf(
        '<p align="center">ANAYASA MAHKEMESİ KARARI</p>'
        '<p style="text-align: right">Başkan</p><center>Karar</center>',
      );
      expect(
        [for (final p in read) p.alignment],
        [DocAlignment.center, DocAlignment.right, DocAlignment.center],
      );
    });
  });

  group('headings the bank sends in plain type', () {
    test('a short line in capitals is a heading', () {
      final read = richParagraphsOf(
        '<p>I. YARGILAMA SÜRECİ<br>Davacı İstemi:<br>Davacı vekili dava '
        'dilekçesinde; müvekkilinin …</p>',
      );
      expect(read[0].isBold, isTrue);
      expect(read[1].isBold, isTrue);
      expect(read[2].isBold, isFalse);
    });

    test('a label in capitals is bold, its value is not', () {
      // Canlı ölçüm: "TARİHİ : 23/06/2011" satırının tamamı kalın çıkıyordu.
      final read = richParagraphsOf(
        '<p>TARİHİ : 23/06/2011<br>MAHKEMESİ :Asliye Hukuk Mahkemesi</p>',
      );
      expect(read[0].runs, [
        const RichRun('TARİHİ :', bold: true),
        const RichRun(' 23/06/2011'),
      ]);
      expect(read[1].runs.first, const RichRun('MAHKEMESİ :', bold: true));
    });

    test('left alone when asked to be', () {
      final read = richParagraphsOf('<p>BİR BAŞLIK</p>', headings: false);
      expect(read.single.isBold, isFalse);
    });
  });

  group('an article laid out from its own shape', () {
    test('the opening is bold and the heading above it too', () {
      final read = articleParagraphsOf(
        'Evlilik birliğinin sarsılması\n'
        'Madde 166- Evlilik birliği, ortak hayatı …',
      );
      expect(read[0].isBold, isTrue);
      expect(read[1].runs.first, const RichRun('Madde 166-', bold: true));
      expect(read[1].alignment, DocAlignment.justify);
    });

    test('an opening alone on its line joins its text', () {
      final read = articleParagraphsOf('MADDE 97-\nKarşılıklı borç …');
      expect(_lines(read), ['MADDE 97- Karşılıklı borç …']);
    });

    test('a line broken mid-sentence is joined again', () {
      // HUMK m.409: "Oturuma çağrılmış olan / tarafların hiçbiri…"
      final read = articleParagraphsOf(
        'MADDE 409- Oturuma çağrılmış olan\ntarafların hiçbiri gelmezse',
      );
      expect(_lines(read), [
        'MADDE 409- Oturuma çağrılmış olan tarafların hiçbiri gelmezse',
      ]);
    });

    test('a bent is not taken for the rest of a sentence', () {
      final read = articleParagraphsOf(
        'MADDE 4- (1) Şunlardır:\na) Birincisi,',
      );
      expect(read, hasLength(2));
    });

    test('an opening is recognised in every form it takes', () {
      for (final text in [
        'MADDE 3- Tanımlar',
        'Madde 89 – Haciz',
        'GEÇİCİ MADDE 1 – Geçiş',
        'Madde 68/a – (Ek: …)',
      ]) {
        expect(
          opensArticle(RichParagraph([RichRun(text)])),
          isTrue,
          reason: text,
        );
      }
      expect(
        opensArticle(const RichParagraph([RichRun('Madde 5/1 saklıdır.')])),
        isFalse,
      );
    });
  });

  group('leaving the app', () {
    test('a document is headed by the reference, bold and centred', () {
      final model = documentOfParagraphs(
        'Yargıtay 3. Hukuk Dairesi, 2021/1 E., 2021/2 K.',
        [
          const RichParagraph([
            RichRun('HÜKÜM', bold: true),
            RichRun(': Onanmasına'),
          ], alignment: DocAlignment.justify),
        ],
      );
      final head = model.blocks.first;
      expect(head.plainText, 'Yargıtay 3. Hukuk Dairesi, 2021/1 E., 2021/2 K.');
      expect(head.alignment, DocAlignment.center);
      expect(head.spans.single.bold, isTrue);
      final body = model.blocks[1];
      expect(body.plainText, 'HÜKÜM: Onanmasına');
      expect(body.alignment, DocAlignment.justify);
      expect(
        [
          for (final span in body.spans)
            (span.startOffset, span.length, span.bold),
        ],
        [(0, 5, true)],
      );
    });

    test('the bank names a chamber alone; a reference names its court', () {
      expect(fullCourtName('15. Hukuk Dairesi'), 'Yargıtay 15. Hukuk Dairesi');
      expect(
        fullCourtName('Hukuk Genel Kurulu'),
        'Yargıtay Hukuk Genel Kurulu',
      );
      expect(fullCourtName('4. Daire'), 'Danıştay 4. Daire');
      expect(
        fullCourtName('Vergi Dava Daireleri Kurulu'),
        'Danıştay Vergi Dava Daireleri Kurulu',
      );
      expect(
        fullCourtName('İstanbul Bölge Adliye Mahkemesi 35. Hukuk Dairesi'),
        'İstanbul Bölge Adliye Mahkemesi 35. Hukuk Dairesi',
      );
    });

    test('a reference is written the way the scanner reads one', () {
      expect(
        decisionReference(
          court: '15. Hukuk Dairesi',
          esas: '2016/1531',
          karar: '2017/3344',
          date: '21.09.2017',
        ),
        'Yargıtay 15. Hukuk Dairesi, 2016/1531 E., 2017/3344 K., 21.09.2017 T.',
      );
    });

    test('a file name leaves out what systems refuse and a final stop', () {
      expect(
        fileNameOf(
          'Yargıtay 15. HD, 2016/1531 E., 2017/3344 K., 21.09.2017 T.',
        ),
        'Yargıtay 15. HD, 2016-1531 E., 2017-3344 K., 21.09.2017 T',
      );
      expect(fileNameOf('???'), '-');
      expect(fileNameOf('   '), 'kaynak');
    });
  });
}
