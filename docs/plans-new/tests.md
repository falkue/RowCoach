# Familie `tests`: Test- und Wettkampfprogramme für RowCoach

Stand 26.11.2026. 20 neue Programme in den Kategorien Test (13) und Wettkampf (7), Datei `tests.json`. Ergänzt `test-2000m` (nicht gedoppelt; die Rennsimulation mit Taktik und die 4 x 500 m üben den Ablauf, sie ersetzen den Test nicht).

## Methode

- Recherche-Reihenfolge Zotero → Fundus → Web. **Zotero**: `zrag search` lieferte nur unbetitelte Transkript-Notizen ohne Bezug; danach war der Zotero-MCP-Server nicht erreichbar (Connection refused auf :8000), `zrag semantic` brach ab. Kein Zotero-Beleg. **Fundus** (Projekt `rowcoach`): vorhanden waren Concept2-4-Wochen-2k-Plan, Wolfson-Zonen, Seiler/Tønnessen, 30-and-Out; zu Tests, Stufentests, Tapering, Renneinrudern nichts. **Web**: Primärquellen Concept2 (Testpläne 500 m, 4 min, 5k, 2k, Rangliste, Pacing-Artikel), World Rowing (Jensen, Hay), USRowing, Studien (Garland 2005, Kass & Carpenter, Lindenthaler/Rice 2018, Bosquet 2007).
- **Tempo der Tests**: Prognose aus der 2k-Bestzeit auf zwei Wegen: (a) Jensen/World Rowing: mittlere Watt in % der 2000-m-Watt (60 min ~76 %, 6000 m ~85 %, 60 s ~153 %, 10 s/100 m ~173 %), umgerechnet mit Watt ~ 1/Pace^3 bei Referenz 2:00/500 m; (b) Paul's Law (Concept2-Forum, Sekundärquelle): pro Verdopplung der Strecke +5 s/500 m, d. h. Offset = 5 · log2(Strecke/2000). Das Fenster liegt jeweils rund ±1,5 s um den Prognosewert. Im Forum wird betont, dass die Konstante individuell 3-7 s beträgt (Sprinter mehr, Ausdauertypen weniger); die Werte sind also Zielhilfen, kein Muss. Bei Zeittests (1 min, 4 min, 30 min, 60 min) gibt es keine Obergrenze: die Strecke ist das Ergebnis, der Tempokorridor nur Orientierung.
- **Stufentests**: Kass & Carpenter geben das Schema genau an (oberste Stufe 2k-Split +10 s, darunter je -25 W). Feste Watt-Abstände ergeben je nach Leistungsniveau andere Pace-Abstände; die Offsets gelten für einen 2k-Split von 2:00. Eine spätere App-Version sollte die Stufen in Watt rechnen.
- **Einrudern**: Concept2 (alle Testpläne): 5-10 min locker beginnen, bis mittlere Intensität steigern, am Ende ein paar kurze Antritte. Kurztests (bis 4 min) haben hier zusätzlich eine 2-min-Antrittsphase und 2 min Pause vor dem Start, lange Tests 10 min Einrudern.
- Lokales Modell nicht benutzt (Texte direkt geschrieben).

## Pulszonen

Concept2-5-Zonen-Modell in % HFmax wie im BRIEF: 1 < 65 (Regeneration), 2 65-75 (UT2), 3 75-80/85 (UT1), 4 80/85-90 (AT/Schwelle), 5 > 90 (TR/AN). Bei sehr kurzen Tests (100 m, 1 min) steht Zone 5 für die Belastungsart; der Puls erreicht sie erst gegen Ende oder danach.

## Nicht abrufbar / Unsicherheiten

- British Rowing (britishrowing.org, plus.britishrowing.org): 403 bzw. Weiterleitung auf die Startseite. Das Renn-Einrudern (J. Brown) und 'The science behind the perfect 2k test' konnten nicht gelesen werden; British Rowing ist beim Einrudern nur mit einem Suchauszug belegt (als solcher gekennzeichnet). Einen offiziellen British-Rowing-Stufentest mit 3-min-Stufen habe ich nicht gefunden; belegt sind 4-min-Stufen (Kass & Carpenter; Lindenthaler/Rice, AIS-Umfeld).
- Concept2-Rangliste: die RowErg-Auswahl auf log.concept2.com/rankings enthält 1000 m; die Concept2-FAQ (laut Suchauszug) listet 1000 m nicht für RowErg. Ich folge der Ranglistenseite.
- Faster Masters (Head-Race-Rennpläne) war im Wartungsmodus; die Head-Race-Simulation stützt sich deshalb auf USRowing, Concept2 und World Rowing und ist als 'abgeleitet' markiert.
- '6000 m als Wintertest bei Junioren und Masters' ist Vereinsbrauch und nicht belegt; belegt ist 6000 m als Standardtest (Jensen) und Ranglistenstück.
- Halbmarathon und Marathon nicht als Test aufgenommen (Überschneidung mit der Familie `grundlage`).
- Lindenthaler/Rice nennen die Leistung der Stufen 1-6 nicht; `stufentest-7x4` setzt sie nach dem Kass-Schema (dort als 'angepasst' vermerkt).

## Test 100 m (`test-100m`)

- Erklärung: Ein 100-m-Sprint auf Bestzeit nach gründlichem Einrudern mit Antritten.
- Zweck/Bereich: Test Maximalkraft und anaerobe Leistung, Concept2-Ranglistenstück (Pulszone 5; Puls steigt erst nach dem Sprint)
- Kategorie: Test; Niveau: Fortgeschritten; Tags: max, power, anaerobic, benchmark, c2-ranked, time-efficient
- Belegstatus: abgeleitet: Distanz direkt (Concept2-Rangliste, Jensen nennt 10 s/100 m als Standardtest); Tempo aus Jensen (~173 % der 2k-Watt) über Watt ~ 1/Pace^3; Einrudern nach Concept2-Plänen, Schlagzahl eigene Eingrenzung
- Quellen: Concept2 - Concept2 Online Ranking (RowErg events: 1 min, 4 min, 30 min, 60 min, 100 m to 100 000 m); World Rowing - Using the indoor rower for testing: why do we test different distances? (K. Jensen: 60 min ~76 %, 6000 m ~85 %, 60 s ~153 %, 10 s/100 m ~173 % of 2000-m watts); Concept2 - Training for a 500m Rowing Ergometer Test
- Ungefähre Dauer: 19 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern 8 min: locker beginnen, bis mittlere Intensität steigern |
| warmup | 2:00 min | 20-34 | 3 | - | - | Antritte: 3 x 5-10 Schläge hart, dazwischen locker |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause vor dem Test: locker paddeln, Monitor einstellen |
| work | 100 m | 36-46 | 5 | 2k -23..-17 s/500 m | - | 100 m Sprint: kurzer Start (halbe, halbe, dreiviertel Schlag), dann voll |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern 7 min: ganz locker |

## Test 500 m (`test-500m`)

- Erklärung: 500 m auf Bestzeit: nicht zu schnell starten, in der zweiten Hälfte zulegen.
- Zweck/Bereich: Test anaerobe Kapazität, Concept2-Ranglistenstück (Pulszone 5)
- Kategorie: Test; Niveau: Fortgeschritten; Tags: max, anaerobic, benchmark, c2-ranked, time-efficient
- Belegstatus: direkt: Concept2 500-m-Plan (500-m-Zeitfahren, Einrudern 5-10 min mit Antritten, Schlagzahl 26-36, nicht zu schnell starten, konstant oder negativer Split); Tempo abgeleitet aus Paul's Law (2k -10 s/500 m)
- Quellen: Concept2 - Training for a 500m Rowing Ergometer Test; Concept2 - Concept2 Online Ranking (RowErg events: 1 min, 4 min, 30 min, 60 min, 100 m to 100 000 m); Concept2 Forum - "Paul's Law" (double the distance, add about 5 s/500 m); forum thread, secondary source
- Ungefähre Dauer: 21 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern 8 min: locker beginnen, bis mittlere Intensität steigern |
| warmup | 2:00 min | 20-34 | 3 | - | - | Antritte: 3 x 5-10 Schläge hart, dazwischen locker |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause vor dem Test: locker paddeln, Monitor einstellen |
| work | 500 m | 30-38 | 5 | 2k -12..-8 s/500 m | - | 500 m Bestzeit: erste 250 m kontrolliert, dann steigern |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern 7 min: ganz locker |

## Test 1000 m (`test-1000m`)

- Erklärung: 1000 m auf Bestzeit, gleichmässig oder mit leicht negativem Split. Guter erster Maximaltest, weil kurz.
- Zweck/Bereich: Test VO2max und anaerobe Kapazität, Concept2-Ranglistenstück (Pulszone 5)
- Kategorie: Test; Niveau: Einsteiger; Tags: max, vo2max, anaerobic, benchmark, c2-ranked, time-efficient, beginner-friendly
- Belegstatus: angepasst: Distanz aus der Concept2-Rangliste, Einrudern und Renntaktik aus den Concept2-Testplänen; Tempo abgeleitet aus Paul's Law (2k -5 s/500 m); Niveau Einsteiger eigene Einschätzung (kurze Belastung, ohne 2k-Bestzeit nach Gefühl rudern)
- Quellen: Concept2 - Concept2 Online Ranking (RowErg events: 1 min, 4 min, 30 min, 60 min, 100 m to 100 000 m); Concept2 - Training for a 2K Rowing Ergometer Test - 4 Week Plan; Concept2 Forum - "Paul's Law" (double the distance, add about 5 s/500 m); forum thread, secondary source
- Ungefähre Dauer: 23 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern 8 min: locker beginnen, bis mittlere Intensität steigern |
| warmup | 2:00 min | 20-34 | 3 | - | - | Antritte: 3 x 5-10 Schläge hart, dazwischen locker |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause vor dem Test: locker paddeln, Monitor einstellen |
| work | 1000 m | 26-34 | 5 | 2k -7..-3 s/500 m | - | 1000 m Bestzeit: erste 250 m 1-2 s langsamer als Ziel, ab 500 m steigern |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern 7 min: ganz locker |

## Test 1 Minute (`test-1min`)

- Erklärung: Eine Minute so weit wie möglich rudern; die Strecke ist das Ergebnis.
- Zweck/Bereich: Test anaerobe Kapazität, Concept2-Ranglistenstück (Pulszone 5)
- Kategorie: Test; Niveau: Fortgeschritten; Tags: max, anaerobic, power, benchmark, c2-ranked, time-efficient
- Belegstatus: abgeleitet: Dauer direkt (Concept2-Rangliste, Jensen nennt 60 s als Standardtest); Tempo aus Jensen (~153 % der 2k-Watt) über Watt ~ 1/Pace^3; Einrudern nach Concept2-Plänen
- Quellen: Concept2 - Concept2 Online Ranking (RowErg events: 1 min, 4 min, 30 min, 60 min, 100 m to 100 000 m); World Rowing - Using the indoor rower for testing: why do we test different distances? (K. Jensen: 60 min ~76 %, 6000 m ~85 %, 60 s ~153 %, 10 s/100 m ~173 % of 2000-m watts)
- Ungefähre Dauer: 20 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern 8 min: locker beginnen, bis mittlere Intensität steigern |
| warmup | 2:00 min | 20-34 | 3 | - | - | Antritte: 3 x 5-10 Schläge hart, dazwischen locker |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause vor dem Test: locker paddeln, Monitor einstellen |
| work | 1:00 min | 32-42 | 5 | 2k -18..-14 s/500 m | - | 1 min auf maximale Strecke: kurzer Start, ab 30 s Tempo halten |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern 7 min: ganz locker |

## Test 4 Minuten (`test-4min`)

- Erklärung: Vier Minuten so weit wie möglich, mit kontrolliertem Beginn und Steigerung in der zweiten Hälfte.
- Zweck/Bereich: Test VO2max (maximale aerobe Leistung), Concept2-Ranglistenstück (Pulszone 5)
- Kategorie: Test; Niveau: Fortgeschritten; Tags: max, vo2max, benchmark, c2-ranked, time-efficient, negative-split
- Belegstatus: direkt: Concept2 4-min-Plan (4-min-Zeitfahren, Einrudern 5-10 min mit Antritten, Schlagzahl 26-36, zweite Hälfte schneller, negativer Split mit 1-2 s langsamerem Start); Tempo abgeleitet aus Paul's Law (rund 1000-1050 m, 2k -3..-5 s)
- Quellen: Concept2 - Training for a 4 Minute Rowing Ergometer Test; Concept2 - Concept2 Online Ranking (RowErg events: 1 min, 4 min, 30 min, 60 min, 100 m to 100 000 m); Concept2 Forum - "Paul's Law" (double the distance, add about 5 s/500 m); forum thread, secondary source
- Ungefähre Dauer: 23 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-24 | 2 | - | - | Einrudern 8 min: locker beginnen, bis mittlere Intensität steigern |
| warmup | 2:00 min | 20-34 | 3 | - | - | Antritte: 3 x 5-10 Schläge hart, dazwischen locker |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause vor dem Test: locker paddeln, Monitor einstellen |
| work | 4:00 min | 28-34 | 5 | 2k -6..-2 s/500 m | - | 4 min auf maximale Strecke: erste 2 min 1-2 s langsamer als Ziel, dann steigern |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern 7 min: ganz locker |

## Test 5000 m (`test-5000m`)

- Erklärung: 5000 m auf Bestzeit im geplanten Renntempo; wer sich auf dem letzten Kilometer gut fühlt, legt zu.
- Zweck/Bereich: Test aerobe Leistung nahe der Schwelle, Concept2-Ranglistenstück (Pulszone 4-5)
- Kategorie: Test; Niveau: Fortgeschritten; Tags: hard, threshold, vo2max, benchmark, c2-ranked
- Belegstatus: direkt: Concept2 5k-Plan (5k-Test im bekannten Renntempo, letzten Kilometer steigern, Schlagzahl 24-30, Einrudern 5-10 min); Tempo abgeleitet aus Paul's Law (2k +6-7 s)
- Quellen: Concept2 - Training for a 5K Rowing Ergometer Test; Concept2 - Concept2 Online Ranking (RowErg events: 1 min, 4 min, 30 min, 60 min, 100 m to 100 000 m); Concept2 Forum - "Paul's Law" (double the distance, add about 5 s/500 m); forum thread, secondary source; World Rowing - Indoor rowing part 2 - ergo testing strategy (G. Hay)
- Ungefähre Dauer: 38 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-26 | 2 | - | - | Einrudern 10 min: locker beginnen, steigern, am Ende 3 kurze Antritte |
| work | 4000 m | 24-30 | 4 | 2k +5..+8 s/500 m | - | Kilometer 1-4 im Renntempo: geduldig, nicht zu schnell beginnen |
| work | 1000 m | 26-32 | 5 | 2k +3..+6 s/500 m | - | Letzter Kilometer: steigern, auf den letzten 250 m alles geben |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern 7 min: ganz locker |

## Test 6000 m (Wintertest) (`test-6000m`)

- Erklärung: 6000 m auf Bestzeit in gleichmässigem Tempo; klassischer Wintertest in Vereinen, auch bei Junioren und Masters.
- Zweck/Bereich: Test aerobe Leistung, Concept2-Ranglistenstück (Pulszone 4-5)
- Kategorie: Test; Niveau: Leistung; Tags: hard, threshold, aerobic, benchmark, c2-ranked
- Belegstatus: abgeleitet: Distanz direkt (Concept2-Rangliste; Jensen/World Rowing nennt 6000 m als Standardtest, Hay: Taktik wie 2000 m, Schlagzahl bewusst wählen); Tempo aus Jensen (~85 % der 2k-Watt, entspricht 2k +6-7 s) und Paul's Law (+8 s); 'Wintertest' Vereinsbrauch, nicht belegt
- Quellen: World Rowing - Using the indoor rower for testing: why do we test different distances? (K. Jensen: 60 min ~76 %, 6000 m ~85 %, 60 s ~153 %, 10 s/100 m ~173 % of 2000-m watts); Concept2 - Concept2 Online Ranking (RowErg events: 1 min, 4 min, 30 min, 60 min, 100 m to 100 000 m); World Rowing - Indoor rowing part 2 - ergo testing strategy (G. Hay); Concept2 Forum - "Paul's Law" (double the distance, add about 5 s/500 m); forum thread, secondary source
- Ungefähre Dauer: 42 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-26 | 2 | - | - | Einrudern 10 min: locker beginnen, steigern, am Ende 3 kurze Antritte |
| work | 2000 m | 24-30 | 4 | 2k +6..+9 s/500 m | - | Erste 2000 m: Zieltempo halten, geduldig bleiben |
| work | 2000 m | 24-30 | 4 | 2k +6..+9 s/500 m | - | 2000-4000 m: Rhythmus halten, Schlagzahl nicht absinken lassen |
| work | 2000 m | 26-32 | 5 | 2k +4..+8 s/500 m | - | Letzte 2000 m: ab 5000 m steigern |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern 7 min: ganz locker |

## Test 10 000 m (`test-10000m`)

- Erklärung: 10 000 m auf Bestzeit in konstantem Tempo, mit Steigerung auf den letzten 2000 m.
- Zweck/Bereich: Test aerobe Ausdauer an der Schwelle, Concept2-Ranglistenstück (Pulszone 4)
- Kategorie: Test; Niveau: Leistung; Tags: hard, threshold, aerobic, benchmark, c2-ranked
- Belegstatus: abgeleitet: Distanz aus der Concept2-Rangliste (10 000 m im 12-Wochen-Plan als konstantes Stück); Testfassung mit Tempo aus Paul's Law (2k +11-12 s); Schlagzahl eigene Eingrenzung
- Quellen: Concept2 - Concept2 Online Ranking (RowErg events: 1 min, 4 min, 30 min, 60 min, 100 m to 100 000 m); Concept2 - Training for a 2K Rowing Ergometer Test - 12 Week Plan; Concept2 Forum - "Paul's Law" (double the distance, add about 5 s/500 m); forum thread, secondary source
- Ungefähre Dauer: 61 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-26 | 2 | - | - | Einrudern 10 min: locker beginnen, steigern, am Ende 3 kurze Antritte |
| work | 8000 m | 22-28 | 4 | 2k +10..+13 s/500 m | - | 0-8000 m: konstantes Zieltempo, ruhiger Rhythmus |
| work | 2000 m | 24-30 | 5 | 2k +7..+11 s/500 m | - | Letzte 2000 m: steigern, letzte 500 m Endspurt |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern 7 min: ganz locker |

## Test 30 Minuten (`test-30min`)

- Erklärung: 30 Minuten so weit wie möglich in gleichmässigem Tempo; die Strecke ist das Ergebnis.
- Zweck/Bereich: Test Schwellenleistung, Concept2-Ranglistenstück (Pulszone 4)
- Kategorie: Test; Niveau: Fortgeschritten; Tags: hard, threshold, benchmark, c2-ranked
- Belegstatus: abgeleitet: Dauer aus der Concept2-Rangliste, Wolfson nennt 30 min (30r20) als üblichen Test; Tempo aus Paul's Law (rund 7-7,5 km, 2k +9-10 s); Schlagzahl eigene Eingrenzung
- Quellen: Concept2 - Concept2 Online Ranking (RowErg events: 1 min, 4 min, 30 min, 60 min, 100 m to 100 000 m); Wolfson College Boat Club, University of Cambridge - Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary source; Concept2 Forum - "Paul's Law" (double the distance, add about 5 s/500 m); forum thread, secondary source
- Ungefähre Dauer: 47 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-26 | 2 | - | - | Einrudern 10 min: locker beginnen, steigern, am Ende 3 kurze Antritte |
| work | 25:00 min | 22-28 | 4 | 2k +8..+11 s/500 m | - | Minute 0-25: konstantes Zieltempo, Schlagzahl ruhig halten |
| work | 5:00 min | 24-30 | 5 | 2k +5..+9 s/500 m | - | Letzte 5 min: steigern, letzte Minute Endspurt |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern 7 min: ganz locker |

## Test 60 Minuten (`test-60min`)

- Erklärung: Eine Stunde so weit wie möglich in konstantem Tempo, mit Steigerung in den letzten 10 Minuten.
- Zweck/Bereich: Test aerobe Ausdauer knapp unter der Schwelle, Concept2-Ranglistenstück (Pulszone 3-4)
- Kategorie: Test; Niveau: Leistung; Tags: hard, aerobic, threshold, benchmark, c2-ranked
- Belegstatus: abgeleitet: Dauer direkt (Concept2-Rangliste; Jensen nennt 60 min als Standardtest); Tempo aus Jensen (~76 % der 2k-Watt = 2k +11-12 s) und Paul's Law (+13-14 s)
- Quellen: World Rowing - Using the indoor rower for testing: why do we test different distances? (K. Jensen: 60 min ~76 %, 6000 m ~85 %, 60 s ~153 %, 10 s/100 m ~173 % of 2000-m watts); Concept2 - Concept2 Online Ranking (RowErg events: 1 min, 4 min, 30 min, 60 min, 100 m to 100 000 m); Concept2 Forum - "Paul's Law" (double the distance, add about 5 s/500 m); forum thread, secondary source
- Ungefähre Dauer: 77 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-26 | 2 | - | - | Einrudern 10 min: locker beginnen, steigern, am Ende 3 kurze Antritte |
| work | 50:00 min | 20-26 | 4 | 2k +11..+14 s/500 m | - | Minute 0-50: konstantes Zieltempo, alle 10 min trinken erlaubt |
| work | 10:00 min | 22-28 | 4 | 2k +8..+12 s/500 m | - | Letzte 10 min: steigern, letzte 2 min Endspurt |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern 7 min: ganz locker |

## Stufentest 5 x 4 min (submaximal) (`stufentest-5x4`)

- Erklärung: Fünf Stufen zu 4 Minuten mit steigender Leistung und 1 Minute Pause; die oberste Stufe liegt 10 s/500 m über dem 2k-Tempo. Puls am Ende jeder Stufe notieren.
- Zweck/Bereich: Leistungsdiagnostik: Puls-Leistungs-Kurve und Schwelle (mit Laktat), Kontrolle der Pulszonen (Pulszone 1-4)
- Kategorie: Test; Niveau: Fortgeschritten; Tags: moderate, threshold, aerobic, progressive, ladder, benchmark
- Belegstatus: direkt: Kass & Carpenter (5 Stufen à 4 min, 1 min Pause, Stufe 5 = 2k-Split +10 s, darunter je -25 W, Einrudern 10 min sehr locker); Pace-Offsets abgeleitet aus Watt ~ 1/Pace^3 für Referenz 2:00/500 m (bei anderen Splits weichen die unteren Stufen ab); Schlagzahl eigene Eingrenzung
- Quellen: University of Hertfordshire Research Archive - The Effect of Sampling Time on Blood Lactate Concentration in Trained Rowers (Kass & Carpenter), incremental test 5 x 4 min, methods p. 3-4; repository manuscript; Frontiers - Differences in Physiological Responses During Rowing and Cycle Ergometry in Elite Male Rowers (Lindenthaler, Rice et al.), Front Physiol 9:1010, doi:10.3389/fphys.2018.01010
- Ungefähre Dauer: 42 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-22 | 1 | - | - | Einrudern 10 min sehr locker, ohne Antritte (sonst verfälscht es Puls und Laktat der ersten Stufen) |
| work | 4:00 min | 18-22 | 1 | 2k +60..+63 s/500 m | - | Stufe 1/5: konstant 4 min |
| rest | 1:00 min | - | 1 | - | stehen | Pause 1 min stehen (Puls notieren) (1/4) |
| work | 4:00 min | 20-24 | 2 | 2k +39..+43 s/500 m | - | Stufe 2/5: konstant 4 min |
| rest | 1:00 min | - | 1 | - | stehen | Pause 1 min stehen (Puls notieren) (2/4) |
| work | 4:00 min | 22-26 | 2 | 2k +25..+29 s/500 m | - | Stufe 3/5: konstant 4 min |
| rest | 1:00 min | - | 1 | - | stehen | Pause 1 min stehen (Puls notieren) (3/4) |
| work | 4:00 min | 24-28 | 3 | 2k +16..+20 s/500 m | - | Stufe 4/5: konstant 4 min |
| rest | 1:00 min | - | 1 | - | stehen | Pause 1 min stehen (Puls notieren) (4/4) |
| work | 4:00 min | 26-30 | 4 | 2k +9..+11 s/500 m | - | Stufe 5/5: konstant 4 min (oberste Stufe = 2k-Split +10 s) |
| cooldown | 8:00 min | 16-20 | 1 | - | - | Ausrudern 8 min: ganz locker |

## Stufentest 7 x 4 min mit Maximalstufe (`stufentest-7x4`)

- Erklärung: Sechs Stufen zu 4 Minuten mit steigender Leistung und 1 Minute Pause, als siebte Stufe 4 Minuten auf maximale Strecke.
- Zweck/Bereich: Leistungsdiagnostik wie im Spitzenrudern: Schwellen, Puls-Leistungs-Kurve und maximale aerobe Leistung (Pulszone 1-5)
- Kategorie: Test; Niveau: Leistung; Tags: hard, threshold, vo2max, progressive, ladder, benchmark
- Belegstatus: angepasst: Lindenthaler/Rice et al. (7 Stufen à 4 min, 1 min Pause, Stufen 1-6 aus der 2k-Saisonbestzeit, Stufe 7 = 4-min-Zeitfahren); die Stufenleistungen nennt die Quelle nicht: hier oberste submaximale Stufe 2k-Split +8 s, darunter je -20 W (in Anlehnung an Kass & Carpenter), umgerechnet mit Watt ~ 1/Pace^3 für 2:00/500 m
- Quellen: Frontiers - Differences in Physiological Responses During Rowing and Cycle Ergometry in Elite Male Rowers (Lindenthaler, Rice et al.), Front Physiol 9:1010, doi:10.3389/fphys.2018.01010; University of Hertfordshire Research Archive - The Effect of Sampling Time on Blood Lactate Concentration in Trained Rowers (Kass & Carpenter), incremental test 5 x 4 min, methods p. 3-4; repository manuscript; Concept2 - Training for a 4 Minute Rowing Ergometer Test
- Ungefähre Dauer: 52 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-22 | 1 | - | - | Einrudern 10 min sehr locker, ohne Antritte (sonst verfälscht es Puls und Laktat der ersten Stufen) |
| work | 4:00 min | 18-22 | 1 | 2k +52..+56 s/500 m | - | Stufe 1/7: konstant 4 min |
| rest | 1:00 min | - | 1 | - | stehen | Pause 1 min stehen (Puls/Laktat) (1/6) |
| work | 4:00 min | 20-24 | 2 | 2k +37..+41 s/500 m | - | Stufe 2/7: konstant 4 min |
| rest | 1:00 min | - | 1 | - | stehen | Pause 1 min stehen (Puls/Laktat) (2/6) |
| work | 4:00 min | 22-26 | 3 | 2k +27..+31 s/500 m | - | Stufe 3/7: konstant 4 min |
| rest | 1:00 min | - | 1 | - | stehen | Pause 1 min stehen (Puls/Laktat) (3/6) |
| work | 4:00 min | 24-28 | 3 | 2k +19..+22 s/500 m | - | Stufe 4/7: konstant 4 min |
| rest | 1:00 min | - | 1 | - | stehen | Pause 1 min stehen (Puls/Laktat) (4/6) |
| work | 4:00 min | 26-30 | 4 | 2k +12..+15 s/500 m | - | Stufe 5/7: konstant 4 min |
| rest | 1:00 min | - | 1 | - | stehen | Pause 1 min stehen (Puls/Laktat) (5/6) |
| work | 4:00 min | 28-32 | 4 | 2k +7..+9 s/500 m | - | Stufe 6/7: konstant 4 min |
| rest | 1:00 min | - | 1 | - | stehen | Pause 1 min stehen (Puls/Laktat) (6/6) |
| work | 4:00 min | 28-36 | 5 | 2k -6..-2 s/500 m | - | Stufe 7/7: 4 min auf maximale Strecke |
| cooldown | 8:00 min | 16-20 | 1 | - | - | Ausrudern 8 min: ganz locker |

## Einsteiger-Test 10 Minuten (`einsteiger-test-10min`)

- Erklärung: Zehn Minuten so weit wie möglich in einem Tempo, das man durchhält; die Strecke ist der Startwert für spätere Vergleiche.
- Zweck/Bereich: Erster Leistungstest ohne 2k-Bestzeit, aerob bis Schwelle (Pulszone 3-4)
- Kategorie: Test; Niveau: Einsteiger; Tags: moderate, aerobic, benchmark, beginner-friendly, time-efficient, negative-split
- Belegstatus: angepasst: Concept2 'How to find your 2k pace' (locker beginnen in einem Tempo, das man sicher halten kann, zweite Hälfte nur bei gutem Gefühl steigern, Test alle 1-2 Wochen wiederholen) und Concept2-Einrudern; 10 min als Dauer eigene Wahl (kein Ranglistenstück); bewusst ohne Tempovorgabe
- Quellen: Concept2 - How To Find Your 2k Race Pace; Concept2 - Training for a 2K Rowing Ergometer Test - 4 Week Plan
- Ungefähre Dauer: 21 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 5:00 min | 18-22 | 2 | - | - | Einrudern 5 min: locker, steigernd |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Kurz locker paddeln, dann Test starten |
| work | 5:00 min | 20-26 | 3 | - | - | Minute 0-5: ruhig beginnen, Tempo finden, das man halten kann |
| work | 5:00 min | 22-28 | 4 | - | - | Minute 5-10: halten, ab Minute 8 steigern, wenn es geht |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern 5 min: ganz locker |

## 2000-m-Rennsimulation mit Taktik (`rennsimulation-2000m-taktik`)

- Erklärung: 2000 m wie im Rennen: schneller Start über 250 m, auf Zieltempo setzen, drittes Viertel halten, Endspurt auf den letzten 500 m.
- Zweck/Bereich: Renntaktik üben, Wettkampfleistung (Pulszone 5)
- Kategorie: Wettkampf; Niveau: Leistung; Tags: max, vo2max, anaerobic, race-pace
- Belegstatus: angepasst: Garland (Ergometer: erste 500 m ~101,5 % der mittleren Geschwindigkeit, dann 99,8/99,0/99,7 %), Concept2 'Fly and Die' (kurze Startschläge, 10 harte Schläge, nach 10-15 Schlägen auf Zieltempo setzen bei 30-34 spm, drittes Viertel am härtesten, letzte 250 m steigern, letzte 100 m Power 10), Hay (Geduld auf den ersten 1000 m); Abschnittslängen und Offsets eigene Umsetzung. Ersetzt nicht den Test 2000 m (test-2000m), sondern übt den Ablauf
- Quellen: BMJ - An analysis of the pacing strategy adopted by elite competitors in 2000 m rowing (Garland), Br J Sports Med 39(1):39-42, doi:10.1136/bjsm.2003.010801; Concept2 - Fly and Die: Strategies for Pacing; World Rowing - Indoor rowing part 2 - ergo testing strategy (G. Hay); Concept2 - Training for a 2K Rowing Ergometer Test - 4 Week Plan
- Ungefähre Dauer: 31 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-28 | 2 | - | - | Einrudern 10 min: steigernd, am Ende 3 Antritte |
| rest | 3:00 min | 16-20 | 1 | - | aktiv | 3 min locker, Startposition einnehmen |
| work | 250 m | 34-40 | 5 | 2k -5..-2 s/500 m | - | Start 250 m: halbe, halbe, dreiviertel Schlag, 10 harte Schläge, dann setzen |
| work | 750 m | 30-34 | 5 | 2k -1..+1 s/500 m | - | 250-1000 m: auf Zieltempo setzen, geduldig bleiben |
| work | 500 m | 30-34 | 5 | 2k 0..+2 s/500 m | - | 1000-1500 m: drittes Viertel, Tempo halten (der härteste Teil) |
| work | 250 m | 32-36 | 5 | 2k -2..0 s/500 m | - | 1500-1750 m: Endspurt vorbereiten, Schlagzahl anheben |
| work | 250 m | 34-40 | 5 | 2k -5..-2 s/500 m | - | Letzte 250 m: Endspurt, letzte 100 m Power 10 |
| cooldown | 10:00 min | 16-20 | 1 | - | - | Ausrudern 10 min: ganz locker |

## 2000 m in 4 x 500 m mit Ziel-Splits (`renntempo-4x500-2000m`)

- Erklärung: Die 2000 m in vier Stücke zu 500 m mit je 1 Minute Pause zerlegt; jedes Stück im Split des Rennplans.
- Zweck/Bereich: Renntempo und Rennplan einüben, Zieltempo für den 2000-m-Test festigen (Pulszone 5)
- Kategorie: Wettkampf; Niveau: Fortgeschritten; Tags: hard, vo2max, race-pace, time-efficient
- Belegstatus: angepasst: Concept2 500-m-Plan (4 x 500 m, 2 min Pause, Schlagzahl 26-36) mit 1 min Pause rennnäher gemacht; Splits nach Concept2-Rennplan (konstant bzw. 1-2 s langsamer beginnen, letzte 500 m zulegen) und Garland (Ergometerprofil)
- Quellen: Concept2 - Training for a 500m Rowing Ergometer Test; Concept2 - Training for a 2K Rowing Ergometer Test - 4 Week Plan; BMJ - An analysis of the pacing strategy adopted by elite competitors in 2000 m rowing (Garland), Br J Sports Med 39(1):39-42, doi:10.1136/bjsm.2003.010801; Concept2 - How To Find Your 2k Race Pace
- Ungefähre Dauer: 27 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-26 | 2 | - | - | Einrudern 8 min: locker beginnen, steigern, am Ende 3 kurze Antritte |
| work | 500 m | 30-34 | 5 | 2k -1..+1 s/500 m | - | 500 m (1/4): wie Rennbeginn, Zielsplit halten |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause 1 min: locker weiterrudern (1/3) |
| work | 500 m | 28-32 | 5 | 2k 0..+2 s/500 m | - | 500 m (2/4): Zielsplit, Rhythmus finden |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause 1 min: locker weiterrudern (2/3) |
| work | 500 m | 28-32 | 5 | 2k 0..+2 s/500 m | - | 500 m (3/4): Zielsplit halten, nicht nachlassen |
| rest | 1:00 min | 16-20 | 1 | - | aktiv | Pause 1 min: locker weiterrudern (3/3) |
| work | 500 m | 32-38 | 5 | 2k -4..-1 s/500 m | - | 500 m (4/4): Endspurt, schneller als Zielsplit |
| cooldown | 8:00 min | 16-20 | 1 | - | - | Ausrudern 8 min: ganz locker |

## Rennvorbereitung 3 x (Start + 1000 m) (`rennvorbereitung-3x-start-1000`)

- Erklärung: Dreimal 500 m mit Start im Renntempo, direkt gefolgt von 1000 m Mittelstück knapp unter Renntempo; 5 Minuten Pause zwischen den Runden.
- Zweck/Bereich: Übergang vom Start ins Mittelstück üben, Renntempo-Ausdauer (Pulszone 5)
- Kategorie: Wettkampf; Niveau: Leistung; Tags: max, vo2max, anaerobic, race-pace
- Belegstatus: abgeleitet: Aufbau eigene Umsetzung der Rennphasen Start - Setzen - Mittelstück (USRowing; Concept2 'Fly and Die': nach 10-15 Schlägen setzen bei 30-34 spm; Hay: Geduld auf den ersten 1000 m); Pausenlänge angelehnt an Concept2 3 x 1000 m mit 3 min Pause, hier 5 min wegen 1500 m Belastung
- Quellen: Concept2 - Training for a 500m Rowing Ergometer Test; World Rowing - Indoor rowing part 2 - ergo testing strategy (G. Hay); Concept2 - Fly and Die: Strategies for Pacing; USRowing - The Race (race phases: start, settle, sprint; head races)
- Ungefähre Dauer: 48 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-26 | 2 | - | - | Einrudern 10 min: locker beginnen, steigern, am Ende 3 kurze Antritte |
| work | 500 m | 32-36 | 5 | 2k -3..-1 s/500 m | - | Start und erste 500 m (1/3): Startschläge, dann hoch im Renntempo |
| work | 1000 m | 28-32 | 5 | 2k +1..+3 s/500 m | - | Mittelstück 1000 m (1/3): Schlagzahl senken, Rhythmus halten |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause 5 min: locker weiterrudern (1/2) |
| work | 500 m | 32-36 | 5 | 2k -3..-1 s/500 m | - | Start und erste 500 m (2/3): Startschläge, dann hoch im Renntempo |
| work | 1000 m | 28-32 | 5 | 2k +1..+3 s/500 m | - | Mittelstück 1000 m (2/3): Schlagzahl senken, Rhythmus halten |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause 5 min: locker weiterrudern (2/2) |
| work | 500 m | 32-36 | 5 | 2k -3..-1 s/500 m | - | Start und erste 500 m (3/3): Startschläge, dann hoch im Renntempo |
| work | 1000 m | 28-32 | 5 | 2k +1..+3 s/500 m | - | Mittelstück 1000 m (3/3): Schlagzahl senken, Rhythmus halten |
| cooldown | 10:00 min | 16-20 | 1 | - | - | Ausrudern 10 min: ganz locker |

## Renntempo 2 x 1000 m (`renntempo-2x1000`)

- Erklärung: Zweimal 1000 m im Zieltempo für das 2000-m-Rennen, 5 Minuten lockere Pause.
- Zweck/Bereich: Renntempo festigen, Tempogefühl für den 2000-m-Test (Pulszone 5)
- Kategorie: Wettkampf; Niveau: Fortgeschritten; Tags: hard, vo2max, race-pace, time-efficient
- Belegstatus: angepasst: Concept2 500-m- und 2k-Pläne (3 x 1000 m mit 3 min Pause, Schlagzahl 24-34; Zieltempo aus dem eigenen Durchschnittstempo); auf 2 Stücke mit 5 min Pause gekürzt, Tempo auf 2k-Zieltempo gesetzt
- Quellen: Concept2 - Training for a 500m Rowing Ergometer Test; Concept2 - Training for a 2K Rowing Ergometer Test - 4 Week Plan; Concept2 - How To Find Your 2k Race Pace
- Ungefähre Dauer: 28 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-26 | 2 | - | - | Einrudern 8 min: locker beginnen, steigern, am Ende 3 kurze Antritte |
| work | 1000 m | 28-32 | 5 | 2k -1..+1 s/500 m | - | 1000 m im 2k-Zieltempo (1/2): gleichmässig |
| rest | 5:00 min | 16-20 | 1 | - | aktiv | Pause 5 min: locker weiterrudern (1/1) |
| work | 1000 m | 28-34 | 5 | 2k -1..+1 s/500 m | - | 1000 m im 2k-Zieltempo (2/2): letzte 250 m steigern |
| cooldown | 7:00 min | 16-20 | 1 | - | - | Ausrudern 7 min: ganz locker |

## Tapering-Einheit vor Test oder Rennen (`tapering-vor-test`)

- Erklärung: Kurze, lockere Einheit für die letzten 1-2 Tage vor einem Test: wenig Umfang, aber ein paar Minuten im Renntempo und zwei Startübungen.
- Zweck/Bereich: Frisch werden und Renntempo wachhalten (Umfang runter, Intensität halten; Pulszone 2-4)
- Kategorie: Wettkampf; Niveau: Fortgeschritten; Tags: easy, recovery, race-pace
- Belegstatus: abgeleitet: Bosquet et al. (Tapering wirkt am besten mit ca. 2 Wochen und 41-60 % weniger Umfang bei gleicher Intensität und Häufigkeit) als Prinzip; konkrete Einheit eigene Umsetzung mit Concept2-Einrudern und Startschlägen nach 'Fly and Die'. Die Concept2-Pläne selbst sehen kein Tapering vor
- Quellen: Lippincott Williams & Wilkins / ACSM - Effects of tapering on performance: a meta-analysis (Bosquet, Montpetit, Arvisais, Mujika), Med Sci Sports Exerc 39:1358-1365 (abstract); Concept2 - Training for a 2K Rowing Ergometer Test - 4 Week Plan; Concept2 - Fly and Die: Strategies for Pacing
- Ungefähre Dauer: 36 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 8:00 min | 18-26 | 2 | - | - | Einrudern 8 min: locker beginnen, steigern, am Ende 3 kurze Antritte |
| work | 10:00 min | 18-22 | 2 | 2k +18..+24 s/500 m | - | 10 min ruhig im Grundlagentempo |
| work | 1:00 min | 28-32 | 4 | 2k -1..+1 s/500 m | - | 1 min im Renntempo (1/3) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause 2 min: locker weiterrudern (1/3) |
| work | 1:00 min | 28-32 | 4 | 2k -1..+1 s/500 m | - | 1 min im Renntempo (2/3) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause 2 min: locker weiterrudern (2/3) |
| work | 1:00 min | 28-32 | 4 | 2k -1..+1 s/500 m | - | 1 min im Renntempo (3/3) |
| rest | 2:00 min | 16-20 | 1 | - | aktiv | Pause 2 min: locker weiterrudern (3/3) |
| work | 0:15 min | 34-40 | 4 | 2k -6..-3 s/500 m | - | Startübung 15 s: halbe, halbe, dreiviertel Schlag, dann 5 volle (1/2) |
| rest | 1:45 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern (1/2) |
| work | 0:15 min | 34-40 | 4 | 2k -6..-3 s/500 m | - | Startübung 15 s: halbe, halbe, dreiviertel Schlag, dann 5 volle (2/2) |
| rest | 1:45 min | 16-20 | 1 | - | aktiv | Pause: locker weiterrudern (2/2) |
| cooldown | 5:00 min | 16-20 | 1 | - | - | Ausrudern 5 min: ganz locker |

## Einrudern vor dem Rennen (`einrudern-rennen`)

- Erklärung: Festes Einrudern-Protokoll vor einem Test oder Indoor-Rennen: 10 min steigernd, dann rund 100 harte Schläge in Stücken zu 20 und 10 mit Startübungen; das letzte Stück endet 10 Minuten vor dem Start.
- Zweck/Bereich: Körper und Puls auf Rennbelastung vorbereiten, Startablauf einüben (Pulszone 1-5)
- Kategorie: Wettkampf; Niveau: Einsteiger; Tags: moderate, power, race-pace, beginner-friendly
- Belegstatus: angepasst: Concept2 'A First Class Warm-up' (mindestens 100 harte Schläge in 10ern und 20ern mit lockerem Rudern dazwischen, letztes Stück 10 min vor dem Start, am liebsten 10 lange Schläge im Renntempo); British Rowing (nur Suchauszug: Einrudern am Renntag insgesamt rund 45 min, viel aerober Anteil, Routine vorher üben) und Concept2 2k-Plan (5-10 min steigernd mit Antritten); Schlagdauern bei 28-34 spm in Sekunden umgerechnet; für Indoor auf rund 30 min gekürzt
- Quellen: Concept2 (Australia) - A First Class Warm-up; British Rowing - Race-day warm-up for indoor rowing (British Rowing Plus, J. Brown); page redirected, only search excerpt read, secondary; Concept2 - Training for a 2K Rowing Ergometer Test - 4 Week Plan
- Ungefähre Dauer: 31 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 5:00 min | 18-20 | 1 | - | - | 5 min ganz locker |
| warmup | 5:00 min | 20-24 | 3 | - | - | 5 min steigernd bis zügig |
| work | 0:40 min | 28-30 | 4 | 2k +2..+5 s/500 m | - | 20 kräftige Schläge (1/7) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause: locker paddeln (1/6) |
| work | 0:40 min | 28-30 | 4 | 2k +1..+3 s/500 m | - | 20 kräftige Schläge (2/7) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause: locker paddeln (2/6) |
| work | 0:40 min | 30-32 | 4 | 2k 0..+2 s/500 m | - | 20 Schläge nahe Renntempo (3/7) |
| rest | 1:30 min | 16-20 | 1 | - | aktiv | Pause: locker paddeln (3/6) |
| work | 0:20 min | 30-34 | 5 | 2k -1..+1 s/500 m | - | 10 Schläge im Renntempo (4/7) |
| rest | 1:10 min | 16-20 | 1 | - | aktiv | Pause: locker paddeln (4/6) |
| work | 0:20 min | 34-40 | 5 | 2k -5..-2 s/500 m | - | 10 Schläge Start: halbe, halbe, dreiviertel, dann voll (5/7) |
| rest | 1:10 min | 16-20 | 1 | - | aktiv | Pause: locker paddeln (5/6) |
| work | 0:20 min | 34-40 | 5 | 2k -5..-2 s/500 m | - | 10 Schläge Start wie im Rennen (6/7) |
| rest | 1:10 min | 16-20 | 1 | - | aktiv | Pause: locker paddeln (6/6) |
| work | 0:20 min | 30-34 | 5 | 2k -1..+1 s/500 m | - | 10 Schläge im Renntempo: lang und rhythmisch (7/7) |
| cooldown | 10:00 min | 14-18 | 1 | - | - | 10 min bis zum Start: locker paddeln oder stehen, trinken, Monitor einstellen |

## Head-Race-Simulation 5000 m (`head-race-5000m`)

- Erklärung: 5000 m wie ein Langstreckenrennen: fliegender Start mit hoher Schlagzahl, dann setzen und gleichmässig nahe der Schwelle, letzter Kilometer steigernd, letzte 500 m Endspurt.
- Zweck/Bereich: Langstreckenrennen üben, Leistung an der Schwelle (Pulszone 4-5)
- Kategorie: Wettkampf; Niveau: Leistung; Tags: hard, threshold, race-pace
- Belegstatus: abgeleitet: Rennphasen Start - Setzen - Endspurt und Head-Race-Format (USRowing, ca. 2,5-3 Meilen, Einzelstart), Taktik und Schlagzahl wie 2000 m nur bewusster gewählt (Hay), Concept2 5k-Plan (Renntempo halten, letzten Kilometer steigern, 24-30 spm); Tempo aus Paul's Law (5k = 2k +6-7 s); Abschnitte eigene Umsetzung
- Quellen: USRowing - The Race (race phases: start, settle, sprint; head races); Concept2 - Training for a 5K Rowing Ergometer Test; World Rowing - Indoor rowing part 2 - ergo testing strategy (G. Hay); Concept2 Forum - "Paul's Law" (double the distance, add about 5 s/500 m); forum thread, secondary source
- Ungefähre Dauer: 41 min (Distanzphasen mit 2:00/500 m Referenz geschätzt)

| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |
|---|---|---|---|---|---|---|
| warmup | 10:00 min | 18-26 | 2 | - | - | Einrudern 10 min: locker beginnen, steigern, am Ende 3 kurze Antritte |
| rest | 2:00 min | 18-22 | 2 | - | aktiv | 2 min locker, dann fliegender Start |
| work | 250 m | 30-34 | 4 | 2k +1..+4 s/500 m | - | Start 250 m: hoch und hart, nach rund 30 Schlägen setzen |
| work | 1750 m | 26-30 | 4 | 2k +5..+8 s/500 m | - | 250-2000 m: Grundtempo, lang und ruhig |
| work | 1500 m | 26-30 | 4 | 2k +5..+8 s/500 m | - | 2000-3500 m: Grundtempo halten, alle 500 m 10 Schläge Druck |
| work | 1000 m | 28-32 | 5 | 2k +3..+6 s/500 m | - | 3500-4500 m: steigern, Schlagzahl anheben |
| work | 500 m | 30-36 | 5 | 2k 0..+3 s/500 m | - | Letzte 500 m: Endspurt |
| cooldown | 8:00 min | 16-20 | 1 | - | - | Ausrudern 8 min: ganz locker |

## Quellenliste

- Concept2: Concept2 Online Ranking (RowErg events: 1 min, 4 min, 30 min, 60 min, 100 m to 100 000 m). https://log.concept2.com/rankings (ohne Datum auf der Seite)
- World Rowing: Using the indoor rower for testing: why do we test different distances? (K. Jensen: 60 min ~76 %, 6000 m ~85 %, 60 s ~153 %, 10 s/100 m ~173 % of 2000-m watts). https://worldrowing.com/2019/11/26/using-the-indoor-rower-for-testing-why-test-different-distances/ (2019-11-26)
- Concept2: Training for a 500m Rowing Ergometer Test. https://www.concept2.com/training/plans/500m-erg-test (ohne Datum auf der Seite)
- Concept2 Forum: "Paul's Law" (double the distance, add about 5 s/500 m); forum thread, secondary source. https://c2forum.com/viewtopic.php?p=100995 (2008-05-14)
- Concept2: Training for a 2K Rowing Ergometer Test - 4 Week Plan. https://www.concept2.com/training/plans/2k-erg-test-4-week (ohne Datum auf der Seite)
- Concept2: Training for a 4 Minute Rowing Ergometer Test. https://www.concept2.com/training/plans/4min-erg-test (ohne Datum auf der Seite)
- Concept2: Training for a 5K Rowing Ergometer Test. https://www.concept2.com/training/plans/5k-erg-test (ohne Datum auf der Seite)
- World Rowing: Indoor rowing part 2 - ergo testing strategy (G. Hay). https://worldrowing.com/2020/04/07/indoor-rowing-part-ergo-testing-strategy/ (2020-04-07)
- Concept2: Training for a 2K Rowing Ergometer Test - 12 Week Plan. https://www.concept2.com/training/plans/2k-erg-test-12-week (ohne Datum auf der Seite)
- Wolfson College Boat Club, University of Cambridge: Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary source. https://www.wolfson.cam.ac.uk/sites/default/files/2019-11/wcbc_erging_0.pdf (2019)
- University of Hertfordshire Research Archive: The Effect of Sampling Time on Blood Lactate Concentration in Trained Rowers (Kass & Carpenter), incremental test 5 x 4 min, methods p. 3-4; repository manuscript. https://uhra.herts.ac.uk/id/eprint/790/2/903972.pdf (ohne Datum auf der Seite)
- Frontiers: Differences in Physiological Responses During Rowing and Cycle Ergometry in Elite Male Rowers (Lindenthaler, Rice et al.), Front Physiol 9:1010, doi:10.3389/fphys.2018.01010. https://pmc.ncbi.nlm.nih.gov/articles/PMC6077239 (2018-07-30)
- Concept2: How To Find Your 2k Race Pace. https://www.concept2.com/training/articles/how-to-find-your-2k-pace (ohne Datum auf der Seite)
- BMJ: An analysis of the pacing strategy adopted by elite competitors in 2000 m rowing (Garland), Br J Sports Med 39(1):39-42, doi:10.1136/bjsm.2003.010801. https://pmc.ncbi.nlm.nih.gov/articles/PMC1725010 (2005-01)
- Concept2: Fly and Die: Strategies for Pacing. https://www.concept2.com/blog/fly-and-die-strategies-for-pacing (2018-01-19)
- USRowing: The Race (race phases: start, settle, sprint; head races). https://usrowing.org/learn-about-rowing/overview/the-race (ohne Datum auf der Seite)
- Lippincott Williams & Wilkins / ACSM: Effects of tapering on performance: a meta-analysis (Bosquet, Montpetit, Arvisais, Mujika), Med Sci Sports Exerc 39:1358-1365 (abstract). https://pubmed.ncbi.nlm.nih.gov/17762369/ (2007)
- Concept2 (Australia): A First Class Warm-up. https://www.concept2.com.au/blog/a-first-class-warmup (2011-06-01)
- British Rowing: Race-day warm-up for indoor rowing (British Rowing Plus, J. Brown); page redirected, only search excerpt read, secondary. https://plus.britishrowing.org/?p=7597 (ohne Datum auf der Seite)

## Fundus-Rückschreiben (Projekt `rowcoach`, alle `unverified`)

- observation:22437 – Jensen/World Rowing: Testleistung in % der 2000-m-Watt (60 min ~76 %, 6000 m ~85 %, 60 s ~153 %, 10 s/100 m ~173 %)
- practice:982 – Kass & Carpenter: submaximaler Stufentest 5 x 4 min (Stufe 5 = 2k-Split +10 s, darunter je -25 W)
- practice:979 – Lindenthaler/Rice et al. 2018: Stufentest 7 x 4 min mit 4-min-Maximalstufe
- study:1043 – Garland 2005: Pacing-Profil 2000 m (Wasser 103,3/99,0/98,3/99,7 %, Ergometer 101,5/99,8/99,0/99,7 %)
- practice:980 – Concept2 'A First Class Warm-up': mind. 100 harte Schläge in 10ern/20ern, letztes Stück 10 min vor dem Start
- study:1044 – Bosquet et al. 2007: Tapering ca. 2 Wochen, Umfang -41-60 %, Intensität und Häufigkeit gleich
- practice:981 – Concept2-Testpläne (Einrudern, Schlagzahlbereiche, Rennplan) und RowErg-Ranglistenstücke
- fact:2436 – Paul's Law (Concept2-Forum, Sekundärquelle)
