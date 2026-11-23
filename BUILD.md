# RowCoach bauen

## App (Mac, Session „Private QNAP“)
Voraussetzungen: Xcode 26, Apple-Entwicklerkonto, `brew install xcodegen` (einmalig).

```bash
cd ~/Projects/Software/RowCoach/App
ROWCOACH_TEAM_ID=<Team-ID aus developer.apple.com> xcodegen generate   # erzeugt RowCoach.xcodeproj
open RowCoach.xcodeproj
```
- Gerät: Falks iPad Pro (A12X, iPadOS 26). Schema RowCoach, Run.
- Capability HealthKit ist über `RowCoach/RowCoach.entitlements` gesetzt. Xcode legt das Provisioning-Profil automatisch an.
- Tests der plattformunabhängigen Logik: `cd App/RowCoachKit && swift test` (macOS) oder in Xcode Product → Test.
- `RowCoach.xcodeproj` nie von Hand ändern, sondern `project.yml` anpassen und neu erzeugen.

### Etappe 0 testen
1. PM5 einschalten, im Menü „Connect“ wählen. Polar H10/H9 anlegen und die Elektroden befeuchten.
2. App → Geräte → Suchen → PM5 und Gurt antippen. Beide merkt sich die App für die nächsten Starts.
3. Einstellungen → „Apple Health verbinden“ → alle Freigaben erteilen.
4. Live → „Aufzeichnung starten“, ein paar Minuten rudern, dann „Beenden und in Health speichern“.
5. In Health prüfen: Training „Rudern“ (indoor) mit Distanz, Energie und Pulskurve, ohne doppelte Pulswerte.

## Kartenpakete (Spark)
```bash
cd ~/Projects/Software/RowCoach/tools/coursebuilder
.venv/bin/python fetch.py   areas/zuerichsee-unteres-becken.json   # swisstopo laden (nur Neues)
.venv/bin/python prepare.py areas/zuerichsee-unteres-becken.json   # Mosaike, Seefläche
.venv/bin/python routes.py  areas/zuerichsee-unteres-becken.json   # Strecken + route_preview.png
.venv/bin/python buildings.py areas/zuerichsee-unteres-becken.json # CityGML → Dreiecke (~1,5 min)
.venv/bin/python bake.py      areas/zuerichsee-unteres-becken.json # Licht vorrechnen: Verdeckung, Sonnenschatten, Dachfarben (CPU ~1–10 min; --device cuda möglich)
.venv/bin/python fetch_tlm.py  areas/zuerichsee-unteres-becken.json # nur mit "bridges": swissTLM3D-Ausschnitt (einmal ~0,55 GB laden)
.venv/bin/python bridges.py    areas/zuerichsee-unteres-becken.json # nur mit "bridges": Brücken-Meshes + Licht (CPU < 1 min)
.venv/bin/python export.py  areas/zuerichsee-unteres-becken.json   # USDZ standard + hoch, course.json
.venv/bin/python minimap.py areas/zuerichsee-unteres-becken.json  # Luftbildkarte je Strecke für den Navigator
.venv/bin/python lanes.py   areas/zuerichsee-unteres-becken.json  # Fahrlinien für Ruderer und Schiffe → course.json "traffic" (CPU, Sekunden)
./run_preview.sh zuerichsee-unteres-becken standard zuerichsee-utoquai zuerichsee-mythenquai  # Vorschau (CPU)
./run_preview.sh basel-rheinknie standard rhein-basel --bridges        # Durchfahrten unter den Brücken → build/<gebiet>/checks/
./run_preview.sh basel-rheinknie standard rhein-basel --at 450,2600    # Bilder an frei gewählten Distanzen (m ab Start)
```
Mit Brücken: `fetch_tlm.py` vor `routes.py` (routes.py hält die Pfeiler frei und braucht dafür die Brücken), `bridges.py`
nach `bake.py` (die Gebäude dienen als Verdeckung) und vor `export.py`. Ohne das Feld `bridges` entfallen beide Schritte.

Weitere Gebiete: `areas/rhein-basel.json`, `areas/rhein-stein.json`, `areas/luzern-seebecken.json` (gleiche
Reihenfolge der Schritte; `run_preview.sh <gebiet> standard <strecke> --checks` legt zusätzlich Kontrollbilder quer zur
Fahrt und eine Schrägansicht der Wende unter `build/<gebiet>/checks/` ab).

### Optionen der Gebietsdatei (neben `core_lv95`, `far_lv95`, `fetch`, `routes`)
| Feld | Wirkung |
|---|---|
| `lake_level_m` | feste Wasserhöhe (Seen, `water_source: "dem"`); bei `"osm"` darf es fehlen, dann bestimmt prepare.py die Höhe (`build/<gebiet>/water_meta.json`) |
| `water_source` | `"dem"` (Standard, Zürich): ebene Fläche auf Seehöhe im Höhenmodell. `"osm"`: Wasserpolygone aus OpenStreetMap (Overpass-API, ein Request je Gebiet → `data/raw/<gebiet>/osm/overpass.json`, © OpenStreetMap contributors, ODbL), am Höhenmodell nachgeschärft; Wasserhöhe = Median des Höhenmodells im Wasser nahe den Start-/Zielpunkten; Ufergelände tiefer als Wasserhöhe + 0,3 m wird angehoben (nicht unterhalb eines Wehrs); Gewässer auf anderer Höhe (Teiche, Bäche) bleiben Gelände |
| `copernicus_tiles` | Kacheln des Copernicus DEM GLO-30 (AWS Open Data, z. B. `Copernicus_DSM_COG_10_N47_00_E007_00_DEM`); füllen Höhenlücken ausserhalb der Schweiz (Versatz geschätzt, 250 m weicher Übergang). Luftbildlücken bekommen eine ruhige Geländefarbe mit Schummerung (Sonne 235°/48°), 300 m Übergang; fehlende Luftbildpixel im Kerngebiet kommen aus dem Umgebungsluftbild |
| `app_qualities` | Stufen, die `install_courses.py` ins App-Bundle kopiert (z. B. `["standard"]`); landet als optionales `bundle_qualities` in course.json |
| `bridge_piers_lv95` | Brückenpfeiler aus dem Luftbild, nur zur Kontrolle (Abstand in `route_check.json`, rot in der Detailvorschau) |
| `extra_obstacles_lv95` | zusätzliche Hindernisse (Polygone), denen die Strecken ausweichen |
| `bridges` | optional, Liste von Brücken für `bridges.py` (swissBUILDINGS3D enthält keine Strassen- und Fussgängerbrücken). Je Brücke: `name`, `slug`, `style` (`"beam"` Balken, mit `depth_m` [Feldmitte, Pfeiler] und `haunch_m` als Voute; `"arch"` Bögen mit `spring_m` Kämpferhöhe und `crown_m` Scheitelstärke; `"substructure"` nur Platte und Holzjoche unter einer Brücke, die als Gebäude schon da ist), Grundriss aus `osm_outline` (OSM-Weg man_made=bridge), `axis_lv95` + `width_m` oder `axis_osm_way`; Deckhöhe aus swissTLM3D (3D-Fahrbahnachsen, `fetch_tlm.py`) oder `deck_m`; `underside_m` feste Unterkante (z. B. doppelstöckig); Pfeiler aus `piers_lv95`, `piers_s` (m auf der Achse), `spans_m` (bekannte Spannweiten, mittig auf dem Wasser bzw. mit `spans_center: "axis"` auf der Achse), `spans_equal` (geschätzt) oder `pile_spacing_m`; Form `pier_t_m`, `pier_len_m`, `pier_nose_m`; Aussehen `parapet` (`"stone"`, `"railing"`), `pattern` (`"stone"`, `"concrete"`, `"truss"`, `"wood"`), `color`, `pier_color`; `pier_source` (Text für Kontrolle und Bericht). routes.py verschiebt die Strecke an Pfeilern, die näher als 8 m (Mitte) bzw. 6 m (Rand) an Hin- oder Rückfahrt stehen, in einem weichen Bogen (`pier_shift_window_m` je Strecke, Standard 120 m); `route_check.json` nennt `pier_shifts`. `bridges.py` schreibt `build/<gebiet>/bridges/` (Meshes, Atlanten, `meta.json` mit Pfeilern, lichter Höhe an der Bahn und Abständen); `export.py` hängt die Brücken unter `/Scene/Bridges` an (je Brücke ein Mesh). Ohne das Feld bleibt alles wie bisher |

Je Strecke zusätzlich: `smooth_m` (Glättungsfenster, Standard 120 m), `avoid` (Standard true bei `"osm"`: Stege,
Anlegestellen, Brückenpfeiler und Fähranleger aus OSM werden umfahren), `obstacle_dist_m` (Abstand zu ihnen,
Standard 20 m). Liegt das Ufer links der Hinfahrt, fährt die Rückfahrt (App: 12 m links) 12 m näher am Ufer:
dann `offset_m` und `obstacle_dist_m` um etwa 6–12 m grösser wählen. routes.py schreibt bei `"osm"`
`route_preview_<strecke>.png` (SWISSIMAGE-Ausschnitt mit Ufer, Brücken, Stegen, Hin- und Rückfahrt) und `route_check.json`.
fetch.py entpackt die Gebäude-ZIPs selbst nach `buildings_x/`.

### Verkehr auf dem Wasser (`lanes.py`, KONZEPT.md Abschnitt 16)
Läuft nach `export.py` und `minimap.py` (export.py schreibt course.json neu und verliert dabei `minimap` und `traffic`).
Trägt in jede course.json des Gebiets das optionale Feld `traffic` ein: `vessels` (Schiffsarten), `density`,
`rower_lanes` (Bahnen der virtuellen Ruderer: Versatz `out_m`/`back_m` zur Hinfahrt, konzentrische Halbkreise an
Wende und Start, ≥ 8 m zur eigenen Bahn, ≥ 10 m zum Ufer, ≥ 6 m zu Pfeilern und Stegen) und `vessel_lanes`
(`parallel` ≥ 40 m bzw. für grosse Schiffe ≥ 80 m neben der Strecke, `far` 300–1500 m draussen, `cross` quer über das
Gewässer, alle im Wasser mit ≥ 20–35 m Uferabstand, weg von Pfeilern, Stegen und – quer – 40 m von Brücken).
Schiffsarten: Feld `traffic` der Gebietsdatei (`{"vessels": [...], "density": 1.0}`), sonst Voreinstellung je Gebiet
(Zürich Kursschiff, Motorboot, Segelboot; Luzern Raddampfer, Motorboot, Segelboot; Basel Rheinschiff, Fähre, Motorboot;
Stein am Rhein Kursschiff, Weidling, Motorboot). Kontrollbild: `build/<gebiet>/lanes_preview_<strecke>.png`.
Danach `python3 install_courses.py` (kopiert nur course.json neu).

### Kartenpakete in die App übernehmen (`install_courses.py`)
```bash
cd ~/Projects/Software/RowCoach/tools/coursebuilder
python3 install_courses.py                     # alle Strecken und Stufen → App/Courses/
python3 install_courses.py --quality standard  # nur Stufe standard (kleineres Bundle, ca. 55 MB statt 215 MB)
python3 install_courses.py --all-qualities     # auch Stufen, die bundle_qualities (app_qualities) ausschliesst
python3 install_courses.py --dry-run           # nur anzeigen
```
- Kopiert je Strecke `course.json` und `preview-*.jpg` nach `App/Courses/<strecke>/` und die USDZ-Szenen nach
  `App/Courses/<gebiet>/scene-<stufe>.usdz`. `Course.scenePath(quality:)` gilt damit relativ zu `Courses/` im Bundle.
- Kopiert nur Geändertes; ein Lauf ohne Argumente entfernt auch Dateien, die zu keinem Paket mehr gehören.
- Die USDZ-Dateien stehen in `.gitignore`. Nach einem frischen Klon (oder auf dem Mac nach dem Sync) deshalb das Skript
  laufen lassen, bevor man baut, sonst zeigt die App nur Wasser und Himmel. `App/Courses` ist als Ordnerreferenz im
  Xcode-Projekt (`project.yml`); nach neuen Dateien genügt Build, kein `xcodegen generate`.

Die Rohdaten liegen unter `data/raw/…` (nicht in Git) und sind in Fundus registriert: Zürich `dataset:832`, Basel `dataset:833`, Stein am Rhein `dataset:834`, Luzern `dataset:835`, swissTLM3D (Strassen, Bahnen; für die Brücken) `dataset:836`.
`fetch_tlm.py` lädt aus dem landesweiten swissTLM3D-Shapefile-ZIP nur die Layer Strasse, Eisenbahn und übrige Bahn (HTTP-Range, ~0,55 GB statt 3,6 GB) nach `data/raw/swisstlm3d/<ausgabe>/` und schneidet je Gebiet `data/raw/swisstlm3d/<gebiet>.gpkg` aus (Kerngebiet + 200 m). Braucht `pyogrio` in der venv (`uv pip install --python .venv/bin/python pyogrio`).
bake.py läuft standardmässig auf der CPU (Warp). Für einen GPU-Lauf zuerst `tools/gpu_preempt.py pause --note "…"`, dann `bake.py … --device cuda`, danach sofort `tools/gpu_preempt.py resume` (Falk: RowCoach-Rechenjobs haben Vorrang, andere Jobs werden sofort pausiert).
Die Sonne der Szene (235°/48°) steht in der USDZ unter `customLayerData` und muss zu `SceneEnvironment.summerSunny` passen; ändert sich die Sonne, bake.py und export.py neu laufen lassen.

### Himmel und Sonnenstand (KONZEPT.md Abschnitt 16)
```bash
.venv/bin/python bake.py    areas/zuerichsee-unteres-becken.json standard hoch --light ambient  # Gebäude ohne Sonnenschatten → bake/<stufe>-ambient/ (CPU ~1,5 bzw. ~8 min)
.venv/bin/python bridges.py areas/zuerichsee-unteres-becken.json --light ambient                 # nur mit "bridges" → bridges-ambient/
.venv/bin/python export.py  areas/zuerichsee-unteres-becken.json standard hoch --light ambient  # Atlanten → courses/<gebiet>/light-ambient-<stufe>/, course.json "light_variants"
./run_preview.sh zuerichsee-unteres-becken standard zuerichsee-utoquai --time morgen,mittag,abend,nachmittag --light ambient  # → build/<gebiet>/checks/<strecke>-<stufe>-<zeit>[-ambient]-<n>.jpg
.venv/bin/python sky_clouds.py   # Wolkenmaske neu erzeugen → App/RowCoach/Resources/sky-clouds.png (eigene Arbeit, ~10 s CPU)
```
- Die Standardläufe (ohne `--light`) bleiben unverändert: Sonnenschatten 235°/48°. Die Variante braucht dieselbe Geometrie
  wie die Szene; export.py prüft das und bricht sonst ab (dann bake.py mit und ohne `--light` und export.py neu).
- Die Variante besteht nur aus Texturatlanten (Zürich standard 8,3 MB); install_courses.py kopiert sie mit.
- `sun.py` (Sonnenstand, NOAA) und `sky.py` (Himmel, Licht, Dunst) sind die Python-Fassungen von
  `RowCoachKit/SolarPosition.swift` und `SceneEnvironment.forSun`/`ProceduralTextures.skyEquirect`; Änderungen in beiden nachziehen.
- Nach dem ersten Mal mit `sky-clouds.png` einmal `xcodegen generate` (neue Datei im Ordner RowCoach/Resources).

## Startargumente für Tests (ohne Bedienung am iPad)
Start z. B. mit `xcrun devicectl device process launch --console --device <UDID> --environment-variables '{"OS_ACTIVITY_DT_MODE":"YES"}' com.falkue.RowCoach -- <argumente>`
(Protokoll: subsystem `com.falkue.RowCoach`, Kategorien Health, Session).

| Argument | Wirkung |
|---|---|
| `-demoCourse <id>` | Simulator-Ruderer an, Strecke direkt öffnen (`teststrecke-2x1000` = gerade Strecke ohne Landschaft) |
| `-demoPlan <id>` | zusammen mit `-demoCourse`: direkt ein Training (ids in `App/RowCoach/Resources/plans.json`) |
| `-demoPaceLine <s/500m>` | zusammen mit `-demoCourse` (ohne `-demoPlan`): freie Fahrt mit Tempo-Linie, z. B. `130` = 2:10 (Simulator rudert 2:05 → Boot voraus; `120` → Boot zurück) |
| `-demoFinishAfter <s>` | Fahrt nach s Sekunden automatisch beenden und speichern |
| `-demoEffort <1-10>` | zusammen mit `-demoFinishAfter`: trägt nach dem Speichern die eigene Belastung ein, als hätte man in der Zusammenfassung gewählt und „Speichern“ getippt |
| `-healthReport 1` | Freigaben (auch Belastung und geschätzte Belastung) und RowCoach-Trainings der letzten 14 Tage aus Apple Health ins Protokoll, je Training mit Belastung: eigene und geschätzte mit Quelle sowie der Vorschlag der App aus den Metadaten |
| `-backfillHealth 1` | Trainings der letzten 7 Tage ohne Health-Eintrag nachtragen (idempotent) |
| `-backfillRoutes 1` | Strecke als Route zu Trainings der letzten 7 Tage (ohne Simulator) nachtragen, die in Apple Health noch keine haben (nie doppelt) |
| `-seedDemoHistory 1` | legt beim Start, falls noch keine da sind, 14 Beispieltrainings der letzten gut 5 Wochen auf vier Strecken an (frei und mit Programm, mit Puls und Phasen; Rhein Stein am Rhein bleibt „noch offen“). Gekennzeichnet als Beispiel (`demo` + `device.source = simulator`): zählen auf dem Startbildschirm, gehen nie nach Apple Health |
| `-demoSun <zeit>` | Sonnenstand für Bildschirmfotos, übersteuert die Einstellung „Sonnenstand“: `morning`, `noon`, `evening` (Sommertag am Ort der Strecke), `now` (Uhrzeit am Ort) oder `afternoon` (fest 235°/48°, Standard). Zusammen mit `-demoCourse`; Protokoll Kategorie Scene nennt Sonne und getauschte Gebäudetexturen |
| `-demoTraffic dense` | mehr Verkehr für Bildschirmfotos: so viele andere Ruderer, wie das Kartenpaket Bahnen hat (meist 3), ein neuer alle 12–30 s, Schiffe etwa dreimal so oft, fester Startwert (immer dieselbe Abfolge); auch `low` oder `normal`. Schaltet den Verkehr ein, auch wenn „Andere Boote auf dem Wasser“ aus ist. Zusammen mit `-demoCourse` |
| `-demoTrafficAhead 1` | setzt ca. 1 s nach dem Öffnen der Fahrt ein Kursschiff 150 m voraus (50 m seitlich, auf der Seite mit Wasser, fährt langsam mit 2,5 m/s) und einen Ruderer 30 m voraus auf der innersten Bahn (im eigenen Tempo), damit beides sicher im Bild ist. Schaltet den Verkehr ein (Dichte normal, fester Startwert). Protokoll Kategorie Traffic: alle 30 s das nächste angezeigte Boot mit Entfernung, Peilung, Weltposition, isEnabled, Deckkraft und Grösse |
| `-demoLookAtSun 1` | nur Testbetrieb: Kamera blickt zur Sonne statt in Fahrtrichtung (Sonne im oberen Bilddrittel), um zu prüfen, ob Abendrot im Himmel und Sonnenscheibe übereinanderliegen; z. B. mit `-demoCourse zuerichsee-utoquai -demoSun evening`. Liegt das Abendrot daneben: `ProceduralTextures.equirectNorthU`/`equirectAzimuthSign` anpassen |
| `-clearDemoHistory 1` | entfernt alle Beispieltrainings beim Start (läuft vor `-seedDemoHistory`; beide zusammen = frisch anlegen) |

Akku-Ausfall nachstellen: Fahrt starten, nach 40 s `xcrun devicectl device process terminate --device <UDID> --pid <PID> --kill`, App neu starten → Wiederherstellung aus `Application Support/active-workout.json`.
