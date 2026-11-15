#!/usr/bin/env python3
"""App Store pictures for LifeOS Folio: each scene a headline over the app
in a device, on Folio's blue. The app's own screens come from
tool/screenshots (invented people and cases only), drawn sharp:

  flutter test tool/screenshots/<x>_screens_test.dart \
      --dart-define=ORAN10=30 --dart-define=CIKTI=<phone>
  flutter test tool/screenshots/<x>_screens_test.dart \
      --dart-define=ORAN10=20 --dart-define=GENISLIK=1376 \
      --dart-define=YUKSEKLIK=1032 --dart-define=CIKTI=<ipad>

  python3 tool/appstore/store_images.py <phone> <ipad> <out>

iPhone 6.9" (1320 × 2868) and iPad 13" (2752 × 2064), JPEG.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BOLD = os.path.join(ROOT, 'fonts/ui/Inter-Bold.ttf')
MEDIUM = os.path.join(ROOT, 'fonts/ui/Inter-Medium.ttf')
SEMI = os.path.join(ROOT, 'fonts/ui/Inter-SemiBold.ttf')

# (eyebrow, headline, line under it, phone screen, iPad screen)
SCENES = [
    ('LIFEOS FOLIO', 'Avukatlık işlerinizin hepsini tek uygulamadan yürütün.',
     'UYAP dosyalarınızı, tebligatlarınızı, dilekçelerinizi, ajandanızı, '
     'müvekkillerinizi ve kasanızı Folio’da toplarsınız. Folio ücretsizdir.',
     'telefon-uyap-dosyalarim', 'ofis-anasayfa'),
    ('UYAP', 'Dava dosyalarınızı her yerden açın.',
     'Tarafları, evrakı, duruşmaları ve harçları kendi e-Devlet girişinizle '
     'ya da mobil imzanızla görürsünüz.',
     'telefon-dosya', 'dosya-sayfasi'),
    ('TEBLİGAT', 'Tebligatı siz okuyun, süreyi Folio hesaplasın.',
     'Folio kanun yolu ve itiraz sürelerini dayanak maddesiyle önerir; siz '
     'onaylayınca ajandaya yazar.',
     'telefon-uets-sure-ekle', 'uets'),
    ('YAPAY ZEKÂ', 'Yapay zekâ dosyanızı okuyarak cevap verir.',
     'Kendi API anahtarınızla Gemini, ChatGPT ya da Claude’u kullanırsınız. '
     'Cevabın dayandığı maddeler tek dokunuşla açılır.',
     'yapay-zeka-telefon', 'yapay-zeka'),
    ('UDF EDİTÖRÜ', 'Dilekçenizi Office olmadan yazıp imzalayın.',
     'UDF ve Word belgelerini düzenlersiniz. Atıf yaptığınız maddeler ve '
     'kararlar resmî kaynağından açılır.',
     'bicim-docx-telefon', 'editor-dayanaklar'),
    ('AJANDA', 'Duruşmalarınız, süreleriniz ve görevleriniz aynı takvimde durur.',
     'UYAP’tan gelen duruşmalar ve tebligat süreleri ajandaya kendiliğinden '
     'yerleşir.',
     'telefon-ajanda', 'ajanda'),
    ('MÜVEKKİL VE KASA', 'Müvekkillerinizi, ücretlerinizi ve kasanızı birlikte izleyin.',
     'Dosyaları, ücret sözleşmesini, avansı, masrafı ve tahsilatı müvekkilin '
     'sayfasında görürsünüz.',
     'muvekkil-telefon', 'muvekkil-genis'),
    ('SENKRON', 'Telefonunuz büro bilgisayarınızla her zaman eşit kalır.',
     'Telefonunuz mobil verideyken de eşitlenir. Veriler kendi cihazlarınız '
     'arasında uçtan uca şifreli gider.',
     'senkron-telefon', 'senkron'),
    ('CANLI BELGE', 'Belgenizi canlı paylaşın ve birlikte yazın.',
     'Büro arkadaşınız ya da karşı tarafın vekili belgenizi anında görür. '
     'Kalemi kime vereceğinize siz karar verirsiniz.',
     'canli-telefon', 'canli-izleyen-kalem'),
    ('GİZLİLİK', 'Verileriniz sizin cihazınızda kalır.',
     'Folio’da hesap ve reklam yoktur, belgeleriniz hiçbir sunucuda saklanmaz. '
     'Folio’yu şifreyle kilitleyebilirsiniz.',
     'kilit-telefon', 'kilit'),
]

# Folio's blues, a little apart from scene to scene.
GRADIENTS = [
    ('#0B2A6F', '#2563EB'), ('#0E3A8A', '#3B82F6'), ('#123A7A', '#1D9BF0'),
    ('#1E1B6E', '#4F46E5'), ('#0B2A6F', '#2563EB'), ('#0F3D7A', '#0EA5E9'),
    ('#13306E', '#3B6CF0'), ('#0E2F66', '#2F80ED'), ('#1E1B6E', '#4F46E5'),
    ('#0A1F4D', '#1E40AF'),
]


def rgb(hex_):
    hex_ = hex_.lstrip('#')
    return tuple(int(hex_[k:k + 2], 16) for k in (0, 2, 4))


def background(w, h, a, b):
    """A diagonal from [a] to [b], a soft light high on the right."""
    a, b = rgb(a), rgb(b)
    small = Image.new('RGB', (64, 64))
    px = small.load()
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126
            px[x, y] = tuple(round(a[k] + (b[k] - a[k]) * t) for k in range(3))
    img = small.resize((w, h), Image.BICUBIC)
    glow = Image.new('L', (w, h), 0)
    ImageDraw.Draw(glow).ellipse(
        (w // 2, -h // 4, w + w // 3, h // 3), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(w // 10))
    img.paste(Image.new('RGB', (w, h), (255, 255, 255)), (0, 0), glow)
    return img


def rounded(size, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def device(src, width, radius, bezel, height=None):
    """[src] fitted to [width] (cut at [height]) in a dark rounded device,
    with its shadow: an RGBA picture."""
    shot = Image.open(src).convert('RGB')
    h = round(shot.height * width / shot.width)
    shot = shot.resize((width, h), Image.LANCZOS)
    if height is not None and h > height:
        shot = shot.crop((0, 0, width, height))
    w, h = shot.size
    W, H = w + 2 * bezel, h + 2 * bezel
    pad = 120
    out = Image.new('RGBA', (W + 2 * pad, H + 2 * pad), (0, 0, 0, 0))
    shadow = Image.new('L', out.size, 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (pad, pad + 40, pad + W, pad + H + 40), radius, fill=120)
    shadow = shadow.filter(ImageFilter.GaussianBlur(45))
    out.paste(Image.new('RGBA', out.size, (5, 12, 35, 255)), (0, 0), shadow)
    body = Image.new('RGBA', (W, H), (11, 18, 32, 255))
    out.paste(body, (pad, pad), rounded((W, H), radius))
    out.paste(shot, (pad + bezel, pad + bezel), rounded((w, h), max(radius - bezel, 8)))
    return out, pad


def wrap(draw, words, font, width):
    lines, line = [], ''
    for word in words.split():
        trial = f'{line} {word}'.strip()
        if draw.textlength(trial, font=font) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    lines.append(line)
    return lines


def centered(img, words, font_path, size, color, width, y, gap=1.18):
    """[words] wrapped to [width], centred, from [y]: where it ends."""
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(font_path, size)
    for line in wrap(draw, words, font, width):
        w = draw.textlength(line, font=font)
        draw.text(((img.width - w) / 2, y), line, font=font, fill=color)
        y += round(size * gap)
    return y


def pill(img, words, y, size):
    font = ImageFont.truetype(SEMI, size)
    w = ImageDraw.Draw(img).textlength(words, font=font)
    pw, ph = round(w + size * 1.6), size * 2
    x = (img.width - pw) // 2
    layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle((x, y, x + pw, y + ph), ph // 2, fill=(255, 255, 255, 46))
    draw.text((x + size * 0.8, y + size * 0.42), words, font=font,
              fill=(255, 255, 255, 255))
    img.alpha_composite(layer)
    return y + ph


def compose(size, scene_i, eyebrow, head, sub, src, device_args, top, sizes):
    W, H = size
    a, b = GRADIENTS[scene_i]
    img = background(W, H, a, b).convert('RGBA')
    pill_size, head_size, sub_size, text_w = sizes
    y = pill(img, eyebrow, top, pill_size) + round(pill_size * 1.2)
    y = centered(img, head, BOLD, head_size, 'white', text_w, y, 1.12)
    y = centered(img, sub, MEDIUM, sub_size, (220, 231, 255), text_w * 0.95,
                 y + round(sub_size * 0.5), 1.3)
    dev, pad = device(src, *device_args)
    img.alpha_composite(dev, ((W - dev.width) // 2, y + round(sub_size * 1.2) - pad))
    return img.convert('RGB')


def iphone(i, scene, src, out):
    eyebrow, head, sub, phone, _ = scene
    img = compose((1320, 2868), i, eyebrow, head, sub,
                  os.path.join(src, phone + '.png'), (1000, 120, 26),
                  150, (34, 92, 44, 1120))
    img.save(out, quality=92)


def ipad(i, scene, src, out):
    eyebrow, head, sub, _, tablet = scene
    img = compose((2752, 2064), i, eyebrow, head, sub,
                  os.path.join(src, tablet + '.png'), (2160, 60, 34, 1640),
                  90, (32, 96, 46, 2300))
    img.save(out, quality=92)


def main():
    phone_dir, ipad_dir, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    only = set(sys.argv[4:])
    for i, scene in enumerate(SCENES):
        n = f'{i + 1:02d}'
        if only and n not in only:
            continue
        iphone(i, scene, phone_dir, f'{out}/iphone-{n}.jpg')
        ipad(i, scene, ipad_dir, f'{out}/ipad-{n}.jpg')
        print(n, scene[1])


if __name__ == '__main__':
    main()
