#!/usr/bin/env python3
"""Macht plans.json (und docs/trainings-recherche.json) zweisprachig: name, summary, purpose, level, category und
die Phasen-Bezeichnungen werden zu {"de": …, "en": …}. Bereits zweisprachige Felder bleiben, wie sie sind.

Aufruf (im Repo-Wurzelordner): python3 App/l10n/plans_en.py
Neue deutsche Texte in EN unten ergänzen (Phasen mit Zähler „(1/4)“ werden über das Muster übersetzt).
"""
import json
import re
from pathlib import Path

EN = {
    'Lockere Grundlage 30 Minuten': 'Easy steady state 30 minutes',
    '30 Minuten gleichmässig im Gesprächstempo bei niedriger Schlagzahl rudern.':
        'Row 30 minutes evenly at conversational pace and a low stroke rate.',
    'UT2 / aerobe Grundlage, Gesprächstempo (Puls ca. 60-70 % HFmax, Pulszone 2)':
        'UT2 / aerobic base, conversational pace (heart rate about 60-70 % of max, zone 2)',
    'Einsteiger': 'Beginner',
    'Fortgeschritten': 'Advanced',
    'Grundlage': 'Steady state',
    'Schwelle': 'Threshold',
    'Intervalle': 'Intervals',
    'Technik & Rhythmus': 'Technique & rhythm',
    'Sprint': 'Sprint',
    'Test': 'Test',
    'Einrudern: locker, steigernd, am Ende kurze Antritte': 'Warm-up: easy, building, a few short bursts at the end',
    'Grundlage UT2, Gesprächstempo, Schlagzahl 18-20': 'Steady state UT2, conversational pace, rate 18-20',
    'Ausrudern: ganz locker': 'Cool-down: very easy',
    'Ausrudern: moderat': 'Cool-down: moderate',
    'Grundlage in 3 Blöcken, Schlagzahl 20': 'Steady state in 3 blocks, rate 20',
    'Drei Blöcke zu 10 Minuten konstant bei Schlagzahl 20 mit kurzer Pause, damit Rhythmus und Frequenz geübt werden.':
        'Three 10-minute blocks held at rate 20 with a short rest, to practise rhythm and rate control.',
    'UT2 mit Frequenzvorgabe (Puls ca. 60-70 % HFmax, Pulszone 2)':
        'UT2 with a set stroke rate (heart rate about 60-70 % of max, zone 2)',
    'Pause: locker weiterrudern': 'Rest: keep paddling easy',
    'Pause: 1 min locker paddeln': 'Rest: 1 min easy paddling',
    'Schwelle 4 x 6 Minuten': 'Threshold 4 x 6 minutes',
    "Vier Blöcke zu 6 Minuten im 'angenehm unangenehmen' Bereich knapp unter dem Tempo für 5000–6000 m.":
        "Four 6-minute pieces in the 'comfortably uncomfortable' zone, just under your 5000–6000 m pace.",
    'Schwelle / AT (Puls ca. 80-85 % HFmax, Pulszone 4)': 'Threshold / AT (heart rate about 80-85 % of max, zone 4)',
    'Kurzintervalle 8 x 2 Minuten': 'Short intervals 8 x 2 minutes',
    'Acht Intervalle zu 2 Minuten im 2000-m-Tempo mit je 1 Minute lockerer Pause.':
        'Eight 2-minute intervals at 2000 m pace with 1 minute easy rest each.',
    'VO2max / Sauerstoffaufnahme (Puls 90 % HFmax und mehr, Pulszone 4-5)':
        'VO2max / oxygen uptake (heart rate 90 % of max and above, zone 4-5)',
    'Langintervalle 4 x 4 Minuten': 'Long intervals 4 x 4 minutes',
    'Vier Intervalle zu 4 Minuten im 2000-m-Tempo (innerhalb 2 s) mit 1 Minute lockerer Pause.':
        'Four 4-minute intervals at 2000 m pace (within 2 s) with 1 minute easy rest.',
    'Intervall nahe dem 2000-m-Tempo / Sauerstofftransport TR (Pulszone 4-5)':
        'Intervals near 2000 m pace / oxygen transport TR (zone 4-5)',
    'Einrudern: steigernd, 3 x 10 Schläge bei 24/28/32': 'Warm-up: building, 3 x 10 strokes at rate 24/28/32',
    'Zeit-Pyramide 1-2-3-4-3-2-1': 'Time pyramid 1-2-3-4-3-2-1',
    'Intervalle von 1, 2, 3, 4, 3, 2, 1 Minute mit je 1 Minute lockerer Pause, Tempo steigt von 2000-m-Tempo + 3 s auf 2000-m-Tempo − 3 s.':
        'Intervals of 1, 2, 3, 4, 3, 2, 1 minutes with 1 minute easy rest each; pace builds from 2000 m pace + 3 s to 2000 m pace − 3 s.',
    'Mischtraining Schwelle bis VO2max (Pulszone 3-5), auch mit Spassfaktor für Freizeit':
        'Mixed threshold to VO2max session (zone 3-5), fun for recreational rowers too',
    'Frequenzleiter 18-20-22-24': 'Rate ladder 18-20-22-24',
    '20 Minuten ohne Pause: alle 1-4 Minuten um 2 Schläge pro Minute höher bis 24, dann wieder herunter, Tempo bleibt gleich.':
        '20 minutes without a break: every 1-4 minutes go up 2 strokes per minute to 24, then back down; the split stays the same.',
    'Frequenz- und Rhythmusgefühl, UT1 (Puls ca. 70-80 % HFmax, Pulszone 3)':
        'Feel for rate and rhythm, UT1 (heart rate about 70-80 % of max, zone 3)',
    'Sprint 8 x 250 m': 'Sprint 8 x 250 m',
    'Acht kurze Sprints über 250 m bei hoher Schlagzahl mit je 1 Minute lockerer Pause.':
        'Eight short 250 m sprints at a high stroke rate with 1 minute easy rest each.',
    'Anaerob / Schnelligkeit (Pulszone 5)': 'Anaerobic / speed (zone 5)',
    'Test 2000 m': '2000 m test',
    '2000 m auf Bestzeit nach gründlichem Einrudern, gleichmässig oder mit negativem Split.':
        '2000 m for a best time after a thorough warm-up, evenly paced or with a negative split.',
    'Leistungstest / Referenz für alle Tempoangaben (Pulszone 5)': 'Performance test / reference for all pace targets (zone 5)',
    'Einrudern 8 min: steigernd, am Ende 3 kurze Antritte': 'Warm-up 8 min: building, 3 short bursts at the end',
    '2000 m Bestzeit: ersten 500 m 1-2 s langsamer als Ziel, dann steigern':
        '2000 m best time: first 500 m 1-2 s slower than target, then build',
    'Technik und Regeneration 25 Minuten': 'Technique and recovery 25 minutes',
    'Sehr lockeres Rudern bei niedriger Schlagzahl mit Technikfokus und kurzen Kraftimpulsen (20 kräftige Schläge) alle 5 Minuten.':
        'Very easy rowing at a low stroke rate with a technique focus and short power bursts (20 strong strokes) every 5 minutes.',
    'Technik / Regeneration, UT2 oder leichter (Pulszone 1-2)': 'Technique / recovery, UT2 or easier (zone 1-2)',
}

PATTERNS = [
    (r'^Block UT2 bei Schlagzahl 20 \((\d+/\d+)\)$', r'UT2 block at rate 20 (\1)'),
    (r'^Schwelle AT, Schlagzahl 20-22 \((\d+/\d+)\)$', r'Threshold AT, rate 20-22 (\1)'),
    (r'^Intervall (\d+) min im 2000-m-Tempo \((\d+/\d+)\)$', r'Interval \1 min at 2000 m pace (\2)'),
    (r'^Pyramide (\d+) min \(Stufe (\d+/\d+)\), Tempo startet 3 s langsamer als das 2000-m-Tempo und steigert bis 3 s schneller$',
     r'Pyramid \1 min (step \2), start 3 s slower than 2000 m pace and build to 3 s faster'),
    (r'^Frequenzleiter (\d+) min bei Schlagzahl (\d+), Tempo konstant$', r'Rate ladder \1 min at rate \2, steady split'),
    (r'^Sprint 250 m \((\d+/\d+)\)$', r'Sprint 250 m (\1)'),
    (r'^Technikblock (\d+/\d+): ruhig, Verhältnis Durchzug zu Vorrollen 1:2; in der letzten Minute 20 Schläge kräftiger$',
     r'Technique block \1: calm, drive to recovery ratio 1:2; 20 stronger strokes in the last minute'),
]


def en(text):
    if text in EN:
        return EN[text]
    for pat, rep in PATTERNS:
        if re.match(pat, text):
            return re.sub(pat, rep, text)
    raise SystemExit(f'Keine Übersetzung für: {text!r}')


def bi(value):
    if isinstance(value, dict) or not value:
        return value
    return {'de': value, 'en': en(value)}


def convert(path):
    data = json.loads(path.read_text(encoding='utf-8'))
    plans = data if isinstance(data, list) else data['plans']
    for p in plans:
        for k in ('name', 'summary', 'purpose', 'level', 'category'):
            if k in p:
                p[k] = bi(p[k])
        for ph in p.get('phases', []):
            if ph.get('label'):
                ph['label'] = bi(ph['label'])
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('zweisprachig:', path)


if __name__ == '__main__':
    for f in ('App/RowCoach/Resources/plans.json', 'docs/trainings-recherche.json'):
        convert(Path(f))
