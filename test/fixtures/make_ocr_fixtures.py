#!/usr/bin/env python3
"""The scanned fixtures OCR is tested against, made from invented text.

Every name, court and number in them is made up. The text carries the
Turkish letters a byte-per-character decoding would mangle (İ, ı, ş, ğ, ç,
Ç, Ş) so that the tests see the mistake if it comes back.

    python3 test/fixtures/make_ocr_fixtures.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

LINES = [
    'ÖRNEK 3. AİLE MAHKEMESİNE',
    'DOSYA NO : 2026/123 E.',
    'Müvekkilimiz aleyhine açılan davanın',
    'reddini saygıyla arz ve talep ederiz.',
    'Vekili: Av. Çiğdem Şenoğlu',
]
FONT = '/usr/share/fonts/liberation/LiberationSerif-Regular.ttf'
HERE = Path(__file__).parent


def page(width, height, size, top, left):
    image = Image.new('L', (width, height), 255)
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(FONT, size)
    y = top
    for line in LINES:
        draw.text((left, y), line, font=font, fill=0)
        y += int(size * 1.45)
    return image


strip = page(1240, 340, 40, 20, 40)
strip.save(HERE / 'ocr_taranmis.png', optimize=True)
strip.save(
    HERE / 'ocr_cok_sayfali.tif',
    save_all=True,
    append_images=[strip, strip],
    compression='tiff_lzw',
)
# An A4 page scanned at 200 dpi, as a scanner's PDF holds it: one JPEG.
page(1654, 2339, 44, 160, 160).convert('RGB').save(
    HERE / 'ocr_taranmis.pdf', resolution=200.0, quality=85
)
