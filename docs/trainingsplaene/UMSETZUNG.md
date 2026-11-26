# Trainingspläne in der App: Umsetzung

Stand 26.11.2026. Setzt die Regeln aus `RECHERCHE.md`, Kapitel 5, um. Alles läuft lokal und offline: kein Konto,
kein Netz. Die Logik liegt in RowCoachKit (nur Foundation, läuft auch unter Linux und Android), die iOS-App zeigt sie an
und speichert den Zustand.

## 1. Dateien

| Datei | Inhalt |
|---|---|
| `App/RowCoach/Resources/training_plans.json` | 17 Pläne (erzeugt mit `docs/trainingsplaene/gen_training_plans.py`, das auch `PLAENE.md` schreibt) |
| `App/RowCoach/Resources/plans.json` | 111 Programme (neu: `einsteiger-5x1-2x5`, `grundlage-locker-45`, `grundlage-6000m-ut2`, `grundlage-12000m-ut2`, `langdistanz-ut2-120`, `langdistanz-ut2-150`, `langdistanz-hmp-50`; Quelle `docs/plans-new/grundlage.json`, Generator `docs/plans-new/generators/gen_grundlage_ergaenzung.py`, dann `App/l10n/merge_plans.py`) |
| `RowCoachKit/…/TrainingProgram.swift` | Modell und tolerantes Lesen: `TrainingProgram`, `ProgramWeek`, `ProgramSession`, `ProgramRules`, `MissedSessionPolicy`, `TrainingProgramCatalog`, `ProgramFilter`, `TrainingProgramCategory`, `ProgramWeekClass` |
| `RowCoachKit/…/TrainingProgramScheduler.swift` | Verteilung auf Wunschtage (`placeWeek`), Regelprüfung (`valid`), `Weekday`, `ProgramDays`, Vorschlag der Wunschtage, `ProgramStartProblem` |
| `RowCoachKit/…/ActiveTrainingProgram.swift` | Zustand (`ActiveTrainingProgram`, `ScheduledProgramSession`, `ProgramWeekRun`, `ProgramNotice`, `ReferenceProposal`, `ProgramSessionRef`) und Logik (`TrainingProgramEngine`): Start, Abgleich, Verpasstes, Pause/Wiedereinstieg, RPE- und Test-Regeln, Tagesplan (`ProgramAgenda`) |
| `RowCoachKit/…/DailySuggestion.swift` | Regel „plan“ und „planRest“, `ProgramContext` |
| `RowCoachKit/…/Workout.swift`, `TrainingStats.swift` | `WorkoutHeader.trainingProgram` und `TrainingSession.programRef`: Bezug der Fahrt auf die Einheit |
| `RowCoachKit/Tests/…/TrainingProgramTests.swift` | 45 Tests (Katalog, Verteilung, Engine, Tagesvorschlag) |
| `App/RowCoach/Storage/ProgramStore.swift` | `ProgramLibrary` (Katalog aus dem Bundle) und `ProgramStore` (Zustand als JSON in UserDefaults `trainingProgram.active`) |
| `App/RowCoach/Views/ProgramViews.swift` | Tab „Pläne“: Liste, Detail, „Plan starten“, aktiver Plan |
| `App/RowCoach/Views/RootView.swift` | Tab „Pläne“, `ProgramsTab`, Start einer Fahrt mit Bezug |
| `App/RowCoach/Views/Home/HomeModel.swift`, `SuggestionCard.swift` | Abgleich bei jedem Neurechnen, „Heute laut Plan“ / „Ruhetag laut Plan“ |
| `App/RowCoach/Session/SessionController.swift`, `Views/RowingView.swift` | Bezug und Tempo-Anpassung beim Start, Bezug im gespeicherten Training |

## 2. Ablauf

1. **Start** (`TrainingProgramEngine.start`): Wunschtage prüfen (weniger als `sessionsPerWeek.min` → `tooFewDays`,
   Hinweis auf „Form halten“), erste Planwoche ab Startdatum anlegen und verteilen.
2. **Abgleich** (`update`, bei jedem Neurechnen des Startbildschirms über `ProgramStore.sync`):
   Fahrten zuordnen → 10 Tage ohne Fahrt: pausieren → verpasste Tage behandeln → Wochenwechsel (auch mehrere) →
   RPE-Regeln → Tests auswerten.
3. **Tagesvorschlag**: `agenda` liefert die Tage der laufenden Woche und eine Vorschau der nächsten; `DailySuggestion`
   wählt daraus.
4. **Fahrt aus dem Plan**: `ProgramStore.launchRef` (vorgemerkte Einheit aus der Wochenansicht, sonst die heutige bzw.
   nächste offene Einheit mit diesem Programm) → `RideLaunch.programRef` → `SessionController.prepare` →
   `WorkoutHeader.trainingProgram`. Fahrten ohne Bezug zählen trotzdem, wenn ihr Programm in derselben Planwoche offen
   ist (gleicher Tag zuerst).

Eine Planwoche (`ProgramWeekRun`) dauert 7 Tage ab ihrem Start (nicht Mo–So); sie kann um höchstens 2 Tage länger
werden (Policy `shift`) oder für die Zieleinheit weiter. Wiederholte Wochen und der Wiedereinstieg sind eigene
Planwochen mit fortlaufender Nummer `run`.

## 3. Regeln und wo sie stehen

| Regel (RECHERCHE) | Umsetzung |
|---|---|
| 5.1 Pflicht-Einheiten in Slot-Reihenfolge auf die frühesten Wunschtage | `TrainingProgramScheduler.placeWeek` / `assign`: Teilmengen der Tage lexikografisch, je Teilmenge die Anordnung mit den wenigsten Vertauschungen |
| 5.1 hart nie an Folgetagen, ≥ 48 h, Masters 72 h, auch über die Wochengrenze | `ProgramRules.hardGapDays` (Stunden / 24, aufgerundet), `valid`; die Tage der Vorwoche gehen als `fixed` ein |
| 5.1 höchstens `maxConsecutiveDays` hintereinander (Einsteiger: Ruhetag) | `valid` |
| 5.1 sonst tauschen → späterer Wunschtag → leichte Variante | Reihenfolge in `placeWeek`; zuletzt wird „Tage hintereinander“ gelockert |
| 5.1 freiwillige auf übrige Tage, sonst entfallen | `placeWeek`, Rest bleibt „ohne Tag“ und wird an Ruhetagen angeboten |
| 5.2 Verpasstes zuerst in der Woche verschieben | `handleMissed` → `freeDay` (nur Wunschtage, ausser `allowAnyDay`) |
| 5.2 `shift` / `replace-easy` / `skip` | `handleMissed`; `shift` nutzt auch andere Tage und verlängert die Woche um höchstens 2 Tage |
| 5.2 nie zwei harte nachholen | `ProgramWeekRun.rescheduledHard` (nur eine harte Einheit je Woche wird verschoben) |
| 5.2 nie zwei Einheiten an einem Tag | `occupied`/`freeDay`, Tage mit erledigter Einheit fallen beim Verteilen weg |
| 5.2 Zieleinheit verschieben, nie streichen | `handleMissed` (`event`): erster passender Tag ab heute, notfalls bis 14 Tage nach Wochenende, Woche wird verlängert |
| 5.2 Einsteiger: Woche wiederholen ab `repeatWeekIfMissed` | `startNextRun` (zählt entfallene Pflicht-Einheiten, nicht „pausiert“) |
| 5.3 pausieren (Nutzer oder 10 Tage ohne Fahrt) | `pause`; `update` setzt `autoPaused` mit Pausenbeginn am Tag nach der letzten Fahrt |
| 5.3 bis 7 Tage: weiter, erste harte leicht | `resume`: dieselbe Woche ab heute, erledigte Einheiten der Woche entfallen (`alreadyDone`), `easyFirstHard` |
| 5.3 8–14 Tage: letzte vollständige Woche, −1 bis −2 s | Woche davor; `paceAdjustment` +1 (bis 10 Tage) bzw. +2 |
| 5.3 15–28 Tage: Wiedereinstieg ab Woche 2 (ab 21 Tagen ab Woche 1), dann eine Woche vor dem Stand | `ProgramBridge`, `paceAdjustment` + Pausenwochen |
| 5.3 29–56 Tage: ganzer Wiedereinstieg, dann Blockbeginn, Retest | `blockStart` (Woche nach der letzten leichteren Woche), Hinweis `retestSuggested` |
| 5.3 über 8 Wochen: neu starten, Retest | Woche 1, Hinweise `restarted` und `retestSuggested` |
| 5.4 Test → Referenz (Paul's Law), schlechter nur nach Rückfrage | `evaluateTests`, `estimateBest2k` (Tempo der Belastungsphasen, +5 s/500 m je Verdopplung); schneller → `ProgramStore` übernimmt sofort, langsamer → Rückfrage in der Wochenansicht; ein Test setzt `paceAdjustment` zurück |
| 5.5 RPE: 3 leichte ≥ 7 (2 ≥ 9) → nächste Woche leichter | `applyEffortRules` → `forceDeloadNext`; die Woche ersetzt harte Einheiten durch die leichte Variante, freiwillige entfallen |
| 5.5 2 harte RPE 10 und Tempo > 2 s verfehlt → −1 bis −2 s | `paceAdjustment` +2, Hinweis `paceLowered` |
| 5.5 3 harte RPE ≤ 6 und Ziel erreicht → Retest | Hinweis `retestSuggested` |
| 5.5 nach leichterer Woche weiter hoher RPE → Pause vorschlagen | Hinweis `pauseSuggested` |
| 5.6 Tagesvorschlag | siehe Abschnitt 4 |

Tempo-Anpassung: `paceAdjustment` (s/500 m, positiv = langsamer) wirkt nur bei Fahrten aus dem Plan: Die App rechnet
die Ziele mit `best2k + 4 × paceAdjustment` (`SessionController.prepare`, HUD in `RowingView`). Die gespeicherte
Bestzeit bleibt unverändert.

Erledigt zählt eine Fahrt, wenn sie zu Ende gefahren wurde oder mindestens 60 % der geplanten Ruderzeit erreicht.

## 4. Tagesvorschlag mit Plan (`DailySuggestion.make(…, program:)`)

- Regel 0 nur, wenn der Plan schon über 7 Tage läuft und die letzte Fahrt über 7 Tage her ist (der Plan führt
  Einsteiger selbst; „weniger als 3 Fahrten“ gilt mit Plan nicht).
- Regel 1 gewinnt gegen eine harte oder mittlere Planeinheit (Begründung: „… heute locker; X rückt auf einen späteren
  Tag“). Die Einheit bleibt geplant und wird am Abend als verpasst behandelt, also nach 5.2 verschoben.
- Regel „plan“: Einheit des Tages, Begründung „Woche 5 von 12 · Einheit 2 von 3“ (bzw. „freiwillige Einheit“, „Ziel des
  Plans“, „Wiedereinstieg: …“).
- Regel „planRest“: kein Plantag → freiwillige Einheit der Woche ohne Tag, sonst Regeneration 20; Alternativen wie
  bisher (lockere Grundlage, „Frei rudern“).
- Regeln 2, 3 und 5 ruhen; Regel 4 ersetzt eine harte Planeinheit nur, wenn der Plan keinen eigenen Test hat.
- Heute schon gerudert: Vorschlag für morgen aus dem Plan (auch aus der Vorschau der nächsten Woche).
- Pausierter Plan: die gewohnten Regeln 0–5.

## 5. Schnittstellen

```swift
// Kit
TrainingProgramCatalog.loadBundled() / .decode(Data) / .program(id:) / .missingPlanIds(in:)
TrainingProgramScheduler.suggestedWeekdays(count:maxConsecutiveDays:), .check(weekdays:program:)
TrainingProgramEngine.start(program:startDate:weekdays:env:now:) throws -> ActiveTrainingProgram   // Fehler: ProgramStartProblem
TrainingProgramEngine.update(&state, rides:now:env:)
TrainingProgramEngine.pause(&state, now:calendar:) / .resume(&state, now:env:)
TrainingProgramEngine.swapToEasy(&state, sessionId:env:) / .restoreOriginal / .dismissNotice / .resolveReference
TrainingProgramEngine.agenda(state, now:env:) -> ProgramAgenda?   // für DailySuggestion
TrainingProgramEngine.preview(state, now:env:)                    // nächste Woche
TrainingProgramEngine.progress(state, env:) -> (week, weeks, doneShare)
TrainingProgramEngine.launchRef(state, planId:now:calendar:) -> ProgramSessionRef?
ProgramRide(session: TrainingSession)                             // Fahrt aus Sicht des Plans
DailySuggestion.make(…, program: ProgramAgenda?)                  // neue Regeln .plan / .planRest, .program-Kontext
// App
ProgramStore: start, pause, resume, end, swapToEasy, restoreOriginal, dismissNotice, answerReference, sync,
              agenda, preview, prepareLaunch, launchRef, paceAdjustment
```

`ProgramEnvironment` bündelt Katalog, Programme (plans.json), Kalender (`TrainingCalendar.swiss()`) und
2000-m-Referenz. Alle Funktionen sind deterministisch.

## 6. Oberfläche (Tab „Pläne“)

- **Liste**: oben der aktive Plan (Name, Woche x von n, Fortschritt, „Heute: …“), darunter Filter (Niveau als
  Segmente, Ziel/Kategorie als Chips, Länge als Menü, Suche) und Kacheln mit Wochen, Einheiten pro Woche,
  Kurzbeschreibung und Wochenbalken (Höhe = Minuten, hell = leichter/Tapering, orange = Zieleinheit).
- **Detail**: Ziel, Voraussetzungen, Wochenbalken, „So läuft der Plan“ (Regeln in Klartext), alle Wochen mit Fokus,
  Kennzeichen und Einheiten (Farbe nach Härte, Länge, Phasenbalken wie bei Programmen; antippen öffnet das Programm),
  Belege und Quellen. Unten „Plan starten“ bzw. „Zum aktiven Plan“.
- **Plan starten** (Sheet): sieben Tasten Mo–So mit Vorschlag nach Einheiten pro Woche, Startdatum (heute bis +60 Tage),
  Vorschau der ersten Woche, Hinweis, wenn ein laufender Plan ersetzt wird.
- **Aktiver Plan**: „Woche x von n“, Fokus, Kennzeichen (leichter, Tapering, Wiederholung, Tempo +s), Fortschritt,
  Wochenbalken mit der laufenden Woche; Hinweise (schliessbar) und Rückfrage zur Referenz; „Diese Woche“ Tag für Tag
  (Einheit oder Ruhetag, Status erledigt / offen / verschoben / entfallen, „Starten“, „Leichter“ bzw. „Wie geplant“);
  freiwillige Einheiten ohne Tag; „Nächste Woche“; „Plan pausieren“/„Fortsetzen“ und „Plan beenden“ (mit Rückfrage).
- **Startseite**: Kicker „Heute laut Plan“, „Ruhetag laut Plan“ oder „Heute: Ziel deines Plans“; Begründung mit Woche
  und Einheit.
- Wortwahl: verpasste Einheiten heissen in der App „entfallen“, nie „verpasst“ (docs/motivation/RECHERCHE.md, #4: keine
  Schuld-Sprache). Ruhetage werden als Teil des Plans gezeigt.

## 7. Tests und Prüfungen

- `cd App/RowCoachKit && swift test -j 4` (Linux und macOS); `tools/kit_check.sh` (Linux + Android-Bau).
- `TrainingProgramTests.swift`: Katalog (alle 17 Pläne, jede planId existiert, tolerantes Lesen, Filter, alle Pläne
  laufen mit perfekter Einhaltung bis zum Ende ohne Regelverstoss), Verteilung (Reihenfolge, harte Einheiten, Ruhetag
  Einsteiger, Masters 72 h über die Wochengrenze, Ersatz durch leichte Variante, zu wenige Tage, freiwillige),
  Engine (Erledigt per Bezug und per Programm, Wochenwechsel mit Abstand über die Grenze, Verschieben, nie zwei harte
  nachholen, `skip`, `shift` mit Verlängerung, Woche wiederholen, Zieleinheit, offene Pläne, Pausen 4/3/10/18/40/76
  Tage, automatische Pause, RPE-Regeln, Tests und Referenz, Paul's Law, Tausch, Codable), Tagesvorschlag (Plantag,
  Ruhetag, Regel 1 vor harter Planeinheit, Regeln 2–5 ruhen, morgen aus Plan, Vorschau, Pause).
- Daten: `python3 App/l10n/check_training_plans.py` (17 Pläne, 0 Fehler, 0 Warnungen),
  `python3 App/l10n/merge_plans.py --check`, `python3 App/l10n/build_catalog.py --check` (0 ohne Englisch).

## 8. Offen

- Erinnerung zur gewählten Zeit (Wenn-dann-Plan, docs/motivation/RECHERCHE.md #3) ist nicht Teil dieser Umsetzung;
  die Wunschtage liegen im Zustand bereit (`ActiveTrainingProgram.weekdays`).
- Wunschtage nachträglich ändern: heute nur über „Plan beenden“ und neu starten.
- Das 80/20-Ziel (Regel 3) erscheint mit Plan nicht als eigener Hinweis; die Pläne liegen rechnerisch bei 75–85 %
  Zeit in Zone 1–2, die Wochenkarte „Leicht und hart“ zeigt den Anteil weiter.
- Saison (`season: winter`) wird im Detail genannt, aber nicht nach Halbkugel empfohlen.
