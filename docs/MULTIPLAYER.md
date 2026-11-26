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
| `RaceParticipant` | id, Anzeigename, Bahn, Quelle (`human`, `ghost`, `bot`), Erscheinung (`appearance`, optional) |
| `LiveFrame` | Teilnehmende, Rennen, laufende Nummer, Sendezeit (Server), Rennzeit, Distanz, Tempo, Schlagzahl, Puls, im Ziel, Zielzeit – kurze JSON-Schlüssel (`p`, `r`, `n`, `at`, `t`, `d`, `pc`, `spm`, `hr`, `f`, `ft`), ca. 120 Byte |
| `RaceResult` | Platz, Distanz, Zeit, im Ziel |
| `RemoteRowerState` | angezeigter Stand eines Gegners: Distanz, Abstand in m und s, Platz, veraltet, seitlicher Versatz |

Ein gerudertes Rennen trägt im gespeicherten Training `header.raceId`.

**Strecke als Voraussetzung:** Alle rudern dieselbe Landschaft. Anmelden kann sich nur, wer die Strecke (in der
verlangten Fassung) installiert hat; die Anmeldung bietet sonst den Download an. Die Prüfung der Installation liegt
im Streckenkatalog (`CourseCatalog.swift`); Rennen fragen nur über `RaceEligibility.check(race) { id, version in … }`.

## Erscheinung und Datenschutz

Andere sehen im Rennen die Figur, ihre Farben, das Boot und – wenn gewünscht – die Flagge (Spezifikation und
Umsetzung: docs/avatar/SPEC.md).

- `RaceParticipant.appearance: RowerAppearance?` geht **einmal beim Beitritt** mit der Teilnehmerliste, nicht in
  jedem `LiveFrame` (ca. 150–200 Byte JSON: Figur-, Farb- und Boot-Ids, zwei Flaggen-Schalter, ggf. Ländercode).
  Ältere Clients ohne das Feld dekodieren weiter (optional, `nil` wird nicht gesendet).
- Die App setzt für sich selbst `RowerProfile.publicAppearance` (aus `RowerProfileStore.shared.appearance`):
  - **Nationalität** nur, wenn mindestens einer der Schalter „Flagge auf dem Trikot“ / „Flagge auf dem Boot“ an ist;
    ohne gewählte Nationalität sind beide Schalter aus.
  - **Geschlecht** geht nie mit; es steht gar nicht in `RowerAppearance`.
  - Der Anzeigename steht in `RaceParticipant.displayName` (leer → „Ich“, höchstens 24 Zeichen).
- Empfänger: `RaceParticipant.resolvedAppearance()` – die gesendete Erscheinung, sonst eine je Teilnehmer-Id stabile
  zufällige (`RowerAppearance.random(seed: id)`, gleich auf allen Geräten, keine Flaggen). Bots und Verkehr
  benutzen dasselbe. Flaggen zeigt die Szene nur über `shirtFlag`/`boatFlag`, also nur bei eingeschaltetem
  Schalter, auch wenn ein fremder Client einen Ländercode ohne Schalter sendet.
- Unbekannte Ids (neuere App beim Gegner) löst `AppearanceCatalog.resolve` mit Ersatzwerten auf (erster Typ,
  Farben des Typs, erstes Boot); die Szene bricht nie.
- Server (später): Erscheinung gegen eine Grössenobergrenze und das Schema prüfen; Länder nur ISO 3166-1 alpha-2.

## Transport-Vertrag (`RaceTransport`)

- `join(race:as:)` → Teilnehmerliste; Fehler `raceFull`, `laneTaken`.
- `publish(_:)` eigenen Frame senden; `frames` liefert nur Frames der anderen; `roster` jede Änderung der Liste.
- `serverTime()` für die Uhr; `leave()` beendet die Ströme.
- Eine Instanz = eine Person in einem Rennen. Mehrere Transporte gleichzeitig sind erlaubt (z. B. Server + Geist).
- Grosse Felder: `fieldSnapshots` (Gesamtübersicht ca. 1/s) und `setInterest(_:)` (Nachbarschafts-Abo), beide mit
  Standard-Umsetzung – siehe Abschnitt „Grosse Felder“.

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

## Grosse Felder (100–300 Teilnehmende), Stand 26.11.2026

Falk (26.11.): Turniere sollen 100, 200, 300 Teilnehmende haben können. Nicht alle Boote auf jedem Gerät animieren:
eine Heuristik soll den Eindruck eines grossen Feldes geben und im direkten Umfeld nur wenige Boote voll zeigen.
Untergrenze ist das iPad mit A12X. Zwei Ebenen: wie viele Daten ein Gerät bekommt (Netz) und wie viele Boote es
zeigt (Szene). Code nur im Kit: `RaceField.swift` (Übersicht, Abo, Rechenhilfen), `RaceScenePlanner.swift` (Planer),
`RaceBotField.swift` (Bot-Feld und Bot-Transport); Tests in `RaceFieldTests.swift`.

### A. Netz: Datenmenge

**Heute (Abo auf `/live/{raceId}`, alle Frames an alle):** ein Frame ≈ 150 Byte auf dem Draht (≈ 120 Byte JSON plus
Pfad und Rahmen), ca. 3 pro Sekunde und Boot.

| 300 Teilnehmende, heutiges Verfahren | Wert |
|---|---|
| Empfang je Gerät | 299 × 3/s × 150 B ≈ **135 KB/s** (≈ 1,1 Mbit/s), dazu 900 JSON-Nachrichten/s zum Auswerten |
| Schreibvorgänge in der Datenbank | 300 × 3/s = **900/s** (Richtwert der Realtime Database: 1000/s je Datenbank) |
| Antworten der Datenbank | 900 × 299 ≈ **269 000/s** (Grenze: ≈ 100 000/s je Datenbank) |
| Download gesamt, 10 min (Rennen über 2000 m ≈ 7 min plus Vorstart) | 300 × 135 KB/s × 600 s ≈ **24 GB ≈ 24 USD** je Rennen |

Das geht nicht: Die Datenbank überschreitet die Antwort-Grenze, und auf dem Gerät kosten Empfang und Auswerten zu viel.
(Grenzen und Preise: Firebase-Dokumentation „Realtime Database limits“ und „Pricing“, abgerufen 26.11.2026:
200 000 gleichzeitige Verbindungen, im kostenlosen Spark-Tarif nur 100; ≈ 1000 Schreibvorgänge/s; ≈ 100 000 Antworten/s;
Download 1 USD/GB nach 360 MB/Tag frei. Turniere mit über 100 Personen brauchen also den Blaze-Tarif.)

**Varianten**

| | (1) Nachbarschaft + Übersicht vom Aggregator | (2) Buckets nach Distanz | (3) wie (1), aber Firestore |
|---|---|---|---|
| Aufbau | Frames unter `/live/{raceId}/f/{uid}`; jedes Gerät hört nur die K nächsten (je ein Listener pro uid, K = 16, Wechsel mit Hysterese). Ein Aggregator schreibt 1/s `/live/{raceId}/field` (alle, kompakt). | Frames unter `/live/{raceId}/buckets/{⌊d/50⌋}/{uid}`, Umzug beim Bucket-Wechsel (Mehrpfad-Update: alt `null`, neu Frame); Geräte hören 3–4 Buckets um sich (−50…+100 m). | Frames und Übersicht als Dokumente, Listener auf Dokumente |
| Empfang je Gerät | 16 × 2,5/s × 150 B = 6,0 KB/s + Übersicht 3,3 KB/s = **9,3 KB/s** (≈ 74 kbit/s), fest begrenzt | alle Boote in den Buckets: am Start alle 300 (≈ 112 KB/s), im Pulk 100–200 (≈ 40–75 KB/s); **nicht begrenzt** | wie (1) |
| Schreiben | 750/s (2,5/s je Boot) + 1/s Übersicht | 750/s + Umzüge | 750 Dokument-Schreibvorgänge/s |
| Antworten/s | 750 × 16 + 750 + 300 ≈ **13 000** | je nach Dichte bis 200 000 | – (Abrechnung je gelesenem Dokument) |
| Gesamtübersicht (Platz „143 von 300“, Führende, Minikarte) | ja, aus der Übersicht | nein – bräuchte zusätzlich ein Aggregat | ja |
| Download/Kosten je Rennen (10 min) | 300 × 9,3 KB/s × 600 s + Aggregator ≈ **1,7 GB ≈ 1,7 USD**; Aggregator (Cloud Run, 1 vCPU, Mindestinstanz 1 während des Rennens) wenige Cent | je nach Dichte 7–20 GB | ≈ 7 Mio. Dokument-Lesungen + 0,45 Mio. Schreibvorgänge ≈ 5 USD (ca., Google-Cloud-Preisliste prüfen); Übersichtsdokument stösst an ≈ 1 Schreibvorgang/s je Dokument |
| Latenz | Nachbarn ≈ 100 ms (+ 0,4 s Anzeigeverzögerung wie heute); Übersicht 0,1–1,2 s alt, mit Tempo vorausgerechnet (Fehler < 1 m) | ≈ 100 ms | 200–500 ms |
| Aufwand | Aggregator nötig (ein kleiner Dienst), Regeln einfach | kein Server, aber Regeln (Bucket = ⌊d/50⌋ prüfen), Umzüge, Lücken an Bucket-Grenzen | wie (1), teurer, langsamer |

**Empfehlung: Variante (1).** Begrenzte, vorhersehbare Last je Gerät (≈ 9 KB/s statt 135 KB/s, Faktor 14), weit
unter den Grenzen der Datenbank, und die Übersicht liefert alles für den Eindruck des Feldes. Details:

- **Aggregator:** ein Cloud-Run-Dienst mit Admin-SDK hört `/live/{raceId}/f` (bekommt alle 750 Frames/s ≈ 112 KB/s) und
  schreibt jede Sekunde `RaceFieldSnapshot.build(...)` als `{"r", "at", "b": Base64}` nach `/live/{raceId}/field`. Er
  übernimmt auch die Plausibilitätsprüfung (Abschnitt „Fairness“) und schreibt am Ende die Ergebnisse. Eine
  RTDB-ausgelöste Cloud Function je Frame wäre falsch (750 Aufrufe/s ≈ 450 000 je Rennen), geplante Functions laufen nur
  minütlich. Die Logik der Übersicht liegt im Kit (`RaceFieldSnapshot.build`) und ist getestet; der Dienst kann sie in
  Swift (Linux) oder nachgebaut in TypeScript nutzen.
- **Übersicht, Byte-Budget:** Kopf 15 Byte, je Teilnehmendem 8 Byte (Kurzindex u16, Distanz in dm u24, Tempo in 0,1 s
  u16, Schlagzahl 6 Bit + „im Ziel“ + „veraltet“). 300 Teilnehmende = 2415 Byte, als Base64 **3220 Byte ≈ 10,7 Byte je
  Teilnehmendem**, mit JSON-Rahmen ≈ 3,3 KB/s je Gerät. Der Kurzindex folgt aus der Teilnehmerliste (Reihenfolge nach Bahn,
  id); `rosterHash` (FNV-1a) erkennt, wenn Gerät und Aggregator verschiedene Listen haben – dann wird die Übersicht
  verworfen (`RaceFieldTracker.rosterMismatches`) und die Liste neu geladen.
- **Nachbarschafts-Abo:** Der Planer (unten) wählt die ids: alle voll gezeigten, dann nach Rang bis K = 16; bisherige
  zählen 20 m näher (Hysterese), neu gesetzt höchstens alle 2 s (`RaceScenePlan.interest`, `interestChanged`). Der
  Firebase-Transport setzt das in `setInterest` als Listener je uid um (an-/abmelden kostet je einmal ≈ 150 Byte).
- **Schreibrate:** 2,5 Frames/s je Boot genügen (Drossel `minInterval` 0,4 s statt 0,33 s für grosse Felder). Pro
  grossem Rennen eine eigene RTDB-Instanz (im Blaze-Tarif mehrere je Projekt möglich), damit parallele Rennen nicht
  gemeinsam an den Richtwert von 1000 Schreibvorgängen/s stossen.
- **Kleine Rennen bleiben wie heute:** bis ca. 30 Teilnehmende (30 × 29 × 3 × 150 B ≈ 13 KB/s je Gerät) abonniert jedes
  Gerät alles; der Transport schaltet nach Grösse der Teilnehmerliste um. Fällt der Aggregator aus, sehen die Geräte
  weiter ihre Nachbarn (letztes Abo), nur Platz und Minikarte frieren ein.

**Transport-Vertrag (abwärtskompatibel erweitert):**
```swift
protocol RaceTransport {
    …                                                            // wie bisher
    var fieldSnapshots: AsyncStream<RaceFieldSnapshot> { get }   // Standard: leerer, sofort beendeter Strom
    func setInterest(_ interest: RaceInterest) async             // Standard: ignoriert (es kommen alle Frames)
}
```
`GhostRaceTransport` und alle bisherigen Transporte laufen unverändert. `LoopbackRaceHub` filtert Frames nach dem Abo
und erzeugt mit `broadcastField(raceId:raceTime:)` die Übersicht wie der Aggregator; `RaceBotTransport` spielt ein
Bot-Feld wie ein Server ab (volle Frames nur für das Abo, ohne Abo die 16 nächsten zur eigenen Distanz, jede Sekunde
eine Übersicht). `RaceLink` nimmt die Übersichten in `field` (`RaceFieldTracker`) auf, `members(...)` führt volle und
grobe Stände für den Planer zusammen, `setInterest(_:)` gibt das Abo an alle Transporte.

### B. Gerät: was gezeigt wird (`RaceScenePlanner`)

Ein reiner Planer (Struct, nur Foundation): Eingabe sind alle bekannten Boote (`RaceFieldMember`: voll aus der
Nachbarschaft, grob aus der Übersicht), der eigene Stand und ein Budget je Gerätestufe. Er entscheidet alle 0,5 s über
Stufe, Bahn und Abo und glättet bei jedem Aufruf Ein-/Ausblenden und Seitenwechsel.

**Stufen und Budgets**

| Stufe | Darstellung | A12X/A12Z (Untergrenze) | A13–A16, M1 | M2+, A17 Pro+ | Reichweite (vor / hinter mir) |
|---|---|---|---|---|---|
| `full` | Figur mit Erscheinung, Ruderanimation, Namensschild, Flagge, Schatten | 6 | 10 | 12 | 200 m / 60 m (Überholende immer) |
| `lite` | Low-Poly-Boot, vereinfachte Animation (Skulls schwingen, keine Figur-Gelenke), kein Schild, kein Schatten | 12 | 16 | 20 | 600 m / 150 m |
| `impostor` | Punkt/Silhouette, instanziert, keine Animation | 48 | 96 | 160 | 1500 m / 250 m, nie näher als die `full`-Reichweite |
| Pulk (`clusters`) | Gruppen ausgeblendeter Boote vor mir je 25 m (Anzahl, Länge) | 12 | 16 | 20 | bis 1500 m vor mir |
| `hidden` | nur HUD und Minikarte | Rest | Rest | Rest | |

Die Zuordnung Gerät → Budget macht die App (Gerätekennung). **Rückkopplung** (`RaceFrameRateGovernor`): die Szene meldet
jede Sekunde die gemessene Bildrate (`reportFrameRate`); unter 50 fps (2 s lang) eine Stufe weniger (−1 voll, −2
vereinfacht, −25 % Impostoren, mindestens 3 voll und 4 vereinfacht), über 57 fps (10 s lang) eine zurück, dazwischen 4 s
Ruhe. Nach einer Absenkung verschwinden überzählige Boote sofort statt auszublenden, damit das neue Budget nach
spätestens einer Entscheidung gilt.

**Rang (wer zuerst Budget bekommt)** – Klasse vor Abstand:

| Klasse | Regel |
|---|---|
| `overtaking` | überholt mich bzw. wird überholt: Vorzeichenwechsel des Abstands, gilt bis 40 m Abstand (höchstens 120 s); „gleich dran“: ≤ 25 m und Annäherung > 0,3 m/s; eigene Bestfahrt (Geist) bis 300 m |
| `immediate` | unmittelbare Gegner ± 30 m |
| `marked` | Freunde/markierte Personen bis 300 m (weiter weg nur im HUD) |
| `near` | Rest nach wirksamem Abstand |

Wirksamer Abstand = Abstand vor mir bzw. 1,5 × Abstand hinter mir (die Kamera schaut nach vorn), +50 m für veraltete.
**Hysterese:** Wer schon gezeigt wird, zählt um max(30 m, 30 %) näher; eine neue Stufe wird 3 s nicht abgegeben (solange
das Boot in ihrer Reichweite ist); Ein- und Ausblenden dauern 0,6 s, Ausblendende behalten Budget und Bahn, bis sie weg sind.
Das Budget wird nie überschritten: bisher sichtbare Stufen sind reserviert, bis ihr Boot an der Reihe war; Abstiege werden
von unten nach oben umgesetzt (machen Platz), dann Aufstiege, dann Neue.

**Visuelle Bahnen** (`RaceVisualLanes`): 300 Boote können nicht auf 300 Bahnen. Gezeigte Boote bekommen einen von
wenigen seitlichen Plätzen relativ zum eigenen Boot: k × 7 m rechts (weg von der Gegenbahn, wie heute `RaceLanes`), auf
Strecken ohne Wende auch links; die eigene Linie nur für Boote, die immer ≥ 30 m vor/hinter mir bleiben.
`RaceVisualLanes.forCourse(course)` leitet die Zahl aus den Ruderbahnen des Verkehrs ab (`traffic.rower_lanes`, 2…6
rechts; Voreinstellung 5). Regeln:
- Auf derselben Bahn ≥ 13 m Abstand in Fahrtrichtung, 6 s vorausgerechnet (Überholen auf derselben Bahn wird früh
  erkannt); Sichtbare dürfen notfalls nur nach jetzigem Abstand bleiben.
- Sichtbare und Überholende belegen ihre Bahn zuerst (nach Rang), Neue fügen sich ein. Wer keinen freien Platz findet,
  wird übersprungen – das Budget geht an die nächsten, statt im dichten Pulk zu verfallen; ferne Boote werden dann Impostor.
- Wechsel zur Seite mit höchstens 1,5 m/s (`lateral` läuft zu `lateralTarget`) – nichts springt.
- Die Distanz wird nie verschoben: Abstände in Fahrtrichtung bleiben wahr.

**HUD** (`RaceFieldSummary`, über alle 300): Platz und Anzahl („143 von 300“), nächstes Boot vor/hinter mir (m, s),
Boote im Pulk ± 25 m, Führende (3), markierte Personen mit Platz, Histogramm entlang der Strecke (50 m je Fach) für die
Minikarte, Zahl der gezeigten Boote.

**Schnittstelle für RaceRowers (zum Einbau):**
```swift
// SessionController, Hauptthread, im Takt der Anzeige (10–60/s; entschieden wird intern alle 0,5 s)
let members = link.members(raceTime: t, myDistance: d, mySpeed: v, marked: friendIds)
let plan = planner.plan(members: members, me: RaceSelf(id: link.me.id, distance: d, speed: v), now: CACurrentMediaTime())
if plan.interestChanged { link.setInterest(plan.interest) }
// Szene: plan.items, plan.clusters; HUD: plan.summary; Bildrate: planner.reportFrameRate(fps, now:)
```

| Feld (`RaceSceneItem`) | Bedeutung für die Szene |
|---|---|
| `participantId` | Schlüssel wie heute; Name und Erscheinung aus der Teilnehmerliste (`RaceParticipant.resolvedAppearance()`) |
| `tier` | `full` → BoatRig mit Figur, Animation, Schild, Flagge, Schatten; `lite` → Low-Poly-Rig ohne Schild/Schatten; `impostor` → eine Instanz im gemeinsamen Impostor-Mesh. Wechsel full↔lite ohne Übergang (LOD-Tausch an derselben Stelle) |
| `distance` | Distanz entlang der Strecke (wie `RemoteRowerState.distance`, weiter mit eigener Glättung/Vorausrechnung wie heute) |
| `lateral` / `lateralTarget` | seitlicher Versatz (m, positiv = links) – ersetzt `RemoteRowerState.lateral`; `lateral` ist schon geglättet |
| `visualLane` | Platz (Fehlersuche, Farbe des Schilds o. ä.) |
| `fade`, `fadingOut` | Sichtbarkeit 0…1 (Opazität bzw. Skalierung beim Erscheinen); bei `fadingOut` nach 0 entfernen |
| `priority` | z. B. Schild hervorheben bei `overtaking`/`marked` |

Lage: `RaceSceneLayout.place(id:, pose: pose(distance), lateral: item.lateral, eye:)` (Kit, getestet) liefert x/z,
Richtung und Schild wie heute. `RaceCrowdCluster {distance, count, length}`: Mitte bei `pose(distance)`, über die rechten
Bahnen verteilt, min(count, 5) Silhouetten.

**Was die 3D-Seite dafür braucht:** (1) ein Low-Poly-Boot für `lite` (Rumpf + Skulls, ≤ 300 Dreiecke, ein Material,
keine Schatten, Ruderbewegung als einfache Rotation der Skulls); (2) Impostoren als *ein* Mesh mit Instanzen
(RealityKit `MeshInstancesComponent` bzw. ein `LowLevelMesh` mit Billboard-Quads, Farbe je Instanz), ein Draw-Call für
alle Punkte und Pulk-Silhouetten; (3) Ein-/Ausblenden über `OpacityComponent` bzw. Skalierung; (4) Bildrate messen und
melden; (5) Objekte poolen (Rigs nicht bei jedem Wechsel neu bauen). Auf Android (Filament) entsprechend: Instancing
und LOD-Stufen.

**Bot-Feld** (`RaceBotField`, für Demo und Tests, später `-demoRace 300`): N Bots, deterministisch (Saat).
Grundtempo normalverteilt um das Bezugstempo (Standardabweichung 6 s/500 m), 8 % deutlich schneller und 12 % deutlich
langsamer (6–15 s/500 m), Anlauf in 12 s, Ermüdung 0,2–1,6 s/500 m je 500 m, Schwankung ± 0,5–2 s mit 30–90 s Periode
(erzeugt natürliche Überholvorgänge), Endspurt auf den letzten 250 m (1–5 s). Verlauf in 1-s-Schritten vorausberechnet.
`RaceBotTransport(field:raceTime:)` liefert es wie ein Server.

**Tests (Linux, `RaceFieldTests.swift`, 20 Tests):** Binärformat, Base64/JSON und Byte-Budget (300 → 3220 Byte),
Datenmenge je Gerät (≈ 112 KB/s ohne, < 10 KB/s mit Nachbarschaft), Kurzindex und Hash, Vorausrechnung, Abo-Filter im
Loopback-Hub, Standard-Umsetzungen alter Transporte, Bot-Transport und RaceLink mit 300 Bots, Bot-Verteilung, Bildraten-
Rückkopplung, Bahnen aus der Strecke. Planer über ein ganzes 2000-m-Rennen mit 300 Bots im 10-Hz-Takt (sehr dichtes Feld:
≈ 290 Boote in ± 200 m): Budget nie überschritten, keine Überlappung auf einer Bahn, kein seitlicher Sprung, 72
Stufenwechsel/min über das ganze Feld (jeder ein weicher Übergang), höchstens 2,4 je Boot und Minute, Umfeld immer mit
≥ 13 Booten besetzt; Überholender bleibt durch einen Pulk von 40 Booten voll sichtbar, bis er 40 m weg ist; Budget nach
Bildraten-Absenkung binnen 1,5 s. **Planungszeit** (300 Boote, Spark, Grace-CPU): Release 0,05 ms je Aufruf im Mittel,
0,25 ms je Entscheidungsschritt, höchstens 0,5 ms; Debug-Build 0,4 ms bzw. 2 ms. Auf dem A12X grob 2–3× langsamer
(Schätzung, nicht gemessen) – weit unter 1 ms.

**Offen**
- Firebase-Transport mit Listenern je uid und Aggregator-Dienst (Cloud Run); Regeln für `/live/{raceId}/f` und `/field`.
- App: Planer in `SessionController`, `RaceRowers` auf `RaceSceneItem` umstellen (Low-Poly-Rig, Impostor-Instanzen,
  Pulk), HUD (Platz, Abstände, Minikarte mit Histogramm, Führende), Gerätestufe → Budget, Bildrate melden,
  `-demoRace 300` mit `RaceBotTransport`.
- `RaceCoordinator.states` rechnet Platz nur über die voll verfolgten Boote; in grossen Feldern gilt
  `RaceFieldSummary.place`. `Race.lanes` ist zugleich die Höchstzahl Teilnehmender (300 Bahnen im Loopback-Hub).
- Gestaffelte Starts (Zeitfahren) und Vorläufe; Freunde/Markierte aus dem Profil.
- Prüfung im Simulator und auf dem A12X-iPad (Bildrate, Speicher).
- Grenzen des Formats: höchstens 65 535 Teilnehmende, Distanz bis 1677 km, Schlagzahl bis 63.

## Erledigt / offen

| Erledigt | Offen |
|---|---|
| Modelle, Uhr, Drossel, Verfolgung, Bahnen, Platz/Abstände, Ergebnisliste | Firebase-Transport, Anmeldung, Turnier-Oberfläche |
| Loopback-Transport (mehrere Boote im Speicher), Geister/Bots | „Gegen meine Bestfahrt“ als Knopf auf der Streckenseite (Transport und Szene sind fertig) |
| Anbindung an die Fahrt (`attachRace`), Boote mit Namen in der Szene, `raceId` im Training | Anzeige von Platz und Abstand im HUD, Countdown vor gemeinsamem Start (Fahrt startet heute mit dem ersten Schlag) |
| 28 Tests (Linux), Android-Bau | Prüfung im Simulator mit `-demoRace 1` (Mac) |
| Grosse Felder im Kit: Übersicht, Nachbarschafts-Abo, Planer, Bot-Feld, 20 Tests | Firebase-Transport mit Aggregator, Einbau des Planers in Szene und HUD (siehe „Grosse Felder“, Offen) |
| Erscheinung im `RaceParticipant` (Profil, Datenschutzregel, Bots mit `random(seed:)` im Demo-Rennen), Tests | Figur und Boot je Teilnehmer in der Szene (3D), Erscheinung im Firebase-Beitritt |
