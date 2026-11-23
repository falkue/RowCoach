# RowCoach – Konzept (Entwurf 23.11.2026)

Status: **zur Freigabe durch Falk**. Es gibt noch keinen Code.

## 1. Ziel

RowCoach ist eine iPad- und iPhone-App für Falks **Concept2 RowErg mit PM5**. Man rudert damit durch 3D-Landschaften.

- Live-Daten vom PM5 über Bluetooth und der Puls vom Polar-Gurt
- Erste Strecke: **Zürichsee, unteres Seebecken**, etwa 4 km am Ufer entlang, hin und zurück mit einer Wende
- Nach jeder Einheit ein Trainingseintrag in **Apple Health**; das Health-Konto wird im Einstellungsmenü verbunden
- Später weitere Karten zur Auswahl. Deshalb wird jede Strecke als austauschbares Kartenpaket gebaut.
- Kein Abo, die Daten bleiben bei Falk

Vorerst nicht dabei: andere Rudergeräte, Strava- oder Garmin-Sync, KI-Coach, Mehrspieler. Diese Teile kommen in Abschnitt 8 vor, damit die Architektur sie später zulässt.

## 2. Was es schon gibt (Recherche)

Zotero und Fundus haben zu diesem Thema nichts. Die folgenden Angaben stammen aus dem Web und von GitHub (Stand 23.11.2026).

### 2.1 PM5-Schnittstelle
- Concept2 legt das Bluetooth-Protokoll offen: *PM5 Bluetooth Smart Interface Definition* (Rev. 1.27) und die *CSAFE Communication Definition*. Concept2 lädt ausdrücklich Drittentwickler ein. Wir nutzen also nur die vorgesehene Schnittstelle und umgehen nichts. Quelle: [Concept2 Software Development](https://www.concept2.com/support/software-development)
- Laut Spezifikation meldet der PM5 unter anderem verstrichene Zeit, Distanz, Tempo pro 500 m, Schlagzahl, Watt, Kalorien, Daten pro Schlag und Pausen- bzw. Intervallstatus. Er kann ausserdem selbst einen Bluetooth-Pulsgurt koppeln und dessen Puls weitergeben. Im Spike wird das gegen die Spezifikation geprüft.
- Bluetooth FTMS (der allgemeine Fitnessgeräte-Standard) wird vom PM5 nicht als Hauptweg genutzt. Massgeblich ist das Concept2-Protokoll.

### 2.2 Open-Source-Projekte (Lizenzen geprüft)
| Projekt | Sprache | Lizenz | Letzte Aktivität | Nutzen für uns |
|---|---|---|---|---|
| [BoutFitness/Concept2-SDK](https://github.com/BoutFitness/Concept2-SDK) | Swift | MIT | Aug. 2021 | Gute Vorlage für die Swift-Anbindung; Übernahme mit Lizenzhinweis möglich, aber veraltet (CocoaPods) |
| [RowBotics/Concept2-SDK](https://github.com/RowBotics/Concept2-SDK) | Swift (SPM) | **keine Lizenz** | Mai 2024 | Code nicht übernehmen (ohne Lizenz gilt: alle Rechte vorbehalten) |
| [OpenRowingCommunity/c2bluetooth](https://github.com/OpenRowingCommunity/c2bluetooth) | Flutter/Dart | LGPL-3.0 | Juni 2025 | Nur zum Nachlesen |
| [tijmenvangulik/ErgometerJS](https://github.com/tijmenvangulik/ErgometerJS) | JavaScript | eigene Lizenz | Nov. 2026, aktiv | Aktuelle Referenz für Datenstrukturen |
| [polarofficial/polar-ble-sdk](https://github.com/polarofficial/polar-ble-sdk) | Swift/Kotlin | eigene Lizenz, auch kommerziell erlaubt | Nov. 2026, aktiv | Nur nötig für Polar-Extras wie EKG oder Rohdaten |

**Empfehlung:** Eine eigene, schlanke Swift-Schicht auf CoreBluetooth, direkt nach der offiziellen Concept2-Spezifikation. Das BoutFitness-SDK (MIT) dient als Vorlage. Damit hängen wir an keiner veralteten Bibliothek und haben keine unklaren Lizenzen.

### 2.3 Puls (Polar)
- Polar-Gurte senden den Puls über das Standardprofil *Heart Rate Service* von Bluetooth. Puls und RR-Intervalle lassen sich deshalb ohne Polar-SDK lesen. Ausnahme: Beim Verity Sense ist im *SDK-Modus* das Puls-Streaming aus; dort muss der normale Modus aktiv sein.
- Es gibt zwei Wege. Beide bauen wir und vergleichen sie im Spike:
  - **A (Standard):** Die App verbindet sich direkt mit dem Gurt. Das ist am genauesten und liefert RR-Intervalle für spätere Auswertungen wie HRV.
  - **B (Rückfall):** Der Gurt wird am PM5 gekoppelt, und die App liest den Puls aus dem Datenstrom des PM5.
- Pulszonen kommen aus Falks Maximalpuls bzw. Laktatschwelle im Profil. Auf dem Ruderbildschirm wird der Puls nach Zone eingefärbt.

### 2.4 Apple Health
- Seit iOS/iPadOS 26 lassen sich Trainings auch auf iPhone und iPad mit `HKWorkoutSession` + `HKLiveWorkoutBuilder` aufzeichnen. Vorher ging das nur mit der Apple Watch. Ein gekoppelter Bluetooth-Pulsgurt wird dabei von HealthKit selbst mitgeschrieben. Quellen: [WWDC25 Session 322](https://developer.apple.com/videos/play/wwdc2025/322/), [HealthKit Updates](https://developer.apple.com/documentation/updates/healthkit)
- RowCoach schreibt ein Training vom Typ `rowing` (indoor) mit Dauer, Distanz, aktiven Kalorien und Pulsreihe. Mitgeliefert werden Metadaten wie Strecke, Durchschnittstempo, Schlagzahl und Watt. Die Strecke wird nicht als GPS-Route gespeichert, sie ist ja virtuell.
- **Im Spike zu prüfen:** Holt HealthKit den Puls selbst, wenn die App den Gurt auch direkt liest? Sonst schreibt die App die Pulswerte selbst in den Builder. Doppelte Einträge sind zu vermeiden.
- Das Einstellungsmenü zeigt den Health-Status. Dort erteilt man die Lese- und Schreibrechte, und ein Link führt in die Health-Einstellungen.

### 2.5 3D-Daten Zürichsee (swisstopo)
- Seit dem 1.3.2021 sind die swisstopo-Standarddaten frei nutzbar (Open Government Data), auch kommerziell. Bedingung ist die Quellenangabe „© swisstopo“. Quelle: [swisstopo Nutzungsbedingungen](https://www.swisstopo.admin.ch/en/terms-and-conditions)
- Für die erste Strecke brauchen wir vier Produkte:
  - **swissALTI3D**: Höhenmodell (0,5 m bzw. 2 m)
  - **swissBUILDINGS3D 3.0** (Beta, mit Dachformen; CityGML, zusätzlich als Cesium 3D Tiles gestreamt): Gebäude, siehe [Produktseite](https://www.swisstopo.admin.ch/en/geodata/landscape/buildings3d3.html) und [3D Tiles](https://docs.geo.admin.ch/visualize-data/3d-tiles.html)
  - **SWISSIMAGE**: Luftbild als Textur für Gelände und Ufer. Die aktuellen Nutzungsbedingungen prüfe ich vor dem Download.
  - **swissTLM3D**: Uferlinie bzw. Seefläche, Quaianlagen
- Vom Rohdatensatz zum App-Modell wird alles **auf der Spark** aufbereitet, nicht im iPad: Python-Skripte schneiden aus, vereinfachen, wandeln CityGML in Meshes um und exportieren USDZ. Die App lädt dann ein fertiges, kleines Kartenpaket (Rechenteil siehe Abschnitt 4a).

## 3. Plattform – Optionen und Empfehlung

| Option | Vorteile | Nachteile |
|---|---|---|
| **A. Native Swift-App (SwiftUI + RealityKit)** | HealthKit, Bluetooth und 3D aus einer Hand; flüssig auf iPad; läuft offline; eine Codebasis für iPad und iPhone | Braucht einen Mac mit Xcode zum Bauen |
| B. Native App mit SceneKit statt RealityKit | Mehr Beispiele für Gelände | Apple hat SceneKit seit WWDC25 abgekündigt (nur noch Wartung): für neues Projekt falsch |
| C. Unity | Starke 3D-Werkzeuge | HealthKit und Bluetooth nur über Plugins, schwerer Unterbau, Lizenzbedingungen |
| D. Web-App (Web Bluetooth + CesiumJS) | Schnellster 3D-Prototyp mit swisstopo-Streaming | **Safari auf iPad/iPhone kann kein Web Bluetooth** und Web-Apps kommen nicht an HealthKit. Scheidet als Hauptweg aus. |
| E. Raspberry Pi am Gerät | Läuft immer, wenn das Gerät läuft | Unnötig, weil das iPad direkt mit dem PM5 spricht |

**Empfehlung: Option A.** SwiftUI für die Bedienung, RealityKit für die 3D-Szene, CoreBluetooth für PM5 und Gurt, HealthKit und SwiftData für die lokale Ablage. **Mindestversion iPadOS/iOS 26.** Ab dieser Version kann ein iPad Trainings aufzeichnen, und sie ist zugleich die letzte Version für Falks iPad Pro von 2018/19 (A12X). iPadOS 27 läuft auf diesem Gerät nicht mehr, siehe [MacRumors](https://www.macrumors.com/2026/06/08/ipados-27-drops-support-for-a-wave-of-ipads/).

**Bauen:** Den Code schreibe ich auf der Spark, die Kartenpakete entstehen ebenfalls dort. Kompiliert wird mit Xcode auf Falks Mac in der Claude-Session **„Private QNAP“**, signiert mit Falks Apple-Entwicklerkonto, installiert direkt auf dem iPad bzw. später über TestFlight. Die Mac-Session hat direkten Zugriff auf dieses Projektverzeichnis und öffnet Code und Xcode-Projekt dort; ein Austausch über ein Repo ist nicht nötig.
Die **Spark** übernimmt schon im ersten Prototyp die Rechenarbeit für die 3D-Darstellung (Abschnitt 4a). Beim Rudern selbst braucht die App sie nicht. Im MVP entsteht deshalb kein neuer Dienst und kein neuer Port, und am Landschafts-Dashboard ändert sich nichts.

## 4. Architektur

```
RowCoach (iPad/iPhone, Swift)
├── Devices
│   ├── PM5Service        CoreBluetooth, Concept2-Protokoll → RowingSample (Zeit, Distanz, Tempo, SPM, Watt, …)
│   ├── HeartRateService  BLE Heart Rate Service (Polar) → HRSample (bpm, RR)
│   └── Simulator         spielt aufgezeichnete Einheiten ab (Entwicklung ohne Ruderer)
├── Session               Zustandsmaschine: bereit → rudert → Pause → Wende → Ziel; vereint die Datenströme
├── Course                Kartenpaket laden, Distanz → Position/Richtung auf der Strecke, Wendepunkt
├── Scene3D (RealityKit)  Gelände, See, Gebäude, Boot und Kamera folgen der Position
├── HUD (SwiftUI)         Anzeigen über der 3D-Szene
├── Health                Freigaben, HKWorkoutSession/Builder, Eintrag nach der Einheit
├── Storage (SwiftData)   Einheiten mit vollem Datenverlauf, Export als FIT/TCX (später)
└── Settings              Health verbinden, Geräte koppeln, Profil (Maximalpuls, Zonen), Einheiten

Spark (Rechenwerk für die 3D-Darstellung, kein Dienst)
└── tools/coursebuilder/  Python + Blender ohne Bildschirm: swisstopo laden → Meshes/Detailstufen →
                          Licht vorrechnen (GPU) → USDZ + course.json bauen; Jobs mit gpu run -p 0
```

**Kartenpaket** (`courses/zuerichsee-utoquai/`):
- `course.json`: Name, Länge, Strecke als Linie mit Wendepunkt, Startrichtung, Quellenangaben
- `terrain.usdz`, `buildings.usdz`, `water`-Parameter
- `preview.jpg` für die Kartenauswahl

Jede neue Karte ist ein neues Paket. Die App bleibt dabei unverändert. Anfangs liegen die Pakete in der App, später können sie nachgeladen werden.

## 4a. Rechenarbeit auf der Spark (ab dem ersten Prototyp)

Die Spark (NVIDIA GB10) erledigt im Voraus alles Rechenintensive. Das iPad muss dann nur noch fertige, schlanke Modelle anzeigen. So bleibt die Darstellung flüssig, und das Bild sieht besser aus, als das iPad es live berechnen könnte.

| Schritt | Was die Spark macht |
|---|---|
| Daten holen | swisstopo-Kacheln für den Ausschnitt laden und zwischenspeichern |
| Gelände | Höhenmodell in ein Mesh umwandeln; nah an der Strecke fein, zum Horizont grob (Detailstufen) |
| Gebäude | CityGML in Meshes umwandeln, zusammenfassen, Detailstufen bilden, unsichtbare Flächen entfernen |
| Licht vorrechnen | Licht, Schatten und Umgebungsverdeckung (Ambient Occlusion) in die Texturen einrechnen (GPU-Raytracing, z. B. Blender Cycles ohne Bildschirm). Das macht den grössten Teil der Bildqualität aus. |
| Texturen | Luftbild zuschneiden, nachschärfen, ins iPad-freundliche Format komprimieren |
| Ferne Kulisse | Hügel und Horizont (Zürichberg, Uetliberg, Alpen) als vorgerenderte Panorama-Kulisse |
| Prüfen | Vorschaubilder aus der Bootsperspektive rendern, damit wir das Paket vor der Übertragung aufs iPad ansehen können |
| Paket bauen | USDZ-Dateien + `course.json` + Vorschau, versioniert unter `courses/` |

- **Priorität:** Diese Jobs haben auf der Spark die **höchste Priorität**: `gpu run -p 0 -o "SPARK SW RowCoach" …`. Laufen sie, pausiert die GPU-Warteschlange die Hintergrunddienste.
- Die Werkzeuge liegen in `tools/coursebuilder/` und laufen in einer eigenen venv. Ein Befehl baut ein Paket neu, z. B. bei neuen swisstopo-Daten oder für eine neue Strecke.
- **Live-Rendering auf der Spark** mit Videostream ans iPad wäre auch möglich, ist aber nicht empfohlen. WLAN-Verzögerung und Aussetzer würden beim Rudern stören, und es bräuchte einen dauerhaft laufenden Dienst. Vorrechnen bringt fast dieselbe Qualität ohne diese Nachteile.

**Bewegung:** Die geruderte Distanz vom PM5 ist die Position auf der Strecke. Das Boot fährt entlang der Linie, und die Geschwindigkeit kommt direkt vom PM5. Physik wie Wind oder Strömung gibt es nicht. Am Wendepunkt dreht das Boot in einem sanften Bogen.

**Kamera (vorerst die einzige Ansicht):** Die Kamera sitzt **leicht erhöht hinter dem Ruderer** und schaut über ihn hinweg nach vorne in Fahrtrichtung. Sie steht etwa 2–3 m hinter dem Boot und 1,5–2 m über dem Wasser und folgt dem Boot weich, auch durch die Wendekurve. Im Bild sind ein einfaches Skiff mit Ruderfigur und die Strecke davor zu sehen. Die Figur bewegt sich vorerst nicht. Später kann sie im Takt der echten Schläge rudern, dafür liefert der PM5 Daten pro Schlag. Weitere Ansichten sind vorerst nicht geplant.

## 5. Erste Strecken: Zürichsee, städtisches Ufer

**Beide Varianten werden gebaut** (Falk, 23.11.2026), als zwei Kartenpakete aus demselben Datenausschnitt. Die Länge messe ich beim Bau auf der swisstopo-Karte nach:
- **Variante 1 – Utoquai/Seefeld:** Start bei der Quaibrücke/Bellevue, dann am Utoquai und Seefeldquai entlang Richtung Zürichhorn. Wende vor dem Zürichhorn, zurück zum Start. Etwa 2 × 2 km.
- **Variante 2 – Mythenquai/Enge:** Start beim Hafen Enge, am Mythenquai entlang Richtung Landiwiese/Rote Fabrik, Wende, zurück. Ähnliche Länge.

Das Boot fährt jeweils ungefähr 50–100 m vor der Uferpromenade, damit man Quai, Bäume und Häuser sieht. Der Ausschnitt reicht etwa 3 × 2 km plus ein Rand mit Hügeln, also Zürichberg bzw. Uetliberg als Horizont.

Ein gemeinsamer Ausschnitt deckt das ganze untere Seebecken ab, also beide Ufer von der Quaibrücke bis etwa Zürichhorn bzw. Wollishofen. Gelände, Gebäude und Licht werden einmal gerechnet und dann für beide Strecken verwendet.

**Zwei Qualitätsstufen pro Paket:** Die Stufe *Standard* ist für das heutige iPad Pro (A12X, 4–6 GB RAM) gedacht: weniger Polygone, Texturen bis 2K, Licht fest eingerechnet, Ziel 60 Bilder pro Sekunde. Die Stufe *Hoch* ist für spätere iPads mit M-Chip, mit mehr Gebäudedetail und schärferen Texturen. Die App wählt die Stufe nach Gerät. Gemessen wird auf dem echten A12X-iPad.

Detailgrad v1: Gelände mit Luftbild, Gebäude grau oder hell aus swissBUILDINGS3D, einfache Wasserfläche mit leichter Bewegung, Himmel. Noch keine Bäume, Boote oder Menschen.

## 6. Bildschirme

1. **Start:** Strecke wählen (Kachel mit Vorschau, Länge), Status von PM5 und Gurt (verbunden/suchen), Taste „Los“.
2. **Rudern (Querformat iPad):**
   - Oben eine Leiste mit **verstrichener Zeit**, **Distanz** und **verbleibender Distanz zum Ziel**. Darunter ein **Fortschrittsbalken** über die ganze Strecke mit Marke für den Wendepunkt und einem Bootssymbol an der aktuellen Position.
   - Unten bzw. an den Seiten grosse Kacheln: **Tempo /500 m**, **Geschwindigkeit**, **Schlagzahl**, **Puls** (in Zonenfarbe), Watt.
   - Welche Kacheln erscheinen, ist einstellbar. In der Mitte läuft die 3D-Szene aus der Kamera hinter dem Ruderer (Abschnitt 4).
   - Das iPhone zeigt dasselbe als kompakte Hochformat-Fassung.
3. **Zusammenfassung:** Zeit, Distanz, Durchschnittstempo, Schlagzahl, Puls mit Verlauf und Zonenanteilen, Häkchen „In Apple Health gespeichert“.
4. **Verlauf:** Liste früherer Einheiten mit Details.
5. **Einstellungen:** Apple Health verbinden bzw. Status, PM5 und Pulsgurt koppeln, Pulsweg A/B, Profil (Gewicht, Maximalpuls, Zonen), Masseinheiten, Quellenangaben (© swisstopo, Lizenzhinweise).

## 7. Vorgehen in Etappen

| Etappe | Inhalt | Ergebnis |
|---|---|---|
| **0 Spike** (klein) | PM5 und Polar verbinden, Rohwerte live auf dem iPad anzeigen, Testeintrag in Apple Health | Technik nachgewiesen, offene Punkte aus 2.3/2.4 geklärt |
| **1 Rudern ohne Landschaft** | Session-Logik, HUD mit Balken, Zusammenfassung, Health-Eintrag, Einstellungen, Simulator | App im Alltag nutzbar, mit einfacher Szene (Wasser und Horizont) |
| **2 Zürichsee** | Kartenpaket-Werkzeug auf der Spark (GPU, Priorität 0): Gelände + Luftbild + Gebäude mit vorgerechnetem Licht; Boot mit Ruderfigur folgt der Strecke, Kamera hinter dem Ruderer | Erste echte Landschaft |
| **3 Ausbau** | Weitere Karten, Intervalle und Trainingspläne, Export (FIT/TCX, Strava), Feinschliff der 3D-Darstellung | – |

Jede Etappe lege ich dir zur Freigabe vor. Für die Logik ohne Hardware (Session, Streckenposition, Protokoll-Parser) gibt es Tests mit aufgezeichneten Daten.

## 8. Später möglich (Architektur ist vorbereitet)
- **KI-Coach mit dem lokalen Modell auf der Spark:** Einheiten werden optional an die Spark synchronisiert (kleiner Dienst über Tailscale). Das Modell kommentiert Trends und schlägt Pläne vor. Erst dann entsteht ein Dienst mit Port und wird im Landschafts-Dashboard registriert.
- Anzeige auf TV (AirPlay) oder auf der G2-Brille
- Gegen frühere eigene Fahrten rudern (Geisterboot)
- Weitere Geräte über Bluetooth FTMS

## 9. Geklärt (23.11.2026)
- Mac mit Xcode vorhanden; gebaut wird in der Mac-Session „Private QNAP“ (Mac ist nicht immer eingeschaltet)
- Apple-Entwicklerkonto vorhanden
- iPad heute: iPad Pro der ersten Generation mit Face ID (2018/19, A12X, iPadOS 26); neuere Geräte folgen
- Strecken: beide Varianten (Utoquai/Seefeld und Mythenquai/Enge)
- Ansicht: eine Kamera, leicht erhöht hinter dem Ruderer, Blick nach vorne
- Spark rechnet die 3D-Darstellung vor; diese Jobs haben die höchste GPU-Priorität
- Pulsgurte: **Polar H10 und H9**. Beide werden direkt mit dem iPad gekoppelt (Weg A), nicht am PM5. Beide senden den Puls über das Standard-Bluetooth-Profil. Der H10 liefert ausserdem zuverlässige RR-Intervalle für spätere Auswertungen wie HRV. Die App merkt sich den zuletzt verwendeten Gurt und verbindet sich automatisch.
- iPad bestätigt: A12X mit iPadOS 26. Alles wird von Anfang an auch für neuere iPads mit M-Chip ausgelegt (Qualitätsstufe *Hoch*, grössere Bildschirme, ProMotion mit 120 Hz).
- App-Name: RowCoach (ohne „Concept2“ im Namen)

## 10. Noch offen
- Nichts. Das Konzept wartet auf Falks Freigabe.

## 11. Stand (23.11.2026, Abend)
- **Etappe 0, App-Code fertig, noch nicht kompiliert:** `App/` (XcodeGen + Swift-Paket `RowCoachKit`).
  - PM5-Parser streng nach der Concept2-Spezifikation (Rev. 0.31), Polar-Pulsprofil, Live-Ansicht, Gerätekopplung.
  - Apple-Health-Aufzeichnung und Einstellungen.
  - Tests für die Parser.
  - Bauen in der Mac-Session „Private QNAP“, siehe `BUILD.md`.
- **Kartendaten fertig:** swisstopo-Ausschnitt geladen (6,8 GB, Fundus `dataset:832`). Beide Strecken sind je 2 × 2000 m lang.
- **3D-Szenen:**
  - *standard*: 1,16 Mio. Dreiecke, 54 MB
  - *hoch*: 4,1 Mio. Dreiecke, 162 MB
  - Vorschaubilder unter `courses/<strecke>/preview-*.jpg`
- **Noch offen in Etappe 2:**
  - Vorgerechnetes Licht auf der GPU (Gebäude wirken noch flach grau)
  - 3D-Ansicht und HUD in der App
  - Wassermaterial und Himmel

## 12. Zielbild und Ausbaustufen (Falk, 23.11.2026)

RowCoach wird **Open Source** veröffentlicht. Jetzt entsteht nur die lokale Version. Die folgenden Stufen sind gesetzt, aber noch nicht im Bau. Die Architektur hält ihnen schon heute die Tür offen.

| Stufe | Inhalt | Was heute schon darauf vorbereitet ist |
|---|---|---|
| **Trainingsverlauf** | Welche Trainings wann gemacht, mit Details | Etappe 1: Verlauf mit SwiftData, Training als offenes Datenformat (Codable) |
| **Trainingsprogramme** | Verschiedene Trainingsarten (Intervalle, Dauer, Pyramiden, Pulsbereich …) auswählen und auf jede Strecke anwenden | Feld `workoutPlanId` im Training; Strecke und Programm sind getrennt, das Programm steuert nur Ziele und Phasen |
| **Wetter und Jahreszeiten** | Dieselbe Strecke als Winter/Schnee, Sturm/Regen, Sonne/Sommer | Himmel, Licht und Wasser liegen gekapselt in `SceneEnvironment`; Feld `weather`/`season` im Training; Licht wird je Variante auf der Spark vorgerechnet |
| **RowServer** | Eigenständiger, quelloffener Server, den jede und jeder bei sich startet; koordiniert Rennen (Start, Live-Positionen, Ergebnisse) | Strecken sind portable, versionierte Kartenpakete (course.json + Szene) mit fester ID; Felder `raceId`/`serverId` im Training; die Distanz-auf-Strecke-Logik liegt plattformunabhängig in RowCoachKit |
| **RowCoordinator** | Kleines Verzeichnis (z. B. Google Firebase), bei dem sich RowServer registrieren; macht nichts weiter als Server auffindbar halten | – |
| **Abos und Einladungen** | Server abonnieren, über Rennen informiert werden, andere Abonnenten einladen; 1–2 hervorgehobene Standardserver von uns; Startseite zeigt das nächste Rennen, zu dem man angemeldet ist | – |

**Grundsätze für das Netz:** Es soll unabhängig und widerstandsfähig sein. Jeder Server ist eigenständig, und der Coordinator ist nur ein Telefonbuch. Fällt er aus, laufen bekannte Server weiter.

**Offene Fragen für später:**
- Wie verteilen Server die Kartenpakete? Bündeln, nachladen oder per Prüfsumme abgleichen?
- Sprache und Technik des RowServer (z. B. Swift on Linux mit RowCoachKit, oder Go/Python)
- Anmeldung und Identität ohne zentrales Konto
- Fairness: dieselbe Strecke und dieselbe Distanzmessung für alle

**Open Source, schon jetzt beachtet:**
- keine proprietären Abhängigkeiten
- swisstopo-Daten nur mit Quellenangabe (OGD)
- Concept2-Spezifikation nicht ins Repo (nur verlinkt)
- Commits ohne private E-Mail-Adresse
- Grosse Szenen-Dateien nicht in Git; jede und jeder erzeugt sie mit dem coursebuilder selbst, oder sie kommen später als Release-Anhang bzw. vom RowServer.
- **Offen: Lizenz** (Vorschlag: Apache-2.0 oder MIT für den Code; die Kartenpakete tragen die swisstopo-Bedingungen)
