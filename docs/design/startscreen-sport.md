# Startbildschirm aus Trainersicht

Stand 23.11.2026. Sportwissenschaftlicher Entwurf für den Tab „Rudern“, iPad quer. Belegte Aussagen tragen eine Quellennummer [n]. Alles ohne Nummer ist Trainererfahrung bzw. eine eigene Regel und als solche gemeint. Recherche: Zotero und Fundus hatten nichts Einschlägiges; Fundus enthält nur die Einträge aus `docs/trainings-recherche.md`. Deshalb stammen die Belege aus dem Web.

## 1. Kurzdiagnose

Der heutige Einstieg besteht aus zwei Kacheln („Frei rudern“, „Training“) auf weissem Grund. Danach kommt die Streckenauswahl.

- **Er kennt Falk nicht.** Kein Wort zur letzten Einheit, zur Woche oder dazu, was heute dran wäre. Die App weiss viel (Splits, Puls, Zeit je Zone, Programm), zeigt es aber erst im Verlauf, Training für Training.
- **Er steuert nicht.** Die Wahl des Programms hängt an Falks Tageslaune. Bei Fitnessruderern führt das typischerweise ins „mittelharte Einerlei“: jede Fahrt etwas zu hart für Grundlage, zu weich für einen Reiz.
- **Er macht keine Lust.** Die schönsten Elemente der App (Luftbilder, Strecken) kommen erst zwei Klicks später.
- **Zwei stille Datenfehler:**
  - Simulatorfahrten (`device.source = simulator`) müssen aus jeder Statistik heraus.
  - Maximalpuls 185, Ruhepuls 55 und die 2000-m-Bestzeit sind Voreinstellungen. Solange Falk sie nicht gesetzt hat, sind Zonen und Tempoziele geschätzt. Das muss sichtbar sein.

## 2. Elemente nach Priorität

Grundregeln für alle Zahlen:
- Nur echte PM5-Fahrten zählen. Unterbrochene Fahrten zählen mit ihrem gespeicherten Teil.
- Zeiträume: „letzte 7 Tage“ heisst rollend, heute eingeschlossen.
- **Drei Intensitätsstufen** nach Herzfrequenzreserve, passend zu `HeartRateZones` und den Ruderbereichen im Wolfson-Leitfaden (UT2 bis 70 %, UT1 70–80 %, AT ab 80 %) [8]:
  - **leicht:** Zone 0–2
  - **mittel:** Zone 3
  - **hart:** Zone 4–5
- **Einheit als Ganzes einstufen** (Session-Goal-Prinzip; Seiler und Kjerland verglichen Puls, Session-RPE und Einstufung je Einheit [2]):
  - mit Programm nach `category`: Grundlage und Technik & Rhythmus = leicht; Schwelle = mittel; Intervalle, Sprint und Test = hart.
  - frei gerudert nach Puls: hart ab ≥ 10 min in Zone 4–5, mittel ab ≥ 20 min in Zone 3–5, sonst leicht (eigene Schwellen).
  - ohne Puls: nach dem Tempo relativ zur 2000-m-Bestzeit.

### Muss

| Element | Was angezeigt wird | Berechnung | Warum | Fehlinterpretation vermeiden |
|---|---|---|---|---|
| **Vorschlag für heute** (grosse Kachel, Luftbild der Strecke als Hintergrund) | Programm, Dauer, Zielbereich (Tempo /500 m, Schlagzahl, Zone), eine Zeile „weil …“, Taste „Los“ (direkt zur zuletzt genutzten Strecke) und „Anders wählen“ | Regel in Abschnitt 3 | Steuert die Verteilung leicht/hart und senkt die Hürde zum Start. Das Bild macht Lust. | Klar als **Vorschlag** beschriften, nie „Plan erfüllt/verfehlt“. Frei rudern bleibt gleichwertig daneben. |
| **Diese Woche** (Streifen Mo–So) | Je Tag ein Punkt, eingefärbt leicht/mittel/hart; Summe in **min** und km; daneben der Schnitt der 4 Wochen davor | Summe `activeDuration` bzw. `distance` je Kalenderwoche; Schnitt = Summe der 4 Vorwochen / 4 | Häufigkeit und Regelmässigkeit sind für Fitnessruderer der wichtigste Hebel. Concept2 plant mit 4 Einheiten pro Woche [5]. | Minuten führen, nicht km: Ein Sprinttag hat wenig km und ist trotzdem hart. Der Schnitt ist ein Vergleich, kein Soll. |
| **Leicht/hart, 28 Tage** (ein Balken) | Anteile leicht/mittel/hart nach **Zeit** im Puls (Zone 0–2 / 3 / 4–5), dazu als Text „x von y Einheiten hart“ | `heartRateZoneSeconds` über 28 Tage summieren; Einheiten nach der Regel oben zählen | Gut trainierte Ausdauersportler trainieren rund 75–80 % leicht [1][2]. Bei Elite-Ruderern lagen die höheren Intensitäten bei etwa 4–10 % der Ruderzeit [1]. | Die Zeit in Zonen unterschätzt harte Intervalle, weil der Puls nachläuft und Pausen dazwischen liegen (Trainerregel). Deshalb beide Sichten zeigen. Unter 6 Einheiten mit Puls: „noch zu wenig Daten“. 80/20 ist eine Orientierung, kein Grenzwert. |
| **Letzte Einheit** | Datum („vor 2 Tagen“), Programm bzw. Strecke, Zeit, Distanz, Tempo; Tippen öffnet die Zusammenfassung | letzter `WorkoutRecord` | Anknüpfen statt bei null beginnen | Bei Intervallen nicht das Durchschnittstempo mit Pausen zeigen, sondern das Tempo der Belastungsphasen (`planPhases`, Typ work). |
| **Hinweis „Profil prüfen“** (nur wenn nötig) | „Pulszonen und Tempoziele beruhen auf Standardwerten“ | Maximalpuls, Ruhepuls oder 2000-m-Bestzeit noch auf Voreinstellung | Ohne eigene Werte sind alle Zonen und Ziele geschätzt. | Verschwindet, sobald gesetzt. |

### Soll

| Element | Was | Berechnung | Warum | Vermeiden |
|---|---|---|---|---|
| **Belastung der Woche** | Balken diese Woche gegen den Schnitt der 4 Vorwochen, ohne Ampel | Edwards-TRIMP: Minuten in 50–60/60–70/70–80/80–90/90–100 % HFmax × 1/2/3/4/5, summiert [3]. Rechnung aus den 1-Hz-Pulswerten, da die Edwards-Bänder auf % HFmax beruhen, nicht auf der Reserve. Ohne Puls: Session-RPE (Dauer × Anstrengung 0–10) [4], ein Tippen nach der Fahrt. | Verbindet Umfang und Intensität in einer Grösse und zeigt Sprünge (z. B. Woche doppelt so hart wie üblich). | Die Gewichte sind linear und willkürlich [3]. Zahl gerundet zeigen, als relativen Vergleich. **Kein** Acute:Chronic-Verhältnis mit Verletzungsampel: Der Kausalzusammenhang ist nicht belegt, das Verhältnis hat konzeptionelle Mängel [6]. |
| **Tage seit hart** | „Letzte harte Einheit: vor 3 Tagen (Schwelle 4 × 6)“ | Datum der letzten Einheit mit Stufe hart oder mittel | Kern der Abwechslung von hart und leicht | Keine Erholungsprognose („erholt in 14 h“) ableiten. |
| **2000-m-Bestzeit und Verlauf** | Aktuelle Bestzeit, Datum, kleine Linie aller Tests; Hinweis, wenn der letzte Test über 8 Wochen her ist | Einheiten mit `test-2000m` bzw. freie Fahrten mit ≥ 2000 m: Zeit bei 2000 m aus den Samples. Bei neuer Bestzeit fragen, ob sie als Referenz gelten soll. | Alle Tempoziele der 10 Programme hängen daran. Die Bestzeit ist der ehrlichste Leistungstrend. | Keine 2000-m-Prognosen aus kurzen Stücken. Langsamere Tests nicht als „Verschlechterung“ werten (Tagesform, Pacing). |
| **Wochen in Folge** | „6 Wochen in Folge mit ≥ 3 Einheiten“ | Kalenderwochen rückwärts zählen, die das Ziel erreichen; Ziel einstellbar (Standard 3) | Motiviert über Regelmässigkeit, ohne Druck zum täglichen Training | **Keine Tagesserie** (sie belohnt Rudern ohne Erholung). Eine verpasste Woche nicht dramatisieren. |

### Später

- **Gleiches Tempo, weniger Puls (Effizienz):** In leichten Einheiten den Puls bei vergleichbarem Tempo als 4-Wochen-Trend zeigen. Nur bei ähnlicher Schlagzahl und Dauer, frühestens ab 8 vergleichbaren Fahrten. Der Puls schwankt mit Hitze, Schlaf und Koffein.
- **Ruhepuls und HRV aus Apple Health** (optional, eigene Leseerlaubnis): HealthKit bietet `restingHeartRate` und `heartRateVariabilitySDNN` [7]. Beide stammen meist von der Apple Watch. Nur als Abweichung vom eigenen 30-Tage-Mittel zeigen und erst ab deutlicher, mehrtägiger Abweichung („Ruhepuls seit 3 Tagen 6 Schläge über deinem Mittel – heute eher leicht?“). Keine Tageswertung, kein „Readiness-Score“. Die RR-Intervalle aus der Fahrt eignen sich dafür nicht (Belastung, nicht Ruhe).
- **Strecken-Sammlung:** „Noch nicht gerudert: Stein am Rhein“, km je Strecke. Das macht Lust, ist aber keine Trainingssteuerung.
- **Nächstes Rennen** (Stufe Abos, KONZEPT 12) oben in die Vorschlagskachel.

## 3. Vorschlag für heute (Regel)

Die erste zutreffende Zeile gilt. Angezeigt werden der Vorschlag mit Begründung und zwei Alternativen; Falk entscheidet. Eingaben sind nur die eigenen Fahrten (Stufe je Einheit wie oben).

| # | Bedingung | Vorschlag | Begründung auf dem Schirm |
|---|---|---|---|
| 0 | Weniger als 3 Fahrten im Verlauf oder > 7 Tage Pause | `grundlage-locker-30` | „Locker einsteigen“ |
| 1 | Letzte harte oder mittlere Einheit < 48 h her | `technik-locker-25`, wenn gestern hart, sonst `grundlage-locker-30` | „Gestern Intervalle – heute locker“ |
| 2 | ≥ 2 harte Einheiten in den letzten 7 Tagen | `grundlage-3x10-r20` (im Wechsel mit `grundlage-locker-30`) | „2 harte Einheiten diese Woche sind genug“ (Concept2: mindestens 2 harte pro Woche als Ziel [5]) |
| 3 | Leicht-Anteil (Zeit, 28 Tage) < 75 % bei ≥ 6 Fahrten mit Puls | Grundlage wie in Zeile 2 | „Mehr lockere Kilometer, Ziel etwa 80/20“ [1][2] |
| 4 | Letzter 2000-m-Test > 8 Wochen her, ≥ 4 Wochen regelmässig trainiert, letzte 2 Tage leicht | `test-2000m` | „Neue Referenz für deine Tempoziele“ |
| 5 | Sonst (harte Einheit fällig) | Unter `schwelle-4x6`, `langintervalle-4x4`, `kurzintervalle-8x2`, `pyramide-1-2-3-4-3-2-1` das am längsten nicht gefahrene; `sprint-8x250` höchstens alle 14 Tage | „Zeit für einen Reiz – zuletzt Schwelle, heute 4 × 4 min“ |

Zusätze:
- Waren die letzten 3 leichten Einheiten dasselbe Programm, wird `frequenzleiter-18-24` als Abwechslung angeboten (mittel, nur nach Zeile 5 bzw. statt Grundlage, wenn nichts dagegen spricht).
- Wurde der Vorschlag heute schon gerudert: „Heute erledigt“, und der Vorschlag für morgen erscheint klein.
- Kennzeichnung immer: „Vorschlag aus deinen letzten Fahrten. Fühlst du dich anders, wähle frei.“ Bei Krankheitsgefühl gilt der allgemeine Hinweis in den Einstellungen, kein Medizin-Rat auf dem Startschirm.

## 4. Bewusst nicht zeigen

- **Kalorien prominent:** Der PM5 rechnet mit einem Referenzruderer von 79,5 kg [9]. Falks Wert ist eine Schätzung; höchstens klein in der Zusammenfassung, gerundet auf 10 kcal.
- **Acute:Chronic-Ratio oder „Verletzungsrisiko“-Ampel** [6].
- **Readiness-, Erholungs- oder Fitness-Scores** sowie VO2max-Schätzungen ohne Labor: Scheingenauigkeit, nicht überprüfbar.
- **Tagesserien** und „Ziel verfehlt“-Rot.
- **Durchschnittstempo über ganze Intervalleinheiten** (enthält Pausen) und Vergleiche verschiedener Programme über ein einziges Durchschnittstempo.
- **Nachkommastellen** bei Belastung, Prozent und Puls; keine Prozentwerte unter 6 Fahrten mit Puls.
- **Simulatorfahrten** in jeder Kennzahl.

## 5. Quellen

1. Seiler S, Tønnessen E (2009): Intervals, Thresholds, and Long Slow Distance. Sportscience 13, 32–53, PDF S. 1 und 11. https://sportsci.org/2009/ss.htm (Fundus study:1035)
2. Seiler KS, Kjerland GO (2006): Quantifying training intensity distribution in elite endurance athletes. Scand J Med Sci Sports 16(1), 49–56: 318 Einheiten, 75/8/17 % (Puls) bzw. 76/6/18 % (Session-RPE). https://pubmed.ncbi.nlm.nih.gov/16430681/ (Fundus study:1042)
3. Shaw JW et al. (2020), Front. Physiol. 11:480, Methodenteil mit der Definition des Edwards-TRIMP (Original: Edwards S 1993, The Heart Rate Monitor Book, S. 113–123). https://doi.org/10.3389/fphys.2020.00480 (Fundus fact:2421)
4. Haddad M et al. (2017): Session-RPE Method for Training Load Monitoring: Validity, Ecological Usefulness, and Influencing Factors. Front. Neurosci. 11:612 (Foster 2001: Last = RPE × Minuten). https://doi.org/10.3389/fnins.2017.00612
5. Concept2: Beginner's Training Plan (Couch to Consistency): vier Einheiten pro Woche; „at least two good hard efforts per week“. https://www.concept2.com/training/plans/couch-to-consistency (Fundus practice:977)
6. Impellizzeri FM et al. (2020): Acute:Chronic Workload Ratio: Conceptual Issues and Fundamental Pitfalls. IJSPP 15(6), 907–913. https://opus.lib.uts.edu.au/handle/10453/141898
7. Apple Developer: HKQuantityTypeIdentifier `restingHeartRate`, `heartRateVariabilitySDNN`. https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier
8. Wolfson College Boat Club (2019): Erging, Abschnitte 1.5–1.6 (Ruderbereiche nach Herzfrequenzreserve). https://www.wolfson.cam.ac.uk/sites/default/files/2019-11/wcbc_erging_0.pdf (Fundus fact:2420)
9. Concept2: Calorie Calculator (Referenzperson 175 lb / 79,5 kg). https://www.concept2.com/indoor-rowers/training/calculators/calorie-calculator (Fundus fact:2422)
