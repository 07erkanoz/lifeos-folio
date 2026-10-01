"""Writes synthetic UDFs, no client data, each built to show one of UYAP's
page rules: how many lines a page holds, what happens to a paragraph that
crosses the bottom, to space above at the top of a page, to a table row,
and what a header and footer take. capture_pages.sh measures them in UYAP.

    python3 make_page_documents.py OUTDIR
"""
import os, sys, zipfile
from xml.sax.saxutils import quoteattr

WORDS = ('dava dilekçesi ekinde sunulan belgeler ile tanık beyanları birlikte '
         'değerlendirildiğinde davalının kusurlu olduğu açıkça anlaşılmaktadır').split()

def sentence(n, seed=0):
    return ' '.join(WORDS[(seed + i) % len(WORDS)] for i in range(n))

class Doc:
    def __init__(self):
        self.text = ''
        self.els = []
    def run(self, t, kind='content', **a):
        start = len(self.text); self.text += t
        attrs = ' '.join(f'{k}={quoteattr(str(v))}' for k, v in a.items())
        return f'<{kind} {attrs} startOffset="{start}" length="{len(t)}" />'
    def para(self, t, **a):
        attrs = ' '.join(f'{k}={quoteattr(str(v))}' for k, v in a.items())
        self.els.append(f'<paragraph {attrs}>' + self.run(t + '\n') + '</paragraph>')
    def table(self, rows, cols=2, **a):
        cell = lambda t: '<cell><paragraph Alignment="0">' + self.run(t + '\n') + '</paragraph></cell>'
        body = ''.join('<row rowName="r%d" rowType="dataRow">' % i + ''.join(cell(c) for c in r) + '</row>'
                       for i, r in enumerate(rows))
        self.els.append(f'<table tableName="T" columnCount="{cols}" columnSpans="{",".join(["200"] * cols)}" border="borderCell">{body}</table>')
    def region(self, tag, lines, extra=''):
        paras = ''.join('<paragraph Alignment="0">' + self.run(t + '\n') + '</paragraph>' for t in lines)
        return f'<{tag}{extra}>{paras}</{tag}>'
    def write(self, path, header=None, footer=None, margin=70.866):
        regions = footer_xml = ''
        if header:
            regions += self.region('header', header)
        if footer:
            # Last among the elements, where UYAP writes it and where its
            # layout expects it: first after the header, it is laid out as
            # the body's first paragraph.
            footer_xml = self.region('footer', footer,
                ' pageNumber-spec="BSP32_2088" pageNumber-seperator="/" pageNumber-fontBold="true" '
                'pageNumber-fontItalic="false" pageNumber-fontFace="Arial" pageNumber-fontSize="9" '
                'pageNumber-color="-16777216" pageNumber-foreStr="" pageNumber-pageStartNumStr=""')
        xml = ('<?xml version="1.0" encoding="UTF-8" ?> \n\n<template format_id="1.8" >\n'
               '<content><![CDATA[' + self.text + ']]></content>\n'
               f'<properties><pageFormat mediaSizeName="1" leftMargin="{margin}" rightMargin="{margin}" topMargin="{margin}" '
               f'bottomMargin="{margin}" paperOrientation="1" headerFOffset="20.0" footerFOffset="20.0" /></properties>\n'
               '<elements resolver="hvl-default" >\n' + regions + '\n'.join(self.els) + footer_xml + '\n</elements>\n'
               '<styles><style name="default" bold="false" italic="false" description="Geçerli" family="Dialog" size="12" '
               'foreground="-13421773" FONT_ATTRIBUTE_KEY="javax.swing.plaf.FontUIResource[family=Dialog,name=Dialog,style=plain,size=12]" />'
               '<style name="hvl-default" description="Gövde" size="12" family="Times New Roman" /></styles>\n</template>\n')
        with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('content.xml', xml.encode('utf-8'))

out = sys.argv[1]; os.makedirs(out, exist_ok=True)

# 1. Lines per page: 80 one-line paragraphs.
d = Doc()
for i in range(80): d.para(f'Satır {i + 1:02d} ' + sentence(4, i))
d.write(f'{out}/01-satirlar.udf')

def filler(d, n, tag='Satır'):
    for i in range(n): d.para(f'{tag} {i + 1:02d} ' + sentence(4, i))

LONG = 'Uzun paragraf ' + sentence(150)  # about ten rows at 12 pt

# 2. A ten-row paragraph that starts five rows above the bottom.
d = Doc(); filler(d, 45); d.para(LONG); filler(d, 5, 'Sonra'); d.write(f'{out}/02-bolunen.udf')
# 3. Only its first row fits on the page: is one row left alone?
d = Doc(); filler(d, 49); d.para(LONG); d.write(f'{out}/03-yetim.udf')
# 4. All but its last row fits: does one row go on alone?
d = Doc(); filler(d, 41); d.para(LONG); filler(d, 3, 'Sonra'); d.write(f'{out}/04-dul.udf')
# 5. Space above a paragraph that starts page 2, and space below one that ends page 1.
d = Doc(); filler(d, 49); d.para('Altında boşluk olan son satır', SpaceBelow='20.0'); d.para('Üstünde boşluk olan ilk satır', SpaceAbove='20.0'); filler(d, 3, 'Sonra'); d.write(f'{out}/05-aralik.udf')
# 6. Space above that no longer fits on page 1, and one that just fits.
d = Doc(); filler(d, 48); d.para('Aralıklı satır A', SpaceAbove='10.0'); d.para('Aralıklı satır B', SpaceAbove='10.0'); filler(d, 3, 'Sonra'); d.write(f'{out}/06-aralik-sigmayan.udf')
# 7. A table whose rows cross the bottom.
d = Doc(); filler(d, 45); d.table([[f'Hücre {i} a', f'Hücre {i} b'] for i in range(10)]); filler(d, 3, 'Sonra'); d.write(f'{out}/07-tablo.udf')
# 8. Line spacing 1.5 throughout.
d = Doc()
for i in range(60): d.para(f'Satır {i + 1:02d} ' + sentence(4, i), LineSpacing='0.5')
d.write(f'{out}/08-aralik15.udf')
# 9. Empty paragraphs at the bottom and the top.
d = Doc(); filler(d, 48)
for _ in range(4): d.para('')
filler(d, 3, 'Sonra'); d.write(f'{out}/09-bos.udf')
# 10. A table taller than what is left and a row taller than one line.
d = Doc(); filler(d, 46); d.table([['Kısa', sentence(40)], ['Kısa 2', 'b']]); filler(d, 3, 'Sonra'); d.write(f'{out}/10-tablo-uzun-hucre.udf')

# 11. A one-line header and a footer with page numbers.
d = Doc(); filler(d, 80); d.write(f'{out}/11-ust-alt.udf', header=['Üst bilgi satırı'], footer=['Alt bilgi satırı'])
# 12. A three-line header, and small margins.
d = Doc(); filler(d, 80); d.write(f'{out}/12-uc-satir-ust.udf', header=['Birinci', 'İkinci', 'Üçüncü'], margin=28.35)

# 13. Row heights: two-row paragraphs in each size, font and line spacing.
d = Doc()
for family in ('Times New Roman', 'Arial'):
    for size in (8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 24):
        for spacing in ('0.0', '0.2', '0.5', '1.0'):
            start = len(d.text); t = f'{family} {size} {spacing} ' + sentence(40, size) + '\n'
            d.text += t
            d.els.append(f'<paragraph LineSpacing="{spacing}"><content family={quoteattr(family)} size="{size}" startOffset="{start}" length="{len(t)}" /></paragraph>')
d.write(f'{out}/13-satir-yukseklik.udf')

# 14. A three-line footer that does not fit in a small bottom margin.
d = Doc(); filler(d, 80); d.write(f'{out}/14-uc-satir-alt.udf', footer=['Birinci', 'İkinci', 'Üçüncü'], margin=28.35)

# 15. Glyph advances: do rows break as if each letter were a whole number
# of points wide? "e " is 5.33 + 3 points in Times at 12, "a " the same,
# "m " 9.33 + 3.
d = Doc()
for letter in ('e', 'm', 'ş', 'W'):
    d.para(' '.join([letter] * 160))
    d.para(' '.join([letter * 3] * 60))
d.write(f'{out}/15-harf-genislik.udf')
