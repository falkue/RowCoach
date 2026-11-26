# Auftrag: Trainingskatalog auf ~100 Programme erweitern (gemeinsamer Teil für alle Recherche-Agenten)

Stand 26.11.2026. RowCoach ist eine App für das Concept2-Rudergerät (PM5). Sie hat heute 10 Programme in
`App/RowCoach/Resources/plans.json` (Recherche dazu: `docs/trainings-recherche.md` und `.json`). Ziel: rund 100
Programme, die verschiedene Trainingsarten abdecken (nach Zeit, nach Distanz, leicht, hart, Intervalle, Langdistanz,
Kurzdistanz, Tests, Technik, Regeneration), damit man in Zukunft unterschiedlich trainieren kann (auch Pläne über
mehrere Wochen, die aus diesen Bausteinen bestehen).

Vier Agenten arbeiten parallel, je eine Familie. Du schreibst NUR in deine zwei Dateien:
`docs/plans-new/<familie>.json` und `docs/plans-new/<familie>.md`. Nichts anderes ändern, nichts committen.

## Recherche-Reihenfolge (Pflicht)
1. Zotero über `zrag search "…"` und `zrag semantic "…"` (rowing ergometer training, interval training, Seiler,
   polarized training, VO2max intervals, threshold). Bei der letzten Recherche war dort nichts zum Rudern; Treffer zu
   Intervall- und Ausdauertraining allgemein (z. B. Seiler) sind trotzdem gute Belege.
2. Fundus (`mcp__fundus__fundus_search`, Projekt `rowcoach`).
3. Web: Concept2 (Workout of the Day, Trainingspläne, Pete Plan auf concept2.com Forum/Blog, Wolverine Plan,
   Ranked Workouts), British Rowing/GB Rowing (Trainingsbänder UT2/UT1/AT/TR/AN), USRowing, Fachliteratur
   (Seiler, Nolte „Rowing Faster“, Steinacker), Vereins- und Uni-Leitfäden (Wolfson CBC), Rowperfect, Dark Horse
   Rowing, ErgData-Workouts. Bevorzugt Primärquellen; Sekundärquellen als solche kennzeichnen.
4. Belegte Angaben (z. B. „UT2 = 18–20 spm, 55–70 % HFmax“) mit `mcp__fundus__fundus_add` zurückschreiben
   (project `rowcoach`, Quelle mit URL und Herausgeber, Tags aus `fundus_vocab`; Sport/Training ggf. fehlend → nur
   vorhandene Tags nutzen). Nicht mehr als ~10 Kernangaben pro Agent.
Lokales Modell (vLLM qwen3.8-27b, http://127.0.0.1:8001, priority 6, enable_thinking false) darfst du für
Übersetzungsentwürfe de→en nutzen; jede Übersetzung selbst prüfen. Nicht nötig, wenn du es schneller selbst machst.

## Format (exakt wie plans.json; Phasen ausgerollt, keine Wiederholungsangaben)
```json
{"id": "kebab-case-eindeutig",
 "name": {"de": "…", "en": "…"},
 "summary": {"de": "1–2 Sätze, was man tut", "en": "…"},
 "purpose": {"de": "Wozu, Band und Puls (z. B. 'UT1 / ... (Puls ca. 70-80 % HFmax, Pulszone 3)')", "en": "…"},
 "level": {"de": "Einsteiger|Fortgeschritten|Leistung", "en": "Beginner|Advanced|Performance"},
 "category": {"de": "<Kategorie unten>", "en": "<…>"},
 "tags": ["…"],
 "sources": [{"title": "…", "publisher": "…", "url": "…", "published": "YYYY oder YYYY-MM-DD oder null", "zotero": "KEY oder null"}],
 "evidence": "direkt | angepasst: … | abgeleitet: …",
 "phases": [{"kind": "warmup|work|rest|cooldown", "durationS": 300 ODER "distanceM": 500,
             "spmMin": 18, "spmMax": 20, "hrZone": 2, "paceOffsetMinS": 10, "paceOffsetMaxS": 15,
             "activeRest": true, "label": {"de": "…", "en": "…"}}]}
```
- Eine Phase hat entweder `durationS` oder `distanceM`.
- `paceOffsetMinS/MaxS`: Sekunden pro 500 m relativ zum Tempo der 2000-m-Bestzeit (+ = langsamer; negativ =
  schneller als 2k-Tempo, z. B. 500-m-Sprints −3..−6). Bezug Referenzsplit ca. 2:00/500 m. Wenn aus Wattprozent
  abgeleitet (Watt ~ 1/Pace³), im Feld `evidence` als „abgeleitet“ vermerken.
- `hrZone` 1–5 nach Concept2-5-Zonen-Modell (% HFmax): 1 <60–65 (Regeneration), 2 65–75 (UT2), 3 75–80/85 (UT1),
  4 80/85–90 (AT/Schwelle), 5 >90 (TR/AN). In `.md` dokumentieren, welche Grenzen du verwendest.
- Pausen: `kind: rest`, `activeRest: true` (locker weiter) oder `false` (stehen). Lange Distanz-Pausen sind ok.
- Jedes Programm hat Einrudern und Ausrudern (ausser Tests ohne, wenn die Quelle das so sagt – dann trotzdem
  Einrudern empfehlen). Phasen-Labels mit Zähler wie „(2/6)“ für Wiederholungen, wie in plans.json.
- Texte: Deutsch Schweizer Schreibung (ss statt ß), sachlich, kurz. Englisch natürlich.
- Kein Programm doppelt zu den vorhandenen 10 (ids: grundlage-locker-30, grundlage-3x10-r20, schwelle-4x6,
  kurzintervalle-8x2, langintervalle-4x4, pyramide-1-2-3-4-3-2-1, frequenzleiter-18-24, sprint-8x250, test-2000m,
  technik-locker-25) und nicht doppelt zu den anderen Familien (Zuständigkeiten unten). Varianten (z. B. 3 Längen
  derselben Idee) sind erlaubt, wenn sie wirklich verschieden einsetzbar sind.
- Insgesamt soll es eine gute Mischung geben: nach Zeit UND nach Distanz, kurze (≤ 25 min), mittlere und lange
  (≥ 60 min) Einheiten, alle drei Niveaus.

## Kategorien (fest, de/en)
Grundlage/Steady state · Langdistanz/Long distance · Schwelle/Threshold · Intervalle/Intervals · Sprint/Sprint ·
Test/Test · Technik & Rhythmus/Technique & rhythm · Regeneration/Recovery · Wettkampf/Race preparation

## Tags (feste Liste, nur diese verwenden)
- Intensität (genau eins): `easy`, `moderate`, `hard`, `max`
- Energiesystem/Fokus (1–2): `aerobic`, `threshold`, `vo2max`, `anaerobic`, `power`, `technique`, `recovery`
- Form (beliebig): `pyramid`, `ladder`, `rate-ladder`, `rate-cap`, `progressive`, `negative-split`, `fartlek`,
  `over-under`, `race-pace`, `benchmark`, `c2-ranked` (Concept2-Rangliste: 100 m, 500 m, 1000 m, 2000 m, 5000 m,
  6000 m, 10 000 m, Halbmarathon, Marathon, 1 min, 4 min, 30 min, 60 min), `beginner-friendly`, `time-efficient`
  (≤ 30 min inkl. Ein-/Ausrudern)

## Abgabe
1. `docs/plans-new/<familie>.json`: JSON-Liste deiner Programme, gültig (mit `python3 -m json.tool` prüfen).
2. `docs/plans-new/<familie>.md`: wie docs/trainings-recherche.md: je Programm Erklärung, Zweck, Niveau,
   Belegstatus, Quellen, Phasentabelle; oben Methode, verwendete Zonen, was nicht abrufbar war.
3. Bericht an den Auftraggeber: Anzahl, Liste id | Name | Kategorie | Niveau | Zeit/Distanz | ca. Dauer,
   Quellenlage, Unsicherheiten.
