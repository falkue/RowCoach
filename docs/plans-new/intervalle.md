# Intervalle und Sprint: neue Programme für RowCoach (Familie `intervalle`)

Stand 26.11.2026. 26 Programme in `docs/plans-new/intervalle.json`: 20 in der Kategorie Intervalle (kurze und mittlere Intervalle bis 4 min, VO2max, Renntempo, Kraftausdauer) und 6 Sprint. Niveaus: 6 Einsteiger, 10 Fortgeschritten, 10 Leistung. 10 Programme nach Distanz, 16 nach Zeit. Erzeugt mit einem Python-Skript (Phasen ausgerollt, Zähler „(i/n)“ in den Labels), JSON mit `python3 -m json.tool` geprüft.

## Methode

1. Zotero (`zrag search`): nur unbenannte Transkript-Notizen ohne Bezug zu Intervalltraining. `zrag semantic` brach mit einem Serverfehler ab (IncompleteRead), der Zotero-Server war zeitweise nicht erreichbar. Kein Zotero-Beleg verwendet, deshalb alle `zotero: null`.
2. Fundus (Projekt `rowcoach`): vorhanden waren der Concept2-4-Wochen-2k-Plan, Gluckmans „30 and Out“ (u. a. 20 x 20 s im Tempo 2k -7..-10 s), die Wolfson-Zonen und Seiler & Tønnessen 2009. Diese wurden übernommen.
3. Web, wenn möglich Primärquellen: Concept2-Trainingspläne (500 m, 2k 12 Wochen) und Blogbeiträge (40/20, Tabata, 20 x 30 s, 10-20-30), Pete Plan (Website des Autors mit FAQ-Pace-Vorgaben), Wolverine Plan (Caviston-Beiträge im Concept2-Forum, Sammlung, also Sekundärquelle), Wolfson-Leitfaden (PDF im Volltext mit pdftotext gelesen), ACE-Distanzpyramide. Studien: Tabata et al. 1996, Rønnestad et al. 2020 und Buchheit & Laursen 2013 als PubMed-Abstract, Gunnarsson & Bangsbo 2012 über die Crossref-Metadaten.
4. Pace-Offsets in Sekunden pro 500 m relativ zum Tempo der 2000-m-Bestzeit (Bezug ca. 2:00/500 m; + = langsamer). Direkt aus Quellen stammen: Pete Plan (8 x 500 m = 2k -3 s, Pyramide = 2k, 4 x 1000 m = 2k +1 s) und Gluckman (20 x 20 s = 2k -7..-10 s, 500 m = 2k -2..-6 s). Alle anderen Offsets sind eigene Eingrenzungen bzw. Ableitungen und im Feld `evidence` gekennzeichnet. Für Schlagzahlen gilt: Concept2 nennt 24-34 spm (2k-Pläne), 26-36 spm (500-m-Plan), 30-36 spm und mehr für kurze Strecken und 22-30 spm als Standard im Workout of the Day.
5. Die Gesamtdauer „ca.“ wird mit 2:00/500 m plus Offset geschätzt, Pausen nach Distanz mit +20 s.

## Verwendete Pulszonen (Concept2-5-Zonen-Modell, % HFmax)

| Zone | % HFmax | Band |
|---|---|---|
| 1 | < 65 | Regeneration, Pausen |
| 2 | 65-75 | UT2, Einrudern |
| 3 | 75-80 | UT1 |
| 4 | 80-90 | AT/Schwelle bis unteres TR |
| 5 | > 90 | TR/AN, VO2max und Sprint |

Bei sehr kurzen Belastungen (10-30 s) erreicht der Puls die angegebene Zone oft erst gegen Ende der Serie. Die Zone beschreibt die Zielintensität, nicht den Puls in jeder Sekunde (vgl. Buchheit & Laursen 2013: Ziel ist, mehrere Minuten pro Einheit über 90 % VO2max zu verbringen).

## Nicht abrufbar bzw. nur eingeschränkt geprüft

- Wolverine-Plan-PDF auf concept2.com: 404. Die Stufen stammen nur aus der Forensammlung von Caviston-Beiträgen (gekürzt gelesen). Die Wolverine-Stufe 3 (3:1, 3-5 min bzw. 1250-1500 m) gehört zu `schwelle` (dort `intervalle-wolverine-8x5`), deshalb nicht hier.
- Beginner Pete Plan: kein vollständiger Wochenplan abrufbar (Scribd/Gist unvollständig). Die Einsteiger-Programme stützen sich deshalb auf Concept2, ACE und Wolfson.
- British-Rowing-Plus-Artikel (Starts, Power Strokes, Pyramiden mit Pause gleich Distanz) leiten auf die Startseite um und sind nicht gelesen. Die Startsequenz stützt sich auf einen Concept2-Neuseeland-Beitrag, der nur über den Suchauszug gelesen ist (Abruf 429/Timeout).
- Concept2 Workout of the Day: Die Tages-Workouts sind nur über ErgData/Logbuch sichtbar. Verwendet sind nur die allgemeinen Vorgaben (Intensität „hard“, 22-30 spm, längeres Einrudern bei hoher Intensität).
- Concept2-1k-Plan: 404.

## Abgrenzung

Nicht doppelt zu den vorhandenen Programmen: `kurzintervalle-8x2` (8 x 2 min / 1 min), `langintervalle-4x4`, `pyramide-1-2-3-4-3-2-1`, `sprint-8x250` (6-12 x 250 m / 1 min). Die Varianten 10-12 x 250 m und 6 x 2 min / 2 min sind deshalb weggelassen. Nicht übernommen, weil Sache anderer Familien: 5 x 1500 m, 4 x 2000 m, 3k-2.5k-2k (Pete Plan, `schwelle`), 3 x 1250 m und Wolverine-Stufe 3 (`schwelle`), Tests über 100 m, 500 m, 1000 m und 1 min (`tests`), 2000-m-Renntempo in 4 x 500 m und 2 x 1000 m sowie Start + 1000 m (`tests`/Wettkampf). „Death by …“-Formate sind nicht seriös belegt und deshalb weggelassen. Ebenso 3 x 750 m (zu nahe an `renntempo-2x1000`) und 15/15-Antritte (kein Ruderbeleg gefunden).


## Einstieg Intervalle 6 x 1 Minute (`intervalle-einsteiger-6x1`)

- Erklärung: Sechs Intervalle zu 1 Minute zügig bis hart mit je 1 Minute lockerer Pause. Erste Intervalle kontrolliert, nicht voll.
- Zweck/Bereich: Einstieg in harte Intervalle / VO2max-Reiz mit kleinem Umfang (Puls am Ende ca. 85-90 % HFmax, Pulszone 4)
- Niveau: Einsteiger · Kategorie: Intervalle · Tags: hard, vo2max, beginner-friendly, time-efficient
- Belegstatus: angepasst: Concept2 12-Wochen-2k-Plan nennt 12 x 1 min / 1 min Pause; hier auf 6 Wiederholungen halbiert und Tempo gedrosselt (2k +2..+6 s, eigene Eingrenzung)
- Quellen: Concept2 - Training for a 2K Rowing Ergometer Test - 12 Week Plan; Springer - High-intensity interval training, solutions to the programming puzzle. Part I: cardiopulmonary emphasis (Buchheit & Laursen), Sports Med 43(5):313-38; Concept2 - Workout of the Day (general guidance: intensity, stroke rate, warm-up)
- Umfang: zeitbasierte Phasen 24:00 min; Gesamtdauer ca. 24 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-26 | 2 | - | - | Einrudern 8 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 1:00 min | 24-28 | 4 | 2k +2..+6 s/500 m | - | Intervall 1 min zügig bis hart (1/6) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 24-28 | 4 | 2k +2..+6 s/500 m | - | Intervall 1 min zügig bis hart (2/6) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 24-28 | 4 | 2k +2..+6 s/500 m | - | Intervall 1 min zügig bis hart (3/6) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 24-28 | 4 | 2k +2..+6 s/500 m | - | Intervall 1 min zügig bis hart (4/6) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 24-28 | 4 | 2k +2..+6 s/500 m | - | Intervall 1 min zügig bis hart (5/6) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 24-28 | 4 | 2k +2..+6 s/500 m | - | Intervall 1 min zügig bis hart (6/6) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Einstieg 10 x 200 m locker-hart (`intervalle-einsteiger-10x200`)

- Erklärung: Zehnmal 200 m zügig bis hart, dazwischen je 1 Minute locker rudern. Gleichmässig, nicht das erste Stück überziehen.
- Zweck/Bereich: Tempohärte und Technik bei höherem Tempo, kleiner VO2max-Reiz (Pulszone 4)
- Niveau: Einsteiger · Kategorie: Intervalle · Tags: hard, vo2max, beginner-friendly, time-efficient
- Belegstatus: angepasst: Concept2 500-m-Plan (kurze Distanzintervalle 250 m mit 1 min Pause, Schlagzahl 26-36) und ACE-Distanzpyramide (200 m mit 1:30 Pause, 24-28 spm); Distanz 200 m, Pause und Tempo (2k +2..+6 s) eigene Eingrenzung
- Quellen: Concept2 - Training for a 500m Rowing Ergometer Test; American Council on Exercise (ACE) - Reap the Benefits of Rowing With 3 Fast and Efficient Workouts (S. Thielen); fitness association blog, secondary source; Concept2 - Workout of the Day (general guidance: intensity, stroke rate, warm-up)
- Umfang: zeitbasierte Phasen 22:00 min + 2000 m in Distanzphasen; Gesamtdauer ca. 30 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-26 | 2 | - | - | Einrudern 8 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 200 m | 24-28 | 4 | 2k +2..+6 s/500 m | - | 200 m zügig bis hart (1/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 200 m | 24-28 | 4 | 2k +2..+6 s/500 m | - | 200 m zügig bis hart (2/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 200 m | 24-28 | 4 | 2k +2..+6 s/500 m | - | 200 m zügig bis hart (3/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 200 m | 24-28 | 4 | 2k +2..+6 s/500 m | - | 200 m zügig bis hart (4/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 200 m | 24-28 | 4 | 2k +2..+6 s/500 m | - | 200 m zügig bis hart (5/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 200 m | 24-28 | 4 | 2k +2..+6 s/500 m | - | 200 m zügig bis hart (6/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 200 m | 24-28 | 4 | 2k +2..+6 s/500 m | - | 200 m zügig bis hart (7/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 200 m | 24-28 | 4 | 2k +2..+6 s/500 m | - | 200 m zügig bis hart (8/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 200 m | 24-28 | 4 | 2k +2..+6 s/500 m | - | 200 m zügig bis hart (9/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 200 m | 24-28 | 4 | 2k +2..+6 s/500 m | - | 200 m zügig bis hart (10/10) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 10-20-30 Intervalle (`intervalle-einsteiger-10-20-30`)

- Erklärung: Zwei Blöcke zu 5 Minuten: jede Minute 30 s locker, 20 s mittel, 10 s Sprint. Zwischen den Blöcken 2 Minuten stehen.
- Zweck/Bereich: Kurzer, abwechslungsreicher Intervallreiz für Fitness und Herz-Kreislauf (Puls steigt bis ca. 85-90 % HFmax, Pulszone 3-5)
- Niveau: Einsteiger · Kategorie: Intervalle · Tags: hard, vo2max, fartlek, beginner-friendly, time-efficient
- Belegstatus: direkt: Concept2 '10-20-30 Training' (5 x [30 s locker, 20 s mittel, 10 s Sprint], 2 min Pause stehen/gehen, 2 Blöcke, ca. 12 min); Ursprung Gunnarsson & Bangsbo 2012 (Läufer). Einrudern, Schlagzahl und Pace-Offsets eigene Eingrenzung
- Quellen: Concept2 - 10-20-30 Training; American Physiological Society - The 10-20-30 training concept improves performance and health profile in moderately trained runners (Gunnarsson & Bangsbo), J Appl Physiol 113(1):16-24
- Umfang: zeitbasierte Phasen 25:00 min; Gesamtdauer ca. 25 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern 8 min: locker, steigernd, am Ende 3 kurze Antritte |
| rest | 0:30 min | 18-22 | 3 | - | aktiv | 30 s locker (Block 1, 1/5) |
| work | 0:20 min | 22-26 | 4 | 2k +4..+10 s/500 m | - | 20 s mittel (Block 1, 1/5) |
| work | 0:10 min | 28-34 | 5 | 2k -10..-4 s/500 m | - | 10 s Sprint (Block 1, 1/5) |
| rest | 0:30 min | 18-22 | 3 | - | aktiv | 30 s locker (Block 1, 2/5) |
| work | 0:20 min | 22-26 | 4 | 2k +4..+10 s/500 m | - | 20 s mittel (Block 1, 2/5) |
| work | 0:10 min | 28-34 | 5 | 2k -10..-4 s/500 m | - | 10 s Sprint (Block 1, 2/5) |
| rest | 0:30 min | 18-22 | 3 | - | aktiv | 30 s locker (Block 1, 3/5) |
| work | 0:20 min | 22-26 | 4 | 2k +4..+10 s/500 m | - | 20 s mittel (Block 1, 3/5) |
| work | 0:10 min | 28-34 | 5 | 2k -10..-4 s/500 m | - | 10 s Sprint (Block 1, 3/5) |
| rest | 0:30 min | 18-22 | 3 | - | aktiv | 30 s locker (Block 1, 4/5) |
| work | 0:20 min | 22-26 | 4 | 2k +4..+10 s/500 m | - | 20 s mittel (Block 1, 4/5) |
| work | 0:10 min | 28-34 | 5 | 2k -10..-4 s/500 m | - | 10 s Sprint (Block 1, 4/5) |
| rest | 0:30 min | 18-22 | 3 | - | aktiv | 30 s locker (Block 1, 5/5) |
| work | 0:20 min | 22-26 | 4 | 2k +4..+10 s/500 m | - | 20 s mittel (Block 1, 5/5) |
| work | 0:10 min | 28-34 | 5 | 2k -10..-4 s/500 m | - | 10 s Sprint (Block 1, 5/5) |
| rest | 2:00 min | - | 1 | - | stehen | Pause 2 min: stehen oder ganz langsam |
| rest | 0:30 min | 18-22 | 3 | - | aktiv | 30 s locker (Block 2, 1/5) |
| work | 0:20 min | 22-26 | 4 | 2k +4..+10 s/500 m | - | 20 s mittel (Block 2, 1/5) |
| work | 0:10 min | 28-34 | 5 | 2k -10..-4 s/500 m | - | 10 s Sprint (Block 2, 1/5) |
| rest | 0:30 min | 18-22 | 3 | - | aktiv | 30 s locker (Block 2, 2/5) |
| work | 0:20 min | 22-26 | 4 | 2k +4..+10 s/500 m | - | 20 s mittel (Block 2, 2/5) |
| work | 0:10 min | 28-34 | 5 | 2k -10..-4 s/500 m | - | 10 s Sprint (Block 2, 2/5) |
| rest | 0:30 min | 18-22 | 3 | - | aktiv | 30 s locker (Block 2, 3/5) |
| work | 0:20 min | 22-26 | 4 | 2k +4..+10 s/500 m | - | 20 s mittel (Block 2, 3/5) |
| work | 0:10 min | 28-34 | 5 | 2k -10..-4 s/500 m | - | 10 s Sprint (Block 2, 3/5) |
| rest | 0:30 min | 18-22 | 3 | - | aktiv | 30 s locker (Block 2, 4/5) |
| work | 0:20 min | 22-26 | 4 | 2k +4..+10 s/500 m | - | 20 s mittel (Block 2, 4/5) |
| work | 0:10 min | 28-34 | 5 | 2k -10..-4 s/500 m | - | 10 s Sprint (Block 2, 4/5) |
| rest | 0:30 min | 18-22 | 3 | - | aktiv | 30 s locker (Block 2, 5/5) |
| work | 0:20 min | 22-26 | 4 | 2k +4..+10 s/500 m | - | 20 s mittel (Block 2, 5/5) |
| work | 0:10 min | 28-34 | 5 | 2k -10..-4 s/500 m | - | 10 s Sprint (Block 2, 5/5) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Einstieg 5 x 500 m (`intervalle-einsteiger-5x500`)

- Erklärung: Fünfmal 500 m zügig und gleichmässig mit je 2 Minuten lockerer Pause. Alle Stücke im gleichen Tempo.
- Zweck/Bereich: Tempohärte und Pacing-Gefühl, VO2max-Bereich (Pulszone 4-5)
- Niveau: Einsteiger · Kategorie: Intervalle · Tags: hard, vo2max, beginner-friendly
- Belegstatus: angepasst: Concept2 500-m-Plan (Zyklus 1: 4-5 x 500 m mit 2 min Pause, Schlagzahl 26-36); Tempo für Einsteiger 2k +0..+4 s und Schlagzahl 24-30 eigene Eingrenzung
- Quellen: Concept2 - Training for a 500m Rowing Ergometer Test; Concept2 - Workout of the Day (general guidance: intensity, stroke rate, warm-up)
- Umfang: zeitbasierte Phasen 21:00 min + 2500 m in Distanzphasen; Gesamtdauer ca. 31 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-28 | 2 | - | - | Einrudern 8 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 500 m | 24-30 | 4 | 2k 0..+4 s/500 m | - | 500 m zügig und gleichmässig (1/5) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 500 m | 24-30 | 4 | 2k 0..+4 s/500 m | - | 500 m zügig und gleichmässig (2/5) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 500 m | 24-30 | 4 | 2k 0..+4 s/500 m | - | 500 m zügig und gleichmässig (3/5) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 500 m | 24-30 | 4 | 2k 0..+4 s/500 m | - | 500 m zügig und gleichmässig (4/5) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 500 m | 24-30 | 4 | 2k 0..+4 s/500 m | - | 500 m zügig und gleichmässig (5/5) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Einstieg Distanzpyramide 200-500-200 m (`intervalle-einsteiger-pyramide-200-500`)

- Erklärung: Pyramide 200, 300, 400, 500, 400, 300, 200 m mit lockeren Pausen von 1:30 bis 3:00 Minuten (je länger das Stück, desto länger die Pause).
- Zweck/Bereich: Abwechslungsreiche Intervalle im Bereich Schwelle bis VO2max (Pulszone 4)
- Niveau: Einsteiger · Kategorie: Intervalle · Tags: hard, vo2max, pyramid, beginner-friendly
- Belegstatus: direkt: ACE 'Pyramid Workout #1: By Meters' (200/300/400/500/400/300/200 m, Pausen 1:30/2:00/2:30/3:00 locker, 24-28 spm, 5 min Einrudern, 3-5 min Ausrudern); Pace-Offset eigene Eingrenzung (2k +3..+8 s)
- Quellen: American Council on Exercise (ACE) - Reap the Benefits of Rowing With 3 Fast and Efficient Workouts (S. Thielen); fitness association blog, secondary source; Concept2 - Workout of the Day (general guidance: intensity, stroke rate, warm-up)
- Umfang: zeitbasierte Phasen 25:30 min + 2300 m in Distanzphasen; Gesamtdauer ca. 35 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 7:00 min | 18-26 | 2 | - | - | Einrudern 7 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 200 m | 24-28 | 4 | 2k +3..+8 s/500 m | - | Pyramide 200 m (Stufe 1/7) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause 1:30 min: locker weiterrudern |
| work | 300 m | 24-28 | 4 | 2k +3..+8 s/500 m | - | Pyramide 300 m (Stufe 2/7) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause 2:00 min: locker weiterrudern |
| work | 400 m | 24-28 | 4 | 2k +3..+8 s/500 m | - | Pyramide 400 m (Stufe 3/7) |
| rest | 2:30 min | 16-20 | 1 | - | aktiv | Pause 2:30 min: locker weiterrudern |
| work | 500 m | 24-28 | 4 | 2k +3..+8 s/500 m | - | Pyramide 500 m (Stufe 4/7) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause 3:00 min: locker weiterrudern |
| work | 400 m | 24-28 | 4 | 2k +3..+8 s/500 m | - | Pyramide 400 m (Stufe 5/7) |
| rest | 2:30 min | 16-20 | 1 | - | aktiv | Pause 2:30 min: locker weiterrudern |
| work | 300 m | 24-28 | 4 | 2k +3..+8 s/500 m | - | Pyramide 300 m (Stufe 6/7) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause 2:00 min: locker weiterrudern |
| work | 200 m | 24-28 | 4 | 2k +3..+8 s/500 m | - | Pyramide 200 m (Stufe 7/7) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Antritte 8 x 20 Sekunden alle 2 Minuten (`sprint-einsteiger-8x20s`)

- Erklärung: Alle 2 Minuten ein schneller Antritt über 20 Sekunden, dazwischen 1:40 Minuten ganz locker. Schnell, aber sauber rudern.
- Zweck/Bereich: Schnelligkeit und Kraft bei voller Erholung, wenig Laktat (Puls bleibt meist unter Zone 5)
- Niveau: Einsteiger · Kategorie: Sprint · Tags: hard, power, beginner-friendly, time-efficient
- Belegstatus: abgeleitet: Gluckman (Concept2) nennt 20 x 20 s / 40 s im Tempo 2k -7..-10 s; hier 8 Antritte mit langer Pause (1:5) für Einsteiger; Pausendauer, Schlagzahl (Concept2: 30-36 spm für kurze Stücke) und Pace-Offset eigene Ableitung
- Quellen: Concept2 - From the Archives: A Great Workout in 30 Minutes (L. Gluckman, 30 and Out, Concept2 Update, spring 1995); Springer - High-intensity interval training, solutions to the programming puzzle. Part I: cardiopulmonary emphasis (Buchheit & Laursen), Sports Med 43(5):313-38; Concept2 - Rowing Stroke Rate Explained
- Umfang: zeitbasierte Phasen 27:20 min; Gesamtdauer ca. 27 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-28 | 2 | - | - | Einrudern 8 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 0:20 min | 28-34 | 4 | 2k -8..-3 s/500 m | - | Antritt 20 s schnell (1/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause 1:40 min: ganz locker |
| work | 0:20 min | 28-34 | 4 | 2k -8..-3 s/500 m | - | Antritt 20 s schnell (2/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause 1:40 min: ganz locker |
| work | 0:20 min | 28-34 | 4 | 2k -8..-3 s/500 m | - | Antritt 20 s schnell (3/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause 1:40 min: ganz locker |
| work | 0:20 min | 28-34 | 4 | 2k -8..-3 s/500 m | - | Antritt 20 s schnell (4/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause 1:40 min: ganz locker |
| work | 0:20 min | 28-34 | 4 | 2k -8..-3 s/500 m | - | Antritt 20 s schnell (5/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause 1:40 min: ganz locker |
| work | 0:20 min | 28-34 | 4 | 2k -8..-3 s/500 m | - | Antritt 20 s schnell (6/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause 1:40 min: ganz locker |
| work | 0:20 min | 28-34 | 4 | 2k -8..-3 s/500 m | - | Antritt 20 s schnell (7/8) |
| rest | 1:40 min | 16-20 | 1 | - | aktiv | Pause 1:40 min: ganz locker |
| work | 0:20 min | 28-34 | 4 | 2k -8..-3 s/500 m | - | Antritt 20 s schnell (8/8) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Intervalle 12 x 1 Minute (`intervalle-12x1`)

- Erklärung: Zwölf Intervalle zu 1 Minute etwas schneller als 2000-m-Tempo mit je 1 Minute lockerer Pause.
- Zweck/Bereich: VO2max / Sauerstoffaufnahme (Puls gegen Ende 90 % HFmax und mehr, Pulszone 5)
- Niveau: Fortgeschritten · Kategorie: Intervalle · Tags: hard, vo2max
- Belegstatus: direkt: Concept2 12-Wochen-2k-Plan, Woche 7 Tag 3 (12 x 1 min / 1 min Pause, Schlagzahl 24-34, Pause = sehr locker rudern); Pace-Offset 2k -4..-1 s abgeleitet (kürzer als 2 min im 2k-Tempo)
- Quellen: Concept2 - Training for a 2K Rowing Ergometer Test - 12 Week Plan; Springer - High-intensity interval training, solutions to the programming puzzle. Part I: cardiopulmonary emphasis (Buchheit & Laursen), Sports Med 43(5):313-38
- Umfang: zeitbasierte Phasen 38:00 min; Gesamtdauer ca. 38 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-30 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 1:00 min | 28-32 | 5 | 2k -4..-1 s/500 m | - | Intervall 1 min schneller als 2000-m-Tempo (1/12) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -4..-1 s/500 m | - | Intervall 1 min schneller als 2000-m-Tempo (2/12) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -4..-1 s/500 m | - | Intervall 1 min schneller als 2000-m-Tempo (3/12) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -4..-1 s/500 m | - | Intervall 1 min schneller als 2000-m-Tempo (4/12) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -4..-1 s/500 m | - | Intervall 1 min schneller als 2000-m-Tempo (5/12) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -4..-1 s/500 m | - | Intervall 1 min schneller als 2000-m-Tempo (6/12) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -4..-1 s/500 m | - | Intervall 1 min schneller als 2000-m-Tempo (7/12) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -4..-1 s/500 m | - | Intervall 1 min schneller als 2000-m-Tempo (8/12) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -4..-1 s/500 m | - | Intervall 1 min schneller als 2000-m-Tempo (9/12) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -4..-1 s/500 m | - | Intervall 1 min schneller als 2000-m-Tempo (10/12) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -4..-1 s/500 m | - | Intervall 1 min schneller als 2000-m-Tempo (11/12) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -4..-1 s/500 m | - | Intervall 1 min schneller als 2000-m-Tempo (12/12) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Intervalle 6 x 3 Minuten (`intervalle-6x3`)

- Erklärung: Sechs Intervalle zu 3 Minuten knapp langsamer als 2000-m-Tempo mit je 2 Minuten lockerer Pause.
- Zweck/Bereich: VO2max / Sauerstofftransport TR (Puls 85-95 % HFmax, Pulszone 4-5)
- Niveau: Fortgeschritten · Kategorie: Intervalle · Tags: hard, vo2max
- Belegstatus: direkt: Concept2 12-Wochen-2k-Plan, Woche 7 Tag 1 (6 x 3 min / 2 min Pause, Schlagzahl 24-34); Pace-Offset 2k +1..+4 s abgeleitet (zwischen 4 x 4 min im 2k-Tempo und Schwelle)
- Quellen: Concept2 - Training for a 2K Rowing Ergometer Test - 12 Week Plan; Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary source; Springer - High-intensity interval training, solutions to the programming puzzle. Part I: cardiopulmonary emphasis (Buchheit & Laursen), Sports Med 43(5):313-38
- Umfang: zeitbasierte Phasen 43:00 min; Gesamtdauer ca. 43 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-30 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 3:00 min | 26-30 | 5 | 2k +1..+4 s/500 m | - | Intervall 3 min knapp unter 2000-m-Tempo (1/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 3:00 min | 26-30 | 5 | 2k +1..+4 s/500 m | - | Intervall 3 min knapp unter 2000-m-Tempo (2/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 3:00 min | 26-30 | 5 | 2k +1..+4 s/500 m | - | Intervall 3 min knapp unter 2000-m-Tempo (3/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 3:00 min | 26-30 | 5 | 2k +1..+4 s/500 m | - | Intervall 3 min knapp unter 2000-m-Tempo (4/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 3:00 min | 26-30 | 5 | 2k +1..+4 s/500 m | - | Intervall 3 min knapp unter 2000-m-Tempo (5/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 3:00 min | 26-30 | 5 | 2k +1..+4 s/500 m | - | Intervall 3 min knapp unter 2000-m-Tempo (6/6) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 40/20 Intervalle, 10 Minuten (`intervalle-40-20`)

- Erklärung: Zehn Minuten im Wechsel 40 Sekunden hart und 20 Sekunden locker. Kurz, intensiv, mit 5 Minuten Ein- und Ausrudern.
- Zweck/Bereich: VO2max mit kurzen Pausen, Puls bleibt hoch (Pulszone 4-5)
- Niveau: Fortgeschritten · Kategorie: Intervalle · Tags: hard, vo2max, time-efficient
- Belegstatus: direkt: Concept2 'The Best Rowing Machine Workouts' (5 min Einrudern, 10 min 40 s hart / 20 s locker, 5 min Ausrudern); Einrudern hier 6 min; Schlagzahl und Pace-Offset (2k -2..+2 s) eigene Eingrenzung
- Quellen: Concept2 - The Best Rowing Machine Workouts; Springer - High-intensity interval training, solutions to the programming puzzle. Part I: cardiopulmonary emphasis (Buchheit & Laursen), Sports Med 43(5):313-38
- Umfang: zeitbasierte Phasen 20:40 min; Gesamtdauer ca. 21 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 6:00 min | 18-28 | 2 | - | - | Einrudern 6 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 0:40 min | 26-32 | 5 | 2k -2..+2 s/500 m | - | 40 s hart (1/10) |
| rest | 0:20 min | 16-20 | 1 | - | aktiv | 20 s locker |
| work | 0:40 min | 26-32 | 5 | 2k -2..+2 s/500 m | - | 40 s hart (2/10) |
| rest | 0:20 min | 16-20 | 1 | - | aktiv | 20 s locker |
| work | 0:40 min | 26-32 | 5 | 2k -2..+2 s/500 m | - | 40 s hart (3/10) |
| rest | 0:20 min | 16-20 | 1 | - | aktiv | 20 s locker |
| work | 0:40 min | 26-32 | 5 | 2k -2..+2 s/500 m | - | 40 s hart (4/10) |
| rest | 0:20 min | 16-20 | 1 | - | aktiv | 20 s locker |
| work | 0:40 min | 26-32 | 5 | 2k -2..+2 s/500 m | - | 40 s hart (5/10) |
| rest | 0:20 min | 16-20 | 1 | - | aktiv | 20 s locker |
| work | 0:40 min | 26-32 | 5 | 2k -2..+2 s/500 m | - | 40 s hart (6/10) |
| rest | 0:20 min | 16-20 | 1 | - | aktiv | 20 s locker |
| work | 0:40 min | 26-32 | 5 | 2k -2..+2 s/500 m | - | 40 s hart (7/10) |
| rest | 0:20 min | 16-20 | 1 | - | aktiv | 20 s locker |
| work | 0:40 min | 26-32 | 5 | 2k -2..+2 s/500 m | - | 40 s hart (8/10) |
| rest | 0:20 min | 16-20 | 1 | - | aktiv | 20 s locker |
| work | 0:40 min | 26-32 | 5 | 2k -2..+2 s/500 m | - | 40 s hart (9/10) |
| rest | 0:20 min | 16-20 | 1 | - | aktiv | 20 s locker |
| work | 0:40 min | 26-32 | 5 | 2k -2..+2 s/500 m | - | 40 s hart (10/10) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 6 x 500 m mit 1 Minute Pause (`intervalle-6x500-r1`)

- Erklärung: Sechsmal 500 m im 2000-m-Tempo bei Schlagzahl 30+ mit nur 1 Minute Pause. Gleiches Tempo halten, das letzte Stück voll.
- Zweck/Bereich: Renntempo-Härte / VO2max, gilt als Prognose für die 2000 m (Pulszone 5)
- Niveau: Fortgeschritten · Kategorie: Intervalle · Tags: hard, vo2max, race-pace
- Belegstatus: direkt: Wolfson-Leitfaden (6 x 500 m, Schlagzahl 30+, 1 min Pause, gleicher Split, letztes Stück voll; Split nahe am 2k-Bestwert); Concept2 4-Wochen-2k-Plan nennt 6 x 500 m mit 2 min; Pace-Offset 2k -1..+1 s abgeleitet
- Quellen: Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary source; Concept2 - Training for a 2K Rowing Ergometer Test - 4 Week Plan
- Umfang: zeitbasierte Phasen 21:00 min + 3000 m in Distanzphasen; Gesamtdauer ca. 33 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-32 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 500 m | 30-34 | 5 | 2k -1..+1 s/500 m | - | 500 m im 2000-m-Tempo (1/6) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 500 m | 30-34 | 5 | 2k -1..+1 s/500 m | - | 500 m im 2000-m-Tempo (2/6) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 500 m | 30-34 | 5 | 2k -1..+1 s/500 m | - | 500 m im 2000-m-Tempo (3/6) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 500 m | 30-34 | 5 | 2k -1..+1 s/500 m | - | 500 m im 2000-m-Tempo (4/6) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 500 m | 30-34 | 5 | 2k -1..+1 s/500 m | - | 500 m im 2000-m-Tempo (5/6) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 500 m | 30-34 | 5 | 2k -4..-1 s/500 m | - | 500 m, letztes Stück voll (6/6) |
| cooldown | 6:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 3 x 1000 m mit 3 Minuten Pause (`intervalle-3x1000-r3`)

- Erklärung: Dreimal 1000 m knapp am 2000-m-Tempo mit je 3 Minuten lockerer Pause. Gleichmässig, kein schneller Start.
- Zweck/Bereich: VO2max / Renntempo-Härte (Pulszone 5)
- Niveau: Fortgeschritten · Kategorie: Intervalle · Tags: hard, vo2max, race-pace
- Belegstatus: direkt: Concept2 500-m-Plan (Zyklus 1: 3 x 1000 m / 3 min) und 4-Wochen-2k-Plan (3 x 1000 m / 3 min), Wolfson (3 x 1000 m r30+, 2 min, gleicher Split); Pace-Offset 2k -1..+2 s abgeleitet
- Quellen: Concept2 - Training for a 500m Rowing Ergometer Test; Concept2 - Training for a 2K Rowing Ergometer Test - 4 Week Plan; Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary source
- Umfang: zeitbasierte Phasen 22:00 min + 3000 m in Distanzphasen; Gesamtdauer ca. 34 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-32 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 1000 m | 28-32 | 5 | 2k -1..+2 s/500 m | - | 1000 m knapp am 2000-m-Tempo (1/3) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1000 m | 28-32 | 5 | 2k -1..+2 s/500 m | - | 1000 m knapp am 2000-m-Tempo (2/3) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1000 m | 28-32 | 5 | 2k -1..+2 s/500 m | - | 1000 m knapp am 2000-m-Tempo (3/3) |
| cooldown | 6:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Schlagzahl-Leiter 24-32 in harten Intervallen (`intervalle-schlagzahlleiter-24-32`)

- Erklärung: Zwei Runden mit je fünf Intervallen zu 2 Minuten bei Schlagzahl 24, 26, 28, 30, 32; das Tempo wird mit jeder Stufe schneller. 1 Minute Pause, 4 Minuten zwischen den Runden.
- Zweck/Bereich: Schwelle bis VO2max, Übergang zu höheren Schlagzahlen ohne Längenverlust (Pulszone 4-5)
- Niveau: Fortgeschritten · Kategorie: Intervalle · Tags: hard, vo2max, rate-ladder, progressive
- Belegstatus: abgeleitet: Concept2 (24-28 spm für längere Arbeit, 30-36 spm für Strecken bis 2000 m) und 2k-Plan-Fenster 24-34 spm; Leiterform, Dauern und Pace-Offsets (von 2k +8 s bei r24 bis 2k -2 s bei r32) eigene Konstruktion, keine Primärquelle für genau diese Einheit
- Quellen: Concept2 - Rowing Stroke Rate Explained; Concept2 - Training for a 2K Rowing Ergometer Test - 12 Week Plan; Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary source
- Umfang: zeitbasierte Phasen 48:00 min; Gesamtdauer ca. 48 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-30 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 2:00 min | 23-25 | 4 | 2k +6..+9 s/500 m | - | 2 min bei Schlagzahl 24 (Runde 1, Stufe 1/5) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2:00 min | 25-27 | 4 | 2k +3..+6 s/500 m | - | 2 min bei Schlagzahl 26 (Runde 1, Stufe 2/5) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2:00 min | 27-29 | 5 | 2k +1..+3 s/500 m | - | 2 min bei Schlagzahl 28 (Runde 1, Stufe 3/5) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2:00 min | 29-31 | 5 | 2k -1..+1 s/500 m | - | 2 min bei Schlagzahl 30 (Runde 1, Stufe 4/5) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2:00 min | 31-33 | 5 | 2k -3..-1 s/500 m | - | 2 min bei Schlagzahl 32 (Runde 1, Stufe 5/5) |
| rest | 4:00 min | 16-20 | 1 | - | aktiv | Pause 4 min zwischen den Runden: locker |
| work | 2:00 min | 23-25 | 4 | 2k +6..+9 s/500 m | - | 2 min bei Schlagzahl 24 (Runde 2, Stufe 1/5) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2:00 min | 25-27 | 4 | 2k +3..+6 s/500 m | - | 2 min bei Schlagzahl 26 (Runde 2, Stufe 2/5) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2:00 min | 27-29 | 5 | 2k +1..+3 s/500 m | - | 2 min bei Schlagzahl 28 (Runde 2, Stufe 3/5) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2:00 min | 29-31 | 5 | 2k -1..+1 s/500 m | - | 2 min bei Schlagzahl 30 (Runde 2, Stufe 4/5) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 2:00 min | 31-33 | 5 | 2k -3..-1 s/500 m | - | 2 min bei Schlagzahl 32 (Runde 2, Stufe 5/5) |
| cooldown | 6:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Kraftausdauer 10 x 1 Minute bei Schlagzahl 20 (`intervalle-kraft-10x1-r20`)

- Erklärung: Zehnmal 1 Minute mit maximalem Druck bei nur Schlagzahl 20, danach 1 Minute ganz leicht bei gleicher Schlagzahl.
- Zweck/Bereich: Kraftausdauer / Druck pro Schlag, AT bis TR (Pulszone 4)
- Niveau: Fortgeschritten · Kategorie: Intervalle · Tags: hard, power, rate-cap
- Belegstatus: direkt: Wolfson-Leitfaden, Power-Einheit '10x(1min on, 1min off), rate 20', in der Belastung all-out bei Schlagzahl 20, in der Pause sehr leicht bei gleicher Schlagzahl; Pace-Offset 2k +2..+8 s abgeleitet (Schlagzahl begrenzt das Tempo)
- Quellen: Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary source; Concept2 - Rowing Stroke Rate Explained
- Umfang: zeitbasierte Phasen 34:00 min; Gesamtdauer ca. 34 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-26 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 1:00 min | 19-21 | 4 | 2k +2..+8 s/500 m | - | 1 min maximaler Druck, Schlagzahl 20 (1/10) |
| rest | 1:00 min | 19-21 | 2 | - | aktiv | 1 min ganz leicht, Schlagzahl 20 halten |
| work | 1:00 min | 19-21 | 4 | 2k +2..+8 s/500 m | - | 1 min maximaler Druck, Schlagzahl 20 (2/10) |
| rest | 1:00 min | 19-21 | 2 | - | aktiv | 1 min ganz leicht, Schlagzahl 20 halten |
| work | 1:00 min | 19-21 | 4 | 2k +2..+8 s/500 m | - | 1 min maximaler Druck, Schlagzahl 20 (3/10) |
| rest | 1:00 min | 19-21 | 2 | - | aktiv | 1 min ganz leicht, Schlagzahl 20 halten |
| work | 1:00 min | 19-21 | 4 | 2k +2..+8 s/500 m | - | 1 min maximaler Druck, Schlagzahl 20 (4/10) |
| rest | 1:00 min | 19-21 | 2 | - | aktiv | 1 min ganz leicht, Schlagzahl 20 halten |
| work | 1:00 min | 19-21 | 4 | 2k +2..+8 s/500 m | - | 1 min maximaler Druck, Schlagzahl 20 (5/10) |
| rest | 1:00 min | 19-21 | 2 | - | aktiv | 1 min ganz leicht, Schlagzahl 20 halten |
| work | 1:00 min | 19-21 | 4 | 2k +2..+8 s/500 m | - | 1 min maximaler Druck, Schlagzahl 20 (6/10) |
| rest | 1:00 min | 19-21 | 2 | - | aktiv | 1 min ganz leicht, Schlagzahl 20 halten |
| work | 1:00 min | 19-21 | 4 | 2k +2..+8 s/500 m | - | 1 min maximaler Druck, Schlagzahl 20 (7/10) |
| rest | 1:00 min | 19-21 | 2 | - | aktiv | 1 min ganz leicht, Schlagzahl 20 halten |
| work | 1:00 min | 19-21 | 4 | 2k +2..+8 s/500 m | - | 1 min maximaler Druck, Schlagzahl 20 (8/10) |
| rest | 1:00 min | 19-21 | 2 | - | aktiv | 1 min ganz leicht, Schlagzahl 20 halten |
| work | 1:00 min | 19-21 | 4 | 2k +2..+8 s/500 m | - | 1 min maximaler Druck, Schlagzahl 20 (9/10) |
| rest | 1:00 min | 19-21 | 2 | - | aktiv | 1 min ganz leicht, Schlagzahl 20 halten |
| work | 1:00 min | 19-21 | 4 | 2k +2..+8 s/500 m | - | 1 min maximaler Druck, Schlagzahl 20 (10/10) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Kraftausdauer 6 x 3 Minuten bei Schlagzahl 16-18 (`intervalle-kraft-6x3-r18`)

- Erklärung: Sechsmal 3 Minuten mit hohem Druck bei tiefer Schlagzahl 16-18 (lange, kräftige Schläge), je 2 Minuten locker.
- Zweck/Bereich: Kraftausdauer und Durchzug, Schwelle AT (Puls ca. 80-88 % HFmax, Pulszone 4)
- Niveau: Fortgeschritten · Kategorie: Intervalle · Tags: hard, power, rate-cap
- Belegstatus: angepasst: Wolfson (Power-Einheiten bei tiefer Schlagzahl, z. B. r20 mit hohem Druck, 'close to a high-weight squat'), Concept2 (18-22 spm fühlt sich eher wie Krafttraining an, keine langen harten Einheiten in diesem Bereich); Schlagzahl 16-18, Dauer und Pace-Offset (2k +6..+12 s) eigene Eingrenzung
- Quellen: Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary source; Concept2 - Rowing Stroke Rate Explained
- Umfang: zeitbasierte Phasen 43:00 min; Gesamtdauer ca. 43 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-24 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 3:00 min | 16-18 | 4 | 2k +6..+12 s/500 m | - | 3 min hoher Druck, Schlagzahl 16-18 (1/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 3:00 min | 16-18 | 4 | 2k +6..+12 s/500 m | - | 3 min hoher Druck, Schlagzahl 16-18 (2/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 3:00 min | 16-18 | 4 | 2k +6..+12 s/500 m | - | 3 min hoher Druck, Schlagzahl 16-18 (3/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 3:00 min | 16-18 | 4 | 2k +6..+12 s/500 m | - | 3 min hoher Druck, Schlagzahl 16-18 (4/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 3:00 min | 16-18 | 4 | 2k +6..+12 s/500 m | - | 3 min hoher Druck, Schlagzahl 16-18 (5/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 3:00 min | 16-18 | 4 | 2k +6..+12 s/500 m | - | 3 min hoher Druck, Schlagzahl 16-18 (6/6) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Sprint 20 x 20 Sekunden (`sprint-20x20-40`)

- Erklärung: Zwanzig schnelle Stücke zu 20 Sekunden, 7-10 s pro 500 m schneller als 2000-m-Tempo, mit je 40 Sekunden lockerer Pause.
- Zweck/Bereich: Anaerobe Kapazität und VO2max (Pulszone 5)
- Niveau: Fortgeschritten · Kategorie: Sprint · Tags: hard, anaerobic, vo2max
- Belegstatus: direkt: Gluckman '30 and Out' (Concept2): 20 x 20 s im Tempo 2k -7..-10 s mit 40 s lockerem Paddeln; Warm-up dort 24/28/32 spm; Schlagzahl eigene Eingrenzung
- Quellen: Concept2 - From the Archives: A Great Workout in 30 Minutes (L. Gluckman, 30 and Out, Concept2 Update, spring 1995); Springer - High-intensity interval training, solutions to the programming puzzle. Part I: cardiopulmonary emphasis (Buchheit & Laursen), Sports Med 43(5):313-38
- Umfang: zeitbasierte Phasen 34:20 min; Gesamtdauer ca. 34 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-32 | 2 | - | - | Einrudern 10 min: steigernd, je 10 Schläge bei 24, 28, 32 |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (1/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (2/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (3/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (4/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (5/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (6/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (7/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (8/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (9/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (10/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (11/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (12/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (13/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (14/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (15/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (16/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (17/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (18/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (19/20) |
| rest | 0:40 min | 16-20 | 1 | - | aktiv | 40 s locker |
| work | 0:20 min | 30-36 | 5 | 2k -10..-7 s/500 m | - | 20 s schnell (20/20) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Startübungen 6 x Start (`sprint-startuebungen-6x`)

- Erklärung: Sechs Rennstarts aus dem Stand: 5 halbe Schläge zum Anrudern, dann 10 hohe, schnelle Schläge. Dazwischen 2 Minuten locker und kurz stoppen.
- Zweck/Bereich: Startschnelligkeit und Kraft, Technik unter Tempo (kurz Pulszone 4-5)
- Niveau: Fortgeschritten · Kategorie: Sprint · Tags: max, power, technique, time-efficient
- Belegstatus: angepasst: Concept2 Neuseeland (erster Schlag mit 1/2-3/4 Rollweg, Zieltempo in den ersten 5 Schlägen erreichen; nur über Suchauszug gelesen), Concept2 (30-36 spm und mehr für kurze Strecken); Zählweise 5 halbe + 10 hohe Schläge ist eine übliche Variante, nicht einheitlich belegt; Dauer 30 s und Pausen eigene Eingrenzung
- Quellen: Concept2 New Zealand - Race starts and changing pace on the indoor rower (read via search excerpt only); Concept2 - Rowing Stroke Rate Explained; Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary source
- Umfang: zeitbasierte Phasen 29:00 min; Gesamtdauer ca. 29 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-30 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 0:30 min | 34-40 | 5 | 2k -12..-6 s/500 m | - | Start: 5 halbe Schläge, dann 10 hohe Schläge (1/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause 2 min: locker, am Ende kurz anhalten für den nächsten Start |
| work | 0:30 min | 34-40 | 5 | 2k -12..-6 s/500 m | - | Start: 5 halbe Schläge, dann 10 hohe Schläge (2/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause 2 min: locker, am Ende kurz anhalten für den nächsten Start |
| work | 0:30 min | 34-40 | 5 | 2k -12..-6 s/500 m | - | Start: 5 halbe Schläge, dann 10 hohe Schläge (3/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause 2 min: locker, am Ende kurz anhalten für den nächsten Start |
| work | 0:30 min | 34-40 | 5 | 2k -12..-6 s/500 m | - | Start: 5 halbe Schläge, dann 10 hohe Schläge (4/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause 2 min: locker, am Ende kurz anhalten für den nächsten Start |
| work | 0:30 min | 34-40 | 5 | 2k -12..-6 s/500 m | - | Start: 5 halbe Schläge, dann 10 hohe Schläge (5/6) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause 2 min: locker, am Ende kurz anhalten für den nächsten Start |
| work | 0:30 min | 34-40 | 5 | 2k -12..-6 s/500 m | - | Start: 5 halbe Schläge, dann 10 hohe Schläge (6/6) |
| cooldown | 6:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 8 x 500 m (Pete Plan) (`intervalle-8x500-pete`)

- Erklärung: Achtmal 500 m etwa 3 s pro 500 m schneller als 2000-m-Bestzeit-Tempo mit je 3:30 Minuten Pause. Alle bis auf das letzte gleich, das letzte voll.
- Zweck/Bereich: Tempohärte über dem 2000-m-Tempo, VO2max und anaerob (Pulszone 5)
- Niveau: Leistung · Kategorie: Intervalle · Tags: hard, vo2max, anaerobic
- Belegstatus: direkt: Pete Plan Woche 1 (8 x 500 m, 3:30 Pause; FAQ: 3 s schneller als 2k-Bestzeit-Tempo; alle bis auf das letzte im Zieltempo, das letzte so schnell wie möglich); auch Wolverine-Plan Stufe 1 (Caviston). Schlagzahl eigene Eingrenzung
- Quellen: The Pete Plan (Pete Marston) - The Pete Plan (author's site, schedule and FAQ pace targets); Concept2 Forum - Wolverine Plan Discussion (compilation of Mike Caviston's posts); forum, secondary source
- Umfang: zeitbasierte Phasen 40:30 min + 4000 m in Distanzphasen; Gesamtdauer ca. 56 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-32 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 500 m | 30-34 | 5 | 2k -4..-2 s/500 m | - | 500 m, 3 s schneller als 2000-m-Tempo (1/8) |
| rest | 3:30 min | 16-20 | 1 | - | aktiv | Pause 3:30 min: locker weiterrudern |
| work | 500 m | 30-34 | 5 | 2k -4..-2 s/500 m | - | 500 m, 3 s schneller als 2000-m-Tempo (2/8) |
| rest | 3:30 min | 16-20 | 1 | - | aktiv | Pause 3:30 min: locker weiterrudern |
| work | 500 m | 30-34 | 5 | 2k -4..-2 s/500 m | - | 500 m, 3 s schneller als 2000-m-Tempo (3/8) |
| rest | 3:30 min | 16-20 | 1 | - | aktiv | Pause 3:30 min: locker weiterrudern |
| work | 500 m | 30-34 | 5 | 2k -4..-2 s/500 m | - | 500 m, 3 s schneller als 2000-m-Tempo (4/8) |
| rest | 3:30 min | 16-20 | 1 | - | aktiv | Pause 3:30 min: locker weiterrudern |
| work | 500 m | 30-34 | 5 | 2k -4..-2 s/500 m | - | 500 m, 3 s schneller als 2000-m-Tempo (5/8) |
| rest | 3:30 min | 16-20 | 1 | - | aktiv | Pause 3:30 min: locker weiterrudern |
| work | 500 m | 30-34 | 5 | 2k -4..-2 s/500 m | - | 500 m, 3 s schneller als 2000-m-Tempo (6/8) |
| rest | 3:30 min | 16-20 | 1 | - | aktiv | Pause 3:30 min: locker weiterrudern |
| work | 500 m | 30-34 | 5 | 2k -4..-2 s/500 m | - | 500 m, 3 s schneller als 2000-m-Tempo (7/8) |
| rest | 3:30 min | 16-20 | 1 | - | aktiv | Pause 3:30 min: locker weiterrudern |
| work | 500 m | 30-34 | 5 | 2k -7..-3 s/500 m | - | 500 m, letztes Stück voll (8/8) |
| cooldown | 6:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 6 x 750 m im 2000-m-Tempo (`intervalle-6x750`)

- Erklärung: Sechsmal 750 m im 2000-m-Tempo mit je 2:30 Minuten lockerer Pause. Zusammen 4500 m Renntempo.
- Zweck/Bereich: Renntempo-Härte / VO2max (Pulszone 5)
- Niveau: Leistung · Kategorie: Intervalle · Tags: hard, vo2max, race-pace
- Belegstatus: abgeleitet: Zwischenform aus Pete Plan 8 x 500 m (2k -3 s, 3:30) und 4 x 1000 m (2k +1 s, 5 min) sowie Concept2-Distanzintervallen; Distanz 750 m, Pause 2:30 und Pace-Offset (2k -1..+1 s) eigene Konstruktion, keine Primärquelle für genau diese Einheit
- Quellen: The Pete Plan (Pete Marston) - The Pete Plan (author's site, schedule and FAQ pace targets); Concept2 - Training for a 500m Rowing Ergometer Test; Springer - High-intensity interval training, solutions to the programming puzzle. Part I: cardiopulmonary emphasis (Buchheit & Laursen), Sports Med 43(5):313-38
- Umfang: zeitbasierte Phasen 28:30 min + 4500 m in Distanzphasen; Gesamtdauer ca. 46 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-32 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 750 m | 28-32 | 5 | 2k -1..+1 s/500 m | - | 750 m im 2000-m-Tempo (1/6) |
| rest | 2:30 min | 16-20 | 1 | - | aktiv | Pause 2:30 min: locker weiterrudern |
| work | 750 m | 28-32 | 5 | 2k -1..+1 s/500 m | - | 750 m im 2000-m-Tempo (2/6) |
| rest | 2:30 min | 16-20 | 1 | - | aktiv | Pause 2:30 min: locker weiterrudern |
| work | 750 m | 28-32 | 5 | 2k -1..+1 s/500 m | - | 750 m im 2000-m-Tempo (3/6) |
| rest | 2:30 min | 16-20 | 1 | - | aktiv | Pause 2:30 min: locker weiterrudern |
| work | 750 m | 28-32 | 5 | 2k -1..+1 s/500 m | - | 750 m im 2000-m-Tempo (4/6) |
| rest | 2:30 min | 16-20 | 1 | - | aktiv | Pause 2:30 min: locker weiterrudern |
| work | 750 m | 28-32 | 5 | 2k -1..+1 s/500 m | - | 750 m im 2000-m-Tempo (5/6) |
| rest | 2:30 min | 16-20 | 1 | - | aktiv | Pause 2:30 min: locker weiterrudern |
| work | 750 m | 28-32 | 5 | 2k -1..+1 s/500 m | - | 750 m im 2000-m-Tempo (6/6) |
| cooldown | 6:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 4 x 1000 m (Pete Plan) (`intervalle-4x1000-pete`)

- Erklärung: Viermal 1000 m etwa 1 s pro 500 m langsamer als 2000-m-Bestzeit-Tempo mit je 5 Minuten Pause; das letzte Stück voll.
- Zweck/Bereich: VO2max / Renntempo-Härte (Pulszone 5)
- Niveau: Leistung · Kategorie: Intervalle · Tags: hard, vo2max, race-pace
- Belegstatus: direkt: Pete Plan Woche 3 (4 x 1000 m, 5 min Pause; FAQ: 1 s langsamer als 2k-Bestzeit-Tempo); Concept2 500-m-Plan Zyklus 2 nennt 4 x 1000 m mit 3 min; Schlagzahl eigene Eingrenzung
- Quellen: The Pete Plan (Pete Marston) - The Pete Plan (author's site, schedule and FAQ pace targets); Concept2 - Training for a 500m Rowing Ergometer Test
- Umfang: zeitbasierte Phasen 32:00 min + 4000 m in Distanzphasen; Gesamtdauer ca. 48 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-32 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 1000 m | 28-32 | 5 | 2k 0..+2 s/500 m | - | 1000 m, 1 s langsamer als 2000-m-Tempo (1/4) |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause 5 min: locker weiterrudern |
| work | 1000 m | 28-32 | 5 | 2k 0..+2 s/500 m | - | 1000 m, 1 s langsamer als 2000-m-Tempo (2/4) |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause 5 min: locker weiterrudern |
| work | 1000 m | 28-32 | 5 | 2k 0..+2 s/500 m | - | 1000 m, 1 s langsamer als 2000-m-Tempo (3/4) |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause 5 min: locker weiterrudern |
| work | 1000 m | 28-32 | 5 | 2k -3..0 s/500 m | - | 1000 m, letztes Stück voll (4/4) |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Speed-Pyramide 250-1000-250 m (Pete Plan) (`intervalle-pyramide-250-1000`)

- Erklärung: Pyramide 250, 500, 750, 1000, 750, 500, 250 m im 2000-m-Tempo; Pause je 1:30 Minuten pro 250 m des vorherigen Stücks.
- Zweck/Bereich: VO2max und Renntempo, 4000 m Arbeit (Pulszone 5)
- Niveau: Leistung · Kategorie: Intervalle · Tags: hard, vo2max, pyramid, race-pace
- Belegstatus: direkt: Pete Plan Woche 2 (250/500/750/1000/750/500/250 m, 1:30 Pause pro vorherige 250 m; FAQ: 2k-Bestzeit-Tempo); Caviston nennt dieselbe Pyramide als Wolverine-Stufe-1-Einheit (500er etwa im 8x500-Tempo, gleich- oder negativ gesplittet). Schlagzahl eigene Eingrenzung
- Quellen: The Pete Plan (Pete Marston) - The Pete Plan (author's site, schedule and FAQ pace targets); Concept2 Forum - Wolverine Plan Discussion (compilation of Mike Caviston's posts); forum, secondary source
- Umfang: zeitbasierte Phasen 39:30 min + 4000 m in Distanzphasen; Gesamtdauer ca. 55 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-32 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 250 m | 28-34 | 5 | 2k -2..+1 s/500 m | - | Pyramide 250 m im 2000-m-Tempo (Stufe 1/7) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause 1:30 min: locker weiterrudern |
| work | 500 m | 28-34 | 5 | 2k -2..+1 s/500 m | - | Pyramide 500 m im 2000-m-Tempo (Stufe 2/7) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause 3:00 min: locker weiterrudern |
| work | 750 m | 28-34 | 5 | 2k -1..+1 s/500 m | - | Pyramide 750 m im 2000-m-Tempo (Stufe 3/7) |
| rest | 4:30 min | 16-20 | 1 | - | aktiv | Pause 4:30 min: locker weiterrudern |
| work | 1000 m | 28-34 | 5 | 2k -1..+1 s/500 m | - | Pyramide 1000 m im 2000-m-Tempo (Stufe 4/7) |
| rest | 6:00 min | 16-20 | 1 | - | aktiv | Pause 6:00 min: locker weiterrudern |
| work | 750 m | 28-34 | 5 | 2k -1..+1 s/500 m | - | Pyramide 750 m im 2000-m-Tempo (Stufe 5/7) |
| rest | 4:30 min | 16-20 | 1 | - | aktiv | Pause 4:30 min: locker weiterrudern |
| work | 500 m | 28-34 | 5 | 2k -2..+1 s/500 m | - | Pyramide 500 m im 2000-m-Tempo (Stufe 6/7) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause 3:00 min: locker weiterrudern |
| work | 250 m | 28-34 | 5 | 2k -2..+1 s/500 m | - | Pyramide 250 m im 2000-m-Tempo (Stufe 7/7) |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Intervalle 2 x 10 x 1 Minute (`intervalle-2x10x1`)

- Erklärung: Zwei Blöcke mit je zehn Intervallen 1 Minute hart / 1 Minute locker, 4 Minuten Pause zwischen den Blöcken.
- Zweck/Bereich: VO2max mit grossem Umfang an Zeit nahe der maximalen Sauerstoffaufnahme (Pulszone 5)
- Niveau: Leistung · Kategorie: Intervalle · Tags: hard, vo2max
- Belegstatus: angepasst: Concept2 12-Wochen-2k-Plan (12 x 1 min / 1 min); auf 20 Wiederholungen in 2 Blöcken erweitert, gestützt auf Buchheit & Laursen (Ziel: mehrere Minuten pro Einheit über 90 % VO2max; Serien mit Blockpausen als Steuergrösse); Blockpause und Pace-Offset (2k -3..0 s) eigene Eingrenzung
- Quellen: Concept2 - Training for a 2K Rowing Ergometer Test - 12 Week Plan; Springer - High-intensity interval training, solutions to the programming puzzle. Part I: cardiopulmonary emphasis (Buchheit & Laursen), Sports Med 43(5):313-38
- Umfang: zeitbasierte Phasen 59:00 min; Gesamtdauer ca. 59 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-30 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 1, 1/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 1, 2/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 1, 3/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 1, 4/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 1, 5/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 1, 6/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 1, 7/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 1, 8/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 1, 9/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 1, 10/10) |
| rest | 4:00 min | 16-20 | 1 | - | aktiv | Pause 4 min zwischen den Blöcken: locker |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 2, 1/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 2, 2/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 2, 3/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 2, 4/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 2, 5/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 2, 6/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 2, 7/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 2, 8/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 2, 9/10) |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern |
| work | 1:00 min | 28-32 | 5 | 2k -3..0 s/500 m | - | 1 min hart (Block 2, 10/10) |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 30/15 Intervalle 3 x 13 (Rønnestad) (`intervalle-30-15`)

- Erklärung: Drei Serien mit je 13 x 30 Sekunden hart / 15 Sekunden locker, 3 Minuten Pause zwischen den Serien. So hart, wie es sich über alle Serien gleichmässig halten lässt.
- Zweck/Bereich: VO2max und Leistung an der Schwelle, kurze Intervalle mit kurzer Pause (Pulszone 4-5)
- Niveau: Leistung · Kategorie: Intervalle · Tags: hard, vo2max, threshold
- Belegstatus: angepasst: Rønnestad et al. 2020 (Radfahrer, Elite): 3 Serien x 13 x 30 s / 15 s Erholung, 3 min zwischen den Serien, Intensität nach maximal gleichmässig haltbarer Anstrengung; Übertragung aufs Rudern sowie Schlagzahl und Pace-Offset (2k -3..+1 s) eigene Ableitung
- Quellen: Wiley - Superior performance improvements in elite cyclists following short-interval vs effort-matched long-interval training (Rønnestad et al.), Scand J Med Sci Sports 30(5):849-857; Springer - High-intensity interval training, solutions to the programming puzzle. Part I: cardiopulmonary emphasis (Buchheit & Laursen), Sports Med 43(5):313-38
- Umfang: zeitbasierte Phasen 51:30 min; Gesamtdauer ca. 52 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-30 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 1, 1/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 1, 2/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 1, 3/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 1, 4/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 1, 5/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 1, 6/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 1, 7/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 1, 8/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 1, 9/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 1, 10/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 1, 11/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 1, 12/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 1, 13/13) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause 3 min zwischen den Serien: locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 2, 1/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 2, 2/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 2, 3/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 2, 4/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 2, 5/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 2, 6/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 2, 7/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 2, 8/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 2, 9/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 2, 10/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 2, 11/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 2, 12/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 2, 13/13) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause 3 min zwischen den Serien: locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 3, 1/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 3, 2/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 3, 3/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 3, 4/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 3, 5/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 3, 6/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 3, 7/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 3, 8/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 3, 9/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 3, 10/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 3, 11/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 3, 12/13) |
| rest | 0:15 min | 16-20 | 1 | - | aktiv | 15 s locker |
| work | 0:30 min | 28-32 | 5 | 2k -3..+1 s/500 m | - | 30 s hart (Serie 3, 13/13) |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## 20 x 30 Sekunden volle Kraft (`intervalle-30-30-x20`)

- Erklärung: Zwanzigmal 30 Sekunden mit voller Kraft, je 30 Sekunden locker. Sehr fordernd, Tempo über alle 20 möglichst halten.
- Zweck/Bereich: VO2max und anaerobe Kapazität (Pulszone 5)
- Niveau: Leistung · Kategorie: Intervalle · Tags: max, vo2max, anaerobic
- Belegstatus: direkt: Concept2 '20 x 30 Seconds Full Power with a CrossFit Champion' (20 x 30 s volle Kraft / 30 s Pause); Einrudern, Schlagzahl und Pace-Offset (2k -8..-3 s) eigene Eingrenzung
- Quellen: Concept2 - 20 x 30 Seconds Full Power with a CrossFit Champion; Springer - High-intensity interval training, solutions to the programming puzzle. Part I: cardiopulmonary emphasis (Buchheit & Laursen), Sports Med 43(5):313-38
- Umfang: zeitbasierte Phasen 34:30 min; Gesamtdauer ca. 34 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-32 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (1/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (2/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (3/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (4/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (5/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (6/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (7/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (8/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (9/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (10/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (11/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (12/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (13/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (14/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (15/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (16/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (17/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (18/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (19/20) |
| rest | 0:30 min | 16-20 | 1 | - | aktiv | 30 s locker |
| work | 0:30 min | 30-36 | 5 | 2k -8..-3 s/500 m | - | 30 s volle Kraft (20/20) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Tabata 8 x 20/10 Sekunden (`sprint-tabata-8x20-10`)

- Erklärung: Acht Runden 20 Sekunden maximal / 10 Sekunden locker (4 Minuten). Nur nach gründlichem Einrudern und für Gesunde mit Erfahrung in harten Einheiten.
- Zweck/Bereich: Anaerobe Kapazität und VO2max, sehr hohe Belastung (Pulszone 5)
- Niveau: Leistung · Kategorie: Sprint · Tags: max, anaerobic, vo2max, time-efficient
- Belegstatus: direkt: Concept2 'The Best Rowing Machine Workouts' (10 min Einrudern, 8 x 20 s maximal / 10 s locker, 5 min Ausrudern; optional nach 2 min ein zweiter Satz); Ursprung Tabata et al. 1996 (Fahrradergometer, 7-8 x 20 s bei ca. 170 % VO2max, 10 s Pause, bis zur Erschöpfung). Pace-Offset (2k -12..-4 s, fällt über die Runden ab) und Schlagzahl eigene Eingrenzung
- Quellen: Concept2 - The Best Rowing Machine Workouts; Medicine & Science in Sports & Exercise (ACSM) - Effects of moderate-intensity endurance and high-intensity intermittent training on anaerobic capacity and VO2max (Tabata et al.), Med Sci Sports Exerc 28(10):1327-30
- Umfang: zeitbasierte Phasen 21:50 min; Gesamtdauer ca. 22 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-32 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 0:20 min | 32-38 | 5 | 2k -12..-4 s/500 m | - | 20 s maximal (1/8) |
| rest | 0:10 min | 16-20 | 1 | - | aktiv | 10 s locker |
| work | 0:20 min | 32-38 | 5 | 2k -12..-4 s/500 m | - | 20 s maximal (2/8) |
| rest | 0:10 min | 16-20 | 1 | - | aktiv | 10 s locker |
| work | 0:20 min | 32-38 | 5 | 2k -12..-4 s/500 m | - | 20 s maximal (3/8) |
| rest | 0:10 min | 16-20 | 1 | - | aktiv | 10 s locker |
| work | 0:20 min | 32-38 | 5 | 2k -12..-4 s/500 m | - | 20 s maximal (4/8) |
| rest | 0:10 min | 16-20 | 1 | - | aktiv | 10 s locker |
| work | 0:20 min | 32-38 | 5 | 2k -12..-4 s/500 m | - | 20 s maximal (5/8) |
| rest | 0:10 min | 16-20 | 1 | - | aktiv | 10 s locker |
| work | 0:20 min | 32-38 | 5 | 2k -12..-4 s/500 m | - | 20 s maximal (6/8) |
| rest | 0:10 min | 16-20 | 1 | - | aktiv | 10 s locker |
| work | 0:20 min | 32-38 | 5 | 2k -12..-4 s/500 m | - | 20 s maximal (7/8) |
| rest | 0:10 min | 16-20 | 1 | - | aktiv | 10 s locker |
| work | 0:20 min | 32-38 | 5 | 2k -12..-4 s/500 m | - | 20 s maximal (8/8) |
| cooldown | 8:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Sprint 10 x 100 m (`sprint-10x100`)

- Erklärung: Zehn Sprints über 100 m bei hoher Schlagzahl mit je 1:30 Minuten lockerer Pause. Jeder Sprint voll, sauberer Start.
- Zweck/Bereich: Schnelligkeit und Maximalkraft, anaerob-alaktazid (Pulszone 4-5)
- Niveau: Leistung · Kategorie: Sprint · Tags: max, anaerobic, power
- Belegstatus: abgeleitet: Concept2 (30-36 spm und mehr für kurze Strecken) und Wolfson (Sprints 6-10 kurze Stücke bei 30-36 spm, all-out); Distanz 100 m (Concept2-Ranglistenstrecke), Pause 1:30 und Pace-Offset (2k -14..-8 s) eigene Konstruktion
- Quellen: Concept2 - Rowing Stroke Rate Explained; Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary source; Springer - High-intensity interval training, solutions to the programming puzzle. Part I: cardiopulmonary emphasis (Buchheit & Laursen), Sports Med 43(5):313-38
- Umfang: zeitbasierte Phasen 29:30 min + 1000 m in Distanzphasen; Gesamtdauer ca. 33 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-34 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 100 m | 34-42 | 5 | 2k -14..-8 s/500 m | - | Sprint 100 m voll (1/10) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause 1:30 min: locker weiterrudern |
| work | 100 m | 34-42 | 5 | 2k -14..-8 s/500 m | - | Sprint 100 m voll (2/10) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause 1:30 min: locker weiterrudern |
| work | 100 m | 34-42 | 5 | 2k -14..-8 s/500 m | - | Sprint 100 m voll (3/10) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause 1:30 min: locker weiterrudern |
| work | 100 m | 34-42 | 5 | 2k -14..-8 s/500 m | - | Sprint 100 m voll (4/10) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause 1:30 min: locker weiterrudern |
| work | 100 m | 34-42 | 5 | 2k -14..-8 s/500 m | - | Sprint 100 m voll (5/10) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause 1:30 min: locker weiterrudern |
| work | 100 m | 34-42 | 5 | 2k -14..-8 s/500 m | - | Sprint 100 m voll (6/10) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause 1:30 min: locker weiterrudern |
| work | 100 m | 34-42 | 5 | 2k -14..-8 s/500 m | - | Sprint 100 m voll (7/10) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause 1:30 min: locker weiterrudern |
| work | 100 m | 34-42 | 5 | 2k -14..-8 s/500 m | - | Sprint 100 m voll (8/10) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause 1:30 min: locker weiterrudern |
| work | 100 m | 34-42 | 5 | 2k -14..-8 s/500 m | - | Sprint 100 m voll (9/10) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause 1:30 min: locker weiterrudern |
| work | 100 m | 34-42 | 5 | 2k -14..-8 s/500 m | - | Sprint 100 m voll (10/10) |
| cooldown | 6:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Sprint 6 x 1 Minute (`sprint-6x1min`)

- Erklärung: Sechsmal 1 Minute sehr hart (deutlich schneller als 2000-m-Tempo) mit je 3 Minuten lockerer Pause.
- Zweck/Bereich: Anaerobe Kapazität / Laktattoleranz (Pulszone 5)
- Niveau: Leistung · Kategorie: Sprint · Tags: max, anaerobic
- Belegstatus: abgeleitet: Concept2 500-m-Plan (kurze harte Stücke mit langen Pausen, 26-36 spm) und Gluckman (500 m 2k -2..-6 s, 20 s 2k -7..-10 s); 1 min mit 1:3-Pause und Pace-Offset (2k -8..-4 s) eigene Konstruktion
- Quellen: Concept2 - Training for a 500m Rowing Ergometer Test; Concept2 - Rowing Stroke Rate Explained; Springer - High-intensity interval training, solutions to the programming puzzle. Part I: cardiopulmonary emphasis (Buchheit & Laursen), Sports Med 43(5):313-38
- Umfang: zeitbasierte Phasen 38:00 min; Gesamtdauer ca. 38 min (Bezug 2:00/500 m)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-32 | 2 | - | - | Einrudern 10 min: locker, steigernd, am Ende 3 kurze Antritte |
| work | 1:00 min | 30-36 | 5 | 2k -8..-4 s/500 m | - | 1 min sehr hart (1/6) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause 3 min: locker weiterrudern |
| work | 1:00 min | 30-36 | 5 | 2k -8..-4 s/500 m | - | 1 min sehr hart (2/6) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause 3 min: locker weiterrudern |
| work | 1:00 min | 30-36 | 5 | 2k -8..-4 s/500 m | - | 1 min sehr hart (3/6) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause 3 min: locker weiterrudern |
| work | 1:00 min | 30-36 | 5 | 2k -8..-4 s/500 m | - | 1 min sehr hart (4/6) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause 3 min: locker weiterrudern |
| work | 1:00 min | 30-36 | 5 | 2k -8..-4 s/500 m | - | 1 min sehr hart (5/6) |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | Pause 3 min: locker weiterrudern |
| work | 1:00 min | 30-36 | 5 | 2k -8..-4 s/500 m | - | 1 min sehr hart (6/6) |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern: ganz locker |

## Quellenliste

- Concept2: Training for a 500m Rowing Ergometer Test. https://www.concept2.com/training/plans/500m-erg-test (ohne Datum). 8- bzw. 12-Wochen-Plan: 4-8 x 500 m / 2 min, 3-4 x 1000 m / 3 min, 6-12 x 250 m / 1 min, 26-36 spm, Pause = sehr locker rudern
- Concept2: Training for a 2K Rowing Ergometer Test - 12 Week Plan. https://www.concept2.com/training/plans/2k-erg-test-12-week (ohne Datum). Enthält 6 x 3 min / 2 min, 10 x 2 min / 1 min, 12 x 1 min / 1 min, 6 x 2 min / 2 min, 24-34 spm
- Concept2: Training for a 2K Rowing Ergometer Test - 4 Week Plan. https://www.concept2.com/training/plans/2k-erg-test-4-week (ohne Datum; Fundus practice 976)
- Concept2: The Best Rowing Machine Workouts. https://www.concept2.com/blog/the-best-rowing-machine-workouts (2018-07-02)
- Concept2: 20 x 30 Seconds Full Power with a CrossFit Champion. https://www.concept2.com/blog/20-x-30-seconds-full-power-with-a-crossfit-champion (2012-06-04)
- Concept2: 10-20-30 Training. https://www.concept2.com/blog/102030-training (2015-08-28)
- Concept2: From the Archives: A Great Workout in 30 Minutes (Gluckman 1995). https://www.concept2.com/news/archives-great-workout-30-minutes (2013-12-31; Fundus practice 975)
- Concept2: Rowing Stroke Rate Explained. https://www.concept2.com/news/rowing-stroke-rate-explained (2017-12-01)
- Concept2: Workout of the Day (allgemeine Vorgaben). https://www.concept2.com/training/wod
- Concept2 New Zealand: Race starts and changing pace on the indoor rower. https://www.concept2.co.nz/Blog/x_post/Race-starts-and-changing-pace-on-the-indoor-rower-00095.html (nur Suchauszug)
- The Pete Plan (Pete Marston): The Pete Plan. https://thepeteplan.wordpress.com/the-pete-plan/ (ohne Datum)
- Concept2 Forum: Wolverine Plan Discussion (Caviston-Beiträge, Sammlung). https://c2forum.com/viewtopic.php?p=100
- Wolfson College Boat Club, University of Cambridge: Erging, Abschnitte 1.5-1.6. https://www.wolfson.cam.ac.uk/sites/default/files/2019-11/wcbc_erging_0.pdf (2019). Power: 10 x (1 min on / 1 min off) r20, 3 x 6 min r26; Sprints: 10 x 250 m r30+ / 30 s, 6 x 500 m r30+ / 1 min, 3 x 1000 m r30+ / 2 min; 6 x 500 m als 2k-Prognose
- ACE (S. Thielen): Reap the Benefits of Rowing With 3 Fast and Efficient Workouts. https://www.acefitness.org/education-and-resources/lifestyle/blog/5881/reap-the-benefits-of-rowing-with-3-fast-and-efficient-workouts (2016-03-28)
- Tabata I. et al.: Effects of moderate-intensity endurance and high-intensity intermittent training on anaerobic capacity and VO2max. Med Sci Sports Exerc 1996;28(10):1327-30. doi:10.1097/00005768-199610000-00018. https://pubmed.ncbi.nlm.nih.gov/8897392/. 7-8 x 20 s bei ca. 170 % VO2max, 10 s Pause, 5 x/Woche, 6 Wochen: VO2max +7 ml/kg/min, anaerobe Kapazität +28 %
- Rønnestad B. R. et al.: Superior performance improvements in elite cyclists following short-interval vs effort-matched long-interval training. Scand J Med Sci Sports 2020;30(5):849-857. doi:10.1111/sms.13627. https://pubmed.ncbi.nlm.nih.gov/31977120/. 3 x 13 x 30 s / 15 s, 3 min zwischen den Serien, 9 Einheiten in 3 Wochen: Spitzenleistung aerob +3,7 % gegenüber -0,3 % bei 4 x 5 min
- Buchheit M., Laursen P. B.: High-intensity interval training, solutions to the programming puzzle. Part I. Sports Med 2013;43(5):313-38. doi:10.1007/s40279-013-0029-x. https://pubmed.ncbi.nlm.nih.gov/23539308/
- Gunnarsson T. P., Bangsbo J.: The 10-20-30 training concept improves performance and health profile in moderately trained runners. J Appl Physiol 2012;113(1):16-24. doi:10.1152/japplphysiol.00334.2012

Hinweis zur Übertragbarkeit: Tabata, Rønnestad und Gunnarsson/Bangsbo haben auf dem Fahrradergometer bzw. mit Läufern gearbeitet. Für das Rudern sind die Protokolle übertragen und nicht eigens geprüft.

## In Fundus zurückgeschrieben (Projekt `rowcoach`, alle `unverified`)

practice 986 (Pete Plan), 987 (Concept2 500-m-Plan), 983 (Concept2 12-Wochen-2k-Plan), 984 (Wolfson-Beispieleinheiten), 985 (Concept2 40/20, Tabata, 20 x 30 s, 10-20-30); study 1045 (Tabata 1996), 1046 (Rønnestad 2020), 1047 (Buchheit & Laursen 2013); fact 2437 (Concept2-Schlagzahlbereiche). Bereits vorhanden und genutzt: practice 975 (Gluckman), 976 (Concept2 4-Wochen-2k-Plan), fact 2420 (Wolfson-Zonen).

Erzeugungsskript (nicht im Repo): `gen_intervalle.py` im Scratchpad der Sitzung; bei Bedarf ins Repo übernehmen.
