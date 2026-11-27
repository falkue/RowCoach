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
| `RaceParticipant` | id, Anzeigename, Bahn, Quelle (`human`, `ghost`, `bot`, `virtual`; unbekannte Werte lesen als `bot`), Erscheinung (`appearance`, optional) |
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
  jedem `LiveFrame` (ca. 150–300 Byte JSON: Figur-, Farb- und Boot-Ids, Form-Überschreibungen nur wenn gesetzt, zwei Flaggen-Schalter,
  ggf. Ländercode).
  Ältere Clients ohne das Feld dekodieren weiter (optional, `nil` wird nicht gesendet).
- Die App setzt für sich selbst `RowerProfile.publicAppearance` (aus `RowerProfileStore.shared.appearance`):
  - **Nationalität** nur, wenn mindestens einer der Schalter „Flagge auf dem Trikot“ / „Flagge auf dem Boot“ an ist;
    ohne gewählte Nationalität sind beide Schalter aus.
  - Ein **Geschlecht** gibt es nicht mehr (Feld gestrichen, Entscheidung Falk 26.11.2026); die Erscheinung enthält
    nur Aussehen (Vorlage, Farben, Form-Überschreibungen wie Frisur, Statur, Oberteil, Kopfbedeckung) und Boot.
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

**Empfehlung: Variante (1)** – inzwischen mit Dead Reckoning, Binärframes und Delta-Übersicht weiter verfeinert und gemessen, siehe Abschnitt „Dead Reckoning und Kosten je Rennen“ (0,053 statt 1,7 USD je 300er-Rennen); die Zahlen hier sind die erste Schätzung. Begrenzte, vorhersehbare Last je Gerät (≈ 9 KB/s statt 135 KB/s, Faktor 14), weit
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

## Dead Reckoning und Kosten je Rennen (Stand 26.11.2026, gemessen)

Falk (26.11.): Echtzeitdaten der Nachbarn sind nicht nötig, Näherungen reichen; genau nur vor der Ziellinie bei denen,
die einen umringen. Kalkulation: 5 USD Abo im Monat, höchstens 15 Rennen je Person; ein Rennen soll gegenüber der
Dead-Reckoning-Variante nochmals um zwei Drittel günstiger werden, ohne den Zieleinlauf zu verschlechtern.
Code: `RaceDeadReckoning.swift` (Voraussage, Sender, Aggregator, Binärframe, Kostenmodell), Empfänger in
`RemoteRowerTracker` (Modus `deadReckoning`), Delta-Übersicht in `RaceField.swift`; Messung in
`RaceDeadReckoningTests.swift` (`simulateRace`).

### Verfahren (Standard im Kit = gewählter Satz)

- **Gemeinsame Voraussage** (`RaceDeadReckoning.predict`): letzter Frame + Geschwindigkeit aus dem Tempo × Zeit; an
  der Ziellinie bleibt die Voraussage stehen. Sender, Empfänger und Aggregator rechnen dasselbe. Einen Tempo-Trend
  braucht es nicht: Ermüdung und Schwankungen verschieben die Distanz um weniger als 1 m, bevor ohnehin gesendet wird.
- **Sender** (`RaceDeadReckoningPublisher`, in `RaceCoordinator.deadReckoning`): sendet, wenn die wahre Distanz um mehr
  als 4 m von der Voraussage abweicht, bei einem Tempo-Sprung ≥ 4 s/500 m oder einem Schlagzahl-Sprung ≥ 2, als
  Lebenszeichen alle 20 s und höchstens einmal je Sekunde. Den Grund protokolliert `lastReason`.
- **Präzisionsmodus**: in den letzten 250 m, sobald ein anderes Boot ± 30 m entfernt ist, kommt spätestens jede
  Sekunde ein Frame und bei Abweichung > 0,5 m schon nach 0,5 s, also 1–2 Frames/s. Die Nachbarschaft wächst dort von
  K = 8 auf 16 (`RaceScenePlanner.Config.interestCountFinish`, `finishDistance`).
- **Ziel**: Der Zielframe geht sofort und unabhängig von allen Regeln mit der exakt interpolierten Zielzeit (Binärformat
  auf die Millisekunde). Die Wertung hängt nicht an der Näherung; gemessener Zielzeitfehler 0,0000 s.
- **Empfänger** (`RemoteRowerTracker.deadReckoning(finishDistance:)`): zeigt ohne Verzögerung dieselbe Voraussage.
  Die Ruderbewegung zeichnet er aus der Schlagzahl des letzten Frames. Eine Korrektur blendet er mit höchstens 1 m/s
  ein, ohne Sprung; über 30 m springt er, etwa nach einem Verbindungsabbruch. An der Ziellinie wartet das Boot auf den
  Zielframe. Veraltet ist ein Boot nach 2 × Lebenszeichen + 5 s = 45 s; schneller erkennt den Abbruch die
  Anwesenheit über `onDisconnect`, die der Aggregator als „veraltet“ meldet.
- **Übersicht** (`RaceFieldAggregator`): alle 10 s ein Delta mit den Einträgen, deren Stand mehr als 8 m von der
  Voraussage aus dem zuletzt verteilten Eintrag abweicht, oder deren Status, Tempo bzw. Schlagzahl sich änderte. In
  der Zielzone (letzte 250 m) gilt ein 5-s-Takt mit 1 m Schwelle. Die volle Übersicht liest jedes Gerät beim Beitritt
  einmal; an alle geht sie nur alle 300 s als Abgleich. Auf dem Draht unterscheidet das Versionsbyte 2 ein Delta;
  `RaceFieldTracker` ergänzt Deltas und rechnet jeden Eintrag ab seiner eigenen Rennzeit voraus.
- **Binärframes** (`RaceCompactFrame`): 18 Byte, im Ziel 22 Byte (Kurzindex statt uid), als Base64-String in der
  Realtime Database 24 bzw. 32 Zeichen statt 94 Byte JSON.
- **Firebase-Aufbau**:
  - `/live/{raceId}/f/{uid}` = Binärframe (Base64), Listener je abonnierter uid.
  - `/live/{raceId}/field` = letztes Delta (alle hören zu).
  - `/live/{raceId}/fieldFull` = volle Übersicht (kein Listener, `get()` beim Beitritt).
  - `/live/{raceId}/online/{uid}` mit `onDisconnect().remove()`.

### Messung: 300 Bots über 2000 m

Aufbau der Simulation (`simulateRace`):
- **Bots:** 300 aus `RaceBotField` (Saat 11): Tempostreuung, Anlauf, Ermüdung, Schwankung, 1–3 Zwischenspurts je Bot
  (−3 s/500 m, +1,5 Schläge), Schlagzahl folgt dem Tempo, Endspurt.
- **Takt und Laufzeiten:** 10 Schritte/s; Laufzeit 0,2 s, zum Aggregator 0,1 s.
- **Nachbarschaft:** die K nächsten mit 20 m Hysterese, alle 2 s neu; beim Abo kommt der aktuelle Stand einmal mit.
- **Fehlermessung:** jede Sekunde je Paar Gerät–Nachbar. „Zielzone“ heisst beide in den letzten 250 m und ± 30 m.
- **Kostenmodell (`RaceCostModel`):** 60 Byte Rahmen je zugestellter Änderung und 40 Byte Schreibbestätigung (beides
  Annahmen); 1 USD/GB Download, nach 360 MB/Tag frei (Firebase „Pricing“, abgerufen 26.11.2026).
- **Aggregator (Cloud Run):** 1 vCPU/0,5 GiB über das Rennen + 4 min, bzw. 0,25 vCPU/0,25 GiB nur im Rennfenster + 1 min.
  Preise ca.: 0,000024 USD je vCPU-s, 0,0000025 USD je GiB-s, zu prüfen.

Rennen: 606 s vom Start bis der letzte im Ziel ist. Jede Zeile enthält die Hebel der Zeilen darüber (ab „K 8“).

| Variante | Frames je Teiln./s | Bytes/s je Gerät | DB: Schreiben/s · Antworten/s | USD je Rennen (300) | USD je Teiln. und Rennen | USD je Abonnent/Monat (15 Rennen) | Fehler nahe Boote ausserhalb: Mittel/95 %/max (m) | nahe Boote Zielzone | Übersicht ausserhalb | Übersicht Zielzone |
|---|---|---|---|---|---|---|---|---|---|---|
| bisheriger Plan (2,5/s, K 16, Übersicht 1/s voll, JSON) | 1,85 | 8937 | 555 · 10 256 | 1,711 | 0,00570 | 0,0855 | 1,63/1,81/2,20 ¹ | 1,66/1,81/1,98 ¹ | 0,00/0,01/0,19 | 0,01/0,00/1,21 |
| **Dead Reckoning** (4 m, Lebenszeichen 8 s, K 16, Übersicht 5 s Delta (5 m) / 30 s voll, JSON) | 0,208 | 824 | 63 · 1193 | **0,178** | 0,00059 | 0,0089 | 0,04/0,15/1,10 | 0,00/0,00/0,81 | 0,43/1,39/3,30 | 0,32/1,16/2,60 |
| DR + dichter beim knappen Überholen (< 10 m, sich annähernd) | 0,220 | 859 | 66 · 1253 | 0,185 | 0,00062 | 0,0093 | 0,04/0,14/1,10 | 0,00/0,00/0,81 | 0,42/1,38/3,30 | 0,32/1,16/2,60 |
| DR + K 8 ausserhalb der Zielzone (16 in der Zone) | 0,208 | 655 | 63 · 929 | 0,148 | 0,00049 | 0,0074 | 0,04/0,15/1,10 | 0,00/0,00/0,81 | 0,43/1,39/3,30 | 0,32/1,16/2,60 |
| … + Binärframes (24 statt 94 Byte) | 0,208 | 386 | 63 · 929 | 0,095 | 0,00032 | 0,0048 | 0,04/0,15/1,10 | 0,00/0,00/0,81 | 0,43/1,39/3,30 | 0,32/1,16/2,60 |
| … + Lebenszeichen 20 s | 0,158 | 347 | 48 · 780 | 0,087 | 0,00029 | 0,0044 | 0,20/0,73/2,94 | 0,00/0,00/1,42 | 0,65/1,99/5,23 | 0,33/1,19/3,28 |
| … + Übersicht 10 s Delta (8 m), voll beim Beitritt und alle 300 s | 0,158 | 243 | 48 · 752 | 0,068 | 0,00023 | 0,0034 | 0,20/0,73/2,94 | 0,00/0,00/1,42 | 1,83/5,61/9,87 | 1,72/5,43/8,71 |
| … + Übersicht in der Zielzone alle 5 s mit 1 m | 0,158 | 253 | 48 · 762 | 0,070 | 0,00023 | 0,0035 | 0,20/0,73/2,94 | 0,00/0,00/1,42 | 1,84/5,64/9,27 | 0,41/1,08/7,70 |
| … + Schwelle 6 m ausserhalb der Zielzone | 0,158 | 253 | 48 · 762 | 0,070 | 0,00023 | 0,0035 | wie oben | wie oben | wie oben | wie oben |
| **gewählter Satz:** … + kleiner Aggregator (0,25 vCPU, nur Rennfenster) | 0,158 | 253 | 48 · 762 | **0,053** | 0,000176 | **0,0026** | 0,20/0,73/2,94 | 0,00/0,00/1,42 | 1,84/5,64/9,27 | 0,41/1,08/7,70 |

¹ Der bisherige Plan zeigt die anderen absichtlich 0,4 s verzögert (ruhige Interpolation); daher ≈ 1,6 m hinter der
Wahrheit, ein gleichmässiger Versatz für alle.

**Ergebnis:** Dead Reckoning allein senkt Download und Kosten gegenüber dem bisherigen Plan um den Faktor 10
(1,71 → 0,178 USD je 300er-Rennen). Der gewählte Satz kostet **0,053 USD = 30 %** davon, also unter einem Drittel; der
Download allein sinkt auf 31 % (0,157 → 0,048 GB). Der Zieleinlauf wird nicht schlechter:
- Zielzeiten exakt.
- Nahe Boote in der Zielzone im Mittel und 95-%-Quantil 0,00 m. Das Maximum steigt von 0,81 auf 1,42 m, einmal beim
  Eintritt in die Zone mit einem bis zu 20 s alten Frame.
- Übersicht in der Zielzone 1,08 statt 1,16 m (95 %).

Ausserhalb der Zielzone wachsen die Fehler wie gewünscht: nahe Boote 95 % 0,73 m, Übersicht 95 % 5,6 m (Minikarte,
ferne Silhouetten). Sendegründe im gewählten Satz: Präzisionsmodus 63 %, Lebenszeichen 17 %, Tempo 12 %, Schlagzahl 6 %,
Start und Ziel je 1 %. Die Abweichungsschwelle selbst löst bei diesen Bots nie aus, weil die anderen Regeln früher
greifen; deshalb bringt eine 6-m-Schwelle nichts.

**Abgewogen, nicht übernommen**
- *Dichter beim knappen Überholen* (< 10 m, sich annähernd, Präzisionstakt): +6 % Frames, +4 % Kosten, und der Fehler
  sinkt nur von 0,15 auf 0,14 m (95 %), weil Überholvorgänge mit 0,1–0,5 m/s Unterschied ohnehin unter der 4-m-Schwelle
  bleiben. Der Parameter `closeOvertakeRange` bleibt, Standard aus.
- *Präzisionsmodus seltener*: Er ist der grösste Posten (63 % der Frames), trägt aber den Zieleinlauf; unverändert.
- *Bündelung mehrerer Nachbarn in ein Dokument je 50-m-Fenster*: ein Abo statt K, aber die Realtime Database schickt
  ohnehin nur geänderte Kinder. Die Bytes hängen dann an der Dichte (im Pulk 50–100 Boote je Fenster) statt an K;
  bei Dead Reckoning teurer.
- *„Lead“-Gerät statt Aggregator*: spart den Cloud-Run-Anteil, im gewählten Satz 0,005 USD je Rennen. Dafür braucht
  es Übergabe beim Abbruch, und ein Teilnehmer erzeugt die Übersicht der anderen (Betrug, Plausibilität). Erst
  sinnvoll, wenn Fixkosten zählen, also bei kleinen Feldern; dort genügt aber auch „alle hören alle“ ohne Übersicht
  (unten).
- *Nur Aggregator ohne RTDB-Fan-out* (Geräte fragen den Dienst): Der Verkehr läuft dann über Cloud Run (Egress
  ≈ 0,12 USD/GB, ähnlich teuer) und braucht eigene WebSocket-Verbindungen und Skalierung. Kein Vorteil bei diesen
  Mengen.
- *Fixkosten*: Blaze hat keine Grundgebühr, Verbindungen kosten nichts (Grenze 200 000), und Speicher fällt kaum an
  (nur letzte Frames). Der Aggregator kostet mit 1 vCPU über das Rennen ± 2 min ≈ 0,021 USD, mit 0,25 vCPU nur im
  Rennfenster ≈ 0,005 USD. Ein Dienst kann mehrere gleichzeitige Rennen bedienen, das teilt die Fixkosten.

### Kosten je Abonnent und Monat (gewählter Satz, je gemessen über 2000 m)

| Feldgrösse | Bytes/s je Gerät | Schreiben/s · Antworten/s | USD je Rennen | USD je Teilnehmer und Rennen | USD je Abonnent/Monat (15 Rennen) | Anteil an 5 USD |
|---|---|---|---|---|---|---|
| 10 | 79 | 1,2 · 11 | 0,0049 ² | 0,00050 | 0,0074 | 0,15 % |
| 50 | 175 | 7,9 · 109 | 0,0101 | 0,00020 | 0,0030 | 0,06 % |
| 300 | 253 | 48 · 762 | 0,0529 | 0,00018 | 0,0026 | 0,05 % |

² Bei 10 Teilnehmenden ist fast alles Fixkosten des Aggregators (0,0048 USD). Bis ca. 30 Teilnehmende ohne Aggregator
fahren: alle hören alle (Dead Reckoning), Übersicht und Platz rechnet jedes Gerät selbst. Dann ≈ 0,0005 USD je Rennen.

**Weitere Kostenblöcke ausserhalb des Rennens** (grob, je Abonnent und Monat):
- **App-Store-Provision** 15 % (Small Business Program) bis 30 % von 5 USD = **0,75–1,50 USD**. Mit Abstand der grösste
  Block, kein Firebase-Posten.
- **Strecken-Downloads** über Firebase Hosting: Pakete 35–70 MB (`docs/ENTSCHEIDUNGEN.md`), 0,15 USD/GB nach 10 GB/Monat
  frei. Bei 2 neuen Strecken im Monat ≈ 120 MB ≈ **0,02 USD**, ein Mehrfaches der Rennkosten. Hebel: Delta-Updates (der
  Installer lädt schon nur geänderte Dateien), Qualitätsstufen, CDN-Cache.
- **Anmeldung** (Firebase Authentication mit Apple/Google): bis 50 000 aktive Nutzer im Monat kostenlos, darüber ca.
  0,005 USD je aktivem Nutzer (Identity-Platform-Preise, zu prüfen).
- **Firestore** (Turniere, Teilnehmende, Ergebnisse): je Rennen ca. 20 Lesungen und 2 Schreibvorgänge je Person. Die
  Ergebnisliste als ein Dokument statt 300 lesen, dann ≈ 0,0003 USD im Monat.
- **Cloud Functions** (Start, Ergebnisse festschreiben, Plausibilität): wenige Aufrufe je Rennen, im Freikontingent.

Fazit: Mit dem gewählten Satz kostet ein Rennen je Person rund 0,0002 USD, bei 15 Rennen im Monat ≈ 0,003 USD. Die
Rennkosten sind damit kein Thema mehr; Strecken-Downloads und vor allem die Store-Provision bestimmen die Marge.

**Offen**
- Die Bots fahren ruhiger als ein echter PM5: Das Tempo schwankt dort von Schlag zu Schlag um 1–3 s. Vor dem Einsatz
  aufgezeichnete Fahrten (`WorkoutRecord.samples`) durch den Sender schicken und Tempo bzw. Schlagzahl vor dem
  Vergleich über 2–3 Schläge glätten, sonst steigen die Sendegründe Tempo und Schlagzahl.
- Firebase-Transport mit Binärframes, Delta-/Voll-Knoten und Anwesenheit; Aggregator als kleiner Cloud-Run-Dienst;
  ohne Aggregator bis ca. 30 Teilnehmende.
- Die Rahmen- und Bestätigungsgrössen (60/40 Byte) im echten Betrieb messen (Firebase-Profiler).

## Umsetzung App (Stand 26.11.2026, ungebaut – auf dem Mac prüfen)

Der Planer läuft in der App; Szene und HUD folgen seinen Schritten. Firebase gibt es noch nicht: getestet wird mit
`-demoRace <N>` (siehe BUILD.md).

| Baustein | Datei | Was |
|---|---|---|
| Planer-Schritt | `Session/SessionController.swift` | `attachRace`: Planer anlegen (`makePlanner`: Budget nach Gerät, sichtbare Bahnen aus der Strecke, `finishDistance` und Länge für Zielzone und Dichteleiste) und eine Schleife mit 10 Schritten/s starten (nicht mehr bei jedem empfangenen Frame neu zeichnen). Je Schritt `RaceLink.members(…)` → `RaceScenePlanner.plan(…)` → `raceScene: RaceSceneFrame`; bei `interestChanged` `RaceLink.setInterest`. `reportSceneFrameRate(_:)` gibt die Bildrate an den Planer. `raceStates` entfällt. |
| Schritt für Szene/HUD | `Session/RaceSceneFrame.swift` | `RaceSceneFrame` (Einträge, Pulk-Gruppen, `RaceFieldSummary`, Teilnehmende, eigene Distanz, Renn-Länge); `RaceDeviceProfile` (Modellkennung über `uname` bzw. `SIMULATOR_MODEL_IDENTIFIER` → `RaceRenderBudget.forDevice` im Kit; `-raceBudget` übersteuert) |
| Szene | `Scene3D/RaceRowers.swift` | je Eintrag: `full`/`lite` → Rig aus dem `BoatRigPool` (`setDetail(.full/.lite)`, Schild nur bei `full`), `impostor` → Silhouette, sonst nichts. Distanz weich nachgezogen wie bisher, `lateral` des Planers zusätzlich geglättet, Lage über `RaceSceneLayout`. Ein-/Ausblenden (`setFade`) nur für vorab angelegte Rigs. |
| Ferne Boote | `Scene3D/RaceImpostors.swift` | ein `LowLevelMesh` (Position, 32-Bit-Indizes) für bis zu 400 Silhouetten: 7 Ecken, 6 Dreiecke je Boot (beidseitig), `UnlitMaterial`, keine Schatten, ein Draw-Call. Pro Bild werden nur die Ecken neu geschrieben. Pulk-Gruppen zeichnen bis 5 Silhouetten über Länge und rechte Bahnen verteilt. Geht das Anlegen schief, bleibt die Stufe leer (Log „Impostoren nicht verfügbar“). |
| Einbindung | `Scene3D/RowingSceneController.swift`, `RowingSceneView.swift` | `.raceScene(frame) { fps in … }` statt `.raceRowers(states)`; `setRaceScene`; Bildrate aus `SceneEvents.Update.deltaTime`, jede Sekunde gemeldet; `prewarmRaceIfExpected()` legt nach `build` und vor dem Laden der Landschaft `voll + vereinfacht` Rigs an (wegen des A12X-Hinweises in `BoatRig.setFade`), wenn `RaceRowersSystem.prewarmHint` (RowingView) oder `-demoRace` gesetzt ist |
| HUD | `Views/RaceFieldPanel.swift`, `RowingView.swift` | unter Phasen- bzw. Tempo-Linien-Anzeige: Platz „143 von 300“, ▲/▼ Abstand vorne/hinten (m · s), „Pulk N“ (± 25 m), die drei Führenden (Hochformat: nur der erste), Dichteleiste entlang der Strecke mit eigener Position. Englische Texte in `App/l10n/en_strings.py`. |
| Demo | `RowingView.demoField` | `-demoRace N` (N ≥ 2): `RaceBotField` (N Bots um das eigene Tempo, Verlauf bis ins Ziel vorausgerechnet) und `RaceBotTransport` (volle Frames nur für das Abo, jede Sekunde eine volle Übersicht); `-demoRace 1` unverändert |
| Kit | `RaceScenePlanner.swift` | `RaceSceneItem.strokeRate`/`finished` (Ruderbewegung), `RaceRenderBudget.forDevice` (getestet), `RaceFieldMember.merge`: veraltete volle Verfolgung (Boot hat die Nachbarschaft verlassen) weicht der Übersicht |

Noch nicht eingebaut: Dead-Reckoning-Sender und -Empfänger (`RaceCoordinator.deadReckoning`,
`RemoteRowerTracker.deadReckoning`) – sie gehören zum Firebase-Transport; der Bot-Transport sendet weiter mit fester
Rate.

**Auf dem Mac prüfen (stumm, Simulator und A12X-iPad)**
1. `xcodegen generate`, bauen: neue Dateien `RaceSceneFrame.swift`, `RaceImpostors.swift`, `RaceFieldPanel.swift`;
   unsicher ohne Compiler sind die `LowLevelMesh`-Aufrufe (`Attribute`, `Layout`, `Part(indexCount:topology:bounds:)`,
   `MeshResource(from:)`) und die Tupel-Typen in `RaceRowers`.
2. `-demoCourse rhein-basel -demoRace 300` (Simulator-Ruderer): Protokoll Kategorie Race „Planer für … Budget …“,
   nach dem ersten Schlag „gezeigt voll 6, vereinfacht …, Impostoren …“, Szene alle 10 s „Silhouetten …, Vorrat …“
   (Vorrat soll bei voll + vereinfacht bleiben, nicht wachsen).
3. Bild: nahe Boote mit Figur und Schild, dahinter vereinfachte, in der Ferne dunkle Silhouetten; beim Wechsel kein
   Springen (seitlich wandern sie langsam). Werden Silhouetten nicht gezeigt (nur Mesh ohne Normalen), notfalls
   Normalen ergänzen oder auf `MeshResource.generate` je Schritt ausweichen.
4. A12X: Bildrate mit `-demoRace 300`; fällt sie unter 50 fps, meldet der Planer nach 2 s eine kleinere Stufe (Log
   „Szene: Rennboote voll …“ zeigt weniger). Mit `-raceBudget high` gegenprüfen, dass die Rückkopplung greift.
   Sind eingeblendete Boote unsichtbar (A12X, `OpacityComponent`), Ein-/Ausblenden in `RaceRowersSystem.prewarm`
   abschalten (`warm` leer lassen).
5. HUD im Quer- und Hochformat: Platz, Abstände, Führende, Dichteleiste; Platz steigt/fällt beim Überholen.
6. `-demoRace 1`: zwei Bots wie bisher (jetzt über den Planer: beide `full`).
7. Ohne Rennen: keine Änderung (kein Vorrat, keine Planer-Schleife).

## Virtuelle Teilnehmende (Stand 27.11.2026, Freigabe Falk: transparente Variante)

Turniere sollen nie leer wirken. Fehlen echte Anmeldungen, füllen **virtuelle Teilnehmende** das Feld auf. Sie sind
**immer gekennzeichnet** (✦, VoiceOver „virtuell“) und bilden keine echte Person nach. Code im Kit unter
`Sources/RowCoachKit/VirtualRowers/` (nur Foundation), Tests in `VirtualRacerTests.swift`.

### Regeln

1. **Mindestfeld:** Beim Anlegen eines Turniers wird eine Zahl 45…387 gewürfelt, gleichverteilt und deterministisch
   aus Turnier-Id und Saat (`TournamentFieldFiller.minimumField`, SplitMix64 ohne Modulo-Verzerrung). Weniger echte
   Anmeldungen → mit virtuellen genau bis zur Zahl auffüllen; gleich viele oder mehr echte → keine virtuellen.
2. **Pool v1:** 5000 erfundene Ruderer (`VirtualRowerPool`), aus fester Saat erzeugt und als Datei mitgeliefert
   (`App/RowCoach/Resources/virtual-rowers-v1.bin`, 92 847 Byte ≈ 18,6 Byte je Person). Geladen wird immer die Datei;
   ein Test prüft, dass der Generator sie bitgenau nachbildet. Ändert sich der Generator, entsteht Pool v2 mit neuen
   Ids (`v2-…`) – nie still ein anderer Pool unter derselben Version. Je Person:
   - stabile Id `v1-0001` … `v1-5000`, **nur Vorname** passend zum Land (offene Namensliste, siehe Quellen) und Land
     (ISO 3166-1 alpha-2). Anzeige „Vorname · Länderkürzel ✦“ bzw. Flagge am Boot.
   - Land nach Gewicht (`VirtualRowerCountries.all`, eigene Schätzung; im Pool v1 69 Länder): USA 22 %,
     Grossbritannien 11 %, Deutschland 6 %, Kanada und Australien je 5 %, insgesamt 56 % Europa, 28 % Nordamerika,
     8 % Ozeanien, 8 % Asien, Südamerika, Afrika (Thailand fehlt mangels weiblicher Vornamen in der Liste). Zeitzone je Person aus den Zonen des Landes nach Bevölkerungsanteil (USA, Kanada,
     Mexiko, Brasilien, Australien, Russland), Sommerzeit-Regel (EU, USA, Südost-Australien, Neuseeland, Chile).
   - Erscheinung `RowerAppearance.random(seed: id)` (Figur, Trikot, Boot aus dem Katalog), Flagge des Landes am
     Boot, am Trikot bei der Hälfte. Hautton und Figur sind bewusst **nicht** nach Land gewichtet.
   - Leistung: 2000-m-Zeit aus der Verteilung der Concept2-Rangliste 2025 (Männer- bzw. Frauen-Verteilung, 25 %
     Frauen), Altersgruppe 18–29 … 70+ mit Faktor (normiert, Gesamtverteilung bleibt), Exponent des
     Leistungs-Dauer-Gesetzes 0,10–0,20 (Ausdauer- bis Sprinttyp); Schwelle daraus wie `ThresholdMath`.
   - Rennstil: gleichmässig 40 %, schneller Start 25 %, Endspurt 25 %, Einbrecher 10 %.
   - Tagesform (Standardabweichung 1,2–3,7 % der Leistung, 4 % Tage mit Einbruch um 3–8 %), saisonale Form
     (± 1–4,5 %, Höhepunkt Mitte Februar im Norden bzw. Mitte August im Süden, in den Tropen ein Drittel),
     Zuverlässigkeit 0,15–1 (Münzwurf je Ortstag: verfügbar oder nicht), bevorzugte Tageszeit (morgens, mittags,
     abends, spät).
3. **Zeitzonen:** Nur Personen, bei denen es zum Start 06:00–22:00 Ortszeit ist; 07–21 Uhr volles Gewicht, die
   Randstunden 30 %, ± 2 h um die bevorzugte Stunde +60 %. Beispiele (Tests): 19:00 in Zürich im Sommer → keine
   Japaner, Neuseeländer, Australier; 08:00 MEZ → Australien, Neuseeland, Japan möglich, keine Amerikaner.
   Achtung: Im europäischen Winter ist 19:00 MEZ in Neuseeland 07:00 (Sommerzeit dort) – Neuseeländer dürfen dann
   mitfahren (Frühruderer), Japaner nicht.
4. **Auswahl und Rotation** (`TournamentFieldFiller.select`): gewichtete Ziehung ohne Zurücklegen (Schlüssel
   −ln(u)/w, deterministisch je Rennen und Person). Gewicht = Ortszeit × Niveau (Normalverteilung um den Median der
   echten 2k-Zeiten, Breite max(30 s, 1,2 × Streuung der echten); ohne Werte um den Pool-Median; optional harte
   Leistungsklasse) × (0,5 + 0,5 × Zuverlässigkeit) × „zuletzt gefahren“ (0,05 direkt danach, quadratisch bis
   voll nach 7 Tagen). Nie zweimal am selben Ortstag, höchstens 3 Rennen in 7 Tagen. Reicht das nicht, wird
   gelockert: erst Verfügbarkeit, dann Klasse und Wochengrenze, zuletzt das Zeitfenster.
   Messung (Test): 30 Tage, täglich ein Rennen mit 300 virtuellen um 18:00 UTC → 2910 verschiedene Personen,
   höchstens 9 Rennen je Person im Monat und 3 je Woche, 1,7 % fahren am Folgetag wieder. Wiederholungen binnen
   7 Tagen (43 %) sind bei 300 Plätzen täglich zur selben Uhrzeit und ≈ 2800 erreichbaren Personen unvermeidlich.
5. **Kennzeichnung:** Namensschild in der Szene („Lea · SE ✦“, `RaceRowers`), Führende im HUD (`RaceFieldPanel`,
   VoiceOver „Lea, virtuell“), Ergebnis- und Ranglistenansicht (`RaceResultsView`: ✦, VoiceOver „virtuell“, Fussnote).
   Beim ersten Turnier ein Info-Blatt (`VirtualParticipantsInfoView`, danach über „i“ in der Ergebnisansicht).
   Filter „Alle“ / „Nur echte“ (Plätze neu gezählt).
   **Standard „Alle“** – Begründung: Die Ergebnisliste soll zeigen, wie das Rennen war (man hat sie überholt bzw.
   wurde überholt); „Nur echte“ ist einen Tipp entfernt. Damit virtuelle, die öfter fahren als echte, die
   **Saisonwertung** nicht beherrschen, zählen dort nur die besten 10 Rennen je Person (`seasonBestOf`). Sollten
   echte Personen sich trotzdem verdrängt fühlen, wäre für die Saisonwertung „Nur echte“ als Standard die nächste Stufe.
6. **Persistente Ranglisten** (`RaceRankingBook`): Ergebnisse je Person und Rennen (Strecke, Ziel, Datum, Platz,
   Feldgrösse, Zeit/Distanz, `isVirtual`), Bestzeiten je Distanz (optional Strecke, Saison), Saisonwertung (Saison
   1. Mai – 30. April wie Concept2, Punkte 100 für den Sieg linear bis 1 für den letzten Platz, beste 10),
   Verlauf je Person. Virtuelle sammeln Ergebnisse wie echte.

### Rennsimulation (`VirtualRaceSimulator`)

- Formfaktor = Saison × Tagesform aus dem Zufall `raceId|rowerId` (gleich auf allen Geräten).
- Mittleres Tempo: Leistung P(t) = P2k · Form · (t / t2k)^(−b), Fixpunkt für die Zeit über die Distanz
  (Zeitrennen: Leistung über das Zeitlimit). Watt ↔ Tempo nach Concept2.
- Verlauf in 1-s-Schritten: Stilprofil (normiert auf Mittelwert 0), Schwankung ± 0,4–1,2 s/500 m mit 25–80 s
  Periode, Anlauf in 10 s (Verlust ausgeglichen), Schlagzahl folgt dem Tempo. Zielzeit auf die Millisekunde.
  Messung: Zielzeit weicht im Median < 1 % von der erwarteten Zeit des Tages ab, höchstens 3 %.
- **Bitgenau auf allen Plattformen:** Systemfunktionen wie `log`, `exp`, `pow`, `sin` sind nicht überall gleich
  gerundet. Pool, Auswahl und Simulation rechnen deshalb mit `DetMath` (nur + − × ÷ und Wurzel, Reihen mit fester
  Reihenfolge) und eigenem Kalender (ohne `Calendar`/Zeitzonendatenbank).
- Abspielen: `VirtualTournamentRace` (Feld + Läufe) → `botField` → `RaceBotTransport` (wie das Bot-Feld, Quelle
  `virtual`). Ergebnisse mit den echten: `results(real:)`; eigenes Ergebnis aus der Fahrt: `RaceResult.fromSamples`.

### Datenschutz und Transparenz

- Keine echte Person wird nachgebildet: Vornamen aus öffentlichen Listen häufiger Vornamen, keine Nachnamen,
  Land und Aussehen per Zufall, Leistung aus aggregierten Quantilen (keine Einzeldaten aus Ranglisten).
- Virtuelle Teilnehmende sind in jeder Ansicht erkennbar; Ranglisten lassen sich ohne sie anzeigen.
- Es werden keine Daten echter Personen in den Pool übernommen; der Pool ist öffentlich (Repository, Apache-2.0
  für den Code, Namen gemeinfrei).

### Textvorschlag für die Nutzungsbedingungen

> **Virtuelle Teilnehmende.** Damit Turniere jederzeit ein ausreichend grosses Feld haben, ergänzt RowCoach Turniere
> mit virtuellen Teilnehmenden. Das sind computergesteuerte, frei erfundene Ruderer; sie stellen keine realen
> Personen dar. Ihre Namen stammen aus öffentlichen Listen häufiger Vornamen, ihre Ergebnisse werden aus einem
> Leistungsmodell berechnet. Virtuelle Teilnehmende sind in der App stets mit dem Zeichen ✦ bzw. als „virtuell“
> gekennzeichnet und erscheinen mit diesem Kennzeichen auch in Ergebnislisten und Ranglisten. Du kannst Ranglisten
> jederzeit auf echte Teilnehmende beschränken. Haben sich genügend echte Teilnehmende angemeldet, nehmen keine
> virtuellen Teilnehmenden teil. Preise oder Auszeichnungen gehen nur an echte Teilnehmende.

> **Virtual participants.** To make sure tournaments always have a large enough field, RowCoach adds virtual
> participants. These are computer-controlled, made-up rowers; they do not represent real people. Their names come
> from public lists of common first names and their results are calculated from a performance model. Virtual
> participants are always marked in the app with the symbol ✦ or as “virtual”, including in result lists and
> rankings. You can limit rankings to real participants at any time. If enough real participants have signed up, no
> virtual participants take part. Prizes or awards go to real participants only.

### Server-Plan (nicht umgesetzt)

- Der Pool liegt als dieselbe Datei auf dem Server (Cloud Storage `pools/virtual-rowers-v1.bin`, öffentlich lesbar,
  oder im Functions-Bundle). Die App liefert dieselbe Datei mit; ein neuer Pool kommt nur als neue Version.
- **Beim Anlegen** eines Turniers würfelt eine Cloud Function das Mindestfeld (`minimumField`, Saat im Turnier-
  Dokument gespeichert) und schreibt es nach `tournaments/{id}` (`minField`, `seed`).
- **Beim Turnierstart** (Anmeldeschluss) füllt sie jedes Rennen auf: `fill(…)` mit der zentralen Rotation
  (`virtualHistory/{rowerId}`: letzter Start, Starts der letzten 14 Tage), schreibt die virtuellen nach
  `races/{id}/participants/{v1-…}` mit `source: "virtual"` und aktualisiert die Rotation. Die Logik liegt im Kit
  (Swift auf Linux) oder wird in TypeScript nachgebaut – dann müssen die Tests (Mindestfeld, Simulation) dieselben
  Werte liefern.
- **Live:** Virtuelle senden keine Frames über die Datenbank. Jedes Gerät simuliert sie selbst (gleiches Ergebnis
  überall); der Aggregator nimmt ihre Stände in die Übersicht auf (spart ≈ alle Schreibvorgänge der Virtuellen).
- **Ergebnisse fest:** Nach dem Rennen schreibt die Function die Ergebnisse aller (echte aus den Zielframes,
  virtuelle aus der Simulation) nach `races/{id}/results` und in die Ranglisten (`rankings/{season}/…`,
  `isVirtual` je Eintrag; Abfrage „nur echte“ über einen Index auf `isVirtual`). Die App zeigt bis dahin „vorläufig“.
- Plausibilität: Ein virtuelles Ergebnis ist nachvollziehbar (Pool-Version, Id, Rennen → Simulation).

### Demo und Prüfung

- Startargument `-demoTournament 1` (zusammen mit `-demoCourse …`, siehe BUILD.md): Turnier zur aktuellen Uhrzeit,
  gewürfeltes Mindestfeld, ich + 0–2 „echte“ Demo-Boote (Anna, Ben; gleichmässiges Tempo), Rest virtuell
  (`RowingView.demoTournament`, `VirtualTournamentStore`). Alle Boote laufen über **einen** `RaceBotTransport`
  (`VirtualTournamentRace.makeLink`, Demo-Boote als `VirtualRaceRun.steady`): Mit einem zweiten Transport stimmte die
  Teilnehmerliste des Geräts nicht mit der der Übersicht überein (`rosterHash`), die Übersicht wurde verworfen und
  nur die Demo-Boote waren zu sehen (Mac-Test 27.11.). Das Info-Blatt beim ersten Turnier erscheint vor dem Start;
  die Fahrt ist bis „Verstanden“ angehalten (`SessionController.hold`, Halten vor dem ersten Schlag zählt nicht).
  „Gesehen“ steht im UserDefaults-Schlüssel `virtualParticipantsInfoSeen` (`VirtualTournamentStore.infoSeen`);
  zurücksetzen mit dem Startargument `-resetVirtualInfo 1` (BUILD.md). Nach dem Speichern „Ergebnis und Rangliste“ in der
  Zusammenfassung; die Ergebnisse landen in der lokalen Rangliste (Application Support/race-rankings.json), die
  Rotation des nächsten Demo-Turniers berücksichtigt sie.
- Auf dem Mac prüfen (stumm): `xcodegen generate` (neue Dateien `Session/VirtualTournamentStore.swift`,
  `Views/RaceResultsView.swift`, Ressource `virtual-rowers-v1.bin` muss in „Copy Bundle Resources“ landen – Log
  „Pool v1: 5000 virtuelle Teilnehmende“); Namensschild „Name · SE ✦“ in der Szene (zeigt `generateText` das ✦?
  sonst `RaceParticipant.virtualMark` z. B. auf „*“ ändern); Info-Blatt beim ersten Turnier; Ergebnisansicht mit
  Filter, Bestzeiten, Saison; VoiceOver-Texte.

### Quellen

- Vornamen: sigpwned, „popular-names-by-country-dataset“, Datei `common-forenames-by-country.csv`, Commit
  eb62e13 (https://github.com/sigpwned/popular-names-by-country-dataset), CC0 1.0, zusammengestellt aus den
  Wikipedia-Listen „List of most popular given names“ (Juli 2023); 106 Länder, lateinische Umschrift. Erzeugt mit
  `tools/virtualrowers/make_names.py`. Schweden fehlt dort: zehn häufigste Vornamen Neugeborener 2024 laut
  Skatteverket (Statistikportal, vorläufig; berichtet u. a. von TV4). Vornamen sind Fakten, keine Werke.
- Leistungsverteilung: Concept2 Logbook, Rankings 2025, RowErg 2000 m (https://log.concept2.com/rankings/2025/rower/2000),
  abgerufen 27.11.2026: Männer 9561 Einträge (5 % 6:35, 25 % 7:13, Median 7:49, 75 % 8:31, 95 % 10:02), Frauen
  2546 (2 % 7:15, 25 % 8:07, Median 8:51, 75 % 9:50, 95 % 12:20); Ränder geschätzt. Länderanteile in Stichproben
  einzelner Seiten (USA ≈ 40–50 %, Grossbritannien ≈ 20 %, Australien ≈ 5 %, Deutschland ≈ 2–10 %).
- Länder-Gewichte, Altersfaktoren, Stilanteile, Tagesform und Saison: eigene Schätzungen (oben), in Pool v1 fest.

## Erledigt / offen

| Erledigt | Offen |
|---|---|
| Modelle, Uhr, Drossel, Verfolgung, Bahnen, Platz/Abstände, Ergebnisliste | Firebase-Transport, Anmeldung, Turnier-Oberfläche |
| Loopback-Transport (mehrere Boote im Speicher), Geister/Bots | „Gegen meine Bestfahrt“ als Knopf auf der Streckenseite (Transport und Szene sind fertig) |
| Anbindung an die Fahrt (`attachRace`), Boote mit Namen in der Szene, `raceId` im Training | Anzeige von Platz und Abstand im HUD, Countdown vor gemeinsamem Start (Fahrt startet heute mit dem ersten Schlag) |
| 28 Tests (Linux), Android-Bau | Prüfung im Simulator mit `-demoRace 1` (Mac) |
| Grosse Felder im Kit: Übersicht, Nachbarschafts-Abo, Planer, Bot-Feld, Dead Reckoning, Delta-Übersicht, Präzisionsmodus, Binärframes, Kostenmessung | Firebase-Transport mit Aggregator, Einbau des Planers in Szene und HUD (siehe „Grosse Felder“, Offen) |
| Planer in der App (Stufen, Bahnen, Silhouetten, Pulk, Bildraten-Rückkopplung, Gerätestufe), Rennanzeige im HUD, `-demoRace N` – ungebaut | Bau und Prüfung auf dem Mac (siehe „Umsetzung App“), Dead Reckoning im Firebase-Transport |
| Erscheinung im `RaceParticipant` (Profil, Datenschutzregel, Bots mit `random(seed:)` im Demo-Rennen), Tests | Figur und Boot je Teilnehmer in der Szene (3D), Erscheinung im Firebase-Beitritt |
| Virtuelle Teilnehmende im Kit (Pool v1, Mindestfeld, Auffüllen, Zeitzonen, Rotation, Simulation, Ranglisten), App-Kennzeichnung, Ergebnisansicht, `-demoTournament` – App ungebaut | Bau und Prüfung auf dem Mac; Cloud Function für Mindestfeld, Auffüllen und Ergebnisse; Aggregator mit simulierten Virtuellen |
