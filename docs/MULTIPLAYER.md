# Rennen und Turniere (Multiplayer) – Grundlage, Stand 26.11.2026

Ziel (Falk): Später organisiert ein Server – voraussichtlich Firebase – Turniere. Man trifft sich zu einem Rennen
auf derselben Strecke, rudert gegeneinander und sieht die anderen in Echtzeit bzw. nahe Echtzeit in der eigenen
App. Jetzt ist nur die Grundlage eingebaut, **kein Server und kein Firebase-SDK**.

## Aufbau

```
 PM5 ──► SessionController ──► RowingSession (Distanz, Zeit, Tempo)
                │
                ▼ feedRace (bei jedem Messwert)
            RaceLink (Hauptthread) ───────────────┐
                │  update → RaceCoordinator        │ join / publish / frames / roster / serverTime
                │           ├ RacePublishThrottle  ▼
                │           ├ RaceClock      ┌─────────────────────────────┐
                │           └ RemoteRowerTracker je Gegner │ RaceTransport (Protokoll)     │
                │                                      │  • LoopbackRaceTransport (Speicher) │
                ▼ states                               │  • GhostRaceTransport (Bestfahrt, Bot) │
   raceStates: [RemoteRowerState]                      │  • FirebaseRaceTransport (später) │
                │                                      └─────────────────────────────┘
                ▼
 RowingSceneView.raceRowers(…) ──► RaceRowersSystem (Boote mit Namen, eigene Farben)
```

- Alles ausser der Darstellung liegt in **RowCoachKit** (nur Foundation): läuft auf iPad, Linux und Android
  (siehe docs/ANDROID.md). Dateien: `Race.swift`, `RaceTiming.swift`, `RaceTransport.swift`,
  `RaceCoordinator.swift`, `RaceLink.swift`; Tests in `RaceTests.swift`.
- App: `SessionController.attachRace(_:)`/`endRace()` (ohne Rennen ändert sich nichts), `Scene3D/RaceRowers.swift`,
  `RowingSceneView.raceRowers(_:)`. Testbetrieb: Startargument `-demoRace 1` → Rennen gegen zwei Bots
  (`RowingView.demoRace`).

## Datenmodell

| Typ | Inhalt |
|---|---|
| `Tournament` | id, Titel, `courseId` (+ `courseVersion`), Beginn (Serverzeit), Format (`singleRace`, `heats`), Rennen |
| `Race` | id, Turnier, `courseId` (+ `courseVersion`), Ziel (`distance`, `time`, `plan`), gemeinsamer Start (oder nil = erster Schlag), Bahnen |
| `RaceParticipant` | id, Anzeigename, Bahn, Quelle (`human`, `ghost`, `bot`) |
| `LiveFrame` | Teilnehmende, Rennen, laufende Nummer, Sendezeit (Server), Rennzeit, Distanz, Tempo, Schlagzahl, Puls, im Ziel, Zielzeit – kurze JSON-Schlüssel (`p`, `r`, `n`, `at`, `t`, `d`, `pc`, `spm`, `hr`, `f`, `ft`), ca. 120 Byte |
| `RaceResult` | Platz, Distanz, Zeit, im Ziel |
| `RemoteRowerState` | angezeigter Stand eines Gegners: Distanz, Abstand in m und s, Platz, veraltet, seitlicher Versatz |

Ein gerudertes Rennen trägt im gespeicherten Training `header.raceId`.

**Strecke als Voraussetzung:** Alle rudern dieselbe Landschaft. Anmelden kann sich nur, wer die Strecke (in der
verlangten Fassung) installiert hat; die Anmeldung bietet sonst den Download an. Die Prüfung der Installation liegt
im Streckenkatalog (`CourseCatalog.swift`); Rennen fragen nur über `RaceEligibility.check(race) { id, version in … }`.

## Transport-Vertrag (`RaceTransport`)

- `join(race:as:)` → Teilnehmerliste; Fehler `raceFull`, `laneTaken`.
- `publish(_:)` eigenen Frame senden; `frames` liefert nur Frames der anderen; `roster` jede Änderung der Liste.
- `serverTime()` für die Uhr; `leave()` beendet die Ströme.
- Eine Instanz = eine Person in einem Rennen. Mehrere Transporte gleichzeitig sind erlaubt (z. B. Server + Geist).

## Zeit und Latenz

- **Uhr:** `RaceClock` schätzt den Versatz zur Serveruhr aus Rundläufen (Mittel der drei kürzesten von acht).
  Gemeinsamer Start = Serverzeitpunkt; Countdown und Rennzeit daraus. Ohne gemeinsamen Start zählt die Zeit ab dem
  ersten eigenen Schlag (Geister, Bots).
- **Senden:** `RacePublishThrottle` – höchstens ca. 3 pro Sekunde, sofort bei neuem Schlag oder im Ziel, sonst
  mindestens 1 pro Sekunde als Lebenszeichen.
- **Anzeigen:** `RemoteRowerTracker` zeigt die anderen mit 0,4 s Verzögerung und interpoliert zwischen zwei Frames
  (ruhig trotz schwankender Laufzeit). Kommt nichts, rechnet er bis 3 s mit dem letzten Tempo voraus und bleibt dann
  stehen; nach 5 s ohne Daten gilt das Boot als veraltet. Abstände und Platz rechnet `RaceCoordinator`.
- **Bahnen:** Alle anderen fahren rechts der eigenen Linie (7 m Abstand, höchstens 4 nebeneinander, dann geteilt) –
  so bleiben sie auf Hin- und Rückfahrt weg von der Gegenbahn, wie die Bahnen des Verkehrs.

## Firebase-Plan (nicht umgesetzt)

- **Auth:** Firebase Authentication (Sign in with Apple, Google); `participantId` = uid.
- **Firestore** (selten geänderte Daten): `tournaments/{id}`, `races/{id}` (Strecke, Fassung, Ziel, Start, Bahnen),
  `races/{id}/participants/{uid}` (Name, Bahn), `races/{id}/results/{uid}` (vom Server geschrieben).
- **Realtime Database** (hohe Frequenz, günstig je Schreibvorgang, Latenz ~100 ms):
  `/live/{raceId}/{uid}` = letzter `LiveFrame` (überschrieben, keine Historie); Abo auf `/live/{raceId}`.
  Serverzeit über `/.info/serverTimeOffset` bzw. `ServerValue.timestamp` (ersetzt die Rundläufe).
- **Cloud Functions:** Start freigeben (Countdown), Ergebnisse aus den letzten Frames festschreiben, Plausibilität prüfen,
  Turnierbaum (Vorläufe → Finale) fortschreiben.
- **Regeln (Skizze):**
  ```
  "live": { "$raceId": { "$uid": {
      ".write": "auth.uid === $uid && root.child('entries/'+$raceId+'/'+$uid).exists()",
      ".read": "root.child('entries/'+$raceId+'/'+auth.uid).exists()",
      ".validate": "newData.child('n').val() > (data.child('n').val() || 0)" } } }
  ```
- **Kosten (grob):** 3 Frames/s × 120 Byte × 6 Boote ≈ 2 KB/s je Rennen hinaus und ~13 KB/s an alle hinein; ein
  10-min-Rennen ≈ 8 MB Download über alle. Das liegt im kostenlosen Rahmen für einzelne Rennen; für viele parallele
  Rennen Frequenz senken (2/s) oder Frames bündeln.
- **Android:** dieselbe `RaceTransport`-Schnittstelle über das Firebase-Android-SDK (swift-java), Logik unverändert.

## Fairness und Missbrauch

- Der PM5 liefert die Werte; Manipulation an der App ist möglich. Server prüft: Tempo unter 1:10/500 m oder
  Sprünge > 15 m zwischen Frames verwerfen, Distanz nie rückwärts, Zielzeit ≈ Distanz/Tempo-Verlauf.
- Ergebnisse gelten erst, wenn der Server sie festschreibt; die App zeigt bis dahin „vorläufig“ (`standings()`).
- Später optional: PM5-Seriennummer und Kraftkurve zur Plausibilität.

## Erledigt / offen

| Erledigt | Offen |
|---|---|
| Modelle, Uhr, Drossel, Verfolgung, Bahnen, Platz/Abstände, Ergebnisliste | Firebase-Transport, Anmeldung, Turnier-Oberfläche |
| Loopback-Transport (mehrere Boote im Speicher), Geister/Bots | „Gegen meine Bestfahrt“ als Knopf auf der Streckenseite (Transport und Szene sind fertig) |
| Anbindung an die Fahrt (`attachRace`), Boote mit Namen in der Szene, `raceId` im Training | Anzeige von Platz und Abstand im HUD, Countdown vor gemeinsamem Start (Fahrt startet heute mit dem ersten Schlag) |
| 28 Tests (Linux), Android-Bau | Prüfung im Simulator mit `-demoRace 1` (Mac) |
