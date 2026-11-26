# Trainingspläne RowCoach: Übersicht

Lesbare Fassung von `App/RowCoach/Resources/training_plans.json` (erzeugt aus den Daten, Stand 26.11.2026). Regeln, Belege und Format: `RECHERCHE.md`.
Legende: Reihenfolge = empfohlene Abfolge in der Woche, *kursiv* = freiwillig, **fett** = Zieleinheit; D = leichtere Woche (Deload), T = Tapering.

| id | Ziel | Niveau | Wochen | Einheiten/Woche | Minuten/Woche | Beleg |
|---|---|---|---|---|---|---|
| `einstieg-4-wochen` | 30 Minuten am Stück locker rudern und eine erste Referenz (10-Minuten-Test) haben. | Einsteiger | 4 | 3–3 | 55–90 | angepasst |
| `einstieg-8-wochen-5000m` | 5000 m am Stück in gleichmässigem Tempo rudern. | Einsteiger | 8 | 3–4 | 55–145 | angepasst |
| `fitness-3x-12-wochen` | Ausdauer verbessern und die Empfehlung von rund 150 Minuten Bewegung pro Woche mit Rudern gut abdecken. | Einsteiger | 12 | 3–4 | 70–150 | abgeleitet |
| `erhaltung-2x` | Ausdauer und 2000-m-Form über Wochen mit wenig Zeit halten. | Fortgeschritten | 8 | 2–3 | 60–110 | abgeleitet |
| `wiedereinstieg-3-wochen` | Nach 2–8 Wochen Pause (Ferien, Krankheit, Arbeit) ohne Rückschlag zum alten Plan zurückfinden. | Einsteiger | 3 | 3–3 | 95–110 | abgeleitet |
| `grundlage-winter-12-wochen` | Die aerobe Grundlage für die Saison aufbauen (rund 80 % locker) und den 5000-m-Wert verbessern. | Fortgeschritten | 12 | 3–4 | 95–240 | angepasst |
| `test-2000m-8-wochen-einsteiger` | Einen 2000-m-Test gut eingeteilt fahren und eine erste Bestzeit setzen. | Einsteiger | 8 | 3–4 | 65–145 | angepasst |
| `test-2000m-8-wochen-fortgeschritten` | Die eigene 2000-m-Bestzeit verbessern. | Fortgeschritten | 8 | 3–4 | 90–190 | angepasst |
| `test-2000m-12-wochen-fortgeschritten` | Die 2000-m-Bestzeit deutlich verbessern. | Fortgeschritten | 12 | 3–4 | 90–205 | angepasst |
| `test-2000m-12-wochen-leistung` | Neue 2000-m-Bestzeit auf hohem Niveau. | Leistung | 12 | 4–5 | 115–290 | angepasst |
| `langdistanz-5000m-8-wochen` | Die 5000-m-Zeit verbessern (6000 m als Alternative für den Schlusstest). | Fortgeschritten | 8 | 3–4 | 100–210 | angepasst |
| `halbmarathon-12-wochen` | Einen Halbmarathon (21 097 m) gleichmässig zu Ende rudern. | Fortgeschritten | 12 | 4–4 | 155–255 | angepasst |
| `marathon-16-wochen` | Einen Marathon (42 195 m) rudern. | Leistung | 16 | 4–4 | 150–315 | angepasst |
| `masters-50plus-12-wochen` | Ausdauer und 2000-m-Form verbessern, ohne die Erholung zu überfordern. | Fortgeschritten | 12 | 3–4 | 75–160 | abgeleitet |
| `polarisiert-80-20-10-wochen` | VO2max und 2000-m-Leistung mit einem klaren Hart-locker-Muster verbessern. | Fortgeschritten | 10 | 4–5 | 125–290 | angepasst |
| `pete-artig-24-wochen` | Über ein halbes Jahr stetig schneller werden und mit einem 2000-m-Test abschliessen. | Fortgeschritten | 24 | 3–4 | 75–220 | angepasst |
| `wettkampf-tapering-3-wochen` | Am Wettkampftag (Indoor-Rennen oder 2000-m-Test) frisch und schnell sein. | Leistung | 3 | 4–4 | 115–200 | direkt |

## Einstieg in 4 Wochen (`einstieg-4-wochen`)

Drei kurze Einheiten pro Woche: Gerät und Technik kennenlernen, dann Schritt für Schritt länger rudern, bis 30 Minuten locker gehen.

- Ziel: 30 Minuten am Stück locker rudern und eine erste Referenz (10-Minuten-Test) haben.
- Niveau: Einsteiger, Kategorie `einstieg`
- Voraussetzung: Keine. Gesund und ohne Beschwerden; wer lange nicht trainiert hat oder Vorerkrankungen hat, klärt das vorher ärztlich ab.
- Regeln: maxConsecutiveDays=1, hardSessionsMinGapHours=48, missedSessionPolicy=shift, repeatWeekIfMissed=2
- Beleg: angepasst: Ablauf nach Concept2 Couch to Consistency (Woche 1: 13 min, 15 min am Stück; Woche 3: 4000 m) und British Rowing Go Row Beginner (kurze Stücke, Schlagzahl 18–24); Ruhetag zwischen den Einheiten und Woche wiederholen nach NHS Couch to 5K; Einheiten auf vorhandene Programme abgebildet (kürzestes Programm 17 min statt 13 min).
- Quellen: [Concept2: Beginner's Training Plan (Couch to Consistency)](https://www.concept2.com/training/plans/couch-to-consistency); [British Rowing: Go Row Indoor – Beginner Training Plan (8 weeks)](https://www.britishrowing.org/wp-content/uploads/2016/10/BR_Go_Row_A4_Beginners_Training_Plan_P3.pdf); [NHS (UK National Health Service): Couch to 5K running plan](https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/couch-to-5k-running-plan); [American College of Sports Medicine / Wolters Kluwer: Garber et al.: Quantity and quality of exercise for developing and maintaining cardiorespi](https://pubmed.ncbi.nlm.nih.gov/21694556/); [British Rowing: How Much How Often (rower development levels: sessions per week, session length, hours)](https://www.britishrowing.org/wp-content/uploads/2019/03/How-Much-How-Often-210219.pdf)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Gerät kennenlernen: kurze Stücke, Ablauf Beine–Rücken–Arme | Einstieg: 1-2-3-2-1 Minuten (leicht) → Einstieg: 90 Sekunden rudern, 30 Sekunden locker (leicht) → Technik und Regeneration 25 Minuten (leicht) |
| 2 | Etwas länger, ruhiger Rhythmus | Einstieg: 90 Sekunden rudern, 30 Sekunden locker (leicht) → Pausendrill: Arme vorne, Körper vorne (leicht) → Kurze Grundlage 20 Minuten (leicht) |
| 3 | Erste zügigere Minuten, 30 Minuten locker | Lockere Grundlage 30 Minuten (leicht) → Schwelle Einstieg 3 x 5 Minuten (mittel) → Schlagzahl-Zehner, 20 Minuten (leicht) |
| 4 | 5000 m locker und erste Referenz | Frequenzleiter 18-20-22-24 (mittel) → Grundlage 5000 m (leicht) → **Einsteiger-Test 10 Minuten (mittel)** |

## In 8 Wochen zu 5000 m am Stück (`einstieg-8-wochen-5000m`)

Aufbau von kurzen Stücken bis zu 5000 m ohne Pause; ab Woche 3 eine zügigere Einheit pro Woche, ab Woche 6 kurze harte Stücke.

- Ziel: 5000 m am Stück in gleichmässigem Tempo rudern.
- Niveau: Einsteiger, Kategorie `einstieg`
- Voraussetzung: Keine; ideal nach „Einstieg in 4 Wochen“, aber auch direkt möglich.
- Regeln: deloadEvery=4, maxConsecutiveDays=1, hardSessionsMinGapHours=48, missedSessionPolicy=shift, retestWeek=8, repeatWeekIfMissed=2
- Beleg: angepasst: Progression nach Concept2 Couch to Consistency (2000 m → 4000 m in Woche 3 → 5000 m in Woche 6) und British Rowing Go Row Beginner (8 Wochen, harte 1-Minuten-Stücke ab Woche 6, Ziel 2000 m); 9-Wochen-Logik und „Woche wiederholen ist in Ordnung“ aus NHS Couch to 5K; leichtere Woche 4 abgeleitet (3:1-Rhythmus, Praxisregel).
- Quellen: [Concept2: Beginner's Training Plan (Couch to Consistency)](https://www.concept2.com/training/plans/couch-to-consistency); [British Rowing: Go Row Indoor – Beginner Training Plan (8 weeks)](https://www.britishrowing.org/wp-content/uploads/2016/10/BR_Go_Row_A4_Beginners_Training_Plan_P3.pdf); [NHS (UK National Health Service): Couch to 5K running plan](https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/couch-to-5k-running-plan); [American College of Sports Medicine / Wolters Kluwer: Garber et al.: Quantity and quality of exercise for developing and maintaining cardiorespi](https://pubmed.ncbi.nlm.nih.gov/21694556/); [Sportscience (sportsci.org): Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity a](https://sportsci.org/2009/ss.htm)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Gerät und Technik kennenlernen | Einstieg: 1-2-3-2-1 Minuten (leicht) → Einstieg: 90 Sekunden rudern, 30 Sekunden locker (leicht) → Technik und Regeneration 25 Minuten (leicht) |
| 2 | Länger rudern, ruhiger Rhythmus | Einstieg: 90 Sekunden rudern, 30 Sekunden locker (leicht) → Pausendrill: Arme vorne, Körper vorne (leicht) → Kurze Grundlage 20 Minuten (leicht) |
| 3 | Erste zügigere Blöcke | Lockere Grundlage 30 Minuten (leicht) → Schwelle Einstieg 3 x 5 Minuten (mittel) → Kurze Grundlage 20 Minuten (leicht) → *Pick-Drill und Grundlage (leicht)* |
| 4 D | Leichtere Woche: festigen | Regeneration 20 Minuten (leicht) → Einstieg: 1-2-3-2-1 Minuten (leicht) → Technik und Regeneration 25 Minuten (leicht) |
| 5 | Länger im Gesprächstempo | Lockere Grundlage 30 Minuten (leicht) → Schwelle Einstieg 3 x 5 Minuten (mittel) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → *Schlagzahl-Zehner, 20 Minuten (leicht)* |
| 6 | Erste harte Minuten | Einstieg Intervalle 6 x 1 Minute (hart) → Lockere Grundlage 30 Minuten (leicht) → Schwelle 2 x 10 Minuten (mittel) → *Ratio-Training: schneller Durchzug, langes Vorrollen (leicht)* |
| 7 | 40 Minuten mit tiefer Schlagzahl | Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Einstieg 5 x 500 m (hart) → Grundlage mit Schlagzahl-Deckel 18, 30 Minuten (leicht) → *Frequenzleiter 18-20-22-24 (mittel)* |
| 8 | Ziel: 5000 m am Stück | Frequenzleiter 18-20-22-24 (mittel) → Schwelle Einstieg 3 x 1500 m (mittel) → **Grundlage 5000 m (leicht)** → *Regeneration 20 Minuten (leicht)* |

## Fitness und Gesundheit: 3-mal pro Woche (`fitness-3x-12-wochen`)

Pro Woche eine lockere, eine zügige und eine kurze harte Einheit, jede vierte Woche leichter. Nach 12 Wochen läuft der Plan ab Woche 5 weiter.

- Ziel: Ausdauer verbessern und die Empfehlung von rund 150 Minuten Bewegung pro Woche mit Rudern gut abdecken.
- Niveau: Einsteiger, Kategorie `fitness`
- Voraussetzung: 30 Minuten locker rudern geht ohne Mühe (z. B. nach einem Einstiegsplan).
- Regeln: deloadEvery=4, maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=replace-easy, retestWeek=12, repeatFrom=5
- Beleg: abgeleitet: Umfang aus ACSM 2011 (≥150 min moderat oder ≥75 min intensiv pro Woche, 3–5 Tage); Wochenmuster leicht–zügig–hart nach Concept2 Couch to Consistency „Going Forward“ (mindestens zwei gute harte Reize pro Woche, Intensität variieren), hier bewusst nur ein harter Reiz für Einsteiger; leichtere Woche alle 4 Wochen als Praxisregel.
- Quellen: [American College of Sports Medicine / Wolters Kluwer: Garber et al.: Quantity and quality of exercise for developing and maintaining cardiorespi](https://pubmed.ncbi.nlm.nih.gov/21694556/); [Concept2: Beginner's Training Plan (Couch to Consistency)](https://www.concept2.com/training/plans/couch-to-consistency); [British Rowing: Go Row Indoor – Beginner Training Plan (8 weeks)](https://www.britishrowing.org/wp-content/uploads/2016/10/BR_Go_Row_A4_Beginners_Training_Plan_P3.pdf); [Sportscience (sportsci.org): Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity a](https://sportsci.org/2009/ss.htm); [Frontiers: Stöggl & Sperlich: Polarized training has greater impact on key endurance variables than t](https://doi.org/10.3389/fphys.2014.00033)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Startwert und lockere Grundlage | Lockere Grundlage 30 Minuten (leicht) → Einsteiger-Test 10 Minuten (mittel) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) |
| 2 | Kurze harte Minuten | Einstieg Intervalle 6 x 1 Minute (hart) → Lockere Grundlage 30 Minuten (leicht) → Schwelle Einstieg 3 x 5 Minuten (mittel) → *Technik und Regeneration 25 Minuten (leicht)* |
| 3 | Zügige Blöcke | Schwelle 2 x 10 Minuten (mittel) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → 10-20-30 Intervalle (hart) → *Pick-Drill und Grundlage (leicht)* |
| 4 D | Leichtere Woche | Technik und Regeneration 25 Minuten (leicht) → Schwelle Einstieg 3 x 5 Minuten (mittel) → Regeneration 20 Minuten (leicht) |
| 5 | Etwas länger | Einstieg 5 x 500 m (hart) → Grundlage mit Schlagzahl-Deckel 18, 30 Minuten (leicht) → 30 Minuten progressiv (mittel) → *Ratio-Training: schneller Durchzug, langes Vorrollen (leicht)* |
| 6 | Mehr Abwechslung | Frequenzwechsel 22/26, 30 Minuten (mittel) → Einstieg 10 x 200 m locker-hart (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → *Frequenzleiter 18-20-22-24 (mittel)* |
| 7 | Längste Woche dieses Blocks | Schwelle Einstieg 3 x 1500 m (mittel) → Grundlage 5000 m (leicht) → Einstieg Distanzpyramide 200-500-200 m (hart) → *Schlagzahl-Zehner, 20 Minuten (leicht)* |
| 8 D | Leichtere Woche | Kurze Grundlage 20 Minuten (leicht) → Technik und Regeneration 25 Minuten (leicht) → Regeneration 20 Minuten (leicht) |
| 9 | Neuer Block: etwas mehr Druck | Kurzintervalle 8 x 2 Minuten (hart) → Grundlage mit Schlagzahl-Deckel 18, 30 Minuten (leicht) → Schwelle 2 x 10 Minuten (mittel) → *Pausendrill: Arme vorne, Körper vorne (leicht)* |
| 10 | Länger im Gesprächstempo | 30 Minuten progressiv (mittel) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Einstieg Intervalle 6 x 1 Minute (hart) → *Technik und Regeneration 25 Minuten (leicht)* |
| 11 | Höhepunkt des Blocks | Langintervalle 4 x 4 Minuten (hart) → Grundlage 5000 m (leicht) → Schwelle Einstieg 3 x 1500 m (mittel) → *Frequenzleiter 18-20-22-24 (mittel)* |
| 12 D | Leichter und Vergleich mit Woche 1 | Technik und Regeneration 25 Minuten (leicht) → Kurze Grundlage 20 Minuten (leicht) → **Einsteiger-Test 10 Minuten (mittel)** |

## Form halten mit 2 Einheiten (`erhaltung-2x`)

Für volle Wochen: eine kurze harte und eine längere lockere Einheit. Der Plan läuft ohne Ende weiter.

- Ziel: Ausdauer und 2000-m-Form über Wochen mit wenig Zeit halten.
- Niveau: Fortgeschritten, Kategorie `erhaltung`
- Voraussetzung: Mindestens 8 Wochen regelmässiges Training mit 3 oder mehr Einheiten pro Woche.
- Regeln: maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=shift, retestWeek=8, repeatFrom=1
- Beleg: abgeleitet: Spiering et al. 2021 – Ausdauerleistung blieb bis zu 15 Wochen erhalten mit nur 2 Einheiten pro Woche oder 33–66 % weniger Umfang, solange die Intensität gehalten wurde (Grundlage v. a. Studien von Hickson, nicht an Ruderern); deshalb jede Woche ein harter Reiz.
- Quellen: [Lippincott Williams & Wilkins: Spiering et al.: Maintaining physical performance: the minimal dose of exercise needed to ](https://pubmed.ncbi.nlm.nih.gov/33629972/); [Springer (Adis): Mujika & Padilla: Detraining: loss of training-induced physiological and performance adapt](https://pubmed.ncbi.nlm.nih.gov/10966148/); [Sportscience (sportsci.org): Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity a](https://sportsci.org/2009/ss.htm)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Intensität halten | Langintervalle 4 x 4 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → *Technik und Regeneration 25 Minuten (leicht)* |
| 2 | Intensität halten | Schwelle 4 x 6 Minuten (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → *Technik und Regeneration 25 Minuten (leicht)* |
| 3 | Intensität halten | Kurzintervalle 8 x 2 Minuten (hart) → Grundlage mit Schlagzahl-Deckel 18, 30 Minuten (leicht) → *Regeneration 20 Minuten (leicht)* |
| 4 | Intensität halten | Zeit-Pyramide 1-2-3-4-3-2-1 (hart) → Grundlage 10 000 m (leicht) → *Technik und Regeneration 25 Minuten (leicht)* |
| 5 | Intensität halten | 40/20 Intervalle, 10 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → *Technik und Regeneration 25 Minuten (leicht)* |
| 6 | Intensität halten | Schwelle 3 x 10 Minuten (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → *Regeneration 20 Minuten (leicht)* |
| 7 | Intensität halten | 6 x 500 m mit 1 Minute Pause (hart) → Grundlage mit Schlagzahl-Deckel 18, 30 Minuten (leicht) → *Technik und Regeneration 25 Minuten (leicht)* |
| 8 | Standortbestimmung | **Test 2000 m (maximal)** → Grundlage 10 000 m (leicht) → *Technik und Regeneration 25 Minuten (leicht)* |

## Wiedereinstieg nach einer Pause (`wiedereinstieg-3-wochen`)

Drei Wochen zurück in den Rhythmus: erst nur locker, dann eine zügige Einheit, zuletzt wieder ein harter Reiz.

- Ziel: Nach 2–8 Wochen Pause (Ferien, Krankheit, Arbeit) ohne Rückschlag zum alten Plan zurückfinden.
- Niveau: Einsteiger, Kategorie `wiedereinstieg`
- Voraussetzung: Frühere Trainingserfahrung. Nach Krankheit erst beschwerdefrei sein; nach Fieber oder Corona länger nur locker.
- Regeln: maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=skip
- Beleg: abgeleitet: Mujika & Padilla 2000/2001 – bei weniger als 4 Wochen ohne Training sinkt die VO2max bei Trainierten rasch, bei kürzlich Trainierten gehen die Zugewinne nach mehr als 4 Wochen weitgehend verloren; Stufung leicht → zügig → hart als Praxisregel; Tempoziele nach Pete-Plan-FAQ um 1 s/500 m pro verpasster Woche senken.
- Quellen: [Springer (Adis): Mujika & Padilla: Detraining: loss of training-induced physiological and performance adapt](https://pubmed.ncbi.nlm.nih.gov/10966148/); [Lippincott Williams & Wilkins: Mujika & Padilla: Cardiorespiratory and metabolic characteristics of detraining in humans,](https://pubmed.ncbi.nlm.nih.gov/11252068/); [The Pete Plan (Pete Marston): The Pete Plan (3-week cycle, FAQ)](https://thepeteplan.wordpress.com/the-pete-plan/); [NHS (UK National Health Service): Couch to 5K running plan](https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/couch-to-5k-running-plan)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Nur locker, Technik auffrischen | Lockere Grundlage 30 Minuten (leicht) → Technik und Regeneration 25 Minuten (leicht) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) |
| 2 | Eine zügige Einheit | Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Schwelle 2 x 10 Minuten (mittel) → Grundlage 5000 m (leicht) |
| 3 | Erster harter Reiz | Kurzintervalle 8 x 2 Minuten (hart) → Lockere Grundlage 30 Minuten (leicht) → 30 Minuten progressiv (mittel) |

## Wintergrundlage 12 Wochen (`grundlage-winter-12-wochen`)

Viel ruhige Grundlage mit tiefer Schlagzahl, eine Schwellen- oder Intervalleinheit pro Woche, jede vierte Woche leichter. Start- und Schlusstest über 5000 m.

- Ziel: Die aerobe Grundlage für die Saison aufbauen (rund 80 % locker) und den 5000-m-Wert verbessern.
- Niveau: Fortgeschritten, Kategorie `grundlage`, Saison: Winter (Nordhalbkugel Okt.–Apr.)
- Voraussetzung: Regelmässig 3 Einheiten pro Woche, 45 Minuten locker am Stück sind kein Problem.
- Regeln: deloadEvery=4, maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=replace-easy, retestWeek=12
- Beleg: angepasst: Intensitätsverteilung nach Seiler & Tønnessen 2009 und Fiskerstrand & Seiler 2004 (≥75–80 % deutlich unter der Schwelle, im Winter mehr Grundlage); Grundlage bei Schlagzahl 18–20 in 20–30-Minuten-Blöcken nach Wolfson-Leitfaden; Start- und Schlusstest 5000 m wie im Concept2-5k-Plan; 3+1-Wochen-Blöcke als Praxisregel.
- Quellen: [Sportscience (sportsci.org): Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity a](https://sportsci.org/2009/ss.htm); [Wiley: Fiskerstrand & Seiler: Training and performance characteristics among Norwegian internatio](https://pubmed.ncbi.nlm.nih.gov/15387804/); [Human Kinetics: Güllich, Seiler & Emrich: Training methods and intensity distribution of young world-class](https://pubmed.ncbi.nlm.nih.gov/20029096/); [Wolfson College Boat Club, University of Cambridge: Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary](https://www.wolfson.cam.ac.uk/sites/default/files/2019-11/wcbc_erging_0.pdf); [Concept2: Training for a 5K Rowing Ergometer Test (8 or 12 weeks)](https://www.concept2.com/training/plans/5k-erg-test); [Springer (Adis): Issurin: New horizons for the methodology and physiology of training periodization, Sports](https://pubmed.ncbi.nlm.nih.gov/20199119/)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Startwert 5000 m | Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Test 5000 m (hart) → Grundlage mit Schlagzahl-Deckel 18, 30 Minuten (leicht) → *Ratio-Training: schneller Durchzug, langes Vorrollen (leicht)* |
| 2 | Grundlage mit tiefer Schlagzahl | Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Schwelle 4 x 6 Minuten (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → *Feet-out-Rudern (leicht)* |
| 3 | Grundlage verlängern | Grundlage 10 000 m (leicht) → Schwelle 3 x 10 Minuten (hart) → Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → *Grundlage 40 Minuten mit Antritten (leicht)* |
| 4 D | Leichtere Woche | Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Schwelle 2 x 10 Minuten (mittel) → Technik und Regeneration 25 Minuten (leicht) |
| 5 | UT1 dazu | UT1 3 x 15 Minuten (mittel) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Langintervalle 4 x 4 Minuten (hart) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 6 | Längere Schwelle | Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → Schwelle 2 x 15 Minuten (hart) → Grundlage 10 000 m (leicht) → *Ratio-Training: schneller Durchzug, langes Vorrollen (leicht)* |
| 7 | Höchster Umfang im Block | 60 Minuten am Stück (mittel) → Schwelle Frequenzstufen 3 x (4-3-2) (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → *Grundlage 40 Minuten mit Antritten (leicht)* |
| 8 D | Leichtere Woche | Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Kurzintervalle 8 x 2 Minuten (hart) → Regeneration 20 Minuten (leicht) |
| 9 | Schwelle über Strecke | Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Schwelle 3 x 2000 m (hart) → Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → *Feet-out-Rudern (leicht)* |
| 10 | Progressiv | Progressive Grundlage 40 Minuten (mittel) → Grundlage 10 000 m (leicht) → Intervalle 6 x 3 Minuten (hart) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 11 | Letzte volle Woche | 60 Minuten am Stück (mittel) → Schwelle 2 x 3000 m (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → *Ratio-Training: schneller Durchzug, langes Vorrollen (leicht)* |
| 12 D | Leichter und Schlusstest 5000 m | Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Technik und Regeneration 25 Minuten (leicht) → **Test 5000 m (hart)** |

## Erster 2000-m-Test in 8 Wochen (`test-2000m-8-wochen-einsteiger`)

Drei Einheiten pro Woche mit kurzen Intervallen im späteren 2000-m-Tempo, ruhiger Grundlage und einer leichteren Woche; am Ende der erste 2000-m-Test.

- Ziel: Einen 2000-m-Test gut eingeteilt fahren und eine erste Bestzeit setzen.
- Niveau: Einsteiger, Kategorie `test-2k`
- Voraussetzung: 5000 m locker am Stück (z. B. nach „In 8 Wochen zu 5000 m am Stück“).
- Regeln: deloadEvery=4, maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=replace-easy, retestWeek=8
- Beleg: angepasst: Inhalte aus Concept2 2k-Plan (4×4 min, 6–8×2 min, 4–6×500 m, Schlagzahl 24–34) für Einsteiger gekürzt; Aufbau und Zielsetzung „2000 m sicher rudern“ nach British Rowing Go Row Beginner; Testwoche mit weniger Umfang nach Bosquet 2007 (verkürzt auf eine Woche).
- Quellen: [British Rowing: Go Row Indoor – Beginner Training Plan (8 weeks)](https://www.britishrowing.org/wp-content/uploads/2016/10/BR_Go_Row_A4_Beginners_Training_Plan_P3.pdf); [Concept2: Training for a 2K Rowing Ergometer Test – 4 Week Plan](https://www.concept2.com/training/plans/2k-erg-test-4-week); [Concept2: Training for a 2K Rowing Ergometer Test – 12 Week Plan](https://www.concept2.com/training/plans/2k-erg-test-12-week); [Lippincott Williams & Wilkins: Bosquet et al.: Effects of tapering on performance: a meta-analysis, Med Sci Sports Exerc ](https://pubmed.ncbi.nlm.nih.gov/17762369/); [Concept2: Beginner's Training Plan (Couch to Consistency)](https://www.concept2.com/training/plans/couch-to-consistency)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Startwert 1000 m | Lockere Grundlage 30 Minuten (leicht) → Test 1000 m (maximal) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) |
| 2 | Tempo kennenlernen | Einstieg 5 x 500 m (hart) → Lockere Grundlage 30 Minuten (leicht) → Schwelle Einstieg 3 x 5 Minuten (mittel) → *Technik und Regeneration 25 Minuten (leicht)* |
| 3 | Mehr Arbeit im Tempo | Einstieg Intervalle 6 x 1 Minute (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Schwelle 2 x 10 Minuten (mittel) → *Pick-Drill und Grundlage (leicht)* |
| 4 D | Leichtere Woche | Einstieg Intervalle 6 x 1 Minute (hart) → Regeneration 20 Minuten (leicht) → Technik und Regeneration 25 Minuten (leicht) |
| 5 | Längere Intervalle | Kurzintervalle 8 x 2 Minuten (hart) → Grundlage 5000 m (leicht) → Schwelle Einstieg 3 x 1500 m (mittel) → *Frequenzleiter 18-20-22-24 (mittel)* |
| 6 | 2000-m-Tempo üben | Langintervalle 4 x 4 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Einstieg Distanzpyramide 200-500-200 m (hart) → *Ratio-Training: schneller Durchzug, langes Vorrollen (leicht)* |
| 7 | Rennplan üben | 2000 m in 4 x 500 m mit Ziel-Splits (hart) → Grundlage mit Schlagzahl-Deckel 18, 30 Minuten (leicht) → Schwelle 2 x 10 Minuten (mittel) → *Technik und Regeneration 25 Minuten (leicht)* |
| 8 T | Weniger Umfang, dann Test | Einstieg 10 x 200 m locker-hart (hart) → Tapering-Einheit vor Test oder Rennen (leicht) → **Test 2000 m (maximal)** |

## 2000 m schneller in 8 Wochen (`test-2000m-8-wochen-fortgeschritten`)

Zwei harte Einheiten pro Woche (Langintervalle, 500er, 1000er) und lockere Grundlage dazwischen; leichtere Woche 4, Test in Woche 8.

- Ziel: Die eigene 2000-m-Bestzeit verbessern.
- Niveau: Fortgeschritten, Kategorie `test-2k`
- Voraussetzung: Ein 2000-m-Ergebnis der letzten 3 Monate und regelmässig 3 Einheiten pro Woche.
- Regeln: deloadEvery=4, maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=replace-easy, retestWeek=8
- Beleg: angepasst: Concept2 2k-Pläne (4×4 min/2 min, 6–8×2 min, 6×500 m/2 min, 3×1000 m/3 min, Grundlage 3000–8000 m; 3 Einheiten plus freiwillige vierte) auf 8 Wochen gestreckt; Testwoche mit reduziertem Umfang bei gleicher Intensität nach Bosquet 2007.
- Quellen: [Concept2: Training for a 2K Rowing Ergometer Test – 4 Week Plan](https://www.concept2.com/training/plans/2k-erg-test-4-week); [Concept2: Training for a 2K Rowing Ergometer Test – 12 Week Plan](https://www.concept2.com/training/plans/2k-erg-test-12-week); [Wolfson College Boat Club, University of Cambridge: Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary](https://www.wolfson.cam.ac.uk/sites/default/files/2019-11/wcbc_erging_0.pdf); [Lippincott Williams & Wilkins: Bosquet et al.: Effects of tapering on performance: a meta-analysis, Med Sci Sports Exerc ](https://pubmed.ncbi.nlm.nih.gov/17762369/); [Sportscience (sportsci.org): Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity a](https://sportsci.org/2009/ss.htm)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Arbeit im 2000-m-Tempo | Langintervalle 4 x 4 Minuten (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Kurzintervalle 8 x 2 Minuten (hart) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 2 | Mehr Wiederholungen | 6 x 500 m mit 1 Minute Pause (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Schwelle 4 x 6 Minuten (hart) → *Technik und Regeneration 25 Minuten (leicht)* |
| 3 | Längere Stücke | 3 x 1000 m mit 3 Minuten Pause (hart) → Grundlage 10 000 m (leicht) → Intervalle 6 x 3 Minuten (hart) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 4 D | Leichtere Woche | Kurzintervalle 8 x 2 Minuten (hart) → Lockere Grundlage 30 Minuten (leicht) → Technik und Regeneration 25 Minuten (leicht) |
| 5 | Renntempo | Renntempo 2 x 1000 m (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Zeit-Pyramide 1-2-3-4-3-2-1 (hart) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 6 | Renntempo und Schwelle | 6 x 750 m im 2000-m-Tempo (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Schwelle 3 x 2000 m (hart) → *Technik und Regeneration 25 Minuten (leicht)* |
| 7 | Rennplan üben | 2000 m in 4 x 500 m mit Ziel-Splits (hart) → Grundlage 10 000 m (leicht) → 6 x 500 m mit 1 Minute Pause (hart) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 8 T | Weniger Umfang, dann Test | Langintervalle 4 x 4 Minuten (hart) → Kurze Grundlage 20 Minuten (leicht) → Tapering-Einheit vor Test oder Rennen (leicht) → **Test 2000 m (maximal)** |

## 2000 m in 12 Wochen (`test-2000m-12-wochen-fortgeschritten`)

Drei Blöcke: erst Grundlage und Schwelle, dann längere Intervalle, zuletzt Renntempo. Zwischentest in Woche 6, zwei Wochen Tapering vor dem Schlusstest.

- Ziel: Die 2000-m-Bestzeit deutlich verbessern.
- Niveau: Fortgeschritten, Kategorie `test-2k`
- Voraussetzung: Ein 2000-m-Ergebnis und mindestens 8 Wochen regelmässiges Training.
- Regeln: deloadEvery=4, maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=replace-easy, retestWeek=12, interimTestWeek=6
- Beleg: angepasst: Intervallformen aus dem Concept2 12-Wochen-2k-Plan (4×4, 5–6×4, 6–10×2, 12×1, 6×3, 3–4×6, 4×5 min); Abfolge Grundlage → Intervalle → Renntempo als Blockfolge nach Issurin 2010 (Akkumulation, Transmutation, Realisation); zwei Wochen Tapering mit 40–60 % weniger Umfang bei gleicher Intensität und Häufigkeit nach Bosquet 2007.
- Quellen: [Concept2: Training for a 2K Rowing Ergometer Test – 12 Week Plan](https://www.concept2.com/training/plans/2k-erg-test-12-week); [Lippincott Williams & Wilkins: Bosquet et al.: Effects of tapering on performance: a meta-analysis, Med Sci Sports Exerc ](https://pubmed.ncbi.nlm.nih.gov/17762369/); [Springer (Adis): Issurin: New horizons for the methodology and physiology of training periodization, Sports](https://pubmed.ncbi.nlm.nih.gov/20199119/); [Sportscience (sportsci.org): Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity a](https://sportsci.org/2009/ss.htm); [Wolfson College Boat Club, University of Cambridge: Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary](https://www.wolfson.cam.ac.uk/sites/default/files/2019-11/wcbc_erging_0.pdf)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Grundlage und Schwelle | Schwelle 4 x 6 Minuten (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Kurzintervalle 8 x 2 Minuten (hart) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 2 | Grundlage und Schwelle | Langintervalle 4 x 4 Minuten (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Schwelle 3 x 10 Minuten (hart) → *Technik und Regeneration 25 Minuten (leicht)* |
| 3 | Mehr Arbeitszeit | Intervalle 6 x 3 Minuten (hart) → Grundlage 10 000 m (leicht) → Schwelle 2 x 15 Minuten (hart) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 4 D | Leichtere Woche | Kurzintervalle 8 x 2 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Technik und Regeneration 25 Minuten (leicht) |
| 5 | Längere Intervalle | Lange Intervalle 4 x 8 Minuten (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Intervalle 12 x 1 Minute (hart) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 6 | Zwischentest | Kurzintervalle 8 x 2 Minuten (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Test 2000 m (maximal) → *Technik und Regeneration 25 Minuten (leicht)* |
| 7 | Schwelle über Strecke | Schwelle 3 x 2000 m (hart) → Grundlage 10 000 m (leicht) → 3 x 1000 m mit 3 Minuten Pause (hart) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 8 D | Leichtere Woche | Langintervalle 4 x 4 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Regeneration 20 Minuten (leicht) |
| 9 | Renntempo | 6 x 500 m mit 1 Minute Pause (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → 4 x 2000 m progressiv (hart) → *Technik und Regeneration 25 Minuten (leicht)* |
| 10 | Renntempo | 6 x 750 m im 2000-m-Tempo (hart) → Grundlage 10 000 m (leicht) → Renntempo 2 x 1000 m (hart) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 11 T | Tapering 1: Umfang runter, Tempo bleibt | Renntempo 2 x 1000 m (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Langintervalle 4 x 4 Minuten (hart) → *Technik und Regeneration 25 Minuten (leicht)* |
| 12 T | Tapering 2 und Test | 2000 m in 4 x 500 m mit Ziel-Splits (hart) → Regeneration 20 Minuten (leicht) → Tapering-Einheit vor Test oder Rennen (leicht) → **Test 2000 m (maximal)** |

## 2000 m Leistung 12 Wochen (`test-2000m-12-wochen-leistung`)

Fünf Einheiten pro Woche mit den Pete-Plan-Klassikern (8×500 m, Pyramide, 4×1000 m, 5×1500 m, 4×2000 m), viel Grundlage dazwischen und zwei Wochen Tapering.

- Ziel: Neue 2000-m-Bestzeit auf hohem Niveau.
- Niveau: Leistung, Kategorie `test-2k`
- Voraussetzung: Mindestens 6 Monate strukturiertes Training mit 4 oder mehr Einheiten pro Woche, aktuelles 2000-m-Ergebnis.
- Regeln: deloadEvery=4, maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=replace-easy, retestWeek=12, interimTestWeek=6
- Beleg: angepasst: Intervallsätze und 3-Wochen-Zyklus aus dem Pete Plan (Tempo-Intervalle 8×500/Pyramide/4×1000, Ausdauer-Intervalle 5×1500/4×2000/3k-2,5k-2k, dazu Grundlage 8–15 km bei Schlagzahl 22–25 und ein Ruhetag); Pete Plan hat 6 Einheiten, hier 4+1; leichtere Wochen und Tapering (Bosquet 2007) ergänzt.
- Quellen: [The Pete Plan (Pete Marston): The Pete Plan (3-week cycle, FAQ)](https://thepeteplan.wordpress.com/the-pete-plan/); [Concept2: Training for a 2K Rowing Ergometer Test – 12 Week Plan](https://www.concept2.com/training/plans/2k-erg-test-12-week); [Lippincott Williams & Wilkins: Bosquet et al.: Effects of tapering on performance: a meta-analysis, Med Sci Sports Exerc ](https://pubmed.ncbi.nlm.nih.gov/17762369/); [Sportscience (sportsci.org): Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity a](https://sportsci.org/2009/ss.htm); [Human Kinetics: Güllich, Seiler & Emrich: Training methods and intensity distribution of young world-class](https://pubmed.ncbi.nlm.nih.gov/20029096/)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Zyklus A: Tempo und Ausdauer | 8 x 500 m (Pete Plan) (hart) → Grundlage 10 000 m (leicht) → 5 x 1500 m (Pete Plan) (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 2 | Zyklus B | Speed-Pyramide 250-1000-250 m (Pete Plan) (hart) → Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → 4 x 2000 m (Pete Plan) (hart) → Grundlage 10 000 m (leicht) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 3 | Zyklus C | 4 x 1000 m (Pete Plan) (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → 3000-2500-2000 m (Pete Plan) (hart) → 60 Minuten am Stück (mittel) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 4 D | Leichtere Woche | Langintervalle 4 x 4 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Schwelle 4 x 6 Minuten (hart) → Technik und Regeneration 25 Minuten (leicht) |
| 5 | Zyklus A, schneller als vor 4 Wochen | 8 x 500 m (Pete Plan) (hart) → Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → 5 x 1500 m (Pete Plan) (hart) → Grundlage 10 000 m (leicht) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 6 | Zwischentest | Speed-Pyramide 250-1000-250 m (Pete Plan) (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Test 2000 m (maximal) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 7 | Zyklus C | 4 x 1000 m (Pete Plan) (hart) → Grundlage 10 000 m (leicht) → 3000-2500-2000 m (Pete Plan) (hart) → 60 Minuten am Stück (mittel) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 8 D | Leichtere Woche | Kurzintervalle 8 x 2 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Schwelle 3 x 10 Minuten (hart) → Regeneration 20 Minuten (leicht) |
| 9 | Renntempo | 6 x 500 m mit 1 Minute Pause (hart) → Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → 4 x 2000 m (Pete Plan) (hart) → Grundlage 10 000 m (leicht) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 10 | Renntempo | Rennvorbereitung 3 x (Start + 1000 m) (maximal) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → 6 x 750 m im 2000-m-Tempo (hart) → Grundlage 10 000 m (leicht) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 11 T | Tapering 1 | Renntempo 2 x 1000 m (hart) → Lockere Grundlage 30 Minuten (leicht) → 2000 m in 4 x 500 m mit Ziel-Splits (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) |
| 12 T | Tapering 2 und Test | Einstieg 5 x 500 m (hart) → Kurze Grundlage 20 Minuten (leicht) → Tapering-Einheit vor Test oder Rennen (leicht) → **Test 2000 m (maximal)** |

## 5000 m und 6000 m in 8 Wochen (`langdistanz-5000m-8-wochen`)

Nach dem Concept2-5k-Plan: eine lange Fahrt, ein Intervall- und ein Schwellentag pro Woche; Test zu Beginn, Zwischentest in Woche 4 und Schlusstest.

- Ziel: Die 5000-m-Zeit verbessern (6000 m als Alternative für den Schlusstest).
- Niveau: Fortgeschritten, Kategorie `langdistanz`
- Voraussetzung: Regelmässig 3 Einheiten pro Woche, 8000 m locker am Stück.
- Regeln: deloadEvery=4, maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=replace-easy, retestWeek=8, interimTestWeek=4
- Beleg: angepasst: Concept2-5k-Plan in der 8-Wochen-Fassung (Zyklus 1 + Zyklus 2; je Woche lange Fahrt 5–10 km, Intervalle 15×1 min/5×1000/8×400/8×500, Schwelle 2×2000/2×3000, 5k-Test in Woche 1 und 4, freiwilliger 30-min-Tag; Schlagzahl 24–30); Programme der App statt exakter Distanzen; leichtere Testwoche 4 und Schlusswoche mit weniger Umfang ergänzt.
- Quellen: [Concept2: Training for a 5K Rowing Ergometer Test (8 or 12 weeks)](https://www.concept2.com/training/plans/5k-erg-test); [Sportscience (sportsci.org): Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity a](https://sportsci.org/2009/ss.htm); [Lippincott Williams & Wilkins: Bosquet et al.: Effects of tapering on performance: a meta-analysis, Med Sci Sports Exerc ](https://pubmed.ncbi.nlm.nih.gov/17762369/)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Startwert 5000 m | Test 5000 m (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Intervalle 12 x 1 Minute (hart) → *Lockere Grundlage 30 Minuten (leicht)* |
| 2 | Länger und Intervalle | Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Kurzintervalle 8 x 2 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Schwelle 3 x 2000 m (hart) |
| 3 | Lange Fahrt 8–10 km | Grundlage 10 000 m (leicht) → 8 x 500 m (Pete Plan) (hart) → Lockere Grundlage 30 Minuten (leicht) → Schwelle 2 x 3000 m (hart) |
| 4 D | Leichtere Woche, Zwischentest | Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Test 5000 m (hart) → Technik und Regeneration 25 Minuten (leicht) |
| 5 | Zweiter Zyklus: jedes Stück schneller | Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → 3 x 1000 m mit 3 Minuten Pause (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Schwelle 2 x 15 Minuten (hart) |
| 6 | Lange Fahrt und Schwelle | Grundlage 10 000 m (leicht) → Intervalle 6 x 3 Minuten (hart) → Lockere Grundlage 30 Minuten (leicht) → Schwelle 2 x 5000 m (hart) |
| 7 | Letzte volle Woche | Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → 8 x 500 m (Pete Plan) (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → 6000 m negativer Split (mittel) |
| 8 T | Weniger Umfang, Schlusstest | Schwelle 4 x 6 Minuten (hart) → Lockere Grundlage 30 Minuten (leicht) → **Test 5000 m (hart)** |

## Halbmarathon in 12 Wochen (`halbmarathon-12-wochen`)

Vier Einheiten pro Woche: eine wachsende lange Fahrt, ein UT1- oder Schwellentag und lockere Kilometer; Halbmarathontempo ab Woche 8, Tapering in Woche 12.

- Ziel: Einen Halbmarathon (21 097 m) gleichmässig zu Ende rudern.
- Niveau: Fortgeschritten, Kategorie `langdistanz`
- Voraussetzung: Regelmässig 3–4 Einheiten pro Woche, 10 km locker am Stück, ein 5000-m-Ergebnis für die Tempoziele.
- Regeln: deloadEvery=4, maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=replace-easy
- Beleg: angepasst: Concept2-Halbmarathonplan (10 Wochen, 4 Einheiten; lange Fahrt 8 → 16 km, UT1 3×10/3×15/2×30 min, AT 4×8/3×10/3×12/5×8/2×20 min, HMP 2×20 min und 50 min ab Woche 7, Tapering in Woche 10; Tempi relativ zum 5000-m-Tempo: UT2 +18–22 s, UT1 +14–18 s, HMP +8–12 s, AT +6–10 s) um zwei Grundlagenwochen und leichtere Wochen auf 12 Wochen erweitert.
- Quellen: [Concept2: Half Marathon Row Training Plan (10 weeks, 4 sessions/week)](https://www.concept2.com/training/plans/half-marathon-row-training-plan); [Concept2: Marathon Row Training Plan (16 weeks, 4 sessions/week)](https://www.concept2.com/training/plans/marathon-row-training-plan); [Sportscience (sportsci.org): Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity a](https://sportsci.org/2009/ss.htm); [Lippincott Williams & Wilkins: Bosquet et al.: Effects of tapering on performance: a meta-analysis, Med Sci Sports Exerc ](https://pubmed.ncbi.nlm.nih.gov/17762369/); [Wolfson College Boat Club, University of Cambridge: Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary](https://www.wolfson.cam.ac.uk/sites/default/files/2019-11/wcbc_erging_0.pdf)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Grundlage | Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → UT1 3 x 15 Minuten (mittel) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) |
| 2 | Grundlage | Grundlage 10 000 m (leicht) → Schwelle 4 x 6 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) |
| 3 | Lange Fahrt wächst | Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → UT1 3 x 15 Minuten (mittel) → Grundlage 10 000 m (leicht) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) |
| 4 D | Leichtere Woche | Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Schwelle 3 x 10 Minuten (hart) → Technik und Regeneration 25 Minuten (leicht) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) |
| 5 | Aerober Aufbau | Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → Schwelle 2 x 15 Minuten (hart) → Grundlage 10 000 m (leicht) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) |
| 6 | Aerober Aufbau | Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Wolverine Level 3: 8 x 5 Minuten (mittel) → Grundlage 10 000 m (leicht) → Schwelle 3 x 10 Minuten (hart) |
| 7 | Eine Stunde am Stück | 60 Minuten am Stück (mittel) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Schwelle 2 x 20 Minuten, Schlagzahl 22 (hart) → Grundlage 10 000 m (leicht) |
| 8 D | Leichtere Woche | Grundlage 10 000 m (leicht) → Schwelle 3 x 10 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Regeneration 20 Minuten (leicht) |
| 9 | Halbmarathontempo | Lange Grundlage 90 Minuten (3 x 30) (leicht) → Halbmarathon-Tempo 2 x 20 Minuten (mittel) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Schwelle 2 x 15 Minuten (hart) |
| 10 | Halbmarathontempo | Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → Halbmarathon-Tempo 2 x 20 Minuten (mittel) → Grundlage 10 000 m (leicht) → Wolverine Level 3: 8 x 5 Minuten (mittel) |
| 11 | Längste Fahrt | Lange Grundlage 90 Minuten (3 x 30) (leicht) → Halbmarathon-Tempo 2 x 20 Minuten (mittel) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Grundlage 10 000 m (leicht) |
| 12 T | Tapering und Halbmarathon | Grundlage 5000 m (leicht) → Halbmarathon-Tempo 2 x 20 Minuten (mittel) → Lockere Grundlage 30 Minuten (leicht) → **Halbmarathon 21 097 m ruhig (mittel)** |

## Marathon in 16 Wochen (`marathon-16-wochen`)

Vier Blöcke wie im Concept2-Marathonplan: Grundlage, aerober Aufbau, marathonspezifisch, Tapering. Die lange Fahrt wächst bis zum Halbmarathon.

- Ziel: Einen Marathon (42 195 m) rudern.
- Niveau: Leistung, Kategorie `langdistanz`
- Voraussetzung: Halbmarathon schon einmal gerudert oder 90 Minuten locker am Stück; 4 Einheiten pro Woche möglich; ein 5000-m-Ergebnis.
- Regeln: deloadEvery=4, maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=replace-easy
- Beleg: angepasst: Blockstruktur und Wochenmuster des Concept2-Marathonplans (16 Wochen, 4 Einheiten; lange UT2-Fahrt 12 → 34 km bis Woche 12, MP 3×25 und 50 min, Tapering ab Woche 13). Abweichung: die längste Vorbereitungsfahrt ist hier der Halbmarathon (rund 21 km), weil die App noch keine UT2-Programme über 2–2,5 h hat (Vorschlag langdistanz-ut2-120 / -150); Tapering auf vier Wochen wie im Original.
- Quellen: [Concept2: Marathon Row Training Plan (16 weeks, 4 sessions/week)](https://www.concept2.com/training/plans/marathon-row-training-plan); [Sportscience (sportsci.org): Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity a](https://sportsci.org/2009/ss.htm); [Lippincott Williams & Wilkins: Bosquet et al.: Effects of tapering on performance: a meta-analysis, Med Sci Sports Exerc ](https://pubmed.ncbi.nlm.nih.gov/17762369/); [Wolfson College Boat Club, University of Cambridge: Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary](https://www.wolfson.cam.ac.uk/sites/default/files/2019-11/wcbc_erging_0.pdf)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Grundlage | Grundlage 10 000 m (leicht) → UT1 3 x 15 Minuten (mittel) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Schwelle 4 x 6 Minuten (hart) |
| 2 | Grundlage | Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Schwelle 3 x 10 Minuten (hart) → Grundlage 10 000 m (leicht) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) |
| 3 | Grundlage | Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → UT1 3 x 15 Minuten (mittel) → Grundlage 10 000 m (leicht) → Schwelle 2 x 15 Minuten (hart) |
| 4 D | Leichtere Woche | Grundlage 10 000 m (leicht) → Schwelle 3 x 10 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Technik und Regeneration 25 Minuten (leicht) |
| 5 | Aerober Aufbau | 60 Minuten am Stück (mittel) → Wolverine Level 3: 8 x 5 Minuten (mittel) → Grundlage 10 000 m (leicht) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) |
| 6 | Aerober Aufbau | Lange Grundlage 90 Minuten (3 x 30) (leicht) → Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → Grundlage 10 000 m (leicht) → Schwelle 2 x 15 Minuten (hart) |
| 7 | Aerober Aufbau | Lange Grundlage 90 Minuten (3 x 30) (leicht) → Schwelle 2 x 20 Minuten, Schlagzahl 22 (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Grundlage 10 000 m (leicht) |
| 8 D | Leichtere Woche | Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Halbmarathon-Tempo 2 x 20 Minuten (mittel) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Regeneration 20 Minuten (leicht) |
| 9 | Marathonspezifisch | Halbmarathon 21 097 m ruhig (mittel) → Schwelle 2 x 15 Minuten (hart) → Grundlage 10 000 m (leicht) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) |
| 10 | Marathontempo | Lange Grundlage 90 Minuten (3 x 30) (leicht) → Marathon-Tempo 3 x 25 Minuten (mittel) → Grundlage 10 000 m (leicht) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) |
| 11 | Marathonspezifisch | Halbmarathon 21 097 m ruhig (mittel) → Schwelle 2 x 20 Minuten, Schlagzahl 22 (hart) → Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → Grundlage 10 000 m (leicht) |
| 12 | Höchster Umfang | Halbmarathon 21 097 m ruhig (mittel) → Marathon-Tempo 3 x 25 Minuten (mittel) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Grundlage 10 000 m (leicht) |
| 13 T | Tapering 1 | Lange Grundlage 90 Minuten (3 x 30) (leicht) → Schwelle 3 x 10 Minuten (hart) → Grundlage 10 000 m (leicht) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) |
| 14 T | Tapering 2 | Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Halbmarathon-Tempo 2 x 20 Minuten (mittel) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Lockere Grundlage 30 Minuten (leicht) |
| 15 T | Tapering 3 | Grundlage 10 000 m (leicht) → Schwelle 4 x 6 Minuten (hart) → Lockere Grundlage 30 Minuten (leicht) → Grundlage 5000 m (leicht) |
| 16 T | Marathonwoche | Lockere Grundlage 30 Minuten (leicht) → Schwelle Einstieg 3 x 5 Minuten (mittel) → Regeneration 20 Minuten (leicht) → **Marathon 42 195 m ruhig (mittel)** |

## Masters 50+: 12 Wochen (`masters-50plus-12-wochen`)

Drei Einheiten pro Woche mit einer harten, einer zügigen und einer lockeren Einheit, mehr Erholung zwischen harten Tagen und jede dritte Woche leichter.

- Ziel: Ausdauer und 2000-m-Form verbessern, ohne die Erholung zu überfordern.
- Niveau: Fortgeschritten, Kategorie `masters`
- Voraussetzung: Regelmässiges Training seit mindestens 3 Monaten; bei Herz-Kreislauf-Risiken ärztliche Abklärung.
- Regeln: deloadEvery=3, maxConsecutiveDays=2, hardSessionsMinGapHours=72, missedSessionPolicy=skip, retestWeek=12
- Beleg: abgeleitet: Fell & Williams 2008 und Borges et al. 2016 – Erholung im Alter möglicherweise langsamer, der Effekt ist aber kleiner als oft angenommen und hängt stark vom Aktivitätsniveau ab; daher nur ein harter Reiz pro Woche, 72 h zwischen harten Einheiten und leichtere Woche alle 3 Wochen (Praxisregel, nicht direkt belegt); Technik und tiefe Schlagzahl nach British Rowing (Qualität vor Umfang, Verletzungsrisiko bei Ermüdung).
- Quellen: [Human Kinetics: Fell & Williams: The effect of aging on skeletal-muscle recovery from exercise: possible i](https://pubmed.ncbi.nlm.nih.gov/18268815/); [Human Kinetics: Borges, Reaburn, Driller & Argus: Age-related changes in performance and recovery kinetics](https://researchcommons.waikato.ac.nz/entities/publication/43c52ed0-3e7e-4f32-98fa-ccd16580054b); [British Rowing: How Much How Often (rower development levels: sessions per week, session length, hours)](https://www.britishrowing.org/wp-content/uploads/2019/03/How-Much-How-Often-210219.pdf); [Sportscience (sportsci.org): Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity a](https://sportsci.org/2009/ss.htm); [American College of Sports Medicine / Wolters Kluwer: Garber et al.: Quantity and quality of exercise for developing and maintaining cardiorespi](https://pubmed.ncbi.nlm.nih.gov/21694556/)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Startwert und Technik | Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Test 1000 m (maximal) → Ratio-Training: schneller Durchzug, langes Vorrollen (leicht) |
| 2 | Zügig und locker | Schwelle 4 x 6 Minuten (hart) → Grundlage mit Schlagzahl-Deckel 18, 30 Minuten (leicht) → Pick-Drill und Grundlage (leicht) → *Regeneration 20 Minuten (leicht)* |
| 3 D | Leichtere Woche | Kurze Grundlage 20 Minuten (leicht) → Frequenzleiter 18-20-22-24 (mittel) → Technik und Regeneration 25 Minuten (leicht) |
| 4 | Kurze harte Stücke | Kurzintervalle 8 x 2 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Schwelle 2 x 10 Minuten (mittel) → *Technik und Regeneration 25 Minuten (leicht)* |
| 5 | Länger locker | Langintervalle 4 x 4 Minuten (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → 30 Minuten progressiv (mittel) → *Regeneration 20 Minuten (leicht)* |
| 6 D | Leichtere Woche | Kurze Grundlage 20 Minuten (leicht) → Schwelle Einstieg 3 x 5 Minuten (mittel) → Technik und Regeneration 25 Minuten (leicht) |
| 7 | Kraft bei tiefer Schlagzahl | Kraftausdauer 10 x 1 Minute bei Schlagzahl 20 (hart) → Grundlage mit Schlagzahl-Deckel 18, 30 Minuten (leicht) → Schwelle 2 x 10 Minuten (mittel) → *Ratio-Training: schneller Durchzug, langes Vorrollen (leicht)* |
| 8 | Schwelle | Zeit-Pyramide 1-2-3-4-3-2-1 (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → 30 Minuten progressiv (mittel) → *Regeneration 20 Minuten (leicht)* |
| 9 D | Leichtere Woche | Lockere Grundlage 30 Minuten (leicht) → Frequenzleiter 18-20-22-24 (mittel) → Technik und Regeneration 25 Minuten (leicht) |
| 10 | Renntempo kennenlernen | 6 x 500 m mit 1 Minute Pause (hart) → Grundlage 10 000 m (leicht) → Schwelle Einstieg 3 x 1500 m (mittel) → *Technik und Regeneration 25 Minuten (leicht)* |
| 11 | Letzte volle Woche | Langintervalle 4 x 4 Minuten (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → 6000 m negativer Split (mittel) → *Regeneration 20 Minuten (leicht)* |
| 12 D | Leichter und Vergleich mit Woche 1 | Kurze Grundlage 20 Minuten (leicht) → Technik und Regeneration 25 Minuten (leicht) → **Test 1000 m (maximal)** |

## Polarisiert 80/20 in 10 Wochen (`polarisiert-80-20-10-wochen`)

Rund 80 % der Zeit ganz locker, zwei harte Intervalltage pro Woche, kaum etwas dazwischen; 2000-m-Test zu Beginn und am Ende.

- Ziel: VO2max und 2000-m-Leistung mit einem klaren Hart-locker-Muster verbessern.
- Niveau: Fortgeschritten, Kategorie `grundlage`
- Voraussetzung: Regelmässig 4 Einheiten pro Woche, 60 Minuten locker am Stück, ein Pulsgurt hilft beim Lockerbleiben.
- Regeln: deloadEvery=4, maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=replace-easy, retestWeek=10
- Beleg: angepasst: Stöggl & Sperlich 2014 (9 Wochen, polarisiert ≈ 80 % locker / ≈ 20 % hart mit grösstem VO2max-Zuwachs, +11,7 %, bei gut trainierten Ausdauersportlern – nicht Ruderern); Intervallformen 4×8 min und 30/15 nach Seiler 2009 bzw. Rønnestad. Einschränkung: Treff et al. 2017 fanden bei nationalen Elite-Ruderern über 11 Wochen keinen Vorteil gegenüber pyramidaler Verteilung (beide ≈ 93 % Zone 1). Der Plan ist sinnvoll, aber kein bewiesener Vorteil für Ruderer.
- Quellen: [Frontiers: Stöggl & Sperlich: Polarized training has greater impact on key endurance variables than t](https://doi.org/10.3389/fphys.2014.00033); [Frontiers: Treff et al.: Eleven-week preparation involving polarized intensity distribution is not su](https://doi.org/10.3389/fphys.2017.00515); [Sportscience (sportsci.org): Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity a](https://sportsci.org/2009/ss.htm); [Wiley: Seiler & Kjerland: Quantifying training intensity distribution in elite endurance athletes](https://pubmed.ncbi.nlm.nih.gov/16430681/); [Wiley: Fiskerstrand & Seiler: Training and performance characteristics among Norwegian internatio](https://pubmed.ncbi.nlm.nih.gov/15387804/); [Human Kinetics: Güllich, Seiler & Emrich: Training methods and intensity distribution of young world-class](https://pubmed.ncbi.nlm.nih.gov/20029096/)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Startwert 2000 m | Test 2000 m (maximal) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Langintervalle 4 x 4 Minuten (hart) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 2 | Polarisiert | Lange Intervalle 4 x 8 Minuten (hart) → Grundlage 10 000 m (leicht) → 30/15 Intervalle 3 x 13 (Rønnestad) (hart) → Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 3 | Polarisiert | Intervalle 6 x 3 Minuten (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Lange Intervalle 4 x 8 Minuten (hart) → Grundlage 10 000 m (leicht) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 4 D | Leichtere Woche | Langintervalle 4 x 4 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Technik und Regeneration 25 Minuten (leicht) |
| 5 | Polarisiert | 30/15 Intervalle 3 x 13 (Rønnestad) (hart) → Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → Lange Intervalle 4 x 8 Minuten (hart) → Grundlage 10 000 m (leicht) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 6 | Polarisiert | Intervalle 6 x 3 Minuten (hart) → 60 Minuten am Stück (mittel) → Intervalle 2 x 10 x 1 Minute (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 7 | Polarisiert, höchster Umfang | Lange Intervalle 4 x 8 Minuten (hart) → Grundlage 2 x 30 Minuten, Schlagzahl 18 (leicht) → 30/15 Intervalle 3 x 13 (Rønnestad) (hart) → 60 Minuten am Stück (mittel) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 8 D | Leichtere Woche | Kurzintervalle 8 x 2 Minuten (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Regeneration 20 Minuten (leicht) |
| 9 | Polarisiert | Intervalle 6 x 3 Minuten (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Lange Intervalle 4 x 8 Minuten (hart) → Grundlage 10 000 m (leicht) → *Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht)* |
| 10 T | Weniger Umfang, Test | Langintervalle 4 x 4 Minuten (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Tapering-Einheit vor Test oder Rennen (leicht) → **Test 2000 m (maximal)** |

## Langer Aufbau 24 Wochen (nach Pete Plan) (`pete-artig-24-wochen`)

Drei Kerneinheiten plus eine freiwillige: die Grundlagenfahrt wird Woche für Woche länger, dazu ein Intervalltag, ab Woche 13 ein zweiter Qualitätstag. Ziele kommen immer aus der letzten gleichen Einheit.

- Ziel: Über ein halbes Jahr stetig schneller werden und mit einem 2000-m-Test abschliessen.
- Niveau: Fortgeschritten, Kategorie `test-2k`
- Voraussetzung: 5000 m locker am Stück und erste Erfahrung mit Intervallen.
- Regeln: deloadEvery=4, maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=shift, retestWeek=24
- Beleg: angepasst: eigene Umsetzung nach dem Beginner Pete Plan (24 Wochen, 3 Kern- + 2 freiwillige Einheiten; Grundlage 5000 → 12 000 m, Intervalle 6×500 bis 5×1500/4×2000, ab Woche 12 Zeitstücke 3×10/2×15/4×8/30 min; Ziel = Schnitt der letzten gleichen Einheit, gleich oder 1–2 s schneller). Abweichungen: Distanzen auf vorhandene Programme gerundet (5000/8000/10 000 m, 40 und 72 min), leichtere Woche alle 4 Wochen und Schlusstest ergänzt (im Original nicht vorgesehen).
- Quellen: [The Pete Plan (Pete Marston): Beginner Pete Plan (24 weeks, 3 core + 2 optional sessions)](https://thepeteplan.wordpress.com/beginner-training/); [The Pete Plan (Pete Marston): The Pete Plan (3-week cycle, FAQ)](https://thepeteplan.wordpress.com/the-pete-plan/); [Sportscience (sportsci.org): Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity a](https://sportsci.org/2009/ss.htm)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Grundlage wächst, ein Intervalltag | Grundlage 5000 m (leicht) → Einstieg 5 x 500 m (hart) → Grundlage 5000 m (leicht) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 2 | Grundlage wächst, ein Intervalltag | Grundlage 5000 m (leicht) → 6 x 750 m im 2000-m-Tempo (hart) → Grundlage 5000 m (leicht) → *Grundlage 5000 m (leicht)* |
| 3 | Grundlage wächst, ein Intervalltag | Grundlage 5000 m (leicht) → Schwelle 3 x 2000 m (hart) → Grundlage mit Schlagzahl-Deckel 18, 30 Minuten (leicht) → *Lockere Grundlage 30 Minuten (leicht)* |
| 4 D | Leichtere Woche | Kurzintervalle 8 x 2 Minuten (hart) → Kurze Grundlage 20 Minuten (leicht) → Regeneration 20 Minuten (leicht) |
| 5 | Grundlage wächst, ein Intervalltag | Grundlage mit Schlagzahl-Deckel 18, 30 Minuten (leicht) → 3 x 1000 m mit 3 Minuten Pause (hart) → Grundlage mit Schlagzahl-Deckel 18, 30 Minuten (leicht) → *Grundlage 5000 m (leicht)* |
| 6 | Grundlage wächst, ein Intervalltag | Grundlage mit Schlagzahl-Deckel 18, 30 Minuten (leicht) → Schwelle 3 x 2000 m (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → *Lockere Grundlage 30 Minuten (leicht)* |
| 7 | Grundlage wächst, ein Intervalltag | Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → 6 x 500 m mit 1 Minute Pause (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 8 D | Leichtere Woche | Kurzintervalle 8 x 2 Minuten (hart) → Kurze Grundlage 20 Minuten (leicht) → Regeneration 20 Minuten (leicht) |
| 9 | Grundlage wächst, ein Intervalltag | Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → 4 x 1000 m (Pete Plan) (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → *Lockere Grundlage 30 Minuten (leicht)* |
| 10 | Grundlage wächst, ein Intervalltag | Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → Schwelle 3 x 2000 m (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 11 | Grundlage wächst, ein Intervalltag | Grundlage 10 000 m (leicht) → 8 x 500 m (Pete Plan) (hart) → Steady 8000 m, Schlagzahl 22-25 (Pete Plan) (leicht) → *Grundlage 5000 m (leicht)* |
| 12 D | Leichtere Woche | Langintervalle 4 x 4 Minuten (hart) → Kurze Grundlage 20 Minuten (leicht) → Regeneration 20 Minuten (leicht) |
| 13 | Zweite Hälfte: zwei Qualitätstage | 4 x 1000 m (Pete Plan) (hart) → Grundlage 10 000 m (leicht) → Schwelle 2 x 15 Minuten (hart) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 14 | Zweite Hälfte: zwei Qualitätstage | 4 x 2000 m (Pete Plan) (hart) → Grundlage 10 000 m (leicht) → Lange Intervalle 4 x 8 Minuten (hart) → *Grundlage 5000 m (leicht)* |
| 15 | Zweite Hälfte: zwei Qualitätstage | 6 x 750 m im 2000-m-Tempo (hart) → Grundlage 10 000 m (leicht) → Schwelle 3 x 10 Minuten (hart) → *Lockere Grundlage 30 Minuten (leicht)* |
| 16 D | Leichtere Woche | Langintervalle 4 x 4 Minuten (hart) → Kurze Grundlage 20 Minuten (leicht) → Regeneration 20 Minuten (leicht) |
| 17 | Zweite Hälfte: zwei Qualitätstage | 8 x 500 m (Pete Plan) (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Schwelle 2 x 15 Minuten (hart) → *Grundlage 5000 m (leicht)* |
| 18 | Zweite Hälfte: zwei Qualitätstage | 4 x 2000 m (Pete Plan) (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → 30 Minuten Schlagzahl 20 (hart) → *Lockere Grundlage 30 Minuten (leicht)* |
| 19 | Zweite Hälfte: zwei Qualitätstage | Speed-Pyramide 250-1000-250 m (Pete Plan) (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Schwelle 3 x 10 Minuten (hart) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 20 D | Leichtere Woche | Langintervalle 4 x 4 Minuten (hart) → Kurze Grundlage 20 Minuten (leicht) → Regeneration 20 Minuten (leicht) |
| 21 | Zweite Hälfte: zwei Qualitätstage | 4 x 1000 m (Pete Plan) (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Lange Intervalle 4 x 8 Minuten (hart) → *Lockere Grundlage 30 Minuten (leicht)* |
| 22 | Zweite Hälfte: zwei Qualitätstage | 4 x 2000 m (Pete Plan) (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → 30 Minuten Schlagzahl 20 (hart) → *Grundlage in 3 Blöcken, Schlagzahl 20 (leicht)* |
| 23 | Zweite Hälfte: zwei Qualitätstage | 8 x 500 m (Pete Plan) (hart) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) → Schwelle 2 x 15 Minuten (hart) → *Grundlage 5000 m (leicht)* |
| 24 T | Abschluss: 2000-m-Test | Einstieg 5 x 500 m (hart) → Lockere Grundlage 30 Minuten (leicht) → Tapering-Einheit vor Test oder Rennen (leicht) → **Test 2000 m (maximal)** |

## Wettkampfvorbereitung mit Tapering (`wettkampf-tapering-3-wochen`)

Eine letzte volle Woche mit Renntempo, dann zwei Wochen mit deutlich weniger Umfang bei gleicher Intensität und gleicher Zahl Einheiten; am Ende Rennen oder Test über 2000 m.

- Ziel: Am Wettkampftag (Indoor-Rennen oder 2000-m-Test) frisch und schnell sein.
- Niveau: Leistung, Kategorie `wettkampf`
- Voraussetzung: Mindestens 8 Wochen Training auf das Rennen hin (z. B. ein 2000-m-Plan), aktuelle Tempoziele.
- Regeln: maxConsecutiveDays=2, hardSessionsMinGapHours=48, missedSessionPolicy=skip, retestWeek=3
- Beleg: direkt: Bosquet et al. 2007 (Metaanalyse, 27 Studien) – am wirksamsten ist ein Tapering von rund 2 Wochen mit 41–60 % weniger Umfang, exponentiell abnehmend, ohne Intensität oder Häufigkeit zu senken (Effektstärke 0,72); Inhalte (Renntempo, Rennsimulation) aus den Concept2-Plänen.
- Quellen: [Lippincott Williams & Wilkins: Bosquet et al.: Effects of tapering on performance: a meta-analysis, Med Sci Sports Exerc ](https://pubmed.ncbi.nlm.nih.gov/17762369/); [Concept2: Training for a 2K Rowing Ergometer Test – 12 Week Plan](https://www.concept2.com/training/plans/2k-erg-test-12-week); [Concept2: Half Marathon Row Training Plan (10 weeks, 4 sessions/week)](https://www.concept2.com/training/plans/half-marathon-row-training-plan)

| Woche | Fokus | Einheiten |
|---|---|---|
| 1 | Letzte volle Woche | 6 x 750 m im 2000-m-Tempo (hart) → Grundlage 10 000 m (leicht) → 2000-m-Rennsimulation mit Taktik (maximal) → Grundlage 3 x 20 Minuten, Schlagzahl 20 (leicht) |
| 2 T | Tapering: Umfang rund 40 % runter, Tempo bleibt | Renntempo 2 x 1000 m (hart) → Lockere Grundlage 30 Minuten (leicht) → 2000 m in 4 x 500 m mit Ziel-Splits (hart) → Grundlage in 3 Blöcken, Schlagzahl 20 (leicht) |
| 3 T | Rennwoche: Umfang rund 60 % runter | Einstieg 5 x 500 m (hart) → Kurze Grundlage 20 Minuten (leicht) → Tapering-Einheit vor Test oder Rennen (leicht) → **Test 2000 m (maximal)** |
