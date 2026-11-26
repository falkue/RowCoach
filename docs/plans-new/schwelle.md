# Familie `schwelle`: Schwellentraining und lange aerobe Intervalle für RowCoach

Stand 26.11.2026. 22 neue Programme: 19 in der Kategorie Schwelle, 3 in Intervalle (nur lange aerobe Intervalle ab 5 min).
Maschinenlesbar in `docs/plans-new/schwelle.json` (Format wie `App/RowCoach/Resources/plans.json`, Phasen ausgerollt).

## Methode

- **Zotero (zrag):** nicht erreichbar (zotero-mcp auf 100.68.243.73:8000 verweigerte die Verbindung, drei Versuche). Keine Zotero-Keys; Seiler-Arbeiten sind über DOI/URL belegt.
- **Fundus (Projekt `rowcoach`):** vorhanden waren Wolfson-Zonen (fact 2420), Seiler & Tønnessen 2009 (study 1035), Concept2 2k-Plan (practice 976), Gluckman 1995 (practice 975). Neu zurückgeschrieben: siehe Abschnitt Fundus unten.
- **Web:** Primärquellen gelesen: Pete Plan (Blog des Autors, 3-Wochen-Zyklus und Beginner-Plan), Concept2 (5k-Plan, 6 Ways to a 30-Minute Workout, 7 Best Worst Workouts, Heart Rate Training), Caviston-Beiträge im Concept2-Forum (Wolverine Plan), Wolfson-Leitfaden (PDF im Volltext), Seiler et al. 2013 (Abstract über PubMed E-Utilities), TrainerRoad (Over-Unders, Radsport).
- **Nicht abrufbar:** GB-Rowing-Trainingsmatrix und British-Rowing-Plus-Artikel (Weiterleitung auf die Startseite), Faster Masters Rowing (Wartungsseite am 26.11.2026; Angaben aus der Recherche vom 23.11.2026 übernommen, siehe `docs/trainings-recherche.md`), Concept2-Workout-of-the-Day-Archiv (lädt nicht), PubMed-Webseite (Cookie-Sperre; Abstract stattdessen per E-Utilities). Kein Rudertext zu Over-Unders und kein Primärbeleg für das Format 4'/3'/2' bei r20/22/24 gefunden: diese beiden Programme sind als angepasst/abgeleitet markiert.

## Tempo- und Pulsbezug

- **Pace-Offsets** in Sekunden pro 500 m relativ zum 2000-m-Tempo, Bezug Referenzsplit 2:00/500 m. Ankerwerte:
  - 5-km-Tempo = 2k + 7-8 s (Faster Masters); Pete Plan: 5 x 1500 m im 5k-Tempo, 4 x 2000 m 5k + 0,5 s, 3k/2,5k/2k 5k + 1 s.
  - Schwelle (ca. 30-60-min-Tempo) = 2k + 10..15 s; Wolverine Level 2 ca. 2K + 8 s, Level 3 ca. 2K + 15 s (Caviston, „85-90 % of 2K velocity“).
  - Gluckman: 20 min bei 2k + 3..5 s.
  - Over-Under: Watt ~ 1/Pace^3; bei Schwelle 2k + 11 s (130 s/500 m) ergeben 95 % Leistung ca. +13 s, 105 % ca. +8 s.
  Für andere 2k-Zeiten skalieren die Offsets nur grob.
- **Pulszonen** nach Concept2-5-Zonen-Modell (% HFmax): 1 unter 60-65 (Regeneration), 2 65-75 (UT2), 3 75-80/85 (UT1), 4 80/85-90 (AT/Schwelle), 5 über 90 (TR/AN). Concept2 selbst: Zone 4 = 80-90 %, „hard to hold for more than 10 minutes“, nicht all-out. Wolfson rechnet mit Herzfrequenzreserve (UT1 70-80 %, AT 80-85 %, TR 85-95 %). Programme mit Zone „3-4“ haben im JSON die Zone der überwiegenden Arbeitsphasen.
- **Abgrenzung:** kurze/harte Intervalle bis 4 min, Sprints und VO2max-Intervalle → Familie `intervalle`; Ranglisten- und Teststücke (30 min, 5000 m, 6000 m als Test) → `tests`; reine UT2-Grundlage → `grundlage`. Pete-Plan-Einheiten 8 x 500 m, 4 x 1000 m und die Speed-Pyramide gehören zu `intervalle`.
- Einrudern 5-10 min steigernd mit kurzen Antritten (Concept2: 5-10 min), Ausrudern 5 min.

## Übersicht

| id | Name | Kategorie | Niveau | Arbeit | ca. Dauer |
|---|---|---|---|---|---|
| `schwelle-einsteiger-3x5` | Schwelle Einstieg 3 x 5 Minuten | Schwelle | Einsteiger | 15 min | 29 min |
| `schwelle-2x10` | Schwelle 2 x 10 Minuten | Schwelle | Einsteiger | 20 min | 32 min |
| `schwelle-3x10` | Schwelle 3 x 10 Minuten | Schwelle | Fortgeschritten | 30 min | 47 min |
| `schwelle-2x15` | Schwelle 2 x 15 Minuten | Schwelle | Fortgeschritten | 30 min | 45 min |
| `schwelle-2x20-r22` | Schwelle 2 x 20 Minuten, Schlagzahl 22 | Schwelle | Leistung | 40 min | 56 min |
| `schwelle-tempo-20` | Tempo 20 Minuten am Stück | Schwelle | Leistung | 20 min | 33 min |
| `schwelle-30-r20` | 30 Minuten Schlagzahl 20 | Schwelle | Fortgeschritten | 30 min | 43 min |
| `schwelle-30-progressiv` | 30 Minuten progressiv | Schwelle | Einsteiger | 30 min | 40 min |
| `schwelle-frequenzstufen-3x9` | Schwelle Frequenzstufen 3 x (4-3-2) | Schwelle | Fortgeschritten | 27 min | 46 min |
| `schwelle-over-under-3x12` | Over-Under 3 x 12 Minuten | Schwelle | Leistung | 36 min | 57 min |
| `schwelle-einsteiger-3x1500` | Schwelle Einstieg 3 x 1500 m | Schwelle | Einsteiger | 4500 m | 36 min |
| `schwelle-3x2000` | Schwelle 3 x 2000 m | Schwelle | Fortgeschritten | 6000 m | 47 min |
| `schwelle-2x3000` | Schwelle 2 x 3000 m | Schwelle | Fortgeschritten | 6000 m | 43 min |
| `schwelle-4x2000` | 4 x 2000 m (Pete Plan) | Schwelle | Leistung | 8000 m | 62 min |
| `schwelle-4x2000-progressiv` | 4 x 2000 m progressiv | Schwelle | Fortgeschritten | 8000 m | 60 min |
| `schwelle-5x1500` | 5 x 1500 m (Pete Plan) | Schwelle | Leistung | 7500 m | 65 min |
| `schwelle-3000-2500-2000` | 3000-2500-2000 m (Pete Plan) | Schwelle | Leistung | 7500 m | 55 min |
| `schwelle-2x5000` | Schwelle 2 x 5000 m | Schwelle | Leistung | 10000 m | 62 min |
| `schwelle-6000-negativ` | 6000 m negativer Split | Schwelle | Fortgeschritten | 6000 m | 40 min |
| `intervalle-4x8` | Lange Intervalle 4 x 8 Minuten | Intervalle | Leistung | 32 min | 53 min |
| `intervalle-3x6-r26` | Kraftausdauer 3 x 6 Minuten, Schlagzahl 26 | Intervalle | Fortgeschritten | 18 min | 36 min |
| `intervalle-wolverine-8x5` | Wolverine Level 3: 8 x 5 Minuten | Intervalle | Leistung | 40 min | 65 min |

## Schwelle Einstieg 3 x 5 Minuten (`schwelle-einsteiger-3x5`)

- Erklärung: Drei Blöcke zu 5 Minuten zügig, aber kontrolliert, mit 2 Minuten lockerer Pause. Der kürzeste Einstieg ins Schwellentraining.
- Zweck/Bereich: Einstieg Schwelle / UT1-AT (Puls ca. 75-85 % HFmax, Pulszone 3-4)
- Niveau: Einsteiger; Kategorie: Schwelle; Tags: moderate, threshold, beginner-friendly, time-efficient
- Belegstatus: angepasst: Concept2 (3 x 9 min / 1 min, für Einsteiger 4 min on / 1 min off) und Faster Masters (Schwelle 4-6 x 5-7 min, 2-3 min Pause, r20-22) auf 3 x 5 min / 2 min verkürzt; Pace-Offset abgeleitet (etwas langsamer als Schwellentempo)
- Quellen: Concept2 - 6 Ways to a 30-Minute Workout (3 x 9 min on / 1 min off; 30 min with pace dropping every 5 min) (2022-06-03); Faster Masters Rowing - UT2, Threshold and VO2max Explained (threshold 4-6 x 5-7 min, 2-3 min rest, r20-22, 80-85 % HRmax); coaching site, secondary source; Concept2 - Heart Rate Training with Your Concept2 Erg (zone 4 = 80-90 % HRmax, hard to hold more than 10 min) (2025-04-17)
- Geschätzte Gesamtdauer: ca. 29 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 5:00 min | 18-22 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 5:00 min | 20-22 | 4 | 2k +12..+16 s/500 m | - | Schwelle zügig, Schlagzahl 20-22 (1/3) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 5:00 min | 20-22 | 4 | 2k +12..+16 s/500 m | - | Schwelle zügig, Schlagzahl 20-22 (2/3) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 5:00 min | 20-22 | 4 | 2k +12..+16 s/500 m | - | Schwelle zügig, Schlagzahl 20-22 (3/3) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Schwelle 2 x 10 Minuten (`schwelle-2x10`)

- Erklärung: Zwei Blöcke zu 10 Minuten an der Schwelle mit 2 Minuten Pause. Im zweiten Block die Distanz des ersten übertreffen.
- Zweck/Bereich: Schwelle / AT (Puls ca. 80-90 % HFmax, Pulszone 4)
- Niveau: Einsteiger; Kategorie: Schwelle; Tags: moderate, threshold, beginner-friendly
- Belegstatus: direkt: Pete Plan Beginner Woche 1 und 5 (2 x 10 min / 2 min, erster Block im 20-min-Tempo, zweiten übertreffen); Schlagzahl 20-24 und Pace-Offset abgeleitet
- Quellen: The Pete Plan (Pete Marston), coaching blog; secondary source - The Pete Plan - Beginner Training (24 weeks; e.g. 2 x 10 min, 3 x 8 min, 3 x 10 min, 2 x 15 min, 4 x 8 min / 2 min; 3 x 1500 m / 3 min; 3 x 2000 m / 4 min); Concept2 - Heart Rate Training with Your Concept2 Erg (zone 4 = 80-90 % HRmax, hard to hold more than 10 min) (2025-04-17)
- Geschätzte Gesamtdauer: ca. 32 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 5:00 min | 18-22 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 10:00 min | 20-24 | 4 | 2k +12..+15 s/500 m | - | Block 10 min an der Schwelle, gleichmässig (1/2) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 10:00 min | 20-24 | 4 | 2k +10..+14 s/500 m | - | Block 10 min, etwas mehr Distanz als im ersten (2/2) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Schwelle 3 x 10 Minuten (`schwelle-3x10`)

- Erklärung: Drei Blöcke zu 10 Minuten im 10-km-Tempo mit 2 Minuten Pause; der letzte darf schneller werden.
- Zweck/Bereich: Schwelle / AT (Puls ca. 80-90 % HFmax, Pulszone 4)
- Niveau: Fortgeschritten; Kategorie: Schwelle; Tags: hard, threshold
- Belegstatus: direkt: Pete Plan Beginner Woche 12/15/19 (3 x 10 min / 2 min, die ersten zwei im 10-km-Tempo, den letzten schneller); ähnlich Concept2 3 x 9 min / 1 min. Pace-Offset abgeleitet (10-km-Tempo ca. 2k + 10..14 s)
- Quellen: The Pete Plan (Pete Marston), coaching blog; secondary source - The Pete Plan - Beginner Training (24 weeks; e.g. 2 x 10 min, 3 x 8 min, 3 x 10 min, 2 x 15 min, 4 x 8 min / 2 min; 3 x 1500 m / 3 min; 3 x 2000 m / 4 min); Concept2 - 6 Ways to a 30-Minute Workout (3 x 9 min on / 1 min off; 30 min with pace dropping every 5 min) (2022-06-03); Faster Masters Rowing - UT2, Threshold and VO2max Explained (threshold 4-6 x 5-7 min, 2-3 min rest, r20-22, 80-85 % HRmax); coaching site, secondary source
- Geschätzte Gesamtdauer: ca. 47 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 10:00 min | 20-24 | 4 | 2k +10..+14 s/500 m | - | Block 10 min im 10-km-Tempo (1/3) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 10:00 min | 20-24 | 4 | 2k +10..+14 s/500 m | - | Block 10 min im 10-km-Tempo (2/3) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 10:00 min | 20-24 | 4 | 2k +8..+12 s/500 m | - | Block 10 min, schneller als die ersten zwei (3/3) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Schwelle 2 x 15 Minuten (`schwelle-2x15`)

- Erklärung: Zwei lange Blöcke zu 15 Minuten im Tempo der 3 x 10 Minuten, der zweite etwas schneller.
- Zweck/Bereich: Schwelle / AT (Puls ca. 80-90 % HFmax, Pulszone 4)
- Niveau: Fortgeschritten; Kategorie: Schwelle; Tags: hard, threshold, negative-split
- Belegstatus: direkt: Pete Plan Beginner Woche 13/17/23 (2 x 15 min / 2 min, Tempo der 3 x 10 min, zweiter Block leicht schneller); Schlagzahl und Pace-Offset abgeleitet
- Quellen: The Pete Plan (Pete Marston), coaching blog; secondary source - The Pete Plan - Beginner Training (24 weeks; e.g. 2 x 10 min, 3 x 8 min, 3 x 10 min, 2 x 15 min, 4 x 8 min / 2 min; 3 x 1500 m / 3 min; 3 x 2000 m / 4 min); Faster Masters Rowing - UT2, Threshold and VO2max Explained (threshold 4-6 x 5-7 min, 2-3 min rest, r20-22, 80-85 % HRmax); coaching site, secondary source; Concept2 - Heart Rate Training with Your Concept2 Erg (zone 4 = 80-90 % HRmax, hard to hold more than 10 min) (2025-04-17)
- Geschätzte Gesamtdauer: ca. 45 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 15:00 min | 20-24 | 4 | 2k +11..+14 s/500 m | - | Block 15 min im Tempo der 3 x 10 min (1/2) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 15:00 min | 20-24 | 4 | 2k +9..+13 s/500 m | - | Block 15 min, leicht schneller als der erste (2/2) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Schwelle 2 x 20 Minuten, Schlagzahl 22 (`schwelle-2x20-r22`)

- Erklärung: Zwei Blöcke zu 20 Minuten am unteren Rand der Schwelle bei höchstens Schlagzahl 22, 3 Minuten Pause.
- Zweck/Bereich: Obere UT1 bis AT, Schwellenausdauer (Puls ca. 78-85 % HFmax, Pulszone 3-4)
- Niveau: Leistung; Kategorie: Schwelle; Tags: hard, threshold, rate-cap
- Belegstatus: abgeleitet: Format 3-4 x 20' aus Caviston (Wolverine Level 4) und 2-3 x 20 min r20 / 2 min (Progression Squad, dort als UT2); hier bewusst etwas schneller (obere UT1/AT) und auf 2 Blöcke begrenzt. Pace-Offset abgeleitet (ca. 60-min-Tempo)
- Quellen: Concept2 Forum (c2forum.com) - Wolverine Plan Discussion (M. Caviston on Level 4 formats such as 6-10 x 10' and 3-4 x 20'); Progression Squad (rowing club, Cambridge) - Erg plan (rate pyramid 2 min at r20-r28; 2-3 x 20 min r20 / 2 min); club plan, secondary source; Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6 (bands, 3 x 6 min r26, 30r20, negative splitting); club guide, secondary source (2019); Wiley - Seiler S, Joranson K, Olesen BV, Hetlelid KJ: Adaptations to aerobic interval training: interactive effects of exercise intensity and total work duration. Scand J Med Sci Sports 23(1):74-83, doi:10.1111/j.1600-0838.2011.01351.x (2013)
- Geschätzte Gesamtdauer: ca. 56 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 20:00 min | 20-22 | 4 | 2k +12..+15 s/500 m | - | Block 20 min, Schlagzahl höchstens 22, gleichmässig (1/2) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 20:00 min | 20-22 | 4 | 2k +12..+15 s/500 m | - | Block 20 min, Schlagzahl höchstens 22, gleichmässig (2/2) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Tempo 20 Minuten am Stück (`schwelle-tempo-20`)

- Erklärung: 20 Minuten ohne Pause knapp langsamer als das 2000-m-Tempo (3-5 Sekunden pro 500 m). Hart, aber gleichmässig.
- Zweck/Bereich: Schwelle bis VO2max-Bereich, Tempohärte (Puls ca. 85-92 % HFmax, Pulszone 4-5)
- Niveau: Leistung; Kategorie: Schwelle; Tags: hard, threshold
- Belegstatus: direkt: Gluckman (Concept2 Update 1995): 20 min am 2k-Tempo + 3..5 s; Schlagzahl 24-28 eingegrenzt
- Quellen: Concept2 - From the Archives: A Great Workout in 30 Minutes (L. Gluckman, 30 and Out; 20 min at 2k + 3..5 s) (2013-12-31); Concept2 - Heart Rate Training with Your Concept2 Erg (zone 4 = 80-90 % HRmax, hard to hold more than 10 min) (2025-04-17)
- Geschätzte Gesamtdauer: ca. 33 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 20:00 min | 24-28 | 4 | 2k +3..+5 s/500 m | - | 20 min am Stück, 2k-Tempo + 3-5 s, gleichmässig |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 30 Minuten Schlagzahl 20 (`schwelle-30-r20`)

- Erklärung: 30 Minuten am Stück mit genau Schlagzahl 20: kräftige Schläge, fest, aber nicht maximal. Trainiert Kraft pro Schlag an der Schwelle.
- Zweck/Bereich: UT1 / AT mit Frequenzbegrenzung (Puls ca. 78-88 % HFmax, Pulszone 3-4)
- Niveau: Fortgeschritten; Kategorie: Schwelle; Tags: hard, threshold, rate-cap
- Belegstatus: angepasst: '30r20' ist bei Wolfson ein üblicher Test (30 min bei Schlagzahl 20); hier als submaximales Trainingsstück (fest, nicht maximal). Pace-Offset abgeleitet; der eigentliche Test gehört zur Familie tests
- Quellen: Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6 (bands, 3 x 6 min r26, 30r20, negative splitting); club guide, secondary source (2019); Progression Squad (rowing club, Cambridge) - Erg plan (rate pyramid 2 min at r20-r28; 2-3 x 20 min r20 / 2 min); club plan, secondary source; Concept2 - Heart Rate Training with Your Concept2 Erg (zone 4 = 80-90 % HRmax, hard to hold more than 10 min) (2025-04-17)
- Geschätzte Gesamtdauer: ca. 43 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-22 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 30:00 min | 20 | 4 | 2k +12..+16 s/500 m | - | 30 min bei Schlagzahl 20, lange kräftige Schläge, fest |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 30 Minuten progressiv (`schwelle-30-progressiv`)

- Erklärung: 30 Minuten ohne Pause in sechs Stufen zu 5 Minuten; jede Stufe 2 Sekunden pro 500 m schneller. Startet locker, endet an der Schwelle.
- Zweck/Bereich: Von UT2 bis AT, Tempogefühl (Puls von ca. 65 bis 85 % HFmax, Pulszone 2-4)
- Niveau: Einsteiger; Kategorie: Schwelle; Tags: moderate, threshold, aerobic, progressive, beginner-friendly
- Belegstatus: direkt: Concept2 '6 Ways to a 30-Minute Workout' (Pace alle 5 min um 2 s schneller, Beispiel 2:24 bis 2:14/500 m); Offsets relativ zum 2k-Tempo abgeleitet
- Quellen: Concept2 - 6 Ways to a 30-Minute Workout (3 x 9 min on / 1 min off; 30 min with pace dropping every 5 min) (2022-06-03); Concept2 - Heart Rate Training with Your Concept2 Erg (zone 4 = 80-90 % HRmax, hard to hold more than 10 min) (2025-04-17)
- Geschätzte Gesamtdauer: ca. 40 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 5:00 min | 18-22 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 5:00 min | 20-24 | 2 | 2k +20..+22 s/500 m | - | 5 min locker-zügig, Startstufe (Stufe 1/6) |
| work | 5:00 min | 20-24 | 3 | 2k +18..+20 s/500 m | - | 5 min, Tempo 2 s schneller als zuvor (Stufe 2/6) |
| work | 5:00 min | 20-24 | 3 | 2k +16..+18 s/500 m | - | 5 min, Tempo 2 s schneller als zuvor (Stufe 3/6) |
| work | 5:00 min | 20-24 | 3 | 2k +14..+16 s/500 m | - | 5 min, Tempo 2 s schneller als zuvor (Stufe 4/6) |
| work | 5:00 min | 20-24 | 4 | 2k +12..+14 s/500 m | - | 5 min, Tempo 2 s schneller als zuvor (Stufe 5/6) |
| work | 5:00 min | 20-24 | 4 | 2k +10..+12 s/500 m | - | 5 min, Tempo 2 s schneller als zuvor (Stufe 6/6) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Schwelle Frequenzstufen 3 x (4-3-2) (`schwelle-frequenzstufen-3x9`)

- Erklärung: Drei Blöcke zu 9 Minuten: 4 Minuten bei Schlagzahl 20, 3 bei 22, 2 bei 24, mit jeder Stufe schneller. 3 Minuten Pause zwischen den Blöcken.
- Zweck/Bereich: UT1 bis AT mit Frequenzwechsel (Puls ca. 75-88 % HFmax, Pulszone 3-4)
- Niveau: Fortgeschritten; Kategorie: Schwelle; Tags: hard, threshold, rate-ladder
- Belegstatus: abgeleitet: Frequenzstufen +2 spm (Concept2 '5 Favorite 20-Minute Workouts', Rate-Pyramide Progression Squad) zu Schwellenblöcken 4/3/2 min bei r20/22/24 kombiniert; Pete-Plan-/Wolverine-Stil, keine Primärquelle für genau dieses Format gefunden. Pace-Offsets abgeleitet
- Quellen: Concept2 - 5 Favorite 20-Minute Workouts (rate ladder +2 spm per step); Progression Squad (rowing club, Cambridge) - Erg plan (rate pyramid 2 min at r20-r28; 2-3 x 20 min r20 / 2 min); club plan, secondary source; Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6 (bands, 3 x 6 min r26, 30r20, negative splitting); club guide, secondary source (2019)
- Geschätzte Gesamtdauer: ca. 46 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 4:00 min | 20 | 3 | 2k +14..+17 s/500 m | - | 4 min Schlagzahl 20 (Block 1/3) |
| work | 3:00 min | 22 | 4 | 2k +11..+14 s/500 m | - | 3 min Schlagzahl 22, schneller (Block 1/3) |
| work | 2:00 min | 24 | 4 | 2k +8..+11 s/500 m | - | 2 min Schlagzahl 24, nochmals schneller (Block 1/3) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 4:00 min | 20 | 3 | 2k +14..+17 s/500 m | - | 4 min Schlagzahl 20 (Block 2/3) |
| work | 3:00 min | 22 | 4 | 2k +11..+14 s/500 m | - | 3 min Schlagzahl 22, schneller (Block 2/3) |
| work | 2:00 min | 24 | 4 | 2k +8..+11 s/500 m | - | 2 min Schlagzahl 24, nochmals schneller (Block 2/3) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 4:00 min | 20 | 3 | 2k +14..+17 s/500 m | - | 4 min Schlagzahl 20 (Block 3/3) |
| work | 3:00 min | 22 | 4 | 2k +11..+14 s/500 m | - | 3 min Schlagzahl 22, schneller (Block 3/3) |
| work | 2:00 min | 24 | 4 | 2k +8..+11 s/500 m | - | 2 min Schlagzahl 24, nochmals schneller (Block 3/3) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Over-Under 3 x 12 Minuten (`schwelle-over-under-3x12`)

- Erklärung: Drei Blöcke zu 12 Minuten, in denen sich je 2 Minuten knapp unter und knapp über der Schwelle abwechseln. 4 Minuten Pause.
- Zweck/Bereich: Schwelle / AT, Laktattoleranz an der Schwelle (Puls ca. 83-90 % HFmax, Pulszone 4)
- Niveau: Leistung; Kategorie: Schwelle; Tags: hard, threshold, over-under
- Belegstatus: angepasst: Over-Under-Format aus dem Radsport (TrainerRoad 'Bear Creek': 3 x 12 min, 2 min 95 % / 2 min 105 % FTP) aufs Rudern übertragen; Pace abgeleitet aus Watt ~ 1/Pace^3 mit Schwellentempo ca. 2k + 11 s (95 % -> ca. +13 s, 105 % -> ca. +8 s). Keine Ruderquelle für Over-Unders gefunden
- Quellen: TrainerRoad - Over-Under Intervals & Workouts: The Science Behind Them (e.g. 3 x 12 min alternating 2 min at 95 % / 2 min at 105 % FTP); cycling, secondary source (2021-11-23); Concept2 - Heart Rate Training with Your Concept2 Erg (zone 4 = 80-90 % HRmax, hard to hold more than 10 min) (2025-04-17); Faster Masters Rowing - How to Set Target Erg Splits (5k target = 2k pace + 7-8 s); coaching site, secondary source
- Geschätzte Gesamtdauer: ca. 57 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 2:00 min | 20-22 | 4 | 2k +12..+14 s/500 m | - | Unter Schwelle 2 min (Block 1/3, 1/3) |
| work | 2:00 min | 24-26 | 4 | 2k +7..+9 s/500 m | - | Über Schwelle 2 min (Block 1/3, 1/3) |
| work | 2:00 min | 20-22 | 4 | 2k +12..+14 s/500 m | - | Unter Schwelle 2 min (Block 1/3, 2/3) |
| work | 2:00 min | 24-26 | 4 | 2k +7..+9 s/500 m | - | Über Schwelle 2 min (Block 1/3, 2/3) |
| work | 2:00 min | 20-22 | 4 | 2k +12..+14 s/500 m | - | Unter Schwelle 2 min (Block 1/3, 3/3) |
| work | 2:00 min | 24-26 | 4 | 2k +7..+9 s/500 m | - | Über Schwelle 2 min (Block 1/3, 3/3) |
| rest | 4:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2:00 min | 20-22 | 4 | 2k +12..+14 s/500 m | - | Unter Schwelle 2 min (Block 2/3, 1/3) |
| work | 2:00 min | 24-26 | 4 | 2k +7..+9 s/500 m | - | Über Schwelle 2 min (Block 2/3, 1/3) |
| work | 2:00 min | 20-22 | 4 | 2k +12..+14 s/500 m | - | Unter Schwelle 2 min (Block 2/3, 2/3) |
| work | 2:00 min | 24-26 | 4 | 2k +7..+9 s/500 m | - | Über Schwelle 2 min (Block 2/3, 2/3) |
| work | 2:00 min | 20-22 | 4 | 2k +12..+14 s/500 m | - | Unter Schwelle 2 min (Block 2/3, 3/3) |
| work | 2:00 min | 24-26 | 4 | 2k +7..+9 s/500 m | - | Über Schwelle 2 min (Block 2/3, 3/3) |
| rest | 4:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2:00 min | 20-22 | 4 | 2k +12..+14 s/500 m | - | Unter Schwelle 2 min (Block 3/3, 1/3) |
| work | 2:00 min | 24-26 | 4 | 2k +7..+9 s/500 m | - | Über Schwelle 2 min (Block 3/3, 1/3) |
| work | 2:00 min | 20-22 | 4 | 2k +12..+14 s/500 m | - | Unter Schwelle 2 min (Block 3/3, 2/3) |
| work | 2:00 min | 24-26 | 4 | 2k +7..+9 s/500 m | - | Über Schwelle 2 min (Block 3/3, 2/3) |
| work | 2:00 min | 20-22 | 4 | 2k +12..+14 s/500 m | - | Unter Schwelle 2 min (Block 3/3, 3/3) |
| work | 2:00 min | 24-26 | 4 | 2k +7..+9 s/500 m | - | Über Schwelle 2 min (Block 3/3, 3/3) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Schwelle Einstieg 3 x 1500 m (`schwelle-einsteiger-3x1500`)

- Erklärung: Drei Stücke zu 1500 m gleichmässig zügig mit 3 Minuten Pause. Einstieg in Distanz-Intervalle an der Schwelle.
- Zweck/Bereich: UT1 bis AT (Puls ca. 75-85 % HFmax, Pulszone 3-4)
- Niveau: Einsteiger; Kategorie: Schwelle; Tags: moderate, threshold, beginner-friendly
- Belegstatus: direkt: Pete Plan Beginner Woche 7 (3 x 1500 m / 3 min, Schlagzahl 24 oder tiefer); Pace-Offset abgeleitet (für Einsteiger etwas langsamer als 5-km-Tempo)
- Quellen: The Pete Plan (Pete Marston), coaching blog; secondary source - The Pete Plan - Beginner Training (24 weeks; e.g. 2 x 10 min, 3 x 8 min, 3 x 10 min, 2 x 15 min, 4 x 8 min / 2 min; 3 x 1500 m / 3 min; 3 x 2000 m / 4 min); Concept2 - Heart Rate Training with Your Concept2 Erg (zone 4 = 80-90 % HRmax, hard to hold more than 10 min) (2025-04-17)
- Geschätzte Gesamtdauer: ca. 36 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 5:00 min | 18-22 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 1500 m | 22-24 | 4 | 2k +12..+15 s/500 m | - | 1500 m gleichmässig zügig, Schlagzahl höchstens 24 (1/3) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1500 m | 22-24 | 4 | 2k +12..+15 s/500 m | - | 1500 m gleichmässig zügig, Schlagzahl höchstens 24 (2/3) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1500 m | 22-24 | 4 | 2k +12..+15 s/500 m | - | 1500 m gleichmässig zügig, Schlagzahl höchstens 24 (3/3) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Schwelle 3 x 2000 m (`schwelle-3x2000`)

- Erklärung: Drei Stücke zu 2000 m etwas schneller als das 6-km-Tempo mit 4 Minuten Pause; alle drei im gleichen Tempo.
- Zweck/Bereich: Schwelle / AT (Puls ca. 80-90 % HFmax, Pulszone 4)
- Niveau: Fortgeschritten; Kategorie: Schwelle; Tags: hard, threshold
- Belegstatus: direkt: Pete Plan Beginner Woche 6/10/14 (3 x 2000 m / 4 min, ca. 2 s schneller als 6000-m-Tempo, Tempo bis zur dritten halten); Concept2 5k-Plan (2 x 2K / 4 min). Pace-Offset abgeleitet aus 5k = 2k + 7-8 s
- Quellen: The Pete Plan (Pete Marston), coaching blog; secondary source - The Pete Plan - Beginner Training (24 weeks; e.g. 2 x 10 min, 3 x 8 min, 3 x 10 min, 2 x 15 min, 4 x 8 min / 2 min; 3 x 1500 m / 3 min; 3 x 2000 m / 4 min); Concept2 - Training for a 5K Rowing Ergometer Test (2 x 2K / 4 min, 2 x 3K / 4 min, rate 24-30, negative split); Faster Masters Rowing - How to Set Target Erg Splits (5k target = 2k pace + 7-8 s); coaching site, secondary source
- Geschätzte Gesamtdauer: ca. 47 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 2000 m | 22-26 | 4 | 2k +8..+10 s/500 m | - | 2000 m, Tempo halten (1/3) |
| rest | 4:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2000 m | 22-26 | 4 | 2k +8..+10 s/500 m | - | 2000 m, Tempo halten (2/3) |
| rest | 4:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2000 m | 22-26 | 4 | 2k +8..+10 s/500 m | - | 2000 m, Tempo halten (3/3) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Schwelle 2 x 3000 m (`schwelle-2x3000`)

- Erklärung: Zwei Stücke zu 3000 m im Tempo der letzten 2 x 2000 m mit 4 Minuten Pause. Klassische Vorbereitung auf 5000 m.
- Zweck/Bereich: Schwelle / AT (Puls ca. 80-90 % HFmax, Pulszone 4)
- Niveau: Fortgeschritten; Kategorie: Schwelle; Tags: hard, threshold
- Belegstatus: direkt: Concept2 5k-Plan Woche 3 (2 x 3K / 4 min, Ziel = Durchschnittstempo der 2 x 2K, Schlagzahl 24-30); Pace-Offset abgeleitet (knapp unter 5-km-Tempo)
- Quellen: Concept2 - Training for a 5K Rowing Ergometer Test (2 x 2K / 4 min, 2 x 3K / 4 min, rate 24-30, negative split); Faster Masters Rowing - How to Set Target Erg Splits (5k target = 2k pace + 7-8 s); coaching site, secondary source
- Geschätzte Gesamtdauer: ca. 43 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 3000 m | 24-28 | 4 | 2k +7..+10 s/500 m | - | 3000 m im Tempo der 2 x 2000 m (1/2) |
| rest | 4:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 3000 m | 24-28 | 4 | 2k +7..+10 s/500 m | - | 3000 m im Tempo der 2 x 2000 m (2/2) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 4 x 2000 m (Pete Plan) (`schwelle-4x2000`)

- Erklärung: Vier Stücke zu 2000 m knapp im 5-km-Tempo mit 5 Minuten Pause; die letzte Wiederholung so schnell wie möglich.
- Zweck/Bereich: Schwelle / Tempoausdauer (Puls ca. 85-92 % HFmax, Pulszone 4-5)
- Niveau: Leistung; Kategorie: Schwelle; Tags: hard, threshold, race-pace
- Belegstatus: direkt: Pete Plan Woche 2 (4 x 2000 m / 5 min, Referenz 5k-Tempo + 0,5 s, alle bis auf die letzte im haltbaren Tempo, die letzte voll); Pace-Offset aus 5k = 2k + 7-8 s abgeleitet, Schlagzahl 24-28 eingegrenzt
- Quellen: The Pete Plan (Pete Marston), coaching blog; secondary source - The Pete Plan (3-week cycle with pace targets: 5 x 1500 m at 5k pace, 4 x 2000 m at 5k + 0.5 s, 3k/2.5k/2k at 5k + 1 s, 5 min rest); Faster Masters Rowing - How to Set Target Erg Splits (5k target = 2k pace + 7-8 s); coaching site, secondary source
- Geschätzte Gesamtdauer: ca. 62 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 2000 m | 24-28 | 4 | 2k +7..+9 s/500 m | - | 2000 m im 5-km-Tempo (1/4) |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2000 m | 24-28 | 4 | 2k +7..+9 s/500 m | - | 2000 m im 5-km-Tempo (2/4) |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2000 m | 24-28 | 4 | 2k +7..+9 s/500 m | - | 2000 m im 5-km-Tempo (3/4) |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2000 m | 26-30 | 5 | 2k +4..+8 s/500 m | - | 2000 m, letzte so schnell wie möglich (4/4) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 4 x 2000 m progressiv (`schwelle-4x2000-progressiv`)

- Erklärung: Vier Stücke zu 2000 m, jedes 2 Sekunden pro 500 m schneller: vom oberen UT1 bis ins 5-km-Tempo. 4 Minuten Pause.
- Zweck/Bereich: UT1 bis Schwelle, Tempo steigern lernen (Puls ca. 75-88 % HFmax, Pulszone 3-4)
- Niveau: Fortgeschritten; Kategorie: Schwelle; Tags: hard, threshold, progressive
- Belegstatus: abgeleitet: Steigerungsprinzip aus Pete Plan Beginner ('faster last', negative Splits), Wolfson (negative splitting) und Concept2 (negativer Split); Abstufung 2 s je Stück und Offsets selbst gesetzt
- Quellen: The Pete Plan (Pete Marston), coaching blog; secondary source - The Pete Plan - Beginner Training (24 weeks; e.g. 2 x 10 min, 3 x 8 min, 3 x 10 min, 2 x 15 min, 4 x 8 min / 2 min; 3 x 1500 m / 3 min; 3 x 2000 m / 4 min); Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6 (bands, 3 x 6 min r26, 30r20, negative splitting); club guide, secondary source (2019); Concept2 - Training for a 5K Rowing Ergometer Test (2 x 2K / 4 min, 2 x 3K / 4 min, rate 24-30, negative split); Faster Masters Rowing - How to Set Target Erg Splits (5k target = 2k pace + 7-8 s); coaching site, secondary source
- Geschätzte Gesamtdauer: ca. 60 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 2000 m | 20-22 | 3 | 2k +13..+14 s/500 m | - | 2000 m ruhig, Schlagzahl 20-22 (1/4) |
| rest | 4:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2000 m | 22-24 | 4 | 2k +11..+12 s/500 m | - | 2000 m, Schlagzahl 22-24, 2 s schneller als zuvor (2/4) |
| rest | 4:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2000 m | 24-26 | 4 | 2k +9..+10 s/500 m | - | 2000 m, Schlagzahl 24-26, 2 s schneller als zuvor (3/4) |
| rest | 4:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2000 m | 26-28 | 4 | 2k +7..+8 s/500 m | - | 2000 m, Schlagzahl 26-28, 2 s schneller als zuvor (4/4) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 5 x 1500 m (Pete Plan) (`schwelle-5x1500`)

- Erklärung: Fünf Stücke zu 1500 m im 5-km-Tempo mit 5 Minuten Pause; die letzte so schnell wie möglich.
- Zweck/Bereich: Schwelle / Tempoausdauer (Puls ca. 85-92 % HFmax, Pulszone 4-5)
- Niveau: Leistung; Kategorie: Schwelle; Tags: hard, threshold, race-pace
- Belegstatus: direkt: Pete Plan Woche 1 (5 x 1500 m / 5 min, Referenz 5k-Tempo, letzte voll); Concept2 'Race Day Prep' (5 x 1500 m / 1 min, hart) als härtere Variante. Pace-Offset aus 5k = 2k + 7-8 s abgeleitet
- Quellen: The Pete Plan (Pete Marston), coaching blog; secondary source - The Pete Plan (3-week cycle with pace targets: 5 x 1500 m at 5k pace, 4 x 2000 m at 5k + 0.5 s, 3k/2.5k/2k at 5k + 1 s, 5 min rest); Concept2 - 7 Best Worst Workouts (Race Day Prep: 5 x 1500 m / 1 min) (2018-02-08); Faster Masters Rowing - How to Set Target Erg Splits (5k target = 2k pace + 7-8 s); coaching site, secondary source
- Geschätzte Gesamtdauer: ca. 65 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 1500 m | 24-28 | 4 | 2k +6..+8 s/500 m | - | 1500 m im 5-km-Tempo (1/5) |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1500 m | 24-28 | 4 | 2k +6..+8 s/500 m | - | 1500 m im 5-km-Tempo (2/5) |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1500 m | 24-28 | 4 | 2k +6..+8 s/500 m | - | 1500 m im 5-km-Tempo (3/5) |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1500 m | 24-28 | 4 | 2k +6..+8 s/500 m | - | 1500 m im 5-km-Tempo (4/5) |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1500 m | 26-30 | 5 | 2k +3..+7 s/500 m | - | 1500 m, letzte so schnell wie möglich (5/5) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 3000-2500-2000 m (Pete Plan) (`schwelle-3000-2500-2000`)

- Erklärung: Drei Stücke mit abnehmender Länge (3000, 2500, 2000 m) knapp im 5-km-Tempo, 5 Minuten Pause; das letzte voll.
- Zweck/Bereich: Schwelle / Tempoausdauer (Puls ca. 85-92 % HFmax, Pulszone 4-5)
- Niveau: Leistung; Kategorie: Schwelle; Tags: hard, threshold, ladder
- Belegstatus: direkt: Pete Plan Woche 3 (3k, 2.5k, 2k / 5 min, Referenz 5k-Tempo + 1 s, letzte voll); Pace-Offset aus 5k = 2k + 7-8 s abgeleitet
- Quellen: The Pete Plan (Pete Marston), coaching blog; secondary source - The Pete Plan (3-week cycle with pace targets: 5 x 1500 m at 5k pace, 4 x 2000 m at 5k + 0.5 s, 3k/2.5k/2k at 5k + 1 s, 5 min rest); Faster Masters Rowing - How to Set Target Erg Splits (5k target = 2k pace + 7-8 s); coaching site, secondary source
- Geschätzte Gesamtdauer: ca. 55 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 3000 m | 24-28 | 4 | 2k +8..+9 s/500 m | - | 3000 m im 5-km-Tempo + 1 s (1/3) |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2500 m | 24-28 | 4 | 2k +8..+9 s/500 m | - | 2500 m im 5-km-Tempo + 1 s (2/3) |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2000 m | 26-30 | 5 | 2k +5..+8 s/500 m | - | 2000 m, letzte so schnell wie möglich (3/3) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Schwelle 2 x 5000 m (`schwelle-2x5000`)

- Erklärung: Zwei lange Stücke zu 5000 m im Stundentempo bei Schlagzahl 22-24, 5 Minuten Pause. Lange Schwellenausdauer.
- Zweck/Bereich: Obere UT1 bis AT (Puls ca. 78-85 % HFmax, Pulszone 3-4)
- Niveau: Leistung; Kategorie: Schwelle; Tags: hard, threshold, aerobic
- Belegstatus: abgeleitet: Distanzblöcke von 5000-8000 m (Wolfson, dort UT2) und 2 x 2500 m / 2 min (Pete Plan Beginner) zu 2 x 5000 m im oberen UT1/AT verlängert; Tempo nahe Wolverine Level 3 (ca. 2k + 15 s, hier etwas schneller). Pace-Offset abgeleitet
- Quellen: Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6 (bands, 3 x 6 min r26, 30r20, negative splitting); club guide, secondary source (2019); The Pete Plan (Pete Marston), coaching blog; secondary source - The Pete Plan - Beginner Training (24 weeks; e.g. 2 x 10 min, 3 x 8 min, 3 x 10 min, 2 x 15 min, 4 x 8 min / 2 min; 3 x 1500 m / 3 min; 3 x 2000 m / 4 min); Concept2 Forum (c2forum.com) - New Wolverine Plan Thread (M. Caviston: Level 2 about 2K + 8, Level 3 about 2K + 15; Level 3 intervals 5' on / 1'40" off, 8-10 x 1500 m), forum posts 18-19 Dec 2009 (2009-12-19)
- Geschätzte Gesamtdauer: ca. 62 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 5000 m | 22-24 | 4 | 2k +12..+15 s/500 m | - | 5000 m im Stundentempo, gleichmässig (1/2) |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 5000 m | 22-24 | 4 | 2k +12..+15 s/500 m | - | 5000 m im Stundentempo, gleichmässig (2/2) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 6000 m negativer Split (`schwelle-6000-negativ`)

- Erklärung: 6000 m ohne Pause in drei Abschnitten zu 2000 m; jeder Abschnitt 3 Sekunden pro 500 m schneller und 2 Schläge höher.
- Zweck/Bereich: UT1 bis AT, Tempo kontrolliert steigern (Puls ca. 75-88 % HFmax, Pulszone 3-4)
- Niveau: Fortgeschritten; Kategorie: Schwelle; Tags: moderate, threshold, negative-split, progressive
- Belegstatus: angepasst: Pete Plan Beginner (8000 m: 6000 m gleichmässig, letzte 2000 m schneller; 'negative-split the 8000m'), Wolfson und Concept2 (negativer Split: langsamer starten, dann steigern); auf 6000 m in drei Stufen übertragen, Offsets abgeleitet. Kein Test (der 6000-m-Test gehört zur Familie tests)
- Quellen: The Pete Plan (Pete Marston), coaching blog; secondary source - The Pete Plan - Beginner Training (24 weeks; e.g. 2 x 10 min, 3 x 8 min, 3 x 10 min, 2 x 15 min, 4 x 8 min / 2 min; 3 x 1500 m / 3 min; 3 x 2000 m / 4 min); Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6 (bands, 3 x 6 min r26, 30r20, negative splitting); club guide, secondary source (2019); Concept2 - Training for a 5K Rowing Ergometer Test (2 x 2K / 4 min, 2 x 3K / 4 min, rate 24-30, negative split)
- Geschätzte Gesamtdauer: ca. 40 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 2000 m | 20-22 | 3 | 2k +15..+17 s/500 m | - | 2000 m ruhig, Schlagzahl 20-22 (Abschnitt 1/3) |
| work | 2000 m | 22-24 | 4 | 2k +12..+14 s/500 m | - | 2000 m 3 s schneller, Schlagzahl 22-24 (Abschnitt 2/3) |
| work | 2000 m | 24-26 | 4 | 2k +9..+11 s/500 m | - | 2000 m nochmals 3 s schneller, Schlagzahl 24-26 (Abschnitt 3/3) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Lange Intervalle 4 x 8 Minuten (`intervalle-4x8`)

- Erklärung: Vier Intervalle zu 8 Minuten im höchsten Tempo, das man über alle vier gleichmässig halten kann, mit 2 Minuten Pause.
- Zweck/Bereich: Hohe aerobe Leistung zwischen Schwelle und VO2max (Puls ca. 88-92 % HFmax, Pulszone 4-5)
- Niveau: Leistung; Kategorie: Intervalle; Tags: hard, vo2max, threshold
- Belegstatus: angepasst: Seiler et al. 2013 (RCT, Radfahrer: 4 x 8 min bei maximal haltbarer Intensität, ca. 90 % HFpeak, brachte grössere Zuwächse als 4 x 4 und 4 x 16 min); Pause 2 min aus Pete Plan Beginner (4 x 8 min / 2 min). Pace-Offset und Schlagzahl abgeleitet (ca. 5-km-Tempo + 0..2 s)
- Quellen: Wiley - Seiler S, Joranson K, Olesen BV, Hetlelid KJ: Adaptations to aerobic interval training: interactive effects of exercise intensity and total work duration. Scand J Med Sci Sports 23(1):74-83, doi:10.1111/j.1600-0838.2011.01351.x (2013); The Pete Plan (Pete Marston), coaching blog; secondary source - The Pete Plan - Beginner Training (24 weeks; e.g. 2 x 10 min, 3 x 8 min, 3 x 10 min, 2 x 15 min, 4 x 8 min / 2 min; 3 x 1500 m / 3 min; 3 x 2000 m / 4 min); Concept2 - Heart Rate Training with Your Concept2 Erg (zone 4 = 80-90 % HRmax, hard to hold more than 10 min) (2025-04-17)
- Geschätzte Gesamtdauer: ca. 53 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-28 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 8:00 min | 24-28 | 4 | 2k +6..+9 s/500 m | - | Intervall 8 min, hart und gleichmässig (1/4) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 8:00 min | 24-28 | 4 | 2k +6..+9 s/500 m | - | Intervall 8 min, hart und gleichmässig (2/4) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 8:00 min | 24-28 | 4 | 2k +6..+9 s/500 m | - | Intervall 8 min, hart und gleichmässig (3/4) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 8:00 min | 24-28 | 4 | 2k +6..+9 s/500 m | - | Intervall 8 min, hart und gleichmässig (4/4) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Kraftausdauer 3 x 6 Minuten, Schlagzahl 26 (`intervalle-3x6-r26`)

- Erklärung: Drei Intervalle zu 6 Minuten bei Schlagzahl 26 mit 3 Minuten Pause; jedes Intervall gleichmässig und etwa 1 Sekunde schneller als das vorige.
- Zweck/Bereich: AT bis TR, Kraftausdauer bei Renn-nahem Rhythmus (Puls ca. 85-92 % HFmax, Pulszone 4-5)
- Niveau: Fortgeschritten; Kategorie: Intervalle; Tags: hard, threshold, power, progressive
- Belegstatus: direkt: Wolfson 'Power' (3 x 6 min, r26, 3 min Pause, Split halten, nächstes Stück eine Sekunde oder mehr schneller; später 3 x 8 min); Pace-Offset abgeleitet
- Quellen: Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6 (bands, 3 x 6 min r26, 30r20, negative splitting); club guide, secondary source (2019); Concept2 - Heart Rate Training with Your Concept2 Erg (zone 4 = 80-90 % HRmax, hard to hold more than 10 min) (2025-04-17)
- Geschätzte Gesamtdauer: ca. 36 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 7:00 min | 18-26 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 6:00 min | 26 | 4 | 2k +8..+10 s/500 m | - | 6 min bei Schlagzahl 26, Split halten (1/3) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 6:00 min | 26 | 4 | 2k +7..+9 s/500 m | - | 6 min bei Schlagzahl 26, Split halten, 1 s schneller als zuvor (2/3) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 6:00 min | 26 | 4 | 2k +6..+8 s/500 m | - | 6 min bei Schlagzahl 26, Split halten, 1 s schneller als zuvor (3/3) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Wolverine Level 3: 8 x 5 Minuten (`intervalle-wolverine-8x5`)

- Erklärung: Acht Intervalle zu 5 Minuten im oberen UT1 mit kurzer lockerer Pause von 1:40 (Verhältnis 3:1). Viel Arbeitszeit knapp unter der Schwelle.
- Zweck/Bereich: Obere UT1 / Wolverine Level 3 (Puls ca. 75-85 % HFmax, Pulszone 3-4)
- Niveau: Leistung; Kategorie: Intervalle; Tags: moderate, aerobic, threshold
- Belegstatus: direkt: Caviston (Wolverine Plan, Level 3: 5' on / 1'40" off, Gesamtarbeit 75-90 % der 60-min-Level-3-Distanz, Tempo ca. 60-min-L3-Tempo - 3 s; L3 ca. 2K + 15 s). Schlagzahl nicht angegeben, hier 20-24 gesetzt; Pace-Offset abgeleitet
- Quellen: Concept2 Forum (c2forum.com) - New Wolverine Plan Thread (M. Caviston: Level 2 about 2K + 8, Level 3 about 2K + 15; Level 3 intervals 5' on / 1'40" off, 8-10 x 1500 m), forum posts 18-19 Dec 2009 (2009-12-19); Sportscience (sportsci.org) - Intervals, Thresholds, and Long Slow Distance: the Role of Intensity and Duration in Endurance Training (Seiler & Tonnessen), Sportscience 13, 32-53 (2009)
- Geschätzte Gesamtdauer: ca. 65 min (Distanzphasen bei 2:00/500 m Referenz)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern: locker, steigernd, am Ende kurze Antritte |
| work | 5:00 min | 20-24 | 3 | 2k +11..+14 s/500 m | - | Intervall 5 min, oberes UT1 (1/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 5:00 min | 20-24 | 3 | 2k +11..+14 s/500 m | - | Intervall 5 min, oberes UT1 (2/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 5:00 min | 20-24 | 3 | 2k +11..+14 s/500 m | - | Intervall 5 min, oberes UT1 (3/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 5:00 min | 20-24 | 3 | 2k +11..+14 s/500 m | - | Intervall 5 min, oberes UT1 (4/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 5:00 min | 20-24 | 3 | 2k +11..+14 s/500 m | - | Intervall 5 min, oberes UT1 (5/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 5:00 min | 20-24 | 3 | 2k +11..+14 s/500 m | - | Intervall 5 min, oberes UT1 (6/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 5:00 min | 20-24 | 3 | 2k +11..+14 s/500 m | - | Intervall 5 min, oberes UT1 (7/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 5:00 min | 20-24 | 3 | 2k +11..+14 s/500 m | - | Intervall 5 min, oberes UT1 (8/8) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Fundus

Zurückgeschrieben (Projekt `rowcoach`, Thema `endurance-training`): siehe Bericht; IDs werden nach dem Schreiben unten ergänzt.
