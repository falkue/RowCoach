#!/usr/bin/env python3
"""Zieht die Quellenangaben nach der Lizenzprüfung (docs/LIZENZEN-GEODATEN.md) nach: Copernicus-Wortlaut nach
Lizenz Art. 6(b), OSM mit Lizenzlink, dl-de/by-2-0 mit „Daten geändert“. Ändert das Feld "attribution" in
tools/coursebuilder/areas/*.json (Quelle für export.py) sowie in courses/*/course.json und App/Courses/*/course.json.

Aufruf (Repo-Wurzel): python3 tools/coursebuilder/fix_attribution.py [--check]
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COPERNICUS = ('produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH '
              '2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved')


def fix(text):
    t = text
    # Copernicus DEM GLO-30, © DLR … bereitgestellt unter COPERNICUS von der Europäischen Union und der ESA
    t = re.sub(r'Copernicus DEM GLO-30, © DLR e\.V\. 2010.2014 und © Airbus Defence and Space GmbH 2014.2018, '
               r'bereitgestellt unter COPERNICUS von der Europäischen Union und der ESA', COPERNICUS, t)
    # OSM: Lizenzlink
    t = re.sub(r'© OpenStreetMap contributors \(ODbL\)(?! – openstreetmap\.org/copyright)',
               '© OpenStreetMap contributors (ODbL) – openstreetmap.org/copyright', t)
    # dl-de/by-2-0: Daten geändert
    t = re.sub(r'dl-de/by-2-0(?!, Daten geändert)', 'dl-de/by-2-0, Daten geändert', t)
    t = re.sub(r'Datenlizenz Deutschland – Namensnennung – 2\.0(?!, Daten geändert)',
               'Datenlizenz Deutschland – Namensnennung – 2.0, Daten geändert', t)
    return t


def process(path):
    raw = path.read_text()
    d = json.loads(raw)
    a = d.get('attribution')
    if not isinstance(a, str):
        return False
    new = fix(a)
    if new == a:
        return False
    d['attribution'] = new
    if '\n' in raw.strip():
        indent = len(raw.split('\n')[1]) - len(raw.split('\n')[1].lstrip())
        out = json.dumps(d, ensure_ascii=False, indent=indent or 2) + '\n'
    else:
        out = json.dumps(d, ensure_ascii=False) + ('\n' if raw.endswith('\n') else '')
    if '--check' not in sys.argv:
        path.write_text(out)
    return True


def main():
    files = sorted(ROOT.glob('tools/coursebuilder/areas/*.json')) + sorted(ROOT.glob('courses/*/course.json')) \
        + sorted(ROOT.glob('App/Courses/*/course.json'))
    changed = [f for f in files if process(f)]
    for f in changed:
        print('geändert:', f.relative_to(ROOT))
    print(f'{len(changed)} Dateien')


if __name__ == '__main__':
    main()
