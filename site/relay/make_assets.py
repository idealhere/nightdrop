"""Prepare the Landing V2 images: clean the cut-outs' edges, crop the icon sheet, and write
compact WebP files into relay2/assets/.

    python make_assets.py <folder with the ten source PNGs named 35.png … 44.png>

35 landing reference   36 app reference     37 logo icon        38 logo horizontal
39 mascot full body    40 hero scene        41 feature icons    42 privacy illustration
43 background light    44 mascot horizontal
The two references (35, 36) are for the eye only and are not published.
"""
import os
import sys

from PIL import Image

SRC = sys.argv[1]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assets')
os.makedirs(OUT, exist_ok=True)


def load(n):
    return Image.open(os.path.join(SRC, '%d.png' % n))


def clean(im, floor=56):
    """Drop the faint halo a background remover leaves: nearly transparent pixels become fully
    transparent, so nothing ghostly shows on a white page."""
    im = im.convert('RGBA')
    alpha = im.getchannel('A').point(lambda a: 0 if a < floor else a)
    im.putalpha(alpha)
    return im


def fit(im, width=None, height=None):
    w, h = im.size
    if width and w > width:
        im = im.resize((width, round(h * width / w)), Image.LANCZOS)
    w, h = im.size
    if height and h > height:
        im = im.resize((round(w * height / h), height), Image.LANCZOS)
    return im


def save(im, name, quality=82):
    path = os.path.join(OUT, name)
    im.save(path, 'WEBP', quality=quality, method=6)
    print('%-22s %4dx%-4d %4d KB' % (name, im.size[0], im.size[1], os.path.getsize(path) // 1024))


def trimmed(im, pad=10):
    box = im.getchannel('A').getbbox()
    if not box:
        return im
    l, t, r, b = box
    return im.crop((max(0, l - pad), max(0, t - pad), min(im.size[0], r + pad), min(im.size[1], b + pad)))


# Cut-outs.
save(fit(trimmed(clean(load(38))), width=720), 'logo-horizontal.webp', 90)
save(fit(trimmed(clean(load(37))), width=384), 'logo-icon.webp', 90)
fit(trimmed(clean(load(37))), width=192).save(os.path.join(OUT, 'icon-192.png'))
save(fit(trimmed(clean(load(39))), height=1000), 'mascot.webp')
save(fit(trimmed(clean(load(42))), width=1000), 'privacy.webp')
save(fit(trimmed(clean(load(44))), width=1000), 'mascot-side.webp')

# Scenes.
save(fit(load(43).convert('RGB'), width=1800), 'background.webp', 74)
save(fit(load(40).convert('RGB'), width=1400), 'hero-scene.webp', 78)

# The icon sheet is a 3 x 2 grid.
sheet = clean(load(41))
w, h = sheet.size
names = ['icon-encrypted', 'icon-identity', 'icon-relay', 'icon-local', 'icon-open', 'icon-files']
for i, name in enumerate(names):
    col, row = i % 3, i // 3
    cell = sheet.crop((col * w // 3, row * h // 2, (col + 1) * w // 3, (row + 1) * h // 2))
    save(fit(trimmed(cell, pad=6), width=240), name + '.webp', 88)
