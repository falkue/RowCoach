#!/usr/bin/env python3
"""Erzeugt App/RowCoach/Resources/Localizable.xcstrings (Quelle Deutsch, Übersetzung Englisch) und
App/RowCoach/Resources/InfoPlist.xcstrings.

Aufruf (im Repo-Wurzelordner): python3 App/l10n/build_catalog.py [--check]
- Schlüssel: alles, was swift_strings.py als lokalisiert erkennt (App und RowCoachKit), plus alle Schlüssel aus
  en_strings.py. Alle Einträge stehen auf extractionState "manual", damit Xcode sie nie als veraltet entfernt (die
  Schlüssel aus RowCoachKit findet Xcode nicht selbst; sie werden zur Laufzeit im Bundle der App gesucht).
- Übersetzungen: en_strings.py (Text oder {"one", "other"} für Mehrzahl).
- --check: nur melden, welche Schlüssel noch keine Übersetzung haben (Exit-Code 1, wenn welche fehlen).
Nach Änderungen an Texten im Code: Skript laufen lassen, fehlende Übersetzungen in en_strings.py ergänzen.
Xcode ergänzt beim Bauen selbst neu gefundene Schlüssel (dann ohne englischen Text: im Catalog nachtragen oder hier).
"""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from en_strings import EN  # noqa: E402
import swift_strings  # noqa: E402

RES = HERE.parent / 'RowCoach' / 'Resources'

INFO_PLIST = {
    'CFBundleDisplayName': ('RowCoach', 'RowCoach'),
    'NSBluetoothAlwaysUsageDescription': (
        'RowCoach verbindet sich mit dem Concept2-PM5 und dem Pulsgurt.',
        'RowCoach connects to the Concept2 PM5 and your heart rate strap.'),
    'NSHealthShareUsageDescription': (
        'RowCoach liest Trainings und Puls, um deine Einheiten auszuwerten.',
        'RowCoach reads workouts and heart rate to analyse your sessions.'),
    'NSHealthUpdateUsageDescription': (
        'RowCoach speichert deine Rudereinheiten als Training in Apple Health.',
        'RowCoach saves your rowing sessions as workouts in Apple Health.'),
}


def unit(value):
    return {'stringUnit': {'state': 'translated', 'value': value}}


def localization(value):
    if isinstance(value, dict):
        return {'variations': {'plural': {k: unit(v) for k, v in value.items()}}}
    return unit(value)


def scanned_keys():
    files = swift_strings.files([str(HERE.parent / 'RowCoach'), str(HERE.parent / 'RowCoachKit' / 'Sources')])
    keys = {}
    for p, ln, kind, key, interps, line in swift_strings.scan(files):
        if kind == 'localized':
            keys.setdefault(key, f'{p}:{ln}')
    return keys


def main():
    check = '--check' in sys.argv
    keys = scanned_keys()
    missing = [k for k in keys if k not in EN]
    if missing:
        print(f'{len(missing)} Schlüssel ohne englische Übersetzung:')
        for k in missing:
            print(f'  {k!r}    ({keys[k]})')
    if check:
        sys.exit(1 if missing else 0)

    strings = {}
    for k in sorted(set(keys) | set(EN), key=str.lower):
        entry = {'extractionState': 'manual'}
        if k in EN:
            entry['localizations'] = {'en': localization(EN[k])}
            # Mehrzahl auch im Deutschen (Quelltext „%lld Fahrten“ → „1 Fahrt“)
            if isinstance(EN[k], dict):
                entry['localizations']['de'] = localization(GERMAN_PLURAL.get(k, {'other': k}))
        strings[k] = entry
    catalog = {'sourceLanguage': 'de', 'strings': strings, 'version': '1.0'}
    (RES / 'Localizable.xcstrings').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n',
                                               encoding='utf-8')
    info = {'sourceLanguage': 'de', 'version': '1.0', 'strings': {
        k: {'comment': 'Info.plist', 'extractionState': 'manual',
            'localizations': {'de': unit(de), 'en': unit(en)}} for k, (de, en) in INFO_PLIST.items()}}
    (RES / 'InfoPlist.xcstrings').write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Localizable.xcstrings: {len(strings)} Schlüssel ({len(missing)} ohne Englisch); InfoPlist.xcstrings: '
          f'{len(INFO_PLIST)} Schlüssel')


# Deutsche Mehrzahl für Schlüssel mit Mehrzahl im Englischen
GERMAN_PLURAL = {
    'Noch %lld Sekunden – gleich geschafft.': {'one': 'Noch %lld Sekunde – gleich geschafft.',
                                              'other': 'Noch %lld Sekunden – gleich geschafft.'},
    'Noch %lld Sekunden – gleich Intervall.': {'one': 'Noch %lld Sekunde – gleich Intervall.',
                                              'other': 'Noch %lld Sekunden – gleich Intervall.'},
    'Noch %lld Sekunden – gleich Pause.': {'one': 'Noch %lld Sekunde – gleich Pause.',
                                          'other': 'Noch %lld Sekunden – gleich Pause.'},
    'Noch %lld Sekunden – gleich Ausrudern.': {'one': 'Noch %lld Sekunde – gleich Ausrudern.',
                                              'other': 'Noch %lld Sekunden – gleich Ausrudern.'},
    'Pause, %lld Meter.': {'one': 'Pause, %lld Meter.', 'other': 'Pause, %lld Meter.'},
    'Noch %lld Meter.': {'one': 'Noch %lld Meter.', 'other': 'Noch %lld Meter.'},
    '%lld Fahrten': {'one': '%lld Fahrt', 'other': '%lld Fahrten'},
    '%lld Strecken offen': {'one': '%lld Strecke offen', 'other': '%lld Strecken offen'},
    'Wochenziel erreicht: %lld Fahrten': {'one': 'Wochenziel erreicht: %lld Fahrt',
                                          'other': 'Wochenziel erreicht: %lld Fahrten'},
    '1 Woche mit %lld Fahrten': {'one': '1 Woche mit %lld Fahrt', 'other': '1 Woche mit %lld Fahrten'},
    'Neue Woche · letzte: %lld Fahrten': {'one': 'Neue Woche · letzte: %lld Fahrt',
                                          'other': 'Neue Woche · letzte: %lld Fahrten'},
    '%lld Wochen in Folge': {'one': '%lld Woche in Folge', 'other': '%lld Wochen in Folge'},
    'Wochenziel: %lld Fahrten': {'one': 'Wochenziel: %lld Fahrt', 'other': 'Wochenziel: %lld Fahrten'},
    '%lld Schläge': {'one': '%lld Schlag', 'other': '%lld Schläge'},
    'vor %lld Tagen': {'one': 'vor %lld Tag', 'other': 'vor %lld Tagen'},
}

if __name__ == '__main__':
    main()
