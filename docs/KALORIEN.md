# Kalorien: aktive Energie mit Körpergewicht (28.11.2026)

Code: `App/RowCoachKit/Sources/RowCoachKit/RowingEnergy.swift` (Tests `RowingEnergyTests.swift`).

## Warum
Bis 1.0.0 (2) hat RowCoach die Kalorien des PM5 unverändert als **aktive Energie** in Apple Health geschrieben
(Beispiel: 321 kcal für 30 min). Das war aus zwei Gründen zu hoch bzw. ungenau:
1. Der PM5 rechnet für eine Referenzperson von 175 lb (79,5 kg), ohne Körpergewicht.
2. Der feste Anteil von 300 kcal/h im PM5-Wert enthält den Ruheumsatz. `activeEnergyBurned` darf laut Apple den
   Ruheumsatz nicht enthalten.

## Formeln
| Grösse | Formel (kcal/h während der Ruderzeit) | Quelle |
|---|---|---|
| PM5-Anzeige | `4 × W + 300` | Concept2 (Referenz 175 lb) |
| Gesamt, gewichtsangepasst | `PM − 300 + 1,714 × lb` = `4 × W + 3,779 × kg` | Concept2 Calorie Calculator |
| Ruheumsatz | `1,0 × kg` (1 MET ≈ 1,0 kcal/(kg·h)) | Compendium of Physical Activities 2024 |
| **Aktiv** (Apple Health, Anzeige) | `4 × W + 2,779 × kg` | Differenz der beiden Zeilen darüber |

- Gerechnet wird mit der **mittleren Leistung** über die **Ruderzeit** ohne Pausen (`summary.averagePower`,
  `activeDuration`). Die Formel ist linear in W. Deshalb ergibt das dasselbe wie die Summe Sekunde für Sekunde.
- Ohne Gewicht im Profil, oder bei einem Wert ausserhalb 30–250 kg, gilt **75 kg**.
- Ohne Leistungswerte (z. B. ein FTMS-Gerät ohne Watt) ist die aktive Energie 0. Die Zusammenfassung zeigt dann
  die Zahl des Geräts.
- Plausibilität: Der Faktor 4 kcal/h je W bedeutet einen Wirkungsgrad von etwa 21,5 %. Das passt zu den ~20 %, die
  Hagerman (1984) für das Rudern berichtet.

Beispiel: 179 W über 30 min (Tests).
| | PM5 | 75 kg | 95 kg |
|---|---|---|---|
| gesamt | 508 | 499,7 | 537,5 |
| Ruheanteil | – | 37,5 | 47,5 |
| **aktiv** | – | **462,2** | **490,0** |

## Wo welche Zahl steht
- **Zusammenfassung nach der Fahrt** und **Apple Health** (`activeEnergyBurned`, live und beim Nachtragen) zeigen
  dieselbe aktive Energie. Die Zusammenfassung schreibt dazu „kcal aktiv“.
- Beim Speichern wird die aktive Energie mit dem damaligen Gewicht festgehalten (`WorkoutSummary.activeCalories`,
  optional und synchronisiert). Ältere Fahrten ohne diesen Wert rechnen mit dem aktuellen Profilgewicht.
- Die PM5-Zahl bleibt als `WorkoutSummary.calories` gespeichert. Angezeigt wird sie nur in der Diagnose als
  „Kalorien (Gerät)“. Begründung: Zusammenfassung und Health sollen übereinstimmen. Die PM5-Zahl ist für eine fremde
  Referenzperson gerechnet und enthält den Ruheumsatz.
- Ruheumsatz (`basalEnergyBurned`) schreibt RowCoach **nicht**. iPhone und Apple Watch schätzen den Ruheumsatz
  selbst. Ein zweiter Eintrag von RowCoach würde ihn doppelt zählen. Apple Health addiert aktive Energie und
  Ruheumsatz selbst.
- Health Connect (später): `ActiveCaloriesBurnedRecord` mit derselben Zahl (`HealthWorkoutExport.totalKilocalories`).

## Grenzen
- Das ist eine Schätzung aus Leistung und Gewicht, keine Messung. Wirkungsgrad, Technik, Fitness, Alter,
  Geschlecht und Körperzusammensetzung fehlen. Ein Geschlechtsfeld gibt es bewusst nicht.
- 1 MET = 3,5 ml O₂/(kg·min) ist eine Konvention. Gemessene Ruhewerte liegen im Mittel tiefer (Byrne et al. 2005:
  2,6 ml/(kg·min) bzw. 0,84 kcal/(kg·h)). Der Ruheanteil ist damit eher etwas zu hoch und die aktive Energie eher
  etwas zu niedrig angesetzt (bei 75 kg etwa 12 kcal je Stunde).
- Den Anteil 1,714 × lb nennt Concept2 ohne Herleitung. Vermutlich enthält er neben dem Ruheumsatz auch den Aufwand, den
  eigenen Körper auf dem Rollsitz zu bewegen (eigene Deutung, nicht von Concept2). Deshalb steigt er mit dem Gewicht.
- Bei sehr kurzen, harten Belastungen (anaerob) unterschätzen alle diese Formeln den Umsatz.

## Quellen
- Concept2: Calorie Calculator, <https://www.concept2.com/indoor-rowers/training/calculators/calorie-calculator>
  (gelesen 28.11.2026: „Concept2 Performance Monitors use a formula based on a 175 pound/79.5 kg individual.“;
  „True Calories/hour burned = Calories on the PM − 300 + (1.714 × weight)“). Fundus `fact:2422`.
- Zotero war bei der Recherche nicht erreichbar (lokale Zotero-API aus); Quellen aus Fundus und dem Web.
- Herrmann SD, Willis EA, Ainsworth BE et al. (2024): 2024 Adult Compendium of Physical Activities. *Journal of
  Sport and Health Science* 13(1):6–12, doi:10.1016/j.jshs.2023.10.010, Abschnitt 2.5 („a standardized RMR of
  3.5 mL/kg/min or approximately 1.0 kcal/kg/h“) Fundus `fact:2461`.
- Hagerman FC (1984): Applied physiology of rowing. *Sports Medicine* 1(4):303–326,
  doi:10.2165/00007256-198401040-00005 (Abstract: „Mechanical efficiency for rowing was calculated at 20 ± 0.9%.“) Fundus `study:1084`.
- Byrne NM, Hills AP, Hunter GR, Weinsier RL, Schutz Y (2005): Metabolic equivalent: one size does not fit all.
  *J Appl Physiol* 99(3):1112–1119, doi:10.1152/japplphysiol.00023.2004 (Abstract: Ruhe 0,84 ± 0,16 kcal/(kg·h)) Fundus `study:1085`.
- Apple: `HKQuantityTypeIdentifier.activeEnergyBurned`, <https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned>
  („These samples should not include the resting energy burned during the sample’s duration.“) Fundus `fact:2462`.
