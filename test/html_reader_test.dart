import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/html/html_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// What Word 2016 puts on the clipboard for a few paragraphs: its styles in
/// a stylesheet inside a comment, a tab as a span that counts tabs, a hanging
/// indent as a negative text-indent, and each list item as a paragraph whose
/// bullet is written out between conditional comments.
const _word = '''
<html xmlns:o="urn:schemas-microsoft-com:office:office"
xmlns:w="urn:schemas-microsoft-com:office:word">
<head><meta name=Generator content="Microsoft Word 15">
<style><!--
/* Font Definitions */
@font-face {font-family:"Cambria Math"; panose-1:2 4 5 3 5 4 6 3 2 4;}
/* Style Definitions */
p.MsoNormal, li.MsoNormal, div.MsoNormal
	{margin:0cm; margin-bottom:.0001pt; font-size:12.0pt;
	font-family:"Times New Roman",serif;}
p.MsoListParagraph, li.MsoListParagraph, div.MsoListParagraph
	{margin-top:0cm; margin-right:0cm; margin-bottom:0cm; margin-left:36.0pt;
	font-size:12.0pt; font-family:"Times New Roman",serif;}
@list l0:level1 {mso-level-number-format:bullet; mso-level-text:\\F0B7;}
--></style></head>
<body lang=TR>
<!--StartFragment-->
<p class=MsoNormal align=center style='text-align:center'><b><span
style='font-size:14.0pt;color:#C00000'>DİLEKÇE<o:p></o:p></span></b></p>
<p class=MsoNormal style='margin-left:113.25pt;text-indent:-113.25pt;
tab-stops:113.25pt'>KONU<span style='mso-tab-count:1'>&nbsp;&nbsp;&nbsp;
</span>: Uzun konu</p>
<p class=MsoNormal><o:p>&nbsp;</o:p></p>
<p class=MsoListParagraphCxSpFirst style='text-indent:-18.0pt;mso-list:l0 level1 lfo1'><![if !supportLists]><span
style='font-family:Symbol'><span style='mso-list:Ignore'>·<span
style='font:7.0pt "Times New Roman"'>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
</span></span></span><![endif]>Birinci madde</p>
<p class=MsoListParagraphCxSpLast style='text-indent:-18.0pt;mso-list:l1 level1 lfo2'><![if !supportLists]><span><span
style='mso-list:Ignore'>1.<span style='font:7.0pt "Times New Roman"'>&nbsp;&nbsp;
</span></span></span><![endif]>Numaralı madde</p>
<p class=MsoNormal style='line-height:150%'>Satır aralığı</p>
<!--EndFragment-->
</body></html>''';

/// Google Docs: every run styled inline, the whole copy wrapped in a bold
/// element that says it is not bold, a list item's text in a paragraph
/// inside the item, and a tab in a span that keeps white space.
const _googleDocs =
    '<meta charset="utf-8"><b style="font-weight:normal;" '
    'id="docs-internal-guid-1a2b3c4d"><p dir="ltr" style="line-height:1.38;'
    'margin-top:0pt;margin-bottom:0pt;"><span style="font-size:11pt;'
    'font-family:Arial,sans-serif;color:#000000;background-color:transparent;'
    'font-weight:700;font-style:normal;font-variant:normal;'
    'text-decoration:none;vertical-align:baseline;white-space:pre;'
    'white-space:pre-wrap;">Başlık</span></p><ul style="margin-top:0;'
    'margin-bottom:0;padding-inline-start:48px;"><li dir="ltr" '
    'style="list-style-type:disc;font-size:11pt;font-family:Arial,sans-serif;'
    'color:#000000;background-color:transparent;font-weight:400;'
    'vertical-align:baseline;white-space:pre;" aria-level="1"><p dir="ltr" '
    'style="line-height:1.38;margin-top:0pt;margin-bottom:0pt;" '
    'role="presentation"><span style="font-size:11pt;font-family:Arial,'
    'sans-serif;color:#000000;background-color:transparent;font-weight:400;'
    'white-space:pre-wrap;">Madde</span></p></li></ul><p dir="ltr" '
    'style="line-height:1.38;margin-top:0pt;margin-bottom:0pt;"><span '
    'style="font-size:11pt;font-family:Arial,sans-serif;font-weight:400;'
    'white-space:pre-wrap;">Ad</span><span style="font-size:11pt;'
    'font-family:Arial,sans-serif;font-weight:400;white-space:pre-wrap;">'
    '<span class="Apple-tab-span" style="white-space:pre;">\t</span></span>'
    '<span style="font-size:11pt;font-family:Arial,sans-serif;'
    'font-weight:400;white-space:pre-wrap;">: Değer  iki boşluk</span></p>'
    '</b><br class="Apple-interchange-newline">';

void main() {
  test('Word: styles from a commented stylesheet, tabs, lists, spacing', () {
    final model = HtmlReader.read(_word, clipboard: true);
    final blocks = model.blocks;
    expect(blocks.map((b) => b.plainText), [
      'DİLEKÇE',
      'KONU\t: Uzun konu',
      '',
      'Birinci madde',
      'Numaralı madde',
      'Satır aralığı',
    ]);
    final heading = blocks[0];
    expect(heading.alignment, DocAlignment.center);
    expect(heading.spans.single.bold, isTrue);
    expect(heading.spans.single.fontSize, 14);
    expect(heading.spans.single.color, '#c00000');
    // p.MsoNormal's family, from the rule after the comment in the sheet.
    expect(heading.spans.single.fontFamily, 'Times New Roman');
    // A negative text-indent is a hanging indent; the stop is Word's own.
    expect(blocks[1].hanging, closeTo(113.25, .01));
    expect(blocks[1].leftIndent, 0);
    expect(blocks[1].tabSet, '113.25:0:0');
    expect(model.metadata['tabRules'], 'word');
    // The bullet is read to tell the list's kind, and left out of the text.
    expect(blocks[3].listType, DocListType.unordered);
    expect(blocks[4].listType, DocListType.ordered);
    expect(blocks[5].lineSpacing, 1.5);
    // The whole last paragraph was selected.
    expect(model.metadata['openEnd'], isFalse);
  });

  test('Word: a selection inside one paragraph is open at its end', () {
    const source =
        '<html><body><p class=MsoNormal>Önce <!--StartFragment-->'
        '<b>seçilen</b><!--EndFragment--> sonra</p></body></html>';
    final model = HtmlReader.read(source, clipboard: true);
    expect(model.blocks.single.plainText, 'seçilen');
    expect(model.metadata['openEnd'], isTrue);
  });

  test('Google Docs: inline runs, list items, kept tabs and spaces', () {
    final model = HtmlReader.read(_googleDocs, clipboard: true);
    final blocks = model.blocks;
    // Chrome's closing line break is not a line of the document.
    expect(blocks.map((b) => b.plainText), [
      'Başlık',
      'Madde',
      'Ad\t: Değer  iki boşluk',
    ]);
    // Inline CSS beats the bold wrapper.
    expect(blocks[0].spans.single.bold, isTrue);
    expect(blocks[2].spans.every((s) => !s.bold), isTrue);
    expect(blocks[0].spans.single.fontFamily, 'Arial');
    expect(blocks[0].spans.single.fontSize, 11);
    // Google Docs writes its 1.15 spacing as 1.38.
    expect(blocks[0].lineSpacing, 1.15);
    expect(blocks[1].listType, DocListType.unordered);
    expect(blocks[1].leftIndent, 0);
    // A transparent background is none.
    expect(blocks[0].spans.single.background, isNull);
  });

  test('LibreOffice: align beats its own stylesheet, tabs are tabs', () {
    const source =
        '<html><head><meta name="generator" content="LibreOffice 26.8.0.3 '
        '(Linux)"/><style type="text/css">p { margin-bottom: 0cm; '
        'text-align: start }</style></head><body><p align="center">'
        '<font face="Times New Roman, serif">BAŞLIK</font></p>'
        '<p><font face="Times New Roman, serif">İHTAR\nEDEN\t\t: Ad</font></p>'
        '</body></html>';
    final blocks = HtmlReader.read(source).blocks;
    expect(blocks[0].alignment, DocAlignment.center);
    // A line break in the HTML source is a space; a tab LibreOffice wrote
    // is a tab.
    expect(blocks[1].plainText, 'İHTAR EDEN\t\t: Ad');
    expect(blocks[1].spacingBefore, 0);
  });

  test('a web page: nested margins, generic families, pictures, tables', () {
    const source =
        '<div style="margin-left:20px"><p style="margin:0">İçeride</p></div>'
        '<p style="font-family:-apple-system,BlinkMacSystemFont,sans-serif">'
        'Sistem yazısı</p>'
        '<p><img width="40" height="20" src="data:image/png;base64,'
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="></p>'
        '<table border="1"><tr><td style="width:100px">A</td>'
        '<td style="width:300px;background:#ff0000">B<table><tr><td>İç</td>'
        '</tr></table></td></tr></table>';
    final blocks = HtmlReader.read(source).blocks;
    expect(blocks[0].leftIndent, 15);
    expect(blocks[1].spans.single.fontFamily, 'Arial');
    final picture = blocks.firstWhere((b) => b.imageBase64 != null);
    expect(picture.imageWidth, 30);
    expect(picture.imageHeight, 15);
    final table = blocks.firstWhere((b) => b.table != null).table!;
    // Only its own rows: the nested table stays in its cell.
    expect(table.rows, hasLength(1));
    expect(table.bordered, isTrue);
    expect(table.columnWidths, [75, 225]);
    expect(table.rows.single.cells.last.backgroundColor, '#ff0000');
    expect(
      table.rows.single.cells.last.blocks.any((b) => b.table != null),
      isTrue,
    );
  });

  test('a paragraph of tabs holds its place', () {
    const source =
        '<p style="margin:0"><span style="white-space:pre">\t\t</span></p>'
        '<p style="margin:0">Sonra</p>';
    expect(HtmlReader.read(source).blocks.first.plainText, '\t\t');
  });
}
