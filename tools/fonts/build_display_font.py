#!/usr/bin/env python3
"""Display-Schrift der App aus Archivo Italic (variabel, SIL OFL 1.1) als statische Instanz erzeugen.

Aufruf: python3 tools/fonts/build_display_font.py <Archivo-Italic[wdth,wght].ttf>
Quelle: https://github.com/google/fonts/tree/main/ofl/archivo (Datei „Archivo-Italic[wdth,wght].ttf“, OFL.txt).
Schreibt App/RowCoach/Resources/Fonts/ArchivoExpandedDisplay-Italic.ttf:
- Achsen fest auf wdth 125 (Expanded) und wght 850 – wie die Überschriften der Website (docs/site/index.html);
- Familie „Archivo Expanded Display“, PostScript „ArchivoExpandedDisplay-Italic“ (DSFont.displayName);
- auf Latein (Basis, Latin-1, Latin Extended-A) und typografische Zeichen beschnitten (~70 KB statt 740 KB).
Archivo hat keinen reservierten Schriftnamen (OFL.txt ohne „Reserved Font Name“); die Instanz darf ihn behalten.
Braucht fontTools (auf der Spark vorhanden).
"""
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

OUT = Path(__file__).resolve().parents[2] / 'App' / 'RowCoach' / 'Resources' / 'Fonts' / \
    'ArchivoExpandedDisplay-Italic.ttf'
AXES = {'wdth': 125, 'wght': 850}
FAMILY, STYLE, PS = 'Archivo Expanded Display', 'Italic', 'ArchivoExpandedDisplay-Italic'
UNICODES = (list(range(0x20, 0x7F)) + list(range(0xA0, 0x180)) +
            [0x2009, 0x2013, 0x2014, 0x2018, 0x2019, 0x201A, 0x201C, 0x201D, 0x201E, 0x2022, 0x2026, 0x202F,
             0x2039, 0x203A, 0x20AC, 0x2190, 0x2192, 0x2212])


def main(src):
    font = instancer.instantiateVariableFont(TTFont(src), AXES, inplace=False)
    name = font['name']
    for rec in list(name.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17, 21, 22, 25):
            name.removeNames(nameID=rec.nameID)
    for pid, eid, lid in ((3, 1, 0x409), (1, 0, 0)):
        name.setName(FAMILY, 1, pid, eid, lid)
        name.setName(STYLE, 2, pid, eid, lid)
        name.setName(f'{PS};instance wdth125 wght850 of Archivo Italic (OFL)', 3, pid, eid, lid)
        name.setName(f'{FAMILY} {STYLE}', 4, pid, eid, lid)
        name.setName(PS, 6, pid, eid, lid)
    os2 = font['OS/2']
    os2.usWeightClass, os2.usWidthClass = 800, 7
    os2.fsSelection = (os2.fsSelection & ~0b1100001) | 0b1   # kursiv, weder fett noch regular
    font['head'].macStyle = 0b10
    if 'DSIG' in font:
        del font['DSIG']
    opts = subset.Options()
    opts.layout_features, opts.name_IDs, opts.name_languages = ['*'], ['*'], ['*']
    opts.notdef_outline = True
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=UNICODES)
    sub.subset(font)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)
    print('geschrieben:', OUT, f'({OUT.stat().st_size // 1024} KB)')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
