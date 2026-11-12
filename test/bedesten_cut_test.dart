import 'package:evrak_convert/services/legal/bedesten_legislation.dart';
import 'package:evrak_convert/services/legal/citation.dart';
import 'package:evrak_convert/services/legal/rich_text.dart';
import 'package:flutter_test/flutter_test.dart';

RichParagraph plain(String t) => RichParagraph([RichRun(t)]);
RichParagraph bold(String t, [String mark = '']) =>
    RichParagraph([RichRun(t, bold: true), if (mark.isNotEmpty) RichRun(mark)]);

List<String> cut(List<RichParagraph> page, int article) => [
  for (final p in cutArticle(
    page,
    Citation(law: Law.numbered(2577), article: article, start: 0, length: 1),
  )!.body)
    p.text,
];

void main() {
  test('the next article\'s heading and its note do not end this one', () {
    // İYUK m. 36's node, as the bank gives it.
    final got = cut([
      plain(
        'Madde 36 – İdari sözleşmelerden doğanlar dışında kalan tam '
        'yargı davalarında yetkili mahkeme, sırasıyla:',
      ),
      plain(
        'c) Diğer hallerde davacının ikametgahının bulunduğu yer '
        'idare mahkemesidir.[27]',
      ),
      bold('Vergi uyuşmazlıklarında yetki:', '[28]'),
      plain('[27] Bu maddenin kendi notu.'),
      plain(
        '[28] 10/6/1994 tarihli ve 4001 sayılı Kanunun 17 nci maddesiyle '
        'bu maddeye (b) bendi eklenmiştir.',
      ),
    ], 36);
    expect(got.last, '[27] Bu maddenin kendi notu.');
    expect(got.join('\n'), isNot(contains('Vergi uyuşmazlıklarında')));
    expect(got.join('\n'), isNot(contains('[28]')));
  });

  test('a heading alone at the foot goes, as before', () {
    final got = cut([
      plain(
        'Madde 35 – Taşınır mallara ilişkin davalarda yetkili mahkeme, '
        'taşınır malın bulunduğu yer idare mahkemesidir.',
      ),
      bold('Tam yargı davalarında yetki:'),
    ], 35);
    expect(got, hasLength(1));
  });

  test('an article\'s own notes stay when no heading follows it', () {
    final got = cut([
      plain('Madde 20 – Hükmolunur.[15]'),
      plain('[15] 5728 sayılı Kanunun 419 uncu maddesiyle değiştirilmiştir.'),
    ], 20);
    expect(got, hasLength(2));
  });
}
