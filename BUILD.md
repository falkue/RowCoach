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
.venv/bin/python export.py  areas/zuerichsee-unteres-becken.json   # USDZ standard + hoch, course.json
.venv/bin/python minimap.py areas/zuerichsee-unteres-becken.json  # Luftbildkarte je Strecke für den Navigator
./run_preview.sh zuerichsee-unteres-becken standard zuerichsee-utoquai zuerichsee-mythenquai  # Vorschau (CPU)
```

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

Je Strecke zusätzlich: `smooth_m` (Glättungsfenster, Standard 120 m), `avoid` (Standard true bei `"osm"`: Stege,
Anlegestellen, Brückenpfeiler und Fähranleger aus OSM werden umfahren), `obstacle_dist_m` (Abstand zu ihnen,
Standard 20 m). Liegt das Ufer links der Hinfahrt, fährt die Rückfahrt (App: 12 m links) 12 m näher am Ufer:
dann `offset_m` und `obstacle_dist_m` um etwa 6–12 m grösser wählen. routes.py schreibt bei `"osm"`
`route_preview_<strecke>.png` (SWISSIMAGE-Ausschnitt mit Ufer, Brücken, Stegen, Hin- und Rückfahrt) und `route_check.json`.
fetch.py entpackt die Gebäude-ZIPs selbst nach `buildings_x/`.

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

Die Rohdaten liegen unter `data/raw/…` (nicht in Git) und sind in Fundus registriert: Zürich `dataset:832`, Basel `dataset:833`, Stein am Rhein `dataset:834`, Luzern `dataset:835`.
bake.py läuft standardmässig auf der CPU (Warp). Für einen GPU-Lauf zuerst `tools/gpu_preempt.py pause --note "…"`, dann `bake.py … --device cuda`, danach sofort `tools/gpu_preempt.py resume` (Falk: RowCoach-Rechenjobs haben Vorrang, andere Jobs werden sofort pausiert).
Die Sonne der Szene (235°/48°) steht in der USDZ unter `customLayerData` und muss zu `SceneEnvironment.summerSunny` passen; ändert sich die Sonne, bake.py und export.py neu laufen lassen.
