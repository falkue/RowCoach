#!/usr/bin/env python3
"""Bildmarke „Bahnen“ für den Startbildschirm (UILaunchScreen) erzeugen.

Aufruf: python3 design/logo/bahnen/build_launch_mark.py   (braucht nur Pillow; Formen aus build_app_icons.py)
Schreibt App/RowCoach/Assets.xcassets/LaunchMark.imageset: weisse Bahnen, zweite Bahn gelb, transparenter Grund,
auf den Inhalt zugeschnitten, 120 pt breit (@2x, @3x). Der Startbildschirm zeigt sie mittig auf
LaunchBackground (Kobalt #2340FF); beides steht in project.yml unter UILaunchScreen.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw

from build_app_icons import ACCENT, ASSETS, LANES

WIDTH_PT = 120
SS = 8  # Überabtastung für glatte Kanten
X0, Y0 = 132.0, 254.0          # Inhalt der Bildmarke in Logo-Koordinaten
W, H = 880.6 - X0, 766.0 - Y0


def render(scale):
    w = round(WIDTH_PT * scale)
    h = round(w * H / W)
    f = w * SS / W
    big = Image.new('RGBA', (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    for i, poly in enumerate(LANES):
        d.polygon([((x - X0) * f, (y - Y0) * f) for x, y in poly],
                  fill='#FFD60A' if i == ACCENT else '#FFFFFF')
    return big.resize((w, h), Image.LANCZOS)


def main():
    out = ASSETS / 'LaunchMark.imageset'
    out.mkdir(exist_ok=True)
    images = []
    for scale in (2, 3):
        name = f'LaunchMark@{scale}x.png'
        render(scale).save(out / name, optimize=True)
        images.append({'filename': name, 'idiom': 'universal', 'scale': f'{scale}x'})
    images.insert(0, {'idiom': 'universal', 'scale': '1x'})
    (out / 'Contents.json').write_text(json.dumps(
        {'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
    print('geschrieben:', out)


if __name__ == '__main__':
    main()
