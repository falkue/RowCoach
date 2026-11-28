#!/usr/bin/env python3
"""App-Symbole „Bahnen“ (Logo-Richtung 2, Entscheid Falk 28.11.2026) für den Asset-Katalog der App erzeugen.

Aufruf: python3 design/logo/bahnen/build_app_icons.py   (braucht nur Pillow; die Formen stehen unten als Polygone,
identisch mit bahnen-icon.svg)
Schreibt nach App/RowCoach/Assets.xcassets:
- AppIcon.appiconset      hell (Kobalt #2340FF), dunkel (Formen auf dunklem Kobalt), getönt (Graustufen auf Schwarz)
- AppIconDev.appiconset   wie AppIcon, mit Band „DEV“ unten (Target RowCoachDev)
- Logo.imageset           Bildmarke auf Kobalt, 512 px (Über RowCoach in den Einstellungen)
Das frühere Symbol liegt unverändert als AppIconAlt.appiconset.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / 'App' / 'RowCoach' / 'Assets.xcassets'
SIZE = 1024
SS = 4  # Überabtastung für glatte Kanten

# Vier Bahnen (Pfeil-Parallelogramme), Koordinaten aus bahnen-icon.svg; die zweite ist die Akzentbahn
LANES = [
    [(191.2, 254.0), (616.6, 254.0), (708.6, 303.0), (616.6, 352.0), (150.0, 352.0)],
    [(263.2, 392.0), (788.6, 392.0), (880.6, 441.0), (788.6, 490.0), (222.0, 490.0)],
    [(227.2, 530.0), (684.6, 530.0), (776.6, 579.0), (684.6, 628.0), (186.0, 628.0)],
    [(173.2, 668.0), (544.6, 668.0), (636.6, 717.0), (544.6, 766.0), (132.0, 766.0)],
]
ACCENT = 1

VARIANTS = {
    # Name: (Hintergrund, Bahnfarbe, Akzentfarbe)
    'light': ('#2340FF', '#FFFFFF', '#FFD60A'),
    'dark': ('#0A1660', '#FFFFFF', '#FFD60A'),
    'tinted': ('#000000', '#FFFFFF', '#BDBDBD'),
}


def render(bg, lane, accent, dev_band=False, size=SIZE):
    big = SIZE * SS
    img = Image.new('RGB', (big, big), bg)
    d = ImageDraw.Draw(img)
    for i, poly in enumerate(LANES):
        d.polygon([(x * SS, y * SS) for x, y in poly], fill=accent if i == ACCENT else lane)
    if dev_band:
        top = int(big * 0.80)
        d.rectangle([0, top, big, big], fill='#FFD60A')
        font = None
        for path in ['/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
                     '/System/Library/Fonts/Supplemental/Arial Bold.ttf']:
            if Path(path).exists():
                font = ImageFont.truetype(path, int(big * 0.13))
                break
        font = font or ImageFont.load_default()
        text = 'DEV'
        box = d.textbbox((0, 0), text, font=font)
        w, h = box[2] - box[0], box[3] - box[1]
        d.text(((big - w) / 2 - box[0], top + (big - top - h) / 2 - box[1]), text, font=font, fill='#0E1A4F')
    return img.resize((size, size), Image.LANCZOS)


def icon_set(name, dev_band=False):
    folder = ASSETS / f'{name}.appiconset'
    folder.mkdir(parents=True, exist_ok=True)
    images = []
    for variant, (bg, lane, accent) in VARIANTS.items():
        fn = f'{name}-{variant}-1024.png'
        render(bg, lane, accent, dev_band=dev_band).save(folder / fn, optimize=True)
        entry = {'filename': fn, 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}
        if variant != 'light':
            entry = {'appearances': [{'appearance': 'luminosity', 'value': variant}], **entry}
        images.append(entry)
    for old in folder.glob('*.png'):
        if old.name not in {i['filename'] for i in images}:
            old.unlink()
    (folder / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}},
                                                     indent=2) + '\n')


def logo():
    folder = ASSETS / 'Logo.imageset'
    for old in folder.glob('*.png'):
        old.unlink()
    bg, lane, accent = VARIANTS['light']
    render(bg, lane, accent, size=512).save(folder / 'Logo-512.png', optimize=True)
    (folder / 'Contents.json').write_text(json.dumps(
        {'images': [{'filename': 'Logo-512.png', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}},
        indent=2) + '\n')


if __name__ == '__main__':
    icon_set('AppIcon')
    icon_set('AppIconDev', dev_band=True)
    logo()
    print('AppIcon, AppIconDev, Logo geschrieben nach', ASSETS)
