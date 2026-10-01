"""Writes uyap-document.udf: a synthetic UYAP document, no client data, with
every attribute a paste from UYAP has to carry — a coloured heading, tab stops,
a hanging indent, alignment left to the style, a list, a table, a picture and
line spacing. capture_uyap.sh opens it in UYAP's own editor and saves what
UYAP puts on the clipboard.

    python3 make_uyap_document.py uyap-document.udf
"""
import zipfile, sys, base64, struct, zlib
from xml.sax.saxutils import quoteattr

def png(w, h, rgb):
    raw = b''.join(b'\x00' + bytes(rgb) * w for _ in range(h))
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')

text = ''
def run(kind, t, **a):
    global text
    start = len(text); text += t
    attrs = ' '.join(f'{k}={quoteattr(str(v))}' for k, v in a.items())
    return f'<{kind} {attrs} startOffset="{start}" length="{len(t)}" />'

def para(runs, **a):
    attrs = ' '.join(f'{k}={quoteattr(str(v))}' for k, v in a.items())
    return f'<paragraph {attrs}>' + ''.join(runs) + '</paragraph>'

RED = -4194304  # 0xFFC00000
els = []
els.append(para([run('content', 'ÖRNEK DİLEKÇE BAŞLIĞI\n', bold='true', foreground=RED, size='14')], Alignment='1'))
els.append(para([run('content', 'MAHKEME', bold='true'), run('tab', '\t', bold='true'), run('content', ': Örnek Asliye Hukuk Mahkemesi\n')], TabSet='113.0:0:0', Alignment='0'))
els.append(para([run('content', 'DOSYA NO'), run('tab', '\t'), run('tab', '\t'), run('content', ': 2026/1 Esas\n')], Alignment='0'))
els.append(para([run('content', 'KONU'), run('tab', '\t'), run('content', ': Uzun bir konu satırı ki değer kendi altında devam etsin diye asılı girinti taşır ve iki satıra yayılır.\n')], TabSet='113.0:0:0', Hanging='113.0', Alignment='3'))
els.append(para([run('content', 'Stilden iki yana yaslanan paragraf: hizası kendisinde değil, hvl-default stilinde yazılı.\n', italic='true', family='Arial', size='11')], FirstLineIndent='35.4375'))
els.append(para([run('content', 'Birinci madde metni.\n')], Bulleted='true', BulletType='BULLET_TYPE_ELLIPSE', ListLevel='1', ListId='1', LeftIndent='25.0', Alignment='3'))
els.append(para([run('content', 'İkinci madde, altı çizili ve sarı zeminli bir sözcükle: '), run('content', 'önemli', underline='true', background='-256'), run('content', '.\n')], Bulleted='true', BulletType='BULLET_TYPE_ELLIPSE', ListLevel='1', ListId='1', LeftIndent='25.0', Alignment='3'))
cell = lambda t, **a: '<cell>' + para([run('content', t + '\n', **a)], Alignment='0', LeftIndent='3.0', RightIndent='1.0') + '</cell>'
els.append('<table tableName="Tablo1" columnCount="2" columnSpans="120,280" border="borderCell">'
           '<row rowName="row1" rowType="dataRow">' + cell('Taraf', bold='true') + cell('Değer', bold='true') + '</row>'
           '<row rowName="row2" rowType="dataRow">' + cell('Davacı') + cell('Örnek Kişi') + '</row></table>')
img = base64.b64encode(png(16, 12, (40, 90, 200))).decode()
els.append(para([run('content', 'Görsel: '), run('image', '¸', imageData=img, width='16.0', height='12.0'), run('content', ' e-imzalıdır\n')], Alignment='2'))
els.append(para([run('content', 'Satır aralığı 1,5 olan son paragraf, 12 punto Times New Roman.\n')], LineSpacing='0.5', SpaceAbove='6.0', SpaceBelow='6.0', Alignment='0'))
els.append(para([run('content', '\n')], Alignment='0'))

xml = ('<?xml version="1.0" encoding="UTF-8" ?> \n\n<template format_id="1.8" >\n'
       '<content><![CDATA[' + text + ']]></content>\n'
       '<properties><pageFormat mediaSizeName="1" leftMargin="42.51968479156494" rightMargin="42.51968479156494" topMargin="42.51968479156494" '
       'bottomMargin="42.51968479156494" paperOrientation="1" headerFOffset="20.0" footerFOffset="20.0" /></properties>\n'
       '<elements resolver="hvl-default" >\n' + '\n'.join(els) + '\n</elements>\n'
       '<styles><style name="default" bold="false" italic="false" description="Geçerli" family="Dialog" size="12" '
       'foreground="-13421773" FONT_ATTRIBUTE_KEY="javax.swing.plaf.FontUIResource[family=Dialog,name=Dialog,style=plain,size=12]" />'
       '<style name="hvl-default" description="Gövde" size="12" family="Times New Roman" Alignment="3" /></styles>\n</template>\n')
with zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('content.xml', xml.encode('utf-8'))
print(sys.argv[1], len(text))
