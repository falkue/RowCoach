# Sprachcoach: adaptive Ansagen während des Trainings (Spezifikation, Stand 26.11.2026)

Wunsch (Falk, 26.11.): Ein Sprachcoach, der lobt, anfeuert, auf harte Phasen vorbereitet, durch lange harte Phasen
trägt und verhindert, dass man kurz vor dem Ende abflacht. Nicht stumpf nach Plan, sondern adaptiv nach den Werten
(Beispiel: Schlagzahl fällt kurz vor Ende einer harten Phase → extra Motivation „Beissen, das noch!“). Rein
algorithmisch (kein LLM auf dem Gerät), mit verschiedenen Szenarien und je Szenario mehreren „Tonkonserven“.

Heute: `CoachCueDetector` (RideEvaluation.swift) erkennt Phasenwechsel, Countdown, Halbzeit, Ziel; `CueText` formt
den Text, `SpeechCoach` spricht ihn mit AVSpeechSynthesizer. Der neue Coach ergänzt das und ersetzt es nicht ganz:
Phasen- und Countdown-Ansagen bleiben (sie sind Information), der Coach fügt Motivation und Korrektur hinzu und
koordiniert alles über einen gemeinsamen Sprech-Planer.

## Bausteine
1. **RowCoachKit/Coach/** (nur Foundation, portabel für Android):
   - `CoachInput`: je Tick (ca. 1 Hz) Planstand (`PlanStatus`: Phase, Art, Index, Zeit/Distanz in der Phase, Rest bis
     Wechsel, Fortschritt gesamt, letzte Belastungsphase?), Messwerte (Schlagzahl, Tempo s/500 m, Watt, Puls,
     Pulszone; geglättet), Ziele der Phase (Schlagzahl-, Tempo-Bereich, Pulszone), Zeit seit Fahrtbeginn.
     Auch für freies Rudern (ohne Plan: Strecke, Rest, Pace-Line-Abstand).
   - `CoachState`: Kennzahlen je Phase (Basiswert aus den ersten 30–45 s einer Belastungsphase, laufende Mittel,
     Trend der letzten 10–20 s), je Intervall (Mitteltempo, Mittelschlagzahl) für Vergleiche zwischen Intervallen.
   - `CoachEngine`: Regeln → Kandidaten (`CoachEvent`: Szenario, Priorität, Variablen), dann **Planer**:
     - globaler Mindestabstand zwischen zwei Ansagen (Standard 12 s; Countdown/Phasenwechsel dürfen näher),
     - Abklingzeit je Szenario (z. B. Lob ≥ 90 s, Korrektur ≥ 30 s),
     - Hysterese: Bedingung muss N s anhalten (z. B. Abflachen 4 s), sonst kein Auslösen,
     - Eskalation: erste Ansage mild, wiederholt sich die Lage, die stärkere Stufe,
     - Ruhezonen: keine Motivation in den letzten 4 s vor einem Wechsel (dort laufen die Töne 3-2-1), nicht während
       einer laufenden Ansage, nicht im Einrudern (ausser Info),
     - Budget nach Einstellung „Häufigkeit“ (wenig / normal / viel: max. Ansagen pro Minute in Belastung,
       z. B. 1 / 2 / 3; in Grundlage deutlich weniger, z. B. alle 3–6 min),
     - Priorität: Sicherheit/Info > Phasenwechsel > Korrektur am Ende > Vorbereitung > Lob > Technik.
   - `CoachPhraseBank`: lädt `coach_phrases.json`, wählt eine Variante je Szenario/Stil/Sprache/Stufe zufällig ohne
     die letzten k (seedbarer Zufall für Tests), setzt Variablen ein.
   - Ausgabe `CoachUtterance`: Text, `phraseId` (für Audiodatei), Szenario, Priorität, unterbrechend ja/nein.
2. **App (iOS-Hülle)**: `TrainingCue` füttert den Coach je Tick und gibt Utterances an `SpeechCoach`.
   `SpeechCoach` spielt eine Audiodatei `Coach/<sprache>/<phraseId>.m4a`, wenn vorhanden („Tonkonserve“), sonst
   AVSpeechSynthesizer. Einstellungen → Training: „Coach“ (aus / sachlich / motivierend / Cox), „Häufigkeit“.
   Der bisherige Schalter „Gesprochene Ansagen“ bleibt (aus = alles stumm).

## Szenarien (ids fest; Stil-Varianten in coach_phrases.json)
Planbasiert (Struktur):
- `prep_hard` – 20–30 s vor einer Belastungsphase mit Pulszone ≥ 4 oder Tempo ≤ 2k+5: vorbereiten („Gleich geht’s
  los: 4 Minuten, Schlagzahl 26 bis 28. Durchatmen, Griff fest.“). Dynamisch (Variablen).
- `go` – Start einer Belastungsphase (kurz, energisch: „Los!“, „Jetzt!“). Ergänzt die Phasenansage.
- `first_strokes` – 10–15 s nach Start: Rhythmus finden, nicht überziehen.
- `phase_half` – Hälfte einer Belastungsphase ≥ 90 s („Halbzeit, du liegst gut“ / „Halbzeit, dranbleiben“ je
  nach Zielerfüllung).
- `last_quarter` – letztes Viertel einer Belastungsphase ≥ 2 min.
- `last_30s`, `last_10s` – bzw. bei Distanzphasen `last_250m`, `last_100m`; nur bei harten Phasen.
- `last_interval` – Beginn des letzten Intervalls („Das letzte! Alles, was du hast.“).
- `interval_done` – Ende einer Belastungsphase: Lob, ggf. mit Vergleich zum vorigen Intervall.
- `rest_recover` – Anfang einer Pause: atmen, locker, trinken; `rest_prepare` – 15–20 s vor Ende der Pause.
- `workout_half`, `workout_final` (letzte 2 min / 500 m des ganzen Trainings), `workout_done` (Abschluss, Lob).
Adaptiv (Werte):
- `fade_end` – im letzten Drittel (bzw. letzten 60 s / 300 m) einer harten Phase fällt die Schlagzahl ≥ 2 unter das
  Ziel bzw. den Phasen-Basiswert, oder das Tempo wird ≥ 2–3 s/500 m langsamer als das Phasenmittel, ≥ 4 s anhaltend.
  Stufe 1 „Halt die Schlagzahl!“, Stufe 2 „Beissen! Das noch!“. Höchste Priorität unter den Motivationen.
- `fade_mid` – dasselbe in der Mitte einer Phase (milder, korrigierend).
- `rate_low` / `rate_high` – Schlagzahl ausserhalb des Zielbereichs ≥ 6 s (bei hoch: „ruhiger, mehr Druck pro
  Schlag“; bei niedrig: „Schlagzahl hoch“). In Grundlage nur bei deutlicher Abweichung (≥ 3).
- `pace_on_target` – ≥ 45 s im Zieltempo und in der Schlagzahl: Lob.
- `pace_too_fast_early` – erste 25 % einer langen Phase (≥ 3 min / ≥ 1000 m) ≥ 3 s schneller als Ziel: einteilen.
- `pace_slow` – ≥ 15 s langsamer als Zielbereich (mitten in der Phase): anfeuern.
- `strong_finish` – letzte 20 % einer Phase schneller als Phasenmittel: Lob.
- `consistent` – Intervall n im Tempo innerhalb ±1,5 s von n−1 (ab Intervall 2): Lob; `slower_than_prev` – ≥ 3 s
  langsamer: Motivation fürs nächste.
- `best_interval` – schnellstes Intervall der Einheit (ab 3 Intervallen).
- `hr_high_easy` – in Grundlage/Regeneration Puls ≥ 1 Zone über Ziel ≥ 60 s: ruhiger.
- `stopped` – in einer Belastungsphase 5 s keine Schläge: „Weiter, dranbleiben!“ (nicht in Pausen).
- `rest_too_hard` – in einer Pause deutlich zu hart gerudert: erholen.
- `technique` – in langen ruhigen Phasen selten (alle 4–7 min): Technikimpuls (Beine–Körper–Arme, lange Rollphase,
  Schultern locker, Griff ohne Hast). Nicht in harten Phasen.
- `free_half`, `free_500_left`, `paceline_ahead`, `paceline_behind` – freies Rudern.
Nach der Fahrt (Auswertung, docs/motivation/UMSETZUNG.md):
- `post_ride` – ein Satz in der Zusammenfassung direkt nach der Fahrt, einmal, nur statische Varianten (Tonkonserven).
  Stufe 1: Anstrengung und Dabeisein würdigen; Stufe 2: nach einem Rekord oder Meilenstein („Was heute gut war“).

## Stile
- `calm` (sachlich, ruhig, informativ), `motivating` (positiv, ermutigend, Standard), `cox` (Steuermann-Stil: kurz,
  laut, fordernd, Rudersprache). Jede Phrase hat de und en. Pro Szenario × Stil × Sprache mindestens 6 Varianten
  (Lob und Anfeuern eher 10–15), Stufe 2 bei Eskalationsszenarien separat.
- Kurz: Motivationsrufe 1–6 Wörter; Vorbereitung bis ~15 Wörter. Keine Beleidigungen, kein Druck auf Schmerz
  („Schmerz ist Schwäche…“) – fordernd ja, abwertend nie. Duzen.

## Format `App/RowCoach/Resources/coach_phrases.json`
```json
{"version": 1,
 "scenarios": {
   "fade_end": {
     "dynamic": false,
     "levels": {
       "1": {"motivating": {"de": ["Halt die Schlagzahl!", "…"], "en": ["Hold the rate!", "…"]},
             "calm": {"de": […], "en": […]}, "cox": {"de": […], "en": […]}},
       "2": {…}}},
   "prep_hard": {
     "dynamic": true,
     "variables": ["duration", "distance", "spm_min", "spm_max", "n", "of"],
     "levels": {"1": {"motivating": {"de": ["Gleich kommt Intervall {n}: {duration}, Schlagzahl {spm_min} bis {spm_max}."]}}}}
 }}
```
- `phraseId` = `<szenario>.<stufe>.<stil>.<index>` (stabil; neue Varianten nur anhängen). Statische Phrasen
  (ohne Variablen) lassen sich als Audiodatei aufnehmen; dynamische spricht immer die Systemstimme.
- Variablen: `{n}`, `{of}` (Intervall n von of), `{duration}` (gesprochen, z. B. „4 Minuten“), `{distance}`
  („500 Meter“), `{spm}`, `{spm_min}`, `{spm_max}`, `{split}` („2 Minuten 05“), `{delta}` („3 Sekunden“).
  Die Engine liefert die Werte als gesprochene Texte in der App-Sprache.

## Prüfen
- Kit-Tests mit synthetischen Fahrten: Abflachen am Ende löst `fade_end` genau einmal aus (Stufe 2 nur bei
  anhaltender Lage), stabiles Rudern löst keine Korrekturen aus, Abstand und Budget werden eingehalten, keine
  Ansage in den letzten 4 s vor einem Wechsel, Grundlage 60 min erzeugt nicht mehr als ~1 Motivation je 3 min.
- Wiedergabe gegen echte gespeicherte Fahrten (WorkoutRecord-Samples) als Test/Werkzeug: Ansagen je Minute zählen.
- `tools/kit_check.sh` grün (Linux + Android).

## Umsetzung (Stand 26.11.2026, nachjustiert nach docs/coach/RECHERCHE.md)

### Dateien
- Kit (`App/RowCoachKit/Sources/RowCoachKit/Coach/`, nur Foundation):
  `CoachSettings.swift` (Stil `off/calm/motivating/cox`, Häufigkeit `low/normal/high`, Sprache),
  `CoachScenario.swift` (Szenario-ids, Gruppen, Priorität, Budget-Ausnahmen), `CoachConfig.swift` (**alle**
  Schwellen, Fenster, Abstände; hier Werte aus RECHERCHE.md nachziehen), `CoachInput.swift` (Eingang je Tick),
  `CoachState.swift` (Glättung, Basiswert, Phasenmittel, kurzes Mittel, Trend, letzter Schlag, Intervallergebnisse),
  `CoachEngine.swift` (Regeln + Planer, plant auch die Info-Ansagen von `CoachCueDetector`),
  `CoachPhraseBank.swift` (Laden, Auswahl ohne Wiederholung der letzten k, seedbarer Zufall `SeededRandom`,
  Variablen), `CoachSpoken.swift` (gesprochene Zahlen/Zeiten de/en), `CoachUtterance.swift` (Ausgang),
  `CoachReplay.swift` (Wiedergabe gespeicherter Fahrten).
- Tests: `Tests/RowCoachKitTests/CoachTests.swift` (synthetische Fahrten, Phrasen, Wiedergabe, Prüfung der echten
  `coach_phrases.json`).
- App: `Views/TrainingCue.swift` (`coachTick`, Einstellungsschlüssel `training.coachStyle`/`training.coachFrequency`,
  `CoachPhrases.bank`), `Views/RowingView.swift` (`feedCoach()`: bei jeder Änderung des Planstands, beim freien
  Rudern bei jeder Distanzänderung und jede Sekunde), `Session/SpeechCoach.swift` (Tonkonserve oder Systemstimme,
  Unterbrechung nach Priorität), `Views/SettingsView.swift` (Picker „Coach“, „Häufigkeit“), `project.yml`
  (Ordnerreferenz `RowCoach/Resources/Coach`).

### Ablauf
1. Je Tick: `CoachState` nimmt die Messwerte auf (nur gerudert zählt; „Schlag“ = Schlagzähler gestiegen, ohne
   Zähler Schlagzahl > 0). Phasenwechsel setzt die Phasenwerte zurück und hält das Ergebnis einer Belastung fest.
2. `CoachCueDetector` liefert die Info-Ansagen; sie kommen sofort und haben Vorrang. Wo ein Szenario passt, spricht
   der Coach stattdessen die Phrase: Start einer Belastung → `go` (letztes Intervall → `last_interval`), Halbzeit →
   `workout_half` bzw. `free_half`, „Noch 500 Meter“ → `free_500_left`, Ziel → `workout_done`, Countdown am Ende
   einer harten Belastung vor Pause/Ausrudern/Ende → `last_10s` (abschaltbar: `last10ReplacesCountdown`; nur solange
   jede `last_10s`-Variante die Restzeit nennt – ein Test prüft das – und das Budget `endPushPerMinute` reicht).
   Die Töne 3-2-1 bleiben immer. Fehlt die Phrase oder ist der Stil `off`, bleibt die Info-Ansage (Text wie bisher
   aus `CueText`).
3. Gab es keine Info-Ansage, werten die Regeln alle Szenarien aus (Hysterese läuft immer weiter), der Planer filtert
   und nimmt den Kandidaten mit der höchsten Priorität, für den es eine Phrase gibt (sonst Ersatzszenario).

### Planer (Standardwerte `CoachConfig`)
| Regel | Wert |
|---|---|
| Priorität | Info 100 > `stopped` 95 > Phasenwechsel-Rufe 90 > Ende harter Phase (`last_quarter`, `fade_end`, `last_30s`, `last_250m`, `last_100m`, `workout_final`) 70 > Korrektur 60 > Vorbereitung 50 > Lob 40 > Technik 20 |
| Mindestabstand | 12 s nach jeder Ansage (Info und Phasenwechsel-Rufe ausgenommen); nie während einer laufenden Ansage (Dauer geschätzt: Wörter / 2,6 + 0,5 s, Info 3,5 s, oder `isSpeaking` der App) |
| Ruhezonen | letzte 4 s vor einem Wechsel nur Info; keine Ansage, die in den Countdown (10 s) hineinliefe; im Einrudern nur `prep_hard`/`rest_prepare` |
| Abklingzeit | Lob 90 s, Korrektur 30 s, Ende harter Phase 20 s, Vorbereitung 30 s, Technik 240 s, `stopped` 15 s; `hr_high_easy`, `paceline_*` 120 s, `rest_too_hard` 45 s; Lob in Grundlage/frei 360 s |
| Budget | in Belastung und Pause höchstens 1/2/3 Ansagen je 60 s (wenig/normal/viel); in Grundlage und beim freien Rudern Mindestabstand 360/180/120 s (Technikimpulse zählen mit). Ausgenommen: Info, Phasenwechsel-Rufe, `stopped`, Ende harter Phase, `prep_hard`, `rest_prepare`, Intervall-Rückmeldung |
| Budget Ende harter Phase | `endPushPerMinute` 2/3/4 je 60 s für `last_quarter`, `fade_end`, `last_30s`, `last_250m`, `last_100m`, `last_10s`, `workout_final`; in den letzten 60 s / 300 m einer harten Phase zählt jede Coach-Ansage ausser `stopped` mit. Ist es erschöpft, kommt statt `last_10s` der normale Countdown. `workout_final` und `last_30s` nie im selben 60-s-Fenster (die erste gewinnt); `fade_end` ersetzt `last_30s`, wenn beide innerhalb von 12 s fällig wären |
| Kurze Rufe | in den letzten 60 s / 300 m harter Phasen bevorzugt statische Varianten mit ≤ 4 Wörtern (`endZoneMaxWords`) |
| Korrekturen | dasselbe Szenario höchstens 2 × je Phase (`maxCorrectionsPerPhase`); nie zwei Korrekturen direkt hintereinander ohne Lob oder Info dazwischen |
| Auswahl | die letzten 5 Varianten je Szenario/Stufe/Stil/Sprache werden nicht wiederholt (`phraseHistory`) |
| Eskalation | `fade_end`: Stufe 1, Stufe 2 frühestens 12 s später (`escalationDelay`) bei anhaltender oder wiederkehrender Lage und nur bei ≥ 15 s Rest, dann Schluss in der Phase; `fade_mid`, `pace_slow`, `rate_low`, `rate_high`: zweites Mal in der Phase Stufe 2 (höchstens 2 je Phase); `stopped`: Stufe 1 nach 5 s, Stufe 2 nach weiteren 12 s, danach alle 60 s |
| Stufe nach Lage | `phase_half` 1 = im Ziel, 2 = hinter dem Ziel; `interval_done` 1 = neutral, 2 = schneller als das vorige Intervall (mit `{delta}`) |

### Regeln je Szenario
„Belastung“ = Phasenart `work`; „hart“ = Belastung mit `intensity() == .hard` (Zone ≥ 4 oder Tempo ≤ 2k + 5 s);
„Grundlage“ = Phase (ausser Pause) mit `intensity() == .easy`. Anlauf: 15 s nach Phasenbeginn keine Korrekturen.
Kurzes Mittel = letzte 6 s; Basiswert = Mittel 10–40 s nach Phasenbeginn; Phasenmittel = ab 10 s bis 10 s vor jetzt.

| Szenario | Auslöser |
|---|---|
| `prep_hard` | 15–30 s vor einer harten Belastung (Ersatz `rest_prepare`), Werte der kommenden Phase |
| `rest_prepare` | Pause ≥ 45 s, 14–22 s vor einer nicht harten Belastung |
| `go` / `last_interval` | Start einer Belastung (ersetzt „Los!“) |
| `first_strokes` | Belastung (nicht leicht) ≥ 60 s, 10–20 s nach Start |
| `phase_half` | Belastung ≥ 90 s, 50–60 % |
| `last_quarter` | Belastung (nicht leicht) ≥ 2 min, 75–85 % (Gruppe „Ende harter Phase“) |
| `last_30s` | harte Zeitphase ≥ 60 s, Rest 31–18 s; entfällt, wenn `fade_end` in den 12 s davor kam |
| `last_10s` | Countdown einer harten Belastung vor Pause/Ausrudern/Ende, wenn das Budget reicht |
| `last_250m`, `last_100m` | harte Distanzphase ≥ 500 m bzw. ≥ 300 m, Rest 251–180 m bzw. 101–60 m |
| `interval_done`, `consistent`, `slower_than_prev`, `best_interval` | 2–30 s nach Ende einer Belastung; Vergleich mit dem vorigen Intervall ähnlicher Länge (≤ 1,25 ×): ±1,5 s `consistent`, ≥ 3 s langsamer `slower_than_prev`, schnellstes (≥ 0,5 s) ab 3 Intervallen `best_interval`, sonst schneller → `interval_done` Stufe 2 |
| `rest_recover` | Pause ≥ 60 s, 12–40 s nach Beginn, nach der Intervall-Rückmeldung |
| `workout_half`, `workout_done` | statt der Info-Ansagen Halbzeit und Ziel |
| `workout_final` | in einer Belastung, Rest des Trainings ≤ 2 min, Training ≥ 10 min, einmal |
| `fade_end` | harte Belastung, letztes Drittel oder letzte 60 s / 300 m: kurzes Mittel Schlagzahl ≤ Basiswert − 2 oder ≤ Zielminimum − 2, oder Tempo ≥ Phasenmittel + max(2,5 s; 2 % des Phasenmittels), 4 s anhaltend |
| `fade_mid` | dasselbe ab 25 % bis vor das letzte Drittel (Belastung mittel/hart) |
| `rate_low` / `rate_high` | Schlagzahl ≥ 1 (Grundlage ≥ 3) ausserhalb des Ziels, 8 s (harte Phasen 6 s); nicht am Ende harter Phasen |
| `pace_on_target` | im Ziel (Tempo- und/oder Schlagzahlziel, Puls nicht über der Zielzone), 45 s; danach erneut 45 s nötig |
| `pace_too_fast_early` | Phase ≥ 3 min / ≥ 1000 m, erste 25 %, ≥ 3 s schneller als das Ziel, 8 s |
| `pace_slow` | ≥ 2 s langsamer als der Zielbereich, 20 s (nicht am Ende harter Phasen) |
| `strong_finish` | Belastung ≥ 60 s, letzte 20 %, kurzes Mittel ≥ 1 s schneller als Phasenmittel, 5 s, einmal |
| `hr_high_easy` | Grundlage (nicht Einrudern) mit Zielzone, Puls ≥ 1 Zone darüber, 60 s |
| `stopped` | Belastung, 5 s kein Schlag (nie in Pausen) |
| `rest_too_hard` | Pause ab 10 s: Tempo ≤ 2k + 20 s oder Schlagzahl ≥ 26, 10 s |
| `technique` | Phase ≥ 8 min, nicht hart, nicht Einrudern/Pause: erster Impuls 3–4 min nach Beginn, dann alle 4–7 min (Zufall); frei ab 2000 m Strecke |
| `paceline_ahead` / `_behind` | freies Rudern: ≥ 10 m vor/hinter der Linie, 20 s |

### Variablen
Die Engine liefert je Szenario die Werte nach docs/coach/PHRASES.md (gesprochen über `CoachSpoken`: „4 Minuten“,
„1 Minute 30“, „500 Meter“, Tempo „2 Minuten 5“, `{delta}` als Betrag „3 Sekunden“). Eine dynamische Variante wird nur
gewählt, wenn alle ihre Platzhalter Werte haben; sonst eine statische Variante desselben Szenarios.

### Tonkonserven ergänzen
- `phraseId` = `<szenario>.<stufe>.<stil>.<index>`, Index = Position (ab 0) in der Liste der Sprache.
- Statische Phrasen rendert `tools/coach_audio/render_coach.py` nach `App/RowCoach/Resources/Coach/<de|en>/<phraseId>.m4a`
  (AAC mono). Die Ordnerreferenz in `project.yml` übernimmt den Ordner unverändert als `Coach/…` ins Bundle (danach
  `xcodegen generate`); fehlt er, baut die App trotzdem.
- `SpeechCoach` spielt die Datei mit AVAudioPlayer, wenn es sie gibt und die Phrase statisch ist, sonst spricht die
  Systemstimme. Neue Varianten nur anhängen, nie umsortieren (sonst passen die Dateien nicht mehr).

### Parameter einstellen
Werte in `CoachConfig` ändern, dann `swift test --filter Coach`. Wiedergabe einer echten Fahrt (WorkoutRecord-JSON,
z. B. aus dem Export): `ROWCOACH_REPLAY=/pfad/fahrt.json [ROWCOACH_PLAN=<id>] [ROWCOACH_STYLE=cox]
[ROWCOACH_FREQUENCY=high] swift test --filter testReplayCountsPerMinute` druckt Ansagen je Minute, Anzahl je
Szenario und das Protokoll (mit `ROWCOACH_REPLAY_LOG=1` auch für die eingebaute Probe).
