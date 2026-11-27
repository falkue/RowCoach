# Schwellenprofil, Schwellentests und Zonen: Umsetzung (Stand 27.11.2026)

Bauauftrag: `docs/schwelle/SPEC.md`, Grundlage `docs/schwelle/RECHERCHE.md`. Diese Datei beschreibt, was gebaut ist,
wo es liegt und was noch offen ist.

## Entscheidungen

- **Schwelle = Leistung, die man etwa 30 min hält** (FTP-Konvention 0,95 × 20 min), intern in Watt; Tempo abgeleitet.
- **Schalter „Ziele nach Leistungsanteil skalieren“ (SPEC 8.2) nicht gebaut, gilt als AUS**: alte Programme rechnen wie
  bisher mit `paceOffset*` relativ zur gespiegelten 2k-Zeit. Nur Phasen mit `powerPctMin/Max` (die vier neuen Tests)
  rechnen in Prozent der Schwelle.
- **DFA-α1** nur, wenn RR-Intervalle in der Fahrt liegen; Anzeige „zweite Meinung (experimentell, am Rudern nicht
  geprüft)“.
- Alles offline, ohne Konto. Das Profil wird synchronisiert, wenn die Synchronisation eingeschaltet ist (unten).

## Programme (plans.json)

- Vier neue Tests in `docs/plans-new/tests.json` (Familie `tests`), JSON wie SPEC 3.6: `schwelle-stufentest-puls`,
  `schwelle-test-20min`, `schwelle-test-3min`, `schwelle-rampentest`. Eingespielt mit
  `python3 App/l10n/merge_plans.py` → 115 Programme (Test 18).
- Vorhandene Tests tragen das Feld `test` (Evaluator): `test-100m` … `test-60min`, `einsteiger-test-10min`
  (`timeTrial`), `stufentest-5x4/7x4` (`stepHR`); `test-2000m` (Grundprogramm) über `EXISTING_TEST` in
  `merge_plans.py`. Das Skript prüft jetzt auch `powerPct*`, `testRole` und `test.evaluator`.
- `WorkoutPlan.test` (`PlanTestInfo`), `WorkoutPhase.powerPctMin/Max`, `allOut`, `endOnFailure`, `testRole`: alle
  optional, alte App-Versionen ignorieren sie (Test: Programme ohne die Felder dekodieren weiter mit Tempozielen).
- `WorkoutPhase.paceRange(best2k:)`: Phasen in % der Schwelle rechnen über die Schwelle zur (gespiegelten) 2k-Zeit,
  `T = threshold(fromBest2k:b:)`, Exponent aus `ThresholdMath.activeExponent` (setzt die App aus dem Profil); alle
  anderen Phasen unverändert. Neu `paceRange(profile:)`.

## RowCoachKit (`Sources/RowCoachKit/Threshold/`, nur Foundation)

| Datei | Inhalt |
|---|---|
| `ThresholdModel.swift` | `ThresholdSourceKind`, `EvaluationNote`, `ThresholdEstimate`, `HeartProfile`, `HealthScreen`, `ThresholdProfile` (formatVersion 1, tolerant dekodiert, unbekannte Quellen bleiben lesbar, höchstens 100 Schätzungen, `mirrorBest2k`, `migrated(…)`, `encodedForSync`, `merged(withRemote:)`) |
| `ThresholdMath.swift` | W ↔ Tempo (Concept2), Potenzgesetz, Schwelle aus Effort und 2k, gleichwertige 2k (Fixpunkt), Exponent aus zwei Efforts |
| `TrainingZones.swift` | 5 Leistungs-/Tempozonen in % T (55/75/88/102), automatische Wahl des Pulszonenmodells (LTHR → Reserve → % HFmax → geschätzt) |
| `ThresholdSeries.swift` | Mittelwerte über Zeitfenster (jeder Wert gilt bis zum nächsten, höchstens 5 s), Stillstand, gleitende Bestleistung, 5-s-Spitzenpuls, Leistungs-Dauer-Kurve (Zwei-Zeiger über kumulierte Arbeit) |
| `ThresholdEvaluator.swift` | Auswertung je Test: `timeTrial` (Potenzgesetz, σ nach Dauer, „zu schnell gestartet“, LTHR aus 30 min), `stepHR` (Regression HR = a + c·P, HR_T aus LTHR bzw. 85 % HFR, Hochrechnung, Talk-Test, DFA-α1, 7 × 4 mit Stufe 7 als 4-min-Zeitfahren), `ramp` (MAP = beste 60 s, Rampenfaktor), `allOut3min` (EP = 150–180 s, Prüfung all-out); `RampFailureDetector` |
| `DFAAlpha1.swift` | Artefakte (20 % vom Median der 11 Nachbarn), Fenster 120 s/10 s, ≤ 5 % Artefakte, α1 über n = 4…16; `LinearFit` |
| `ThresholdSelector.swift` | σ(t) (+0,5 %/Woche ab Woche 7, +3 % nach ≥ 14 Tagen Pause, Deckel 15 %), beste Schätzung, `decide` (Eingaben nie abgelöst, höher → aktiv, > 3 % tiefer → Rückfrage, Prüfhinweis → nur Hinweis), Vorschlag bei aktiver Eingabe, Kalibrierung b (zwei Zeitfahren ≤ 42 Tage, Verhältnis ≥ 2,5) und Rampenfaktor; `ThresholdRetest` (bevorzugter Test, R1, R3, R4/R5) |
| `ThresholdDetector.swift` | Schätzung aus Fahrten: maximale Efforts (Test, Belastung ≥ 8 oder Puls ≥ Zone 4 über ≥ 8 min), Kandidat Zeitfahren (≥ 8 min, inklusive der ganzen Fahrtlänge), Kandidat CP (2 Efforts, W′ 5–40 kJ), Vorschlag (≥ T·1,03 und ≥ T + 5 W, abgelehnt erst ab + 2 %, höchstens je 7 Tage), Entkopplung, gemessener Maximalpuls |

Geändert im Kit:

- `HeartRateZones` hat ein `model` (`reserve` wie bisher, `percentMax`, `lthr`); JSON ohne Modell bleibt Karvonen.
- `PlanEngine.endTestPart()`: Rampe nicht gehalten bzw. Stufentest vorzeitig zu Ende → weiter mit dem Ausrudern.
- `TrainingProgramEngine.estimateBest2k`: **Paul's Law ersetzt durch das Potenzgesetz** (Tempo → Watt → Schwelle →
  gleichwertige 2k). Ein 2000-m-Test ergibt genau seine Zeit; Tests unter 3 min liefern keine Referenz mehr (nur
  Bestmarke); Stufentest, Rampe und 3 min werten nur in der App aus. Unterschied für Nicht-2k-Tests: 1000 m in
  1:50 → früher 7:40,0, jetzt 7:36,3; 30 min mit 2:10 → früher 8:04,2, jetzt 8:07,1. `isTestPlan` kennt die neuen Tests.
- `DailySuggestion.make(…, threshold:)`: Regel 4 wird mit Schwellenprofil „Schwellentest fällig“ (R1: Schwelle älter
  als 8 Wochen oder σ > 8 %, 4 Wochen regelmässig, 48 h leicht, letzter Test ≥ 21 Tage) mit dem bevorzugten Test; ohne
  Profil wie bisher 2000 m.
- Sprachcoach: neue Gruppe `test` und Szenarien `test_intro`, `test_step_next`, `test_step_hold`, `test_talk_check`,
  `test_hr_reached`, `test_tt_pacing`, `test_allout_go`, `test_allout_encourage`, `test_ramp_next`, `test_ramp_end`,
  `test_result` (Variable `{watts}`), `CoachTestContext` (Schwelle, b, Rampenfaktor). Im Stufentest keine Motivation
  (nur Information, Testansagen, `stopped`); `test_ramp_next` ersetzt den Countdown vor jeder Rampenminute (10 s vorher
  statt 5 s, damit es nicht mit dem Countdown kollidiert); `test_allout_go` ersetzt `go`.
- Synchronisation: `SyncSettingsCatalog` hat `profile/threshold` (`threshold.profile.v1`). Beim Senden auf
  15 000 Zeichen gekürzt (älteste nicht aktive Schätzungen fallen weg), beim Übernehmen mit dem lokalen Verlauf
  vereinigt. Firestore-Regeln (`firebase/firestore.rules`) um das Feld ergänzt – **muss deployt werden**, sonst lehnt
  der Server das Profil-Dokument ab, sobald das Feld gesendet wird.

## Tests (XCTest, `ThresholdTests.swift`)

Sollwerte aus SPEC 11, alle grün (508 Tests gesamt):

- Math: W(2:00) = 202,5 W, pace(202,5) = 2:00,0; 2k 8:00 → T = 166,1 W → 2k 480,0 s; T = 200 W → 449,7 s; Faktoren
  20/30/60 min 0,941/1,000/1,110, 4 min 0,739, 10 min 0,848.
- Zonen T = 166,1 W: Grenzen 2:36,5 / 2:21,1 / 2:13,8 / 2:07,4; Pulsmodelle (LTHR, % HFmax, Karvonen, altes JSON).
- `stepHR`: P = 80…150 W, HR = 60 + 0,5·P ± 1, HR_T = 135 → T = 150 W ± 2; < 3 Stufen → nicht auswertbar; HR_T 20 bpm
  über der höchsten Stufe → nur Hinweis; ohne LTHR 85 % HFR.
- DFA-α1: weisses Rauschen 0,5, Brownsches 1,5, 1/f 1,0 (± 0,1); Fenster mit > 5 % Artefakten verworfen.
- Rampe bis 140 %, dann 80 % des Ziels → Abbruch nach 15 s unter 90 % (gleitendes 15-s-Mittel, ≈ 21 s nach dem
  Einbruch), MAP = 1,40·T, T = 0,75·MAP; Rampe < 6 min → Hinweis, nächste 10 % tiefer.
- 3 min: Spitze 1,6 × EP → gültig, T = 0,88·EP; gleichmässig → „nicht all-out“, nie aktiv.
- Zeitfahren 20 min (0,941), „zu schnell gestartet“, Unterbrechung > 15 s → ungültig, 30 min → LTHR, 500 m → Bestmarke.
- Auswahl: Eingabe nicht abgelöst; Test höher → aktiv; tiefer → Rückfrage; Vorschlag bei Eingabe; Alterung.
- Fahrten: 24 min mit 175 W, Belastung 8 → 169,2 W; ohne Maximalität → nichts; CP 3 min/300 W + 12 min/230 W →
  206,7 W, W′ 16,8 kJ, T 181,9 W; Vorschlag ≥ 3 % und je 7 Tage.
- Migration: best2k 455 → Spiegel 455,0; Standard → σ 15 %; Zielwerte aller Programme ohne `powerPct*` unverändert
  (Prüfung über `paceRange(best2k:)` für 6:40/7:35/8:00/9:00); neue Programme dekodieren, auch ohne die neuen Felder.
- Coach: Stufentest ohne Motivation, 6 × `test_step_next`, 5 × `test_talk_check`; All-out: `test_allout_go` statt `go`,
  Zuspruch alle ≥ 20 s, zuletzt Stufe 2; Rampe: `test_ramp_next` je Minute, `test_ramp_end`.
- Angepasst: `TrainingProgramTests.testPowerLawEstimate` (vorher `testPaulsLawEstimate`), `SyncTests` (Feldliste).

## App

- `Storage/ThresholdStore.swift` (neu): Profil in UserDefaults `threshold.profile.v1`, Migration beim ersten Start
  (legacy2k aus `profile.best2k`, Standard 8:00 → σ 15 % und kein Spiegel, damit „Profil prüfen“ bleibt), Spiegel nach
  `profile.best2k` bei jeder Änderung der aktiven Schwelle, Eingaben, Puls, Verlauf, Testergebnisse (mit „Rückgängig“),
  Referenz aus Trainingsplänen, Fahrten-Vorschlag, Retest-Eingang. `ThresholdSettings`: Lesezugriff ohne Hauptthread,
  Pulszonen nach Modell (`TrainingSettings.zones` nutzt das jetzt; ohne LTHR wie bisher Karvonen).
- `Views/ThresholdViews.swift` (neu): Einstellungen → Profil → „Schwelle & Zonen“ (aktive Schwelle mit Watt, Tempo,
  gleichwertiger 2k, Quelle, Datum, Unsicherheit; Eingabe Watt/Tempo/2k/„weiss nicht“ mit Datum; Puls HFmax, Ruhepuls,
  LTHR, Geburtsjahr, Pulsmodell; Zonentabelle Watt/Tempo/Puls; Verlauf mit Details, „als aktiv verwenden“,
  „verwerfen“; „Test starten“ mit Empfehlung, bevorzugtem Test, Gesundheitsfragen), `ThresholdResultCard`
  (Zusammenfassung nach der Fahrt), `ThresholdTestControls` (Talk-Test, „Ich kann nicht mehr“/„Zu anstrengend“),
  `HealthScreenSheet`, `ThresholdTestNotice`, `ThresholdTargetLine`.
- Geändert: `SettingsView` (Link, Fusszeile, Zonenvorschau nach Modell, `closeSettings`), `ProfileViews` (2k-Rad schreibt
  eine Eingabe ins Profil; Beschriftung „2k-Referenz für Ziele“, wenn die Schwelle nicht aus einer 2k-Zeit stammt),
  `SummaryView` (Ergebniskarte), `PlanViews` (Hinweise, Zeile „Ziele aus Schwelle …“, Gesundheitsfragen vor dem Start),
  `RootView` (Gesundheitsfragen vor jedem maximalen Test, auch vom Startbildschirm), `HomeModel` (Efforts je Fahrt,
  Vorschlag „Neue Schwelle erkannt“, Retest-Eingang), `HomeView` (Banner Vorschlag und offene Rückfrage),
  `SessionController` (Rampenabbruch, Stufentest-Ende bei Schwellenpuls + 3 über 30 s, Talk-Test-Antworten),
  `RowingView` (Testbedienung), `TrainingCue` (Coach mit Testkontext), `ProgramStore` (Referenz → Schwellenprofil),
  `AppSyncStore` (Kürzen/Vereinigen), `RowCoachApp` (Profil beim Start laden).
- Texte: 136 neue Schlüssel in `App/l10n/en_strings.py`, `build_catalog.py` → 0 ohne Englisch.
- Coach-Phrasen: 11 Szenarien in `coach_phrases.json` (de/en, drei Stile), `check_coach_phrases.py` grün;
  512 neue statische Phrasen (256 je Sprache) für die Tonkonserven: `python3 tools/coach_audio/render_coach.py`.

## Nachgezogen (27.11.2026, zweite Runde)

- **Sicherheit (SPEC 9):** Kit `Threshold/ThresholdSafety.swift`: `HeartRateSafetyMonitor` – „Pulsgurt prüfen“ bei
  Puls > Maximalpuls + 8 über ≥ 10 s oder Sprung > 30 bpm/s (bleibt 15 s stehen; ohne eingetragenen Maximalpuls nur
  die Sprungregel), „Puls fehlt“ nur in Stufen eines Stufentests nach > 15 s ohne frischen Messwert (Gurt: Wert
  höchstens 3 s alt, ohne Hautkontakt zählt nicht). Kein Pausieren, kein Abbruch: dezentes Banner in der Fahrt
  (`HeartRateSafetyBanner`, `SessionController.heartStrapCheck/heartRateMissing`). Die Auswertung markiert:
  `stepHR` setzt `heartRateMissing`, sobald eine Stufe eine Pulslücke > 15 s hat
  (`ThresholdSeries.longestHeartRateGap`); die Stufe zählt weiter nur mit ≥ 45 s Puls in der letzten Minute.
  Schwelle 15 s statt 30 s (SPEC) nach Auftrag.
- **R3/R4/R5 als Karte:** Kit `Threshold/ThresholdRetestCards.swift`: `RetestRide` (Einheit Schwelle/Intervalle,
  unabhängig von der 2k-Referenz verdichtet: Dauer, Zielmitte, Leistung, Puls, 100 Quantile von „Tempo − Ziel
  langsam − 3 s“) → `ThresholdRetest.Session` mit der aktuellen Referenz; `ThresholdRetestCard.make` (höchstens eine
  Karte, R3 vor R4 vor R5; nicht mit laufendem Trainingsplan – der Plan hat eigene Regeln für harte Einheiten,
  Tests und Wiedereinstieg; Testvorschlag nicht innerhalb 21 Tagen nach einem Test; R4/R5 zählen nur Einheiten seit
  der aktiven Schwelle und seit dem letzten Schliessen; R3 nach Schliessen 14 Tage weg). App: `HomeModel` rechnet,
  `ThresholdStore.retestCard`, `ThresholdRetestCardView` auf der Startseite und oben in „Schwelle & Zonen“
  („Test: …“, bei R4 „Schwelle −3 %“, schliessen lokal in `threshold.retestDismissed`).
- **Eine Rückfrage statt zwei:** `ProgramReferenceLink` (Kit). Kennt das Schwellenprofil die Testfahrt eines
  Trainingsplans, entscheidet es (Ergebniskarte bzw. Hinweis auf der Startseite); die Plan-Rückfrage „Neue Referenz
  übernehmen?“ erscheint nur ohne Schätzung zur Fahrt und wird erledigt, sobald die Karte beantwortet ist
  (`ProgramStore.referenceQuestion`, Beobachter auf `ThresholdStore.didChange`).
- **Profil:** Einstellungen → Profil: Maximal-/Ruhepuls führen nach „Schwelle & Zonen“ (springt zum Abschnitt Puls);
  dort speichern die Pulsfelder beim Verlassen selbst (nur bei echter Änderung).
- **Wiedereinstieg:** neues Programm `grundlage-locker-15` (3 + 10 + 2 min, UT2) in `docs/plans-new/grundlage.json`,
  `merge_plans.py` → 116 Programme; `ReentryRule.shortPlans` nimmt es als erstes.
- Tests: `ThresholdSafetyTests` (9).

## Offen

1. Auf dem Mac bauen (SwiftUI-Teile sind unter Linux nur syntaktisch geprüft) und `xcodegen generate` (zwei neue
   Dateien der ersten Runde; die zweite Runde hat neue Dateien nur im Kit).
2. Der Stufentest startet ohne Pulsgurt nur aus der Programmansicht und aus „Schwelle & Zonen“ nicht; vom
   Startbildschirm (auch über die Karte „Wieder dabei“) startet er auch ohne Gurt – dann meldet die Fahrt „Puls
   fehlt“.
3. Entkopplung (Pa:HR) und gemessener Maximalpuls aus allen Fahrten sind im Kit, aber ohne Anzeige (der Maximalpuls
   aus Testfahrten wird in der Ergebniskarte vorgeschlagen).
4. Watt-Ampel (± 5 %) für Phasen mit `powerPct*` und Tempo nur als Orientierung in `allOut`-Phasen: HUD unverändert.
5. „Zonen aller Fahrten neu berechnen“ fehlt (gespeicherte Fahrten behalten ihre Zonensekunden).
6. Faktoren 0,88 (CP → T), 0,75 (Rampe), 0,77 (LT1 → T), b = 0,15 nach den ersten eigenen Daten prüfen (SPEC 12).
