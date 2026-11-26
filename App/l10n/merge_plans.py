#!/usr/bin/env python3
"""Führt die Programme der Recherche-Familien (docs/plans-new/<familie>.json) mit den vorhandenen Programmen zusammen
und schreibt App/RowCoach/Resources/plans.json und docs/trainings-recherche.json.

Aufruf (im Repo-Wurzelordner): python3 App/l10n/merge_plans.py [--check]
- Vorhandene Programme behalten ihre id (DailySuggestion und Startargumente hängen daran) und bekommen hier ihre Tags.
- Prüft: eindeutige ids, zweisprachige Texte, feste Kategorien/Niveaus/Tags (docs/plans-new/BRIEF.md), genau eine
  Intensität, Phasen mit genau einer Länge, Quellen vorhanden, Einrudern und Ausrudern.
- Reihenfolge: nach Kategorie (Liste unten), innerhalb nach Niveau, dann nach Reihenfolge in der Quelle.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLANS = ROOT / 'App/RowCoach/Resources/plans.json'
RESEARCH = ROOT / 'docs/trainings-recherche.json'
FAMILIES = ['grundlage', 'schwelle', 'intervalle', 'tests']

CATEGORIES = [('Grundlage', 'Steady state'), ('Langdistanz', 'Long distance'), ('Schwelle', 'Threshold'),
              ('Intervalle', 'Intervals'), ('Sprint', 'Sprint'), ('Test', 'Test'),
              ('Wettkampf', 'Race preparation'), ('Technik & Rhythmus', 'Technique & rhythm'),
              ('Regeneration', 'Recovery')]
LEVELS = [('Einsteiger', 'Beginner'), ('Fortgeschritten', 'Advanced'), ('Leistung', 'Performance')]
INTENSITIES = ['easy', 'moderate', 'hard', 'max']
TAGS = set(INTENSITIES) | {'aerobic', 'threshold', 'vo2max', 'anaerobic', 'power', 'technique', 'recovery',
                           'pyramid', 'ladder', 'rate-ladder', 'rate-cap', 'progressive', 'negative-split', 'fartlek',
                           'over-under', 'race-pace', 'benchmark', 'c2-ranked', 'beginner-friendly', 'time-efficient'}

# Tags der ursprünglichen zehn Programme
EXISTING_TAGS = {
    'grundlage-locker-30': ['easy', 'aerobic', 'beginner-friendly'],
    'grundlage-3x10-r20': ['easy', 'aerobic', 'rate-cap', 'beginner-friendly'],
    'schwelle-4x6': ['hard', 'threshold'],
    'kurzintervalle-8x2': ['hard', 'vo2max'],
    'langintervalle-4x4': ['hard', 'vo2max'],
    'pyramide-1-2-3-4-3-2-1': ['hard', 'vo2max', 'pyramid'],
    'frequenzleiter-18-24': ['moderate', 'technique', 'aerobic', 'rate-ladder', 'beginner-friendly'],
    'sprint-8x250': ['max', 'anaerobic', 'power', 'time-efficient'],
    'test-2000m': ['max', 'vo2max', 'benchmark', 'c2-ranked'],
    'technik-locker-25': ['easy', 'technique', 'recovery', 'beginner-friendly', 'time-efficient'],
}


def de(v):
    return v.get('de') if isinstance(v, dict) else v


def check(p, errors):
    pid = p.get('id', '?')
    for f in ('name', 'summary', 'purpose', 'level', 'category'):
        v = p.get(f)
        if not (isinstance(v, dict) and v.get('de') and v.get('en')):
            errors.append(f'{pid}: {f} nicht zweisprachig')
    if (de(p.get('category')), (p.get('category') or {}).get('en')) not in CATEGORIES:
        errors.append(f'{pid}: Kategorie {p.get("category")}')
    if (de(p.get('level')), (p.get('level') or {}).get('en')) not in LEVELS:
        errors.append(f'{pid}: Niveau {p.get("level")}')
    tags = p.get('tags') or []
    if set(tags) - TAGS:
        errors.append(f'{pid}: unbekannte Tags {set(tags) - TAGS}')
    if sum(t in INTENSITIES for t in tags) != 1:
        errors.append(f'{pid}: nicht genau eine Intensität {tags}')
    if not p.get('sources'):
        errors.append(f'{pid}: keine Quellen')
    phases = p.get('phases') or []
    for i, ph in enumerate(phases):
        if ph.get('kind') not in ('warmup', 'work', 'rest', 'cooldown'):
            errors.append(f'{pid}: Phase {i} Art {ph.get("kind")}')
        if (ph.get('durationS') is None) == (ph.get('distanceM') is None):
            errors.append(f'{pid}: Phase {i} braucht genau eine Länge')
        lab = ph.get('label')
        if lab is not None and not (isinstance(lab, dict) and lab.get('de') and lab.get('en')):
            errors.append(f'{pid}: Phase {i} Label nicht zweisprachig')
        z = ph.get('hrZone')
        if z is not None and z not in (1, 2, 3, 4, 5):
            errors.append(f'{pid}: Phase {i} Pulszone {z}')
        a, b = ph.get('spmMin'), ph.get('spmMax')
        if a is not None and b is not None and a > b:
            errors.append(f'{pid}: Phase {i} Schlagzahl {a}>{b}')
    if not any(ph.get('kind') == 'work' for ph in phases):
        errors.append(f'{pid}: keine Belastungsphase')


def main():
    only_check = '--check' in sys.argv
    existing = json.loads(PLANS.read_text())
    base = [p for p in existing if p['id'] in EXISTING_TAGS]
    for p in base:
        p['tags'] = EXISTING_TAGS[p['id']]
    merged = list(base)
    for fam in FAMILIES:
        f = ROOT / f'docs/plans-new/{fam}.json'
        if not f.exists():
            print(f'fehlt: {f.relative_to(ROOT)}')
            continue
        for p in json.loads(f.read_text()):
            p.setdefault('family', fam)
            merged.append(p)
    errors = []
    seen = set()
    for p in merged:
        if p['id'] in seen:
            errors.append(f'{p["id"]}: doppelt')
        seen.add(p['id'])
        check(p, errors)
    cat_rank = {c[0]: i for i, c in enumerate(CATEGORIES)}
    lvl_rank = {l[0]: i for i, l in enumerate(LEVELS)}
    order = {id(p): i for i, p in enumerate(merged)}
    merged.sort(key=lambda p: (cat_rank.get(de(p.get('category')), 99), lvl_rank.get(de(p.get('level')), 9), order[id(p)]))
    counts = {}
    for p in merged:
        counts[de(p['category'])] = counts.get(de(p['category']), 0) + 1
    print(f'{len(merged)} Programme:', ', '.join(f'{k} {v}' for k, v in counts.items()))
    for e in errors:
        print('FEHLER', e)
    if errors or only_check:
        sys.exit(1 if errors else 0)
    for p in merged:
        p.pop('family', None)
    text = json.dumps(merged, ensure_ascii=False, indent=2) + '\n'
    PLANS.write_text(text)
    RESEARCH.write_text(text)
    print(f'geschrieben: {PLANS.relative_to(ROOT)}, {RESEARCH.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
