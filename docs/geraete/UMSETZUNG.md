# Umsetzung: FTMS-Rudergeräte (Beta, 27.11.2026)

Stand: RowCoach liest neben dem Concept2 PM5 jedes Rudergerät mit **Bluetooth FTMS** (Rower Data 0x2AD1).
**Mit echter Hardware ungetestet** – geprüft sind Parser und Datenfluss mit Testpaketen und dem FTMS-Simulator.
Warum FTMS und welche Geräte: [RECHERCHE.md](RECHERCHE.md).

## Aufbau

| Teil | Datei | Aufgabe |
|---|---|---|
| Protokoll (Kit) | `App/RowCoachKit/Sources/RowCoachKit/FTMSProtocol.swift` | UUIDs, Werbepaket (`FTMSAdvertisement`), Fähigkeiten (`FTMSFeatures`), Rower-Data-Parser und -Encoder, Control-Point-Befehle und -Antworten, Fitness Machine Status |
| Abstraktion (Kit) | `App/RowCoachKit/Sources/RowCoachKit/RowingMachine.swift` | `RowingMachineKind` (pm5/ftms), `FTMSRowerTracker` (Pakete → `RowingSnapshot`), `FTMSRowerSimulator` |
| Kit, kleine Ergänzungen | `RowingSnapshot.swift`, `StrokePhaseTracker.swift`, `Workout.swift` | Pulsquelle `.machine`, `isPowerEstimated`, `registerStroke(at:interval:)`, `WorkoutDevice.machineKind` |
| Geräte (App) | `App/RowCoach/Devices/DeviceManager.swift` | Erkennen, Verbinden, Merken, FTMS-Characteristics, Callback `onFTMSData` |
| Simulator (App) | `App/RowCoach/Devices/SimulatorDevice.swift` | `-simulateFTMS 1` bzw. `2` |
| Fahrt (App) | `SessionController.handleRowerUpdate(at:)`, `RowCoachApp` | FTMS-Updates laufen in dieselbe Fahrt wie PM5-Updates |
| Oberfläche | `DevicesView.swift`, `Home/WeekCards.swift`, `RowingView.swift` | „FTMS-Rudergerät (Beta)“, Hinweis „ungetestet“, neutrale Texte „Rudergerät“ |
| Tests | `App/RowCoachKit/Tests/RowCoachKitTests/FTMSTests.swift` | 23 Tests (siehe unten) |

Der PM5-Pfad ist unverändert: dieselben Characteristics, derselbe Parser, `onPM5Message` wie bisher;
`SessionController.handlePM5` ruft nur die neue gemeinsame Methode `handleRowerUpdate(at:)` auf.

## Ablauf

1. **Erkennen** (`centralManager(_:didDiscover:)`): zuerst PM5 (Name „PM5…“ oder Dienst CE060000) – so gewinnt
   der PM5 auch, falls er zusätzlich FTMS anbietet. Sonst FTMS-Kandidat, wenn der Dienst 0x1826 beworben wird oder
   Service Data zu 0x1826 vorliegt; Service Data mit Typ-Bits ohne „Rudergerät“ (Fahrrad, Laufband) wird ausgefiltert.
   Liste: „FTMS-Rudergerät (Beta)“.
2. **Verbinden**: Rudergerät belegt denselben Platz wie der PM5 (`pm5`, `pm5State`, `pm5Name`), dazu `rowerKind`
   (gemerkt unter `device.pm5.kind`, Neuverbinden beim Start wie beim PM5). Entdeckt wird nur der Dienst 0x1826.
3. **Abonnieren**: Rower Data 0x2AD1 und Status 0x2ADA (Notify), Feature 0x2ACC lesen. Fehlt 0x2AD1, erscheint
   „Das Gerät sendet keine Ruderdaten …“.
4. **Daten**: `FTMSRowerDataParser.parse` → `FTMSRowerTracker.ingest(_:at:into:)` schreibt in `DeviceManager.snapshot`
   → `onFTMSData` → `SessionController.handleRowerUpdate(at:)` → `RowingSession.update` (wie beim PM5).
5. **Ruderfigur**: neuer Schlag laut Zähler = Wasserfassen (`StrokePhaseTracker.registerStroke`), Durchzug ≈ 1/3 der
   gemessenen Schlagdauer. FTMS kennt den Zeitpunkt im Schlag nicht – die Figur kann gegenüber dem echten Schlag
   versetzt sein.

## Robustheit im Tracker (`FTMSRowerTracker`)

- Teilpakete („More Data“, Bit 0 invertiert): jedes Feld behält seinen letzten Wert; jedes Paket aktualisiert.
- Widerstand 1 oder 2 Byte: Breite aus der Paketlänge (Parser), Standard sint16.
- Schläge aus dem Stroke Count: Überlauf 65 535 → 0 wird gezählt, Rücksetzen am Gerät oder Sprünge > 5 nur als neue
  Grundlinie. Ohne Stroke Count: Schläge aus der Schlagzahl hochgerechnet (`strokesDerived`).
- 6 s ohne neuen Schlag: Schlagzahl 0 (Pause), auch wenn das Gerät noch die alte Zahl meldet.
- Schlagzahl ohne Faktor 0,5: liegt der gemeldete Wert fünfmal in Folge bei 40–60 % der aus dem Zähler gemessenen
  Schlagzahl, wird er verdoppelt (`strokeRateScale`).
- Tempo fehlt (oder 0/0xFFFF): aus der Distanzänderung der letzten 2–8 s (`paceDerived`).
- Distanz fehlt: aus dem Tempo aufintegriert (`distanceDerived`).
- Zeit fehlt: eigene Uhr, zählt nur bei Aktivität.
- Watt fehlen: `power` bleibt 0, `displayPower` schätzt nach Concept2 aus dem Tempo (2,80/(s/m)³), markiert über
  `RowingSnapshot.isPowerEstimated`. Negative Watt (sint16) → 0.
- Puls vom Gerät (`.machine`) nur ohne Pulsgurt; Puls 0 = keiner. Energie 0xFFFF = nicht unterstützt.
- Distanz uint24 und Zähler-Rücksprünge fängt zusätzlich `RelativeCounter` in der Fahrt ab (wie beim PM5).

## Bewusst nicht umgesetzt

- **Control Point wird nicht beschrieben.** Befehle (Request Control, Reset, Start, Stop/Pause) sind im Kit kodiert und
  getestet (`FTMSControlCommand`, `FTMSControlResponse`), aber die App sendet nichts: Ein Reset könnte laufende
  Anzeigen am Gerät löschen, und die Fahrt erkennt Start, Pause und Neustart schon selbst (wie beim PM5). Bei Bedarf
  später: Indications auf 0x2AD9 einschalten, Request Control, auf Antwort 0x80/0x00/0x01 warten, dann Befehl.
- Training Status (0x2AD3) und Widerstandsbereich (0x2AD6): nicht nötig.
- Proprietäre Protokolle (Echelon, iFit, Domyos „e-connected“), USB-Seriell (WaterRower S4), ANT+: siehe RECHERCHE.md.
- `WorkoutDevice.source` bleibt bei FTMS `.pm5` („echtes Gerät“): ein neuer Enum-Wert würde ältere App-Fassungen beim
  Synchronisieren am Dekodieren hindern. Das Protokoll steht im neuen optionalen Feld `machineKind` („ftms“).

## Tests (Linux, `swift test`)

`FTMSTests.swift`, 23 Tests, alle grün (27.11.2026):
- Parser mit von Hand gebauten Paketen nach Spezifikation: typisches Paket, halbe Schlagzahl-Auflösung, invertiertes
  More-Data-Bit, alle Felder mit Widerstand 2 bzw. 1 Byte (30/29 Bytes), uint24-Maximum, negative Leistung,
  Energie „nicht unterstützt“, Puls 0, zu kurze Pakete, überzählige Bytes, Zusammenführen aufgeteilter Pakete,
  Encoder-Rundlauf.
- Werbepaket (Rudergerät, Fahrrad, ohne Service Data), Feature-Bits, Control-Point-Bytes, Antworten, Status.
- Tracker: Schläge mit Überlauf, Reset und Sprung; Pause nach 6 s; Gerätewerte; Gurt hat Vorrang; Tempo aus Distanz
  und geschätzte Watt; Distanz aus Tempo; Schläge aus der Schlagzahl; Korrektur halbierter Schlagzahl (und keine
  Korrektur bei richtiger); Schlagphase.
- Ende zu Ende: FTMS-Simulator (voll und karg) → Bytes → Parser → Tracker → `RowingSession`.

## Auf dem Mac prüfen

1. Bauen (Swift 6-Toolchain, App im Sprachmodus 5): neue Dateien liegen im Kit, die App-Änderungen sind klein.
2. **Ohne Hardware, FTMS-Simulator**: Startargument `-simulateFTMS 1` (voll, Teilpakete) bzw. `-simulateFTMS 2`
   (karg: nur Schlagzahl, Zähler, Distanz) zusammen mit dem Simulator (Einstellungen → Entwickler → „Simulator statt
   PM5“ oder `-demoCourse <id>`). Erwartet: Fahrt startet mit dem ersten Schlag, Tempo ≈ eingestelltes Tempo,
   Schlagzahl stimmt, Ruderfigur im Takt, in der Diagnose „Sim FTMS 0x2AD1“ statt „Sim 0x0031…“; bei `2` Watt
   geschätzt (≈ 180 W bei 2:05). Gespeichertes Training: `device.machineKind = "ftms"`.
3. **PM5 unverändert**: echte Fahrt mit dem PM5 (Erkennung, Neuverbinden nach Neustart, Schlagtakt der Figur, Puls).
4. **Geräteliste**: Sheet „Geräte“ – PM5 erscheint wie bisher als „Rudergerät“, FTMS-Geräte als „FTMS-Rudergerät
   (Beta)“; nach dem Verbinden Karte mit Hinweis „Beta – ungetestet“. „Vergessen“ löscht auch die gemerkte Art.
5. Mit echter FTMS-Hardware (falls verfügbar, z. B. bei einem Händler): Diagnose-Zähler, Werte gegen die Konsole,
   Widerstandsbreite (`resistanceFieldWidth`), ob Teilpakete kommen.
