# Motivation: Umsetzung (Stand 26.11.2026)

Grundlage: `RECHERCHE.md` (Top 5 + Querschnittsregeln, Ton und Ethik, „Nicht bauen“) und
`docs/design/startscreen-gamification.md`. Gebaut wurden die Features 1–5, dazu 6 (Erholungs-Wächter) und 7
(Wochenziel flexibel mit Pause) als Regeln. Alles offline, ohne Konto, jede Funktion abschaltbar.

## Aufteilung
Logik in RowCoachKit (nur Foundation, Tests unter Linux in `MotivationTests.swift`), App-Hülle schlank:

| Feature | Kit (`Sources/RowCoachKit/Motivation/…`) | App (`RowCoach/Views/Motivation/…` und Einbindung) |
|---|---|---|
| 1 Was heute gut war + `post_ride` | `RideHighlights.swift` (Regeln, Rangfolge, max. 3; `PostRideCoach`) | `RideHighlightsCard` oben in `SummaryView`; Coach-Satz einmal direkt nach der Fahrt |
| 2 Wann ruderst du? | `Reminders.swift` (`RowingIntention`, `ReminderPlanner`) | `RowingIntentionView`, `ReminderService` (UNUserNotificationCenter) |
| 3 Sanfter Wiedereinstieg | `Reentry.swift`, Regel `reentry` in `DailySuggestion` (`wishDays`) | Vorschlagskarte zeigt Regel und Begründung wie bisher |
| 4 Bestmarken + Bestfahrt | `BestEfforts.swift` (`BestEffortFinder`, `RideDigest`, `PersonalRecords`) | `RecordsView` (Verlauf → „Bestmarken und Meilensteine“), `GhostRaceButton` auf der Streckenseite, `RowingView.ghostRace` |
| 5 Meilensteine | `Milestones.swift` | Karte in der Auswertung, nächste Schwelle als Zeile auf der Startseite, Liste in `RecordsView` |
| 6 Erholungs-Wächter | `RecoveryGuard.swift` | schaltet Bestfahrt-Knopf und Meilenstein-Hinweise ab, Ruhetag-Lob auf der Startseite |
| 7 Wochenziel mit Pause | `WeeklyGoal.swift` (`WeeklyGoal`, `GoalPause`, `WeeklyGoalTracker`, `GoalReview`), `TrainingStats(goal:pauses:)` | `WeeklyGoalSettingsView`, Texte der Serie (`StreakText`), Vorschlag „etwas mehr/weniger?“ auf der Startseite |
| Startseite | `HomeMotivation.swift` (eine Zeile, Vorrang: Ruhetag-Lob, Zielvorschlag, Wenn-dann, Meilenstein) | `HomeMotivationLine` unter den Hinweisen in `HomeView` |

`HomeModel` liest jede Fahrt einmal im Hintergrund als `RideDigest` (Bestmarken aus den Samples, Intervalltempi) und
rechnet bei jedem Neurechnen Kennzahlen, Vorschlag, `HomeMotivation`, Rekorde, Meilensteine und plant die
Erinnerungen neu. Einstellungen in `MotivationSettings` (UserDefaults, Schlüssel `motivation.*`).

## Regeln (Kurzfassung; Einzelheiten in den Doc-Kommentaren)
- **Was heute gut war**: Bestzeit Strecke › Bestmarken Distanz/Zeit › Meilenstein › schnellstes Intervall des
  Programms › gleichmässige Intervalle (±1,5 s) › wieder da nach ≥ 7 Tagen › Puls ≥ 4 tiefer bei gleichem Tempo als
  vor 4–8 Wochen › Wochenziel erreicht › ≥ 85 % bis Zone 2 › locker nach hart. Sonst Anstrengung (≥ 7) oder
  Dabeisein. Erste Messung einer Distanz ist kein Rekord. Simulator nie.
- **Bestmarken**: 500, 1000, 2000, 5000, 6000, 10 000 m, HM, M, 30 und 60 min, schnellstes Teilstück per
  Zwei-Zeiger-Suche über Uhrzeit (Pausen zählen mit, daher keine 2000-m-Rekorde aus Intervallen), PM5-Neustart trennt
  Abschnitte, schneller als 65 s/500 m gilt als Messfehler.
- **Bestfahrt**: beste ganze freie Fahrt der Strecke als Geisterboot (`GhostRaceTransport`, Zeit ab erstem Schlag,
  Start mit dem ersten eigenen Schlag wie `-demoRace`). Nicht angeboten, solange der Erholungs-Wächter gilt.
- **Wiedereinstieg**: Gestern Wunschtag ohne Fahrt, heute noch keine → ohne Plan Regel `reentry` (nach Regel 1)
  mit der ersten vorhandenen kurzen Einheit aus `ReentryRule.shortPlans`; mit Plan bleibt die Planeinheit, die kurze
  wird erste Alternative. Wunschtage: Plantage (aktiver Plan, „Tage aus dem Plan“) bzw. eigene Tage; in einer Pause
  keine. **Offen**: Es gibt keine 15-min-Grundlage im Katalog; bis `grundlage-locker-15` existiert, gilt
  „Einstieg 1-2-3-2-1“ (17 min).
- **Erinnerung**: standardmässig aus, Berechtigung erst beim Einschalten; höchstens 1/Tag, nur an Wunschtagen, nicht
  an Plan-Ruhetagen, nicht in einer Pause, nicht wenn heute schon gerudert, eine Woche Ruhe nach zwei unbeachteten.
  Text „Dein Ruderplan für heute“ mit Anlass und (heute/morgen) dem Programm des Vorschlags.
- **Meilensteine**: Lebens-km 100…25 000 (1000 km = Million Meter), Fahrten 10…1000, je Gewässer 25…1000 km
  (Gewässer = Teil von `region` vor dem Komma), Seen-Pass je Land ab 2 Strecken. Startseite nur, wenn in 1–2 Fahrten
  erreichbar und kein Erholungsbedarf.
- **Erholungs-Wächter**: hart < 48 h (Masters-Plan 72 h), mittel < 48 h, Anstrengung ≥ 9 < 48 h, lockere Fahrten
  zu hart empfunden (3 × ≥ 7 bzw. 2 × ≥ 9), Hinweis des Plans (Erholung/Pause), Plan-Ruhetag.
- **Wochenziel**: Fahrten 1–6 oder Minuten 30–600; Pausentage senken das Ziel der Woche anteilig, bei 0 ist die
  Woche eingefroren (zählt nicht, bricht nichts, Joker bleibt). Pause 1–28 Tage, vorzeitig beendbar. Vorschlag nach
  4 erreichten Wochen (+1 Fahrt/+30 min) bzw. 3 verfehlten (−1/−30), nicht vor 4 Wochen mit dem Ziel, nach
  „Passt so“ 4 Wochen Ruhe.

## Ton
Keine Verlust-Sprache, nie „verpasst“, Pausen neutral, Lob nur für Wahres, keine Punkte. Abschalten in
Einstellungen → Motivation („Was heute gut war“, „Meilensteine“, „Wann ruderst du?“ mit Erinnerung, Wochenziel und
Pause). Das Wochenziel ist aus „Training“ nach „Motivation“ umgezogen.

## Coach-Satz `post_ride`
Neues Szenario in `coach_phrases.json` (SPEC.md ergänzt, `check_coach_phrases.py` grün), nur statische Varianten:
Stufe 1 (Dabeisein/Anstrengung) je 12 calm/motivating, 10 cox; Stufe 2 (Rekord/Meilenstein) je 8 calm/motivating,
6 cox; de und en. Tonkonserven: `python3 tools/coach_audio/render_coach.py` rendert die neuen phraseIds
`post_ride.<1|2>.<stil>.<index>`.

## Auf dem Mac prüfen (stumm testen)
1. Bauen; Einstellungen → Motivation: Schalter, „Wann ruderst du?“ (Erinnerung an → Berechtigungsdialog),
   Wochenziel Minuten, Pause starten/beenden; Startseite zeigt „Pause bis …“ in der Wochenkarte.
2. Simulatorfahrt (Debug zählt für Pläne; für Motivation zählt der Simulator nie – mit `-seedDemoHistory 1`
   testen): Auswertung zeigt „Was heute gut war“; mit Ansagen an spricht der Coach einen Satz.
3. Streckenseite einer Strecke mit ganzer freier Fahrt: „Gegen meine Bestfahrt“ startet ein Rennen gegen das
   Geisterboot; nach harter Fahrt (Erholung) ist der Knopf weg.
4. Verlauf → „Bestmarken und Meilensteine“.
5. Wunschtage setzen, einen Tag auslassen → am nächsten Tag Vorschlag „Kurz und locker: 17 min zählen genauso.“
