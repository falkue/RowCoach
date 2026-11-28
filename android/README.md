# RowCoach für Android – Machbarkeitstest

Zweck: zeigen, dass eine RowCoach-Strecke auf einem älteren Android-Telefon flüssig in 3D läuft, mit simulierter oder
echter Ruderquelle (Concept2 PM5 per Bluetooth LE) und Coach-Ansage. Das ist keine fertige App, sondern ein kleiner, echter
Prototyp: Kotlin + Jetpack Compose, 3D mit Google Filament (gltfio), Szene als GLB aus dem Streckenbauer.

Stand 28.11.2026: Code geschrieben auf der Spark (Linux arm64, dort läuft das Android-SDK nicht); **noch nie gebaut**.
Erster Bau und Test auf dem Mac (Apple Silicon) mit Falks altem Google-Telefon (Android 11 = API 30).

## Was der Prototyp zeigt

| Bildschirm | Inhalt |
|---|---|
| Startseite | Marke „Bahnen“ (Kobalt #2340FF, Gelb #FFD60A), Liste der Strecken in den Assets (zuerst nur Henley), Knopf **Demo-Fahrt**, Feld **Concept2 PM5** (suchen, verbinden), Knopf **Mit PM5 fahren** (aktiv, sobald verbunden) |
| Fahrt | 3D-Szene: Gelände mit Luftbild, Gebäude, Brücke, Bäume, Wasserfläche, Himmel mit Dunst, Einer (Detailstufe lite) auf der Route, Kamera 9 m hinter und 2,6 m über dem Boot, die der Route folgt. Anzeige Zeit, Distanz, Tempo/500 m, Schlagzahl, Watt. Unten rechts Messwerte. Knopf **Bäume aus/an** (A/B-Test der Bildrate), **Ende** |

- **Simulierte Ruderquelle:** `sim/ErgSimulator.kt` ist ein Port von `ErgSimulator` aus RowCoachKit (Tempo 1:58/500 m,
  24 Schläge/min). Er erzeugt alle 0,25 s dieselben Bytes wie ein PM5; `pm5/RowingState` dekodiert sie mit demselben
  Parser wie die echten Notifications (Gedanke von `SimulatorDevice` in der iOS-App). Die Bootsposition wird zwischen den
  Meldungen mit der Geschwindigkeit interpoliert, damit das Bild mit 60 Hz flüssig fährt.
- **PM5 per Bluetooth:** `ble/PM5BleClient.kt` sucht (Name `PM5…` oder Discovery-Service `CE060000-…`), verbindet,
  schreibt 0x0034 = 3 (100 ms, wie iOS) und abonniert 0x0031/32/33/35/36/39. Dekodierung in `pm5/PM5Protocol.kt` ist
  ein Byte-für-Byte-Port von `PM5Protocol.swift` (Längen, Mindestlängen für ältere Firmware, Skalierung).
- **Coach-Audio:** Beim Start der Fahrt spielt `MediaPlayer` die Ansage `go.1.cox.0.m4a` aus
  `App/RowCoach/Resources/Coach/en/`.

## Szene (GLB) erzeugen – Spark

Der Streckenbauer schreibt wie bisher USDZ für iOS. `tools/coursebuilder/export_glb.py` liest die fertige Szene
(`courses/<gebiet>/scene-<stufe>/scene.usdc`, sonst die USDZ) und schreibt dieselben Meshes und Texturen als GLB, plus
Wasserfläche (y = 0) und den Einer aus `tools/avatars/lite.py` (Knoten `Boat`, Bug in −z). Koordinaten bleiben gleich
(Meter, y oben, rechtshändig), `path_xz` aus `course.json` passt direkt.

```bash
cd tools/coursebuilder
free -g    # available ≥ 15 GB
flock /tmp/rowcoach-heavy.lock .venv/bin/python export_glb.py henley-regatta standard
# Optionen: --max-tex 1024 (Texturen verkleinern), --no-water, --no-boat, --out PFAD
```

Henley-Regatta, Stufe standard (28.11.2026):

| | Meshes | Dreiecke |
|---|---:|---:|
| Gelände (12 Kacheln + Umgebung) | 13 | 105 945 |
| Gebäude | 10 | 19 992 |
| Brücke | 1 | 1 388 |
| Bäume | 7 | 249 990 |
| Wasser | 1 | 2 |
| Boot (Rumpf, Ruderer, 2 Ruder) | 4 | 589 |
| **Summe** | **36** | **377 906** (332 945 Punkte) |

GLB 18,4 MB, davon Texturen 4,4 MB (31 JPEG + Bootspalette, grösste Kante 2048 px, nichts verkleinert);
Ausdehnung ±7 km (Umgebung) um die 2,1 km lange Strecke. Die GLB ist in `.gitignore` (`courses/*/*.glb`).

## Mac einrichten (einmalig)

Variante A – Android Studio installieren (bringt SDK, JDK und Emulator mit), Projekt `android/` öffnen.

Variante B – nur Kommandozeile:

```bash
brew install --cask temurin@17 android-commandlinetools
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-37.0" "build-tools;36.0.0"
export PATH="$ANDROID_HOME/platform-tools:$PATH"   # adb
```

(Die Pfade in `~/.zshrc` eintragen. AGP lädt fehlende SDK-Pakete auch selbst, wenn die Lizenzen angenommen sind.)

## Telefon vorbereiten

1. Einstellungen → Über das Telefon → 7 × auf **Build-Nummer** tippen (Entwickleroptionen an).
2. Einstellungen → System → Entwickleroptionen → **USB-Debugging** an.
3. Per USB an den Mac, auf dem Telefon „USB-Debugging zulassen“ bestätigen; `adb devices` zeigt das Gerät als `device`.
4. Für den PM5-Test unter Android 11: **Standort** einschalten (sonst liefert die BLE-Suche nichts) und Bluetooth an.

## Bauen und installieren

```bash
git clone spark:Projects/Software/RowCoach && cd RowCoach/android   # oder git pull
./fetch_assets.sh                  # course.json + Ansage aus dem Repo, GLB per rsync von spark
./gradlew installDebug             # baut app-debug.apk und installiert es (erstes Mal: Gradle + Abhängigkeiten laden)
adb shell am start -n com.falkue.rowcoach/.MainActivity
```

`fetch_assets.sh [strecke]` kopiert nach `app/src/main/assets/` (in `.gitignore`):
`courses/<strecke>/course.json`, `courses/<gebiet>/scene-standard.glb`, `coach/en/go.1.cox.0.m4a`.
Ist die GLB nicht lokal vorhanden, holt das Skript sie mit `rsync spark:Projects/Software/RowCoach/courses/…`
(`SPARK=…` für ein anderes SSH-Ziel). Ohne GLB läuft die App trotzdem (Himmel, Anzeige, Hinweis „Szene fehlt“).

Logcat:

```bash
adb logcat -s RowCoach3D:V RowCoachBLE:V RowCoachAudio:V Filament:V gltfio:V AndroidRuntime:E
```

`RowCoach3D` meldet Ladezeit, Grösse und ob der Knoten `Boat` gefunden wurde.

## Messgrössen

Unten rechts in der Fahrt-Ansicht, einmal pro Sekunde (`render/SceneRenderer.kt`):

- **fps** – tatsächlich gerenderte Bilder pro Sekunde (Choreographer-Takt; Ziel 60, akzeptabel ≥ 30 ohne Ruckler).
- **CPU ms/Bild** – Zeit im Bildaufruf auf dem Main-Thread (Kamera, Filament-Befehle; GPU-Zeit nicht enthalten).
- **verpasst/s** – Abstände zwischen zwei Choreographer-Bildern > 25 ms plus von Filament übersprungene Bilder.
- **GLB … in … ms** – Lesen + Parsen der GLB; **Texturen %** – Fortschritt der asynchronen Texturdekodierung.

Vorschlag für den Test: 2 Minuten Demo-Fahrt, Werte mit und ohne Bäume notieren, dazu
`adb shell dumpsys gfxinfo com.falkue.rowcoach` (Jank) und Temperatur/Akku nach 10 Minuten.
Ist die Bildrate zu niedrig, in dieser Reihenfolge ansetzen: Bäume als Impostor/kleinere Zellen, `--max-tex 1024`,
Gelände-Fernbereich gröber, Auflösung über `View.dynamicResolutionOptions`, KTX2/Basis-Texturen (weniger GPU-Speicher).

## Offene Punkte und Risiken

- **Nie kompiliert.** Die Versionen sind aktuell (AGP 9.5.3, Gradle 9.6.0, Kotlin/Compose-Plugin 2.4.21,
  Compose BOM 2026.11.01, Filament 1.81.0, compileSdk/targetSdk 37), die Filament-Aufrufe sind gegen die Klassen
  von filament-android 1.81.0 abgeglichen. Kleine Kompilierfehler beim ersten Bau sind trotzdem möglich. Meldet AGP
  Probleme mit `compileSdk = 37`, auf 36 zurückgehen (`platforms;android-36`).
- Wasser ist eine glatte, einfarbige PBR-Fläche (kein Wellen-Shader, keine Spiegelung). Für das iOS-Wasser braucht
  Android ein eigenes Filament-Material (`matc`, Teil des Filament-Releases für macOS).
- Himmel = Farbe + Dunst; die iOS-Himmelskuppel (Wolken, Sonnenstand) fehlt noch.
- Keine Schatten (Licht der Gebäude ist eingebacken; Sonnenschatten des Boots fehlt).
- Die GLB (18 MB) wird beim Öffnen der Fahrt auf dem Main-Thread gelesen (einige 100 ms); für die echte App in einen
  Hintergrund-Thread verlegen.
- Nur arm64-v8a (Testgerät). PM5 ohne FTMS-Geräte und ohne Pulsgurt; keine Wiederverbindung.
- Gerät dreht nicht (Querformat fest).

## Weg zum Swift-Kern (Skizze)

RowCoachKit baut bereits für Android arm64 (`tools/kit_check.sh`). Für die volle App soll die Logik nicht doppelt
in Kotlin entstehen:

1. Kit als Shared Library (`libRowCoachKit.so`) mit dem Swift SDK für Android bauen, mit den Swift-Laufzeit-Bibliotheken
   in `app/src/main/jniLibs/arm64-v8a/` legen.
2. Brücke mit **swift-java** (jextract erzeugt Java/Kotlin-Bindings aus Swift-Code) oder einer schmalen
   C-Schnittstelle (`@_cdecl`) + JNI; Daten als Byte-Arrays/JSON über die Grenze.
3. Erste Kandidaten: `PM5Parser`/`FTMSParser` (ersetzt den Kotlin-Port), `ErgSimulator`, `SessionController`-Logik,
   `PlanEngine`, Auswertung, Sync-Merge. Kotlin behält nur Plattform: Compose-UI, Filament, BLE, Health Connect,
   MediaPlayer/TextToSpeech, Room.
4. Alternative: Skip Fuse (SwiftUI → Compose) für die Oberfläche – Entscheidung offen (docs/ANDROID.md).

## Aufwandsschätzung volle Android-App (grob, ein erfahrener Entwickler + Claude)

| Baustein | Aufwand |
|---|---|
| Swift-Kern per JNI/swift-java einbinden, Build-Pipeline (Gradle ruft Swift-Build), CI | 2–3 Wochen |
| Bildschirme in Compose (Start, Streckenwahl mit Karten/Vorschau, Training/Programme, Fahrt-HUD, Auswertung, Statistik, Einstellungen, Konto) | 5–7 Wochen |
| 3D-Pipeline: GLB-Export aller Strecken + Stufe hoch, Wasser- und Himmels-Material (matc), Avatare/Ruderbewegung, Verkehr/virtuelle Ruderer, Licht-Varianten, Streckendownload, Speicher-/LOD-Tuning auf Geräteklassen | 5–8 Wochen |
| Geräte: PM5 komplett (Workouts setzen, Wiederverbinden), FTMS-Rudergeräte, Pulsgurte, Hintergrundbetrieb | 2–3 Wochen |
| Health Connect (Workouts, Puls) | 1 Woche |
| Coach-Audio/Ansagen (Clips, TextToSpeech, Audio-Fokus) | 1 Woche |
| Konto, Sync (Firebase Auth/Firestore), Rennen | 2–3 Wochen |
| Play Store: Signierung, Datenschutzangaben, Data-Safety-Formular, interne/geschlossene Tests, Gerätematrix | 1–2 Wochen |
| **Summe** | **ca. 19–28 Wochen** |

Grösstes Risiko: Grafikleistung und Speicher auf schwachen Geräten (sehr breite Geräteklasse) und die Swift-Brücke.
