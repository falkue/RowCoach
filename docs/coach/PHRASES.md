# Sprachcoach: Spruchsammlung („Tonkonserven“) – Festlegungen (Stand 26.11.2026)

Datei: `App/RowCoach/Resources/coach_phrases.json` (Format nach `docs/coach/SPEC.md`).
Prüfung: `python3 App/l10n/check_coach_phrases.py`. Das Skript muss vor jedem Commit „OK“ melden.

## Bedeutung der Stufen je Szenario
| Szenario | Stufe "1" | Stufe "2" |
|---|---|---|
| `fade_end`, `fade_mid`, `pace_slow`, `stopped`, `rate_low`, `rate_high` | erste, milde Ansage | Eskalation, wenn die Lage anhält (deutlich stärker) |
| `phase_half` | Halbzeit **im Ziel** (Tempo/Schlagzahl im Zielbereich) | Halbzeit **hinter dem Ziel** |
| `interval_done` | Ende der Belastung, neutral (Lob, optional mit `{split}`, `{n}`, `{of}`) | Ende der Belastung, **schneller als das vorige Intervall** (optional `{delta}` = Zeitgewinn) |
| alle anderen | einzige Stufe | – |

Für die Engine heisst das: Bei `phase_half` und `interval_done` ist Stufe 2 eine **Lage**, keine Eskalation. Die
Engine wählt die Stufe dort nach dem Zustand, nicht nach Wiederholung. Fehlt eine Stufe, nimmt `CoachPhraseBank`
die nächstniedrigere. Ist ein Intervall langsamer als das vorige, gilt `slower_than_prev`. Liegt es innerhalb von
±1,5 s, gilt `consistent`. In beiden Fällen bleibt `interval_done` Stufe 1 die Abschlussansage.

## Variablen je Szenario
Nur die Variablen aus der SPEC kommen vor: `{n} {of} {duration} {distance} {spm} {spm_min} {spm_max} {split} {delta}`.
Eine Variante mit Variablen wird nur gewählt, wenn die Engine **alle** ihre Variablen liefert. Sonst wählt die Engine
statische Varianten. Jede Liste eines dynamischen Szenarios hat deshalb mindestens 6 statische Varianten (aufnehmbar).

| Szenario | Variablen | Bedeutung |
|---|---|---|
| `prep_hard` | duration, distance, spm_min, spm_max, n, of, split | kommende Belastung; Zeitphase → `{duration}`, Distanzphase → `{distance}`; `{split}` = Zieltempo |
| `last_interval` | n, of, duration, distance | Länge des letzten Intervalls |
| `interval_done` | n, of, split, delta | `{split}` = Mitteltempo des Intervalls; `{delta}` (nur Stufe 2) = schneller als das vorige |
| `rest_recover` | duration | Länge der Pause |
| `rest_prepare` | n, of, duration, distance, spm_min, spm_max | das **nächste** Intervall |
| `workout_done` | duration, distance, n | Gesamtzeit, Gesamtstrecke, Anzahl Intervalle |
| `rate_low`, `rate_high` | spm, spm_min, spm_max | aktuelle Schlagzahl und Zielbereich |
| `pace_on_target` | split | aktuelles Tempo |
| `pace_too_fast_early` | delta, split | `{delta}` = um so viel schneller als das Ziel; `{split}` = Zieltempo |
| `pace_slow` | delta, split | `{delta}` = um so viel langsamer als das Ziel; `{split}` = Zieltempo |
| `consistent` | n, split | Intervallnummer, Mitteltempo |
| `slower_than_prev` | delta, n | `{delta}` = um so viel langsamer als das vorige Intervall |
| `best_interval` | n, split | Nummer und Mitteltempo des besten Intervalls |
| `free_half` | distance, duration | **Rest** bis zum Ziel |
| `paceline_ahead`, `paceline_behind` | distance, delta | Abstand zur Tempo-Linie in Metern (`{distance}`) oder Sekunden (`{delta}`) |

`{delta}` wird als Betrag ohne Vorzeichen gesprochen („3 Sekunden“). Die Richtung steckt im Satz.

## Mindestanzahlen (geprüft)
- Jede Liste (Szenario × Stufe × Stil × Sprache): mindestens 6 Varianten.
- Mindestens 10 Varianten (Stufe 1, bei `fade_end` auch Stufe 2) für Lob, Anfeuern, Countdown und Start: `go`,
  `last_30s`, `last_10s`, `fade_end`, `interval_done`, `pace_on_target`, `strong_finish`, `pace_slow`,
  `consistent`, `best_interval`, `workout_done`. Viele weitere Listen haben ebenfalls 10 Varianten (z. B.
  `last_quarter`, `last_250m`, `last_100m`, `last_interval` in motivating/cox).

## Sprachregeln
- **Rufe** (Szenarien `go`, `last_*`, `fade_*`, `rate_*`, `pace_slow`, `pace_on_target`, `strong_finish`,
  `stopped`, `phase_half`, `last_quarter`, `workout_half`, `free_500_left`): höchstens 6 Wörter. Ausnahme:
  Stufe 2 im Stil calm darf 8 Wörter haben. Alle anderen Szenarien (Vorbereitung, Pause, Information, Technik):
  höchstens 15 Wörter. `{n} {of} {spm*}` zählen als ein Wort, die übrigen Variablen als zwei.
- Duzen. Deutsch in Schweizer Schreibung (ss, kein ß), allgemein verständliches Hochdeutsch.
- **Deutsch ist eigenständig geschrieben, nicht aus dem Englischen übersetzt** (Falk, 26.11.2026). Gemeint sind
  Rufe, wie sie ein deutschsprachiger Trainer am Steg oder ein Steuermann im Boot wirklich ruft: „Durchziehen!“,
  „Dranbleiben!“, „Halt die Frequenz!“, „Jetzt nochmal alles!“, „Gleich hast du's!“, „Nicht nachlassen!“,
  „Beine, Beine!“, „Hände schnell weg!“, „Frequenz zwei hoch!“. Lehnübersetzungen sind ausgeschlossen, zum Beispiel
  „Leer machen“ (empty it), „Setzen!“ (settle), „Sitz für Sitz“ (seat by seat), „Das ist deins“ (this is yours),
  „Hoch in zwei“ (up two in two), „Druck aufs Blatt“ (auf dem Ergometer ohnehin schief). Deutsch und Englisch
  dürfen inhaltlich voneinander abweichen. Wichtig ist, dass jede Sprache für sich natürlich klingt.
  „Schlagzahl“ und „Frequenz“ kommen beide vor: calm und motivating sagen meist „Schlagzahl“, cox auch „Frequenz“.
- Englisch: natürlich, britisch und amerikanisch neutral, mit Rudersprache („hold the rate“, „legs!“, „power ten“,
  „send it“, „paddle“, „easy all“).
- Für die Sprachausgabe (TTS): keine Ziffern im Text (Zahlen sind Variablen oder ausgeschrieben, z. B.
  „Zweihundertfünfzig“, „two fifty“), keine Abkürzungen, keine Emojis. Betont wird mit „!“ und „…“.
  Tempo-Linie heisst wie in der App „Tempo-Linie“ bzw. „pace line“.
- Ton: fordernd ja, abwertend nie. Kein Schmerz-Kult, keine Schuldgefühle, kein Body-Shaming, keine Flüche. Lob
  benennt Anstrengung oder konkrete Leistung (gesteigert, konstant, bis zum Schluss gehalten).
- Stile: `calm` sachlich, informativ, mit Punkt statt Ausrufezeichen. `motivating` warm, ermutigend. `cox`
  knapp, laut, rhythmisch, „wir“-Form wie im Boot. Calls wie „Zehn Schläge Beine – jetzt!“ bzw. „Power ten in
  two… one… now!“ kommen sparsam vor, nur bei Eskalation (Stufe 2), bei `phase_half` Stufe 2 und bei `paceline_behind`.
- Mannschaftsbegriffe („Zusammen!“, „Mannschaft“) werden vermieden: Gerudert wird allein auf dem Ergometer.

## phraseId und Pflege
- `phraseId` = `<szenario>.<stufe>.<stil>.<index>`, wobei der Index die Position im Array der jeweiligen
  Sprache ist (ab 0). Neue Varianten **nur anhängen**. Bestehende nicht umsortieren und nicht löschen, sonst passen
  aufgenommene Audiodateien nicht mehr. Statt zu löschen eine Zeile durch eine gleichwertige ersetzen und die
  Audiodatei neu aufnehmen.
- de und en sind unabhängige Listen. Gleicher Index heisst nicht gleicher Inhalt.
- Dynamische Varianten (mit `{…}`) spricht immer die Systemstimme. Nur statische Varianten lassen sich als
  `Coach/<sprache>/<phraseId>.m4a` aufnehmen.

## Quellen und Anregungen
Steuermann-Calls stammen aus üblicher Rudersprache (Power Ten, Beine, Länge, Rhythmus). Zur Orientierung dienten
öffentliche Erklärungen und Glossare, zum Beispiel Concept2 „What is a Power Ten?“
(https://www.concept2.com.au/node/8522), USRowing Terminology (https://usrowing.org/learn-about-rowing/terminology)
und Coxing-Unterlagen von Hochschulclubs (z. B. https://students.washington.edu/ubrc/coxing/basic-coxing-commands).
Aus diesen Quellen ist nichts wörtlich übernommen ausser kurzer Rudersprache. Zotero war zum Zeitpunkt der Arbeit
nicht erreichbar, Fundus hatte keine passenden Einträge. Eine Belegsammlung zur Wirkung von Anfeuerung entsteht
separat in `docs/coach/RECHERCHE.md`.
