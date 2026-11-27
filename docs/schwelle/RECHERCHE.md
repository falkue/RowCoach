# Schwellen-Test und Trainingszonen: Recherche (Stand 27.11.2026)

Auftrag (Falk, 27.11.): „Wir brauchen einen Functional Threshold Test, der bestimmt, wie die Trainingszonen sind.
Recherchiere, wie solche Tests aussehen. Ich hatte mal einen All-Out-Test gemacht, aber es gibt wohl auch Tests, die einen
nicht an die maximale Grenze bringen und trotzdem eine gute Abschätzung liefern. Wer seinen Threshold kennt, soll ihn auch
einfach eingeben können, und daraus werden die Zonen berechnet.“

Diese Datei sammelt die fachliche Grundlage. Die Umsetzung steht in `docs/schwelle/SPEC.md`.

## Methode und Belegstärke

- Reihenfolge Zotero → Fundus → Web. **Zotero**: `zrag search` lief in einen Timeout, `zrag semantic` meldete „Another
  Zotero API operation is still in progress“ (einmal versucht, wie vereinbart). Kein Zotero-Beleg.
  **Fundus** (Projekt `rowcoach`): vorhanden waren Jensen/World Rowing (Wattanteile der Standardtests), Kass & Carpenter
  (Stufentest 5 × 4 min), Lindenthaler/Rice (7 × 4 min), Wolfson-Bänder nach Herzfrequenzreserve, Seiler/Tønnessen,
  Edwards-TRIMP und drei Studien zu verbaler Ermutigung in Tests. Zu FTP, Critical Power, DFA-α1, Conconi, Reliabilität und
  App-Verfahren war nichts da. **Web**: Abstracts über PubMed (E-Utilities) gelesen, Herstellerseiten direkt.
- Jede Zahl aus Studien ist mindestens am Abstract geprüft (PubMed-ID angegeben). Herstellerangaben sind als solche
  gekennzeichnet; sie sind keine unabhängigen Belege.
- Belegstärke in dieser Datei: **stark** (mehrere Studien oder Übersichtsarbeit, gleiche Richtung), **mittel** (eine
  Studie, kleines n, oder Übertragung aus dem Radsport), **schwach** (Praxis, Hersteller, Forum), **abgeleitet** (eigene
  Rechnung aus belegten Zahlen; Rechenweg steht dabei).
- In Fundus zurückgeschrieben (Projekt `rowcoach`, alle unverifiziert): Studien 1068 (Cheng 2012), 1069 (Quittmann &
  Piehl 2026), 1070 (Rogers 2021, DFA-α1), 1071 (Bourgois & Vrijens 1998, Conconi), 1072 (Schabort 1999), 1073 (Bourdin
  2004), 1074 (Borszcz 2019 / Lillo-Beviá 2022, FTP vs MLSS), 1075 (Ingham 2002); Fakt 2447 (Tanaka 2001); Praxis 997
  (Friel/Coggan-Zonen, TrainingPeaks), 998 (Rampentest TrainerRoad/Zwift).

## Kurzfassung

1. Es gibt keinen „richtigen“ Schwellenwert, sondern mehrere Grenzen mit verschiedener Physiologie: erste Schwelle
   (LT1/VT1, Ende „locker“), zweite Schwelle (LT2/VT2, MLSS, Critical Power, FTP als Praxisgrösse). Für Trainingszonen
   reicht eine gute Schätzung der zweiten Schwelle als Leistung (Watt) plus eine Pulsreferenz.
2. Am verlässlichsten auf dem Ergometer sind **maximale Zeitfahren** (2000 m, 20 min, 30 min): sehr reproduzierbar
   (2000 m: Variationskoeffizient 2,0 % der Leistung, Schabort 1999), aber die Umrechnung auf die Schwelle ist eine
   Faustregel (± 5 %).
3. **Submaximal** geht es mit einem Stufentest und Puls (Leistung bei Schwellenpuls) und optional DFA-α1 aus den
   RR-Intervallen. Genauigkeit eher ± 10–15 %, DFA-α1 ist am Rudern nicht validiert. Für Einsteiger, Masters und
   Menschen mit gesundheitlichen Einschränkungen trotzdem die richtige Wahl, weil die Zonen nur Orientierung brauchen.
4. **Conconi** ist für das Rudern widerlegt (Bourgois & Vrijens 1998) und kommt nicht in die App. Altersformeln für den
   Maximalpuls (Tanaka) taugen nur als Startwert.
5. Empfehlung: Schwelle intern als **Leistung in Watt** führen (Tempo folgt über Watt = 2,8 / (Tempo/500)³), Zonen in
   Prozent der Schwelle (fünf Zonen passend zu den Ruderbändern UT2/UT1/AT/TR/AN), Pulszonen aus LTHR, sonst wie heute
   nach Herzfrequenzreserve. Die 2000-m-Bestzeit bleibt als eine Quelle unter mehreren und wird für alte Programme aus der
   Schwelle zurückgerechnet.

## 1. Schwellenbegriffe und wie man sie misst

### 1.1 Laktatschwellen, MLSS, ventilatorische Schwellen

- **LT1/VT1** (aerobe Schwelle): erster Anstieg des Laktats über Ruhe bzw. erster Knick der Atmung. Obergrenze der
  lockeren Grundlage (UT2). Messung im Labor (Laktat, Spiroergometrie).
- **LT2/VT2, MLSS** (anaerobe Schwelle): höchste Belastung, bei der Laktat über 30 min stabil bleibt (MLSS: Anstieg
  < 1 mmol/l in den letzten 20 min eines 30-min-Dauertests). Die fixe 4-mmol/l-Schwelle („OBLA“) ist eine Näherung.
- **Rudern**: Bei Ruderern trafen die 4-mmol-Schwelle und die individuelle anaerobe Schwelle die MLSS-Leistung nicht
  (Beneke 1995, Med Sci Sports Exerc 27:863–867; nur Abstract über Sekundärquelle; n = 9), während Stegmann & Kindermann
  bei 19 Ruderern fanden, dass die individuelle anaerobe Schwelle 50 min ohne Laktatanstieg gehalten werden konnte, die
  4-mmol-Schwelle bei 15 von 19 dagegen nach 14,4 ± 6,3 min zur Erschöpfung führte (Int J Sports Med 1982;3:105–110,
  doi:10.1055/s-2008-1026072, PubMed 7107102). **Belegstärke mittel**: Laktat-Fixwerte sind beim Rudern unsicher; die
  Schwelle hängt am Protokoll.
- Leistung bei 4 mmol/l, Leistung bei VO2max und Maximalleistung erklären zusammen 98 % der Varianz der 2000-m-Leistung
  bei WM-Finalisten (Ingham et al. 2002, Eur J Appl Physiol 88:243–246, doi:10.1007/s00421-002-0699-9, PubMed 12458367;
  Fundus 1075). Die Schwelle ist also eng mit der 2k-Leistung verknüpft, aber nicht dasselbe.

### 1.2 Critical Power (CP) und W′

- Modell nach Monod & Scherrer: Arbeit W = CP · t + W′ (lineares Arbeit-Zeit-Modell) bzw. P = CP + W′/t. CP ist die
  Asymptote der Leistungs-Dauer-Kurve, die Grenze zwischen schwerer und sehr schwerer Belastung; W′ der endliche
  Arbeitsvorrat darüber. Bestimmung aus 2–5 erschöpfenden Belastungen zwischen etwa 2 und 15–20 min.
- Jones et al. (2019, Physiol Rep 7:e14098, „The maximal metabolic steady state: redefining the ‚gold standard‘“)
  argumentieren, dass MLSS den höchsten metabolischen Steady State unterschätzt und CP die bessere Grenze ist. CP liegt
  damit typischerweise etwas über MLSS/FTP (**mittel**, Übersichts- und Positionsartikel).
- **3-min-All-out-Test** (Vanhatalo, Doust & Burnley 2007, Med Sci Sports Exerc 39:548–555): Die Leistung fällt
  innerhalb von etwa 135 s auf ein Plateau; die Endleistung (Mittel der letzten 30 s, „EP“) unterschied sich nicht von
  der separat bestimmten CP (Radsport, n = 10; Abstract über Repositorium).
- **Rudern**: Cheng et al. (2012, Eur J Appl Physiol 112:1251–1260, doi:10.1007/s00421-011-2081-2, PubMed 21769731;
  Fundus 1068): 18 trainierte Ruderer, EP 269 ± 39 W gegen CP 272 ± 30 W (Arbeit-Zeit) bzw. 276 ± 32 W, kein
  signifikanter Unterschied; die Arbeit über EP entsprach aber nicht W′ (zu hoch). Reproduzierbarkeit „moderat“.
  Korrektur 2026 zu Tabelle 1.
- **Neue Metaanalyse** (Quittmann & Piehl 2026, Eur J Appl Physiol 126:4673–4691, doi:10.1007/s00421-026-06356-w,
  PubMed 42479066; Fundus 1069): 20 Radsport-Studien, N = 284. EP ist gut reproduzierbar (ICC 0,89–0,99), überschätzt
  CP aber systematisch (g = 0,41); W′ lässt sich nicht verlässlich schätzen. Gewöhnungsversuch und verbale Ermutigung
  sind Pflicht. **Belegstärke für „EP ≈ CP“: mittel; Tendenz zur Überschätzung beachten.**
- CP und 2000 m: In japanischen Studien korrelierte CP eng mit der 2000-m-Leistung (Shimoda & Kawakami 2005, Int J Sport
  Health Sci 3:21–26: r = 0,87, n = 9; Shirai et al. 2015, BMC Sports Sci Med Rehabil 7(Suppl 1):P1, Kongressabstract:
  CP 302,7 ± 35,2 W, P2000 326,9 ± 29,3 W, r = 0,86). **Abgeleitet** aus den Mittelwerten: CP ≈ 93 % der 2k-Leistung bei
  trainierten Studenten-Ruderern (nur Gruppenmittel, kleine Stichprobe).

### 1.3 FTP (Functional Threshold Power, Allen & Coggan)

- Definition: höchste Leistung, die man etwa eine Stunde halten kann; im Feld meist **95 % der mittleren Leistung eines
  20-min-Zeitfahrens**. Entwickelt im Radsport.
- Validität gegen MLSS (Radsport): Borszcz et al. 2019 (Int J Sports Physiol Perform 14:1029–1035,
  doi:10.1123/ijspp.2018-0572, PubMed 30676826): 15 Radfahrer, Bias 1,4 % ± 9,2 % (95-%-Grenzen), typischer Fehler 4,7 %
  (6,4 % bei „trainiert“, 3,0 % bei „gut trainiert“), r = 0,91. Lillo-Beviá et al. 2022 (J Strength Cond Res 36:167–173,
  doi:10.1519/JSC.0000000000003403, PubMed 31714462): 11 Radfahrer, 95 % von TT20 überschätzte MLSS um 12 ± 7 W;
  individueller Faktor im Mittel 91 %; TT20 sehr reproduzierbar (SEM ± 3 W). (Fundus 1074.)
  **Belegstärke mittel: auf Gruppenebene brauchbar, einzeln ± 5–10 %; für das Rudern nicht validiert.**
- Der Begriff „FTP“ wird in Ruder-Apps übernommen (EXR: 20-min- oder Rampentest, FTP als Leistung für ca. 60 min;
  Herstellerangabe).

### 1.4 Schwellenpuls (LTHR, Friel)

- Friel: 30 min allein so hart wie ein Rennen, Runde bei Minute 10; **LTHR = Durchschnittspuls der letzten 20 min**.
  Pulszonen Radsport in % LTHR: Z1 < 81, Z2 81–89, Z3 90–93, Z4 94–99, Z5a 100–102, Z5b 103–106, Z5c > 106 (Laufen:
  Z1 < 85, Z2 85–89, Z3 90–94, Z4 95–99, …). Leistungszonen nach Allen & Coggan in % FTP: Z1 < 55, Z2 55–74, Z3 75–89,
  Z4 90–104, Z5 105–120, Z6 > 120. FTP-Retest alle 4–6 Wochen. Quelle: TrainingPeaks, „Joe Friel's Quick Guide to Setting
  Zones“ (Fundus Praxis 997). **Schwach bis mittel** (Praxisstandard, keine Validierungsstudie zitiert).
- Friel warnt ausdrücklich vor „220 minus Alter“.

### 1.5 Ruderspezifisch: Bänder, Concept2, 30 min r20, 2k → Schwelle

- **Bänder** UT2/UT1/AT/TR/AN stammen aus dem Ruderverbandssystem (GB Rowing Team verwendet ein Siebenzonenmodell UT3,
  UT2, UT1, AT, TR, AC, AP; British Rowing Plus, D. Moore 2023, nur Suchauszug, Seite gesperrt). Die offizielle
  GB-Rowing-„Training Matrix“ (PDF auf plus.britishrowing.org) war nicht abrufbar (Weiterleitung). Lesbar war nur, dass sie
  Bänder nach % Herzfrequenzreserve, Laktat, RPE, Schlagzahl und % der 2-km-Zeit führt (UT3: < 59 % HFR, < 1 mmol/l,
  Schlagzahl < 18; Suchauszug).
- **Wolfson College Boat Club** (Fundus 2420): UT2 bis 70 % der Herzfrequenzreserve, UT1 70–80, AT 80–85, TR 85–95, AN
  95–100. **Indoor Sports Services** („Interactive 2000m Programme“, nicht mehr online; rekonstruiert im Quelltext von
  guyru.github.io/calculators): UT2 65–70 % HFR und **45–60 % der 2k-Watt**, UT1 70–80 % HFR / 60–70 %, AT 80–85 % /
  70–80 %, TR 85–95 % / 80–105 %, AN 95–100 % / 105–115 %. Ein Concept2-Forumsbeitrag nennt „bis 60/70/80 % der 2k-Watt“
  für UT2/UT1/AT. **Schwach** (Sekundär-/Forenquellen), aber in sich stimmig.
- **GB Rowing / SAS-Programm** (Olympia-Wochenpläne, PDF): UT1 = 75–80 % HFmax, UT2 = 65–75 % HFmax („Unterhaltung
  möglich“); im Wochenplan steht „30 mins ergo (R20 flat out)“ als Einheit. Damit ist **30 min r20** als harter Standard
  der Ruderwelt belegt, nicht aber als validierter Schwellentest. Schlagzahlbegrenzung (r20) senkt die Leistung; als
  Schwellentest besser freie Schlagzahl oder r20 nur als Wiederholungsvergleich.
- **Concept2**: Pulszonen in % HFmax (Z1 50–60, Z2 60–70, Z3 70–80, Z4 80–90 „anaerobic threshold“, Z5 90–100),
  HFmax-Start mit 220 − Alter, danach höchsten gemessenen Wert nehmen; harte Zonen nur nach ärztlicher Freigabe
  (Concept2-Blog „Heart Rate Training with Your Concept2 Erg“, 17.04.2025). ErgData kennt Pulszonen (HFmax im Profil,
  eigene Zonen); Leistungszonen oder einen Schwellentest bietet Concept2 nicht an (App-Store-Text; keine Concept2-Doku
  gefunden). Watt-Tempo: **Watt = 2,80 / (Tempo/500)³**, Tempo in s/500 m (Concept2 Pace Calculator, „Formulas Used“).
- **Jensen/World Rowing** (Fundus 22437): mittlere Leistung in % der 2000-m-Leistung bei Weltmeistern: 60 min ~76 %,
  6000 m ~85 %, 60 s ~153 %, 10 s ~173 %.
- **Paul's Law** (Concept2-Forum, Praxisregel): je Verdopplung der Strecke +5 s/500 m, individuell 3–7 s. In der App
  bereits für Tests → Referenz im Einsatz (`TrainingProgramEngine.estimateBest2k`).
- **2k → Schwelle (abgeleitet)**: Schwellenleistung ≈ was man ~30 min halten kann. Aus Jensen (Weltmeister): zwischen
  6000 m (~19 min, 85 %) und 60 min (76 %) logarithmisch interpoliert ergibt 30 min ≈ 81 % der 2k-Watt. Aus Paul's Law
  (k = 5) für einen 2:00-Ruderer: 30 min ≈ 80,5 % (k = 3: 87 %, k = 7: 75 %). Aus den ISS-Bändern: AT 70–80 % der 2k-Watt.
  **Ergebnis: Schwelle ≈ 0,80 × 2k-Watt (Spanne 0,75–0,87)**, entsprechend etwa 2k-Tempo + 8–10 s/500 m bei 2:00.
  Das passt zu den bestehenden Programmen (`test-30min`: 2k +8..+11 s).
- **Potenzgesetz statt Sekundenregel (abgeleitet)**: P(t) = P_ref · (t/t_ref)^(−b). Aus Jensens Verhältnissen ergibt sich
  b ≈ 0,12–0,14 (6000 m: 0,139; 60 min: 0,117), aus Paul's Law bei 2:00 b ≈ 0,16. Gewählt: **b = 0,15** (zwischen beiden,
  eher vorsichtig, d. h. eher niedrigere Schwelle). Es beschreibt alle Dauern zwischen ~3 und 60 min mit einer Formel
  und passt zur FTP-Regel: P(30 min)/P(20 min) = 1,5^(−0,15) = 0,941, also 0,95 × P20 ≈ P30. Für die 2k ergibt es
  Schwelle/P2k = (t2k/1800 s)^0,15: 6:40 → 0,80; 7:30 → 0,81; 8:00 → 0,82; 10:00 → 0,84. Paul's Law in Sekunden wirkt je nach Grundtempo unterschiedlich stark (schnelle Ruderer werden
  in Watt stärker bestraft); das Potenzgesetz in Watt ist neutral.
- **Stufentests in der Ruderdiagnostik**: Kass & Carpenter (Fundus 982): 5 × 4 min, 1 min Pause, Stufe 5 = 2k-Split
  +10 s, darunter je −25 W. Lindenthaler/Rice 2018 (Fundus 979, AIS): 7 × 4 min, Stufe 7 = 4-min-Zeitfahren.
  Bourgois & Vrijens (1998): Laktatstufentest 150 W + 50 W je 3 min; Beneke (1995): Start 215 W, +35 W je 3 min. Ein
  aktuelles Protokoll des Deutschen Ruderverbands habe ich nicht gefunden (Steinacker 1984 „A rowing ergometer test with
  stepwise increased work loads“ nur als Literaturangabe; auf rudern.de ein Concept2-Testmanual für 2000 m mit
  mindestens 10 min Einrudern bei 60–65 %).
- **Reliabilität**: 2000 m auf dem Concept2: CV 2,0 % der mittleren Leistung (95-%-KI 1,3–3,1 %), etwa ein Drittel davon
  in der Zeit; Retest r = 0,96; vom 1. zum 2. Versuch +2,3 % Leistung (Lerneffekt) (Schabort et al. 1999, J Sports Sci
  17:627–632, doi:10.1080/026404199365650, PubMed 10487463; Fundus 1072). Übersicht Smith & Hopkins 2012 (Sports Med
  42:343–358, doi:10.2165/11597230-000000000-00000): typischer Fehler ~0,5 % der 2000-m-Zeit bei gut Trainierten;
  Spitzenleistung im Stufentest, einige Laktatschwellenmasse und 30-s-All-out sind ebenfalls genau genug, um
  Veränderungen zu verfolgen (nur Abstract). **Stark** für trainierte Ruderer; für Einsteiger ist mit grösserem
  Lerneffekt zu rechnen.
- **Spitzenleistung im Stufentest** sagt die 2000-m-Leistung gut voraus (r = 0,92; Bourdin et al. 2004, Int J Sports Med
  25:368–373, doi:10.1055/s-2004-815844, PubMed 15241717; Fundus 1073). Grundlage dafür, dass ein Rampentest auch beim
  Rudern eine brauchbare Leistungsgrösse liefert; der Umrechnungsfaktor auf die Schwelle ist aber nicht ruderspezifisch
  belegt.

## 2. Testformen nach Belastung

### 2.1 All-out (maximal)

| Test | Auswertung | Belege fürs Rudern | Vorteile | Nachteile |
|---|---|---|---|---|
| 2000 m | Schwelle ≈ 0,80 × P2k (abgeleitet, Spanne 0,75–0,87) | sehr reproduzierbar (CV 2 % Leistung); Standard im Rudern | jeder Ruderer kennt ihn, Ranglisten | sehr hart, Taktik/Einteilung, Umrechnung ± 6 % |
| 20 min | Schwelle = 0,95 × P20 (Coggan) | im Radsport validiert (Bias +1 bis +12 W gegen MLSS), Rudern nicht | etablierter FTP-Test, Apps (EXR, Zwift) | Einteilung schwierig, 20 min hart |
| 30 min (frei oder r20) | Schwelle = P30; LTHR = Puls letzte 20 min (Friel) | 30 min r20 ist Standard-Einheit (GB Rowing); Ranglistenstück | trifft die Schwelle direkt, liefert auch LTHR | lang, r20 drückt die Leistung |
| 60 min | Schwelle = 1,10 × P60 (Potenzgesetz) | Jensen: Standardtest | trifft die FTP-Definition | sehr lang, mental hart |
| 3-min-All-out | CP ≈ Mittel letzte 30 s (EP) | Cheng 2012: EP ≈ CP (n = 18), Reproduzierbarkeit moderat | kurz | brutal, verlangt echtes All-out ohne Einteilung, EP eher zu hoch (Metaanalyse 2026), W′ unbrauchbar |
| Rampentest | Schwelle = 0,75 × beste Minute (TrainerRoad/Zwift) | Spitzenleistung sagt 2k voraus (r = 0,92); Faktor 0,75 nur Radsport-Praxis | kurz (8–15 min), weniger Einteilungsfehler, „weniger schlimm“ | hängt von der Rampensteilheit ab; Faktor fürs Rudern unbelegt |

### 2.2 Submaximal

| Verfahren | Wie | Belege | Genauigkeit (Schätzung) | Für wen |
|---|---|---|---|---|
| Stufentest mit Puls (Puls-Leistungs-Gerade) | 5–7 Stufen à 4 min, Puls am Stufenende, lineare Regression, Leistung beim Schwellenpuls | Puls steigt im submaximalen Bereich annähernd linear mit der Leistung (Lehrbuchwissen); Schwellenpuls muss bekannt sein (LTHR oder Anteil HFR) | ± 10–15 % (abgeleitet: typische Steigung ~0,4 Schläge/W, z. B. 110 → 170 bpm von 100 → 250 W; ± 5 Schläge Fehler beim Schwellenpuls ≈ ± 12 W ≈ ± 7–8 % bei 160 W, dazu Tagesform und Pulsdrift) | Einsteiger, Masters, Einschränkungen; Pulsgurt nötig |
| DFA-α1 aus RR-Intervallen | α1 fällt mit der Intensität; α1 = 0,75 ≈ VT1, α1 = 0,5 ≈ VT2 | Rogers et al. 2021a (Front Physiol 11:596567, doi:10.3389/fphys.2020.596567, PubMed 33519504): VT1 152 bpm vs HRVT 154 bpm, ICC 0,96 (HR); Rogers et al. 2021b (J Funct Morphol Kinesiol 6:38, doi:10.3390/jfmk6020038, PubMed 33925974): VT2 174 vs 171 bpm, r = 0,78; jeweils n = 15, Laufband. Weitere Validierungen Radsport (Frauen, Untrainierte), Herzinsuffizienz. **Keine Ruderstudie gefunden.** | Gruppenmittel gut; einzeln streuend; Rudern unbekannt | als Zusatz zum Stufentest, „experimentell“ |
| Artefakte | fehlende Schläge verzerren α1 | Rogers et al. 2021c (Sensors 21:821, doi:10.3390/s21030821, PubMed 33530473): 1–3 % fehlende Schläge kleiner Bias, HRVT trotzdem innerhalb 1 bpm bis 6 %; Polar H7 gegen EKG −4 bpm | | Polar H9/H10 tauglich, Artefakte zählen und anzeigen |
| Conconi | Knick der Puls-Leistungs-Kurve | **widerlegt fürs Rudern**: kein Zusammenhang mit AT4/IAT (rs = 0,27 bzw. −0,09); bei Conconi-Leistung hielten nur 4 von 10 jungen Ruderern 30 min durch, einer im Laktat-Steady-State (Bourgois & Vrijens 1998, Int J Sports Med 19:553–559, doi:10.1055/s-2007-971959, PubMed 9877147; Fundus 1071). Eine Feldstudie mit abgewandeltem Protokoll auf dem Wasser fand Übereinstimmung mit VT2 (PMC3761509), widerlegt den Laborbefund aber nicht. | Leistung überschätzt | nicht verwenden |
| Talk-Test | „Kann ich noch bequem in ganzen Sätzen sprechen?“ je Stufe | Systematische Übersicht (Herz-Kreislauf-Patienten, Rev Cardiovasc Med 2022, doi:10.31083/j.rcm2307225): letzte positive Stufe korreliert mit VT1; bei gut trainierten Radfahrern (PubMed 23007491) und gesunden Personen (PubMed 21774751) ähnlich, teils näher an der Laktatschwelle | grob (Zone-1/2-Grenze) | alle, besonders Einsteiger; kostet nichts |
| RPE (Borg) | Schwelle ≈ „hart, aber kontrolliert“ | Talk-Test- und RPE-Werte hängen an Gewöhnung; keine präzise Schwelle | grob | Ergänzung, Plausibilitätsprüfung |
| Pulsdrift / aerobe Entkopplung | Effizienz (Leistung/Puls) 1. gegen 2. Hälfte einer gleichmässigen Einheit; < 5 % = Grundlage trägt | TrainingPeaks/Friel (Praxis): < 5 % gut, 5–10 % begrenzend, > 10 % wohl über der aeroben Schwelle; unter 20 min wenig aussagekräftig | kein Schwellenwert, sondern Zustand der Grundlage | Hinweis in der Auswertung langer Fahrten |
| Schätzung aus Fahrten (Leistungs-Dauer-Kurve) | beste 8–60-min-Leistung aus maximalen Fahrten, CP-Fit aus 2–3 Efforts | Herstellerverfahren (Zwift 8–60 min, intervals.icu eFTP ab ≥ 180 s, Morton-3P mit 5 s, 3–5 min, 10–30 min) | ± 5–10 %, wenn wirklich maximal | alle mit Wattdaten (PM5 liefert immer Watt) |
| Altersformel HFmax | Tanaka: 208 − 0,7 × Alter | Metaanalyse 351 Studien, 18 712 Personen, Kreuzvalidierung n = 514 (J Am Coll Cardiol 37:153–156, doi:10.1016/s0735-1097(00)01054-8, PubMed 11153730; Fundus 2447); Standardfehler ~10 bpm (Sekundärquellen) | ± 10 bpm ≈ eine Pulszone | nur Startwert |

Verbale Ermutigung: Bei maximalen Tests steigert Zuspruch alle 20–60 s die Leistung und die Ausbelastung (Fundus 1048,
1049, 1050). Für den Sprachcoach heisst das: in All-out-Tests anfeuern, im submaximalen Stufentest dagegen ruhig
halten, damit niemand über die Vorgabe geht.

### 2.3 Vergleichstabelle der Tests

| Test | Belastung | Dauer inkl. Ein-/Ausrudern | Genauigkeit für die Schwelle | Ausrüstung | Eignung |
|---|---|---|---|---|---|
| Stufentest submaximal + Puls | moderat bis „ziemlich hart“ (bis knapp unter Schwelle) | ~40 min | ± 10–15 % (mittel–schwach) | Pulsgurt Pflicht | Einsteiger, Masters, Einschränkungen, Wiedereinstieg |
| … plus DFA-α1 | dito | dito | experimentell (Rudern nicht validiert) | Brustgurt mit RR (Polar H9/H10) | Zusatz |
| Einsteiger-Test 10 min | hart, aber selbst eingeteilt | ~20 min | ± 8 % (abgeleitet) | keine | Einsteiger ohne 2k |
| Rampentest | maximal am Ende, kurz | ~25 min | ± 8 % (Faktor unbelegt fürs Rudern) | keine | Fortgeschrittene, wer kurze Tests mag |
| 20 min | maximal, lang | ~45 min | ± 5 % (Radsport) | keine (Puls optional) | Fortgeschrittene |
| 30 min | maximal, lang | ~50 min | ± 3–4 % | Puls optional (für LTHR) | Fortgeschrittene, Leistung |
| 2000 m | maximal, sehr hart | ~30 min | ± 6 % (Umrechnung), Messung selbst sehr genau | keine | Fortgeschrittene, Leistung, wer ohnehin 2k testet |
| 3-min-All-out | maximal, brutal | ~25 min | ± 8 %, eher zu hoch | keine | Leistung, mit Erfahrung im All-out |
| Fahrten-Schätzung | keine zusätzliche | – | ± 5–10 %, nur mit maximalen Fahrten | Watt (immer), Puls hilfreich | alle, laufend |
| Eingabe | – | – | so gut wie die Quelle | – | wer seine Werte kennt |

## 3. Zonenmodelle

### 3.1 Leistungszonen

- Coggan (7 Zonen, % FTP): < 55, 55–74, 75–89, 90–104, 105–120, 121–150, > 150 (TrainingPeaks; Zone 7 neuromuskulär).
- Ruderbänder in % der 2k-Watt (ISS, schwach belegt): UT2 45–60, UT1 60–70, AT 70–80, TR 80–105, AN 105–115.
- **Abgeleitet**: Mit Schwelle = 0,80 × 2k-Watt werden die ISS-Bänder zu UT2 56–75 %, UT1 75–88 %, AT 88–100 %,
  TR 100–131 %, AN > 131 % der Schwelle. Das deckt sich fast genau mit Coggan (55/75/90/105/120). Ein Fünfzonenmodell
  „Rudern“ in % der Schwelle ist daher gut begründet:

| Zone | Band | % Schwelle (Watt) | Tempo (Schwelle 2:09,3/500 m = 162 W) | Puls (% LTHR) | Puls (% HFR, heute) |
|---|---|---|---|---|---|
| 1 Regeneration | UT3 | < 55 | langsamer als 2:37,8 | < 81 | 50–60 |
| 2 Grundlage | UT2 | 55–75 | 2:37,8–2:22,3 | 81–89 | 60–70 |
| 3 Grundlage intensiv | UT1 | 75–88 | 2:22,3–2:14,9 | 90–93 | 70–80 |
| 4 Schwelle | AT | 88–102 | 2:14,9–2:08,4 | 94–99 | 80–90 |
| 5 Über Schwelle | TR/AN | > 102 | schneller als 2:08,4 | ≥ 100 | ≥ 90 |

  Tempo aus Watt: Tempo = 500 · (2,8 / W)^(1/3); für x % der Schwelle: Tempo = Tempo_Schwelle · x^(−1/3)
  (55 % → × 1,220; 75 % → × 1,101; 88 % → × 1,043; 102 % → × 0,993).
- Die Pulsgrenzen in % LTHR sind Friels Radsporttabelle (Rudern ist wie Radfahren eine Ganzkörper-/Sitzbelastung; das
  ist eine **Annahme**). Die HFR-Spalte ist das, was die App heute rechnet (`HeartRateZones`, Karvonen 50/60/70/80/90 %).

### 3.2 Pulszonen: drei Verfahren

- **% LTHR** (Friel): am genauesten, wenn LTHR aus einem 30-min-Test stammt.
- **% Herzfrequenzreserve (Karvonen)**: Ruderbänder sind traditionell so definiert (Wolfson, ISS, GB-Matrix). Die App
  rechnet heute so.
- **% HFmax** (Concept2, GB-SAS-Plan): einfach, aber ungenauer. Die Programme in `plans.json` wurden nach dem
  Concept2-%-HFmax-Modell beschrieben, die App wertet nach Karvonen aus: Bei HFmax 185 / Ruhe 55 beginnt Zone 2 nach
  Karvonen bei 133 bpm (72 % HFmax), nach Concept2 bei 120 bpm (65 %). Das ist eine bestehende Unschärfe, keine neue.

### 3.3 Abbildung auf die App

- Heute: `paceOffsetMinS/MaxS` relativ zum 2k-Tempo (Referenzsplit beim Schreiben der Programme: 2:00/500 m),
  `hrZone` 1–5. Eine feste Sekundenzahl bedeutet je nach Grundtempo eine andere Intensität (+10 s sind für einen
  1:40-Ruderer 75 % der 2k-Watt, für einen 2:30-Ruderer 82 %).
- Künftig: Schwelle in Watt ist die Referenz. Für alte Programme wird aus der Schwelle eine **gleichwertige 2k-Zeit**
  zurückgerechnet (Potenzgesetz); stammt die Schwelle aus einem 2k-Test, kommt exakt die alte Zeit heraus, alle Ziele
  bleiben gleich. Optional können Programme neue Felder in % der Schwelle tragen (SPEC, Abschnitt 7).

### 3.4 Mehrere Quellen und Unsicherheit

- Jede Schätzung hat eine typische Unsicherheit (Tabelle 2.3). Sinnvoll ist: die Quelle mit der kleinsten aktuellen
  Unsicherheit nehmen, Unsicherheit mit dem Alter wachsen lassen, eingegebene Werte nie still überschreiben (gleiches
  Prinzip wie heute beim 2k: schneller sofort übernehmen, langsamer nur nach Rückfrage; docs/trainingsplaene/RECHERCHE.md).
- Retest: Friel/TrainingPeaks alle 4–6 Wochen; TrainerRoad schlägt eine neue FTP höchstens alle 28 Tage vor; die App
  schlägt heute den 2k-Test nach 8 Wochen vor (`DailySuggestion` Regel 4). Zusätzlich: wenn Fahrten deutlich darüber
  liegen (automatisch erkannt) oder nach längerer Pause.

## 4. Wie es Apps und Geräte machen (was ist belegt?)

| Anbieter | Verfahren | Beleg |
|---|---|---|
| Zwift | Rampentest +20 W/min (Lite +10 W/min), FTP = 75 % der besten Minute; automatische FTP-Erkennung aus Efforts von 8–60 min (seit Dez. 2024; früher 95 % der besten 20 min) | Hersteller/Zwift Insider; keine Validierung |
| TrainerRoad | Rampentest (5 min Einfahren, dann jede Minute schwerer bis zum Abbruch), FTP = 75 % der besten Minute; „AI FTP Detection“ aus allen Fahrten mit Leistung, Vorschlag höchstens alle 28 Tage, Datensatz 150 Mio. Fahrten | nur Herstellerzahlen („38 % seltener überschätzt als 20-min-Test“) |
| Garmin | geführter LT-Test mit Brustgurt (Laufen, braucht VO2max-Schätzung), automatische LT-Erkennung bei Läufen mit Brustgurt; geführter FTP-Test Rad (~30 min, Brustgurt + Powermeter) | Handbücher; Firstbeat-Algorithmus nicht offen |
| Polar | Fitness-Test in Ruhe (Ruhepuls, HRV, Alter, Geschlecht, Grösse, Gewicht, Selbsteinschätzung) → OwnIndex ~ VO2max; für gesunde Erwachsene 20–65 Jahre; Arrhythmien stören | White Paper; Fehlerangabe für den Fitness-Test nicht gefunden (Walking-Test: SEE 3,3–5,1 ml/kg/min). OwnZone: nichts Aktuelles gefunden |
| Concept2 ErgData | Pulszonen aus HFmax (eigene Zonen möglich), Zeit je Zone; kein Schwellentest, keine Leistungszonen | Concept2-Blog, App-Store |
| ErgZone (Drittanbieter) | Tempo je Intervall aus Benchmarks (1k, 2k, 5k) | App-Store |
| EXR | 20-min- oder Rampentest, FTP auch manuell; Farben relativ zur FTP; Pulszonen getrennt | Hersteller-Support |
| Hydrow, Aviron | nichts Belastbares gefunden | – |
| intervals.icu | eFTP: eine maximale Leistung ≥ 180 s (einstellbar) wird auf eine Kurvenfamilie (Morton-3P, angepasst an reale Kurven, nur bis 20 min) gelegt; optional Morton-3P mit drei Efforts (5 s, 3–5 min, 10–30 min); auch Monod-Scherrer-CP | Entwickler im Forum; keine Validierung |
| WKO (mFTP), Strava | modellierte FTP aus der Leistungs-Dauer-Kurve; Strava nur Leistungskurve | keine unabhängigen Belege gefunden |

Fazit: Die verbreiteten App-Verfahren (Rampe × 0,75, 20 min × 0,95, Erkennung aus 8–60-min-Efforts, Leistungs-Dauer-Kurve)
sind Praxisregeln aus dem Radsport. Sie funktionieren auf Gruppenebene, unabhängige Validierungen gibt es kaum; fürs
Rudern keine. RowCoach sollte deshalb die Unsicherheit ehrlich anzeigen und sich selbst kalibrieren (persönlicher
Faktor, sobald zwei Testarten vorliegen).

## 5. Empfehlung für RowCoach

1. **Testprogramme** (neu): submaximaler Stufentest mit Puls (+ optional DFA-α1, Talk-Test-Abfrage), 20-min-Test,
   Rampentest, 3-min-All-out. Vorhandene Tests (2000 m, 30 min, 60 min, 5000/6000 m, Einsteiger 10 min, Stufentests
   5 × 4 / 7 × 4) werten ebenfalls auf die Schwelle aus. Empfohlene Standardwege: Einsteiger/Masters → Stufentest
   submaximal; Fortgeschrittene → 20 min oder 30 min; wer 2k trainiert → 2000 m; wer es kurz mag → Rampe.
2. **Zonenmodell**: fünf Leistungszonen in % der Schwelle (Tabelle 3.1), Tempozonen daraus über Watt ~ 1/Tempo³,
   Pulszonen aus LTHR (sonst Karvonen wie heute).
3. **Eingabe**: Schwelle in Watt oder Tempo, 2k-Bestzeit, LTHR, HFmax, Ruhepuls.
4. **Schätzung aus Fahrten** über Potenzgesetz (b = 0,15, persönlich anpassbar) und CP-Fit; Vorschlag statt stiller
   Änderung.
5. **Migration**: Programme bleiben gültig; ihr 2k-Bezug kommt aus der Schwelle.

## 6. Nicht abrufbar / Unsicherheiten

- Zotero nicht erreichbar (Timeout, blockierte Operation).
- British Rowing (Training Matrix, Plus-Artikel) liefert Weiterleitung bzw. 403; Bänder in % 2k-Watt nur aus
  Sekundärquellen (ISS-Rekonstruktion, Forum).
- Kein ruderspezifischer Beleg für: Faktor 0,75 beim Rampentest, Faktor 0,95 beim 20-min-Test, DFA-α1-Schwellen,
  Friels LTHR-Zonen. Ruderer atmen oft im Schlagrhythmus; ob das DFA-α1 verzerrt, ist ungeprüft (eigene Vermutung).
- Beneke 1995 und Vanhatalo 2007 nur über Abstract-Auszüge/Repositorien; Shirai 2015 ist ein Kongressabstract.
- Kein aktuelles DRV-Stufentestprotokoll gefunden.
- Der Faktor Schwelle/2k (0,80) ist abgeleitet; individuell 0,75–0,87. Darum persönliche Kalibrierung (SPEC 4.4).

## Quellen (Auswahl, mit DOI)

- Beneke R (1995) Anaerobic threshold, individual anaerobic threshold, and maximal lactate steady state in rowing. Med Sci Sports Exerc 27:863–867.
- Borszcz FK, Tramontin AF, Costa VP (2019) Is the Functional Threshold Power Interchangeable With the Maximal Lactate Steady State in Trained Cyclists? Int J Sports Physiol Perform 14:1029–1035. doi:10.1123/ijspp.2018-0572
- Bourdin M, Messonnier L, Hager JP, Lacour JR (2004) Peak power output predicts rowing ergometer performance in elite male rowers. Int J Sports Med 25:368–373. doi:10.1055/s-2004-815844
- Bourgois J, Vrijens J (1998) The Conconi test: a controversial concept for the determination of the anaerobic threshold in young rowers. Int J Sports Med 19:553–559. doi:10.1055/s-2007-971959
- Cheng CF et al. (2012) Determination of critical power in trained rowers using a three-minute all-out rowing test. Eur J Appl Physiol 112:1251–1260. doi:10.1007/s00421-011-2081-2
- Ingham SA, Whyte GP, Jones K, Nevill AM (2002) Determinants of 2,000 m rowing ergometer performance in elite rowers. Eur J Appl Physiol 88:243–246. doi:10.1007/s00421-002-0699-9
- Jones AM, Burnley M, Black MI, Poole DC, Vanhatalo A (2019) The maximal metabolic steady state: redefining the ‚gold standard‘. Physiol Rep 7:e14098.
- Lillo-Beviá JR et al. (2022) Is the Functional Threshold Power a Valid Metric to Estimate the Maximal Lactate Steady State in Cyclists? J Strength Cond Res 36:167–173. doi:10.1519/JSC.0000000000003403
- Quittmann OJ, Piehl MA (2026) The 3-min all-out test in cycling: a systematic review and meta-analysis on its reliability and validity. Eur J Appl Physiol 126:4673–4691. doi:10.1007/s00421-026-06356-w
- Rogers B, Giles D, Draper N, Hoos O, Gronwald T (2021) A New Detection Method Defining the Aerobic Threshold … Fractal Correlation Properties of Heart Rate Variability. Front Physiol 11:596567. doi:10.3389/fphys.2020.596567
- Rogers B, Giles D, Draper N, Mourot L, Gronwald T (2021) Detection of the Anaerobic Threshold in Endurance Sports … J Funct Morphol Kinesiol 6:38. doi:10.3390/jfmk6020038
- Rogers B et al. (2021) Influence of Artefact Correction and Recording Device Type … Sensors 21:821. doi:10.3390/s21030821
- Schabort EJ, Hawley JA, Hopkins WG, Blum H (1999) High reliability of performance of well-trained rowers on a rowing ergometer. J Sports Sci 17:627–632. doi:10.1080/026404199365650
- Smith TB, Hopkins WG (2012) Measures of rowing performance. Sports Med 42:343–358. doi:10.2165/11597230-000000000-00000
- Stegmann H, Kindermann W (1982) Comparison of prolonged exercise tests at the individual anaerobic threshold and the fixed anaerobic threshold of 4 mmol/l lactate. Int J Sports Med 3:105–110. doi:10.1055/s-2008-1026072
- Tanaka H, Monahan KD, Seals DR (2001) Age-predicted maximal heart rate revisited. J Am Coll Cardiol 37:153–156. doi:10.1016/s0735-1097(00)01054-8
- Vanhatalo A, Doust JH, Burnley M (2007) Determination of critical power using a 3-min all-out cycling test. Med Sci Sports Exerc 39:548–555.
- Praxis/Hersteller: Concept2 Pace Calculator (https://www.concept2.com/training/pace-calculator); Concept2 Blog Heart Rate Training (https://concept2.com/blog/heart-rate-training-with-your-concept2-erg, 2025-04-17); World Rowing/Jensen (https://worldrowing.com/2019/11/26/using-the-indoor-rower-for-testing-why-test-different-distances/); TrainingPeaks/Friel (https://www.trainingpeaks.com/learn/articles/joe-friel-s-quick-guide-to-setting-zones/); TrainingPeaks Aerobic Decoupling (https://help.trainingpeaks.com/hc/en-us/articles/204071724); TrainerRoad Ramp Test (https://support.trainerroad.com/hc/en-us/articles/360003910912) und AI FTP Detection (https://support.trainerroad.com/hc/en-us/articles/4415864080155); Zwift Insider FTP-Tests (https://zwiftinsider.com/zwift-ftp-tests); Garmin LT-Test (https://www8.garmin.com/manuals/webhelp/fenix5/EN-US/GUID-1B0C9B93-01CD-4A0C-A30F-B815C0347159.html); Polar Fitness Test White Paper (https://polar.com/img/static/whitepapers/pdf/polar-fitness-test-white-paper.pdf); EXR FTP (https://exrgame.com/support/ftp); intervals.icu Forum eFTP (https://forum.intervals.icu/t/model-power-curve/1007); ISS-Bänder rekonstruiert (https://guyru.github.io/calculators/rowing-training-bands-calculator.html); GB Rowing/SAS-Programm (https://www.sas.com/content/dam/SAS/en_gb/doc/other2/sas-gb-perfect-rowing-programme.pdf); Wolfson CBC (https://www.wolfson.cam.ac.uk/sites/default/files/2019-11/wcbc_erging_0.pdf).
