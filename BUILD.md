# RowCoach bauen

## App (Mac)
Voraussetzungen: Xcode 26, Apple-Entwicklerkonto, `brew install xcodegen` (einmalig).

```bash
cd ~/Projects/Software/RowCoach/App
ROWCOACH_TEAM_ID=<Team-ID aus developer.apple.com> xcodegen generate   # erzeugt RowCoach.xcodeproj
open RowCoach.xcodeproj
```
- Gerät: iPad/iPhone mit iPadOS/iOS 26 (getestet: iPad Pro A12X). Schema RowCoach, Run.
- Capability HealthKit ist über `RowCoach/RowCoach.entitlements` gesetzt. Xcode legt das Provisioning-Profil automatisch an.
- Tests der plattformunabhängigen Logik: `cd App/RowCoachKit && swift test` (macOS) oder in Xcode Product → Test.
- `RowCoach.xcodeproj` nie von Hand ändern, sondern `project.yml` anpassen und neu erzeugen.
- Sprachcoach: `RowCoach/Resources/coach_phrases.json` kommt mit den übrigen Ressourcen ins Bundle, die
  Tonkonserven `RowCoach/Resources/Coach/<de|en>/*.m4a` als Ordnerreferenz (`Coach/…`, optional). Nach neuen
  Tonkonserven `xcodegen generate`. Einstellungen → Training → „Coach“/„Häufigkeit“; Details docs/coach/SPEC.md
  („Umsetzung“), Parameter in `RowCoachKit/…/Coach/CoachConfig.swift`.
- Motivation (Was heute gut war, Wann ruderst du?, Wiedereinstieg, Bestmarken, Meilensteine, Wochenziel mit Pause):
  Logik in `RowCoachKit/…/Motivation/`, Ansichten in `RowCoach/Views/Motivation/`, Einstellungen → Motivation.
  Erinnerungen sind lokale Mitteilungen (keine Capability nötig, Berechtigung erst beim Einschalten). Neue Coach-Sätze
  `post_ride.*` mit `tools/coach_audio/render_coach.py` rendern. Details docs/motivation/UMSETZUNG.md.

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
.venv/bin/python trees.py     areas/zuerichsee-unteres-becken.json # nur mit "trees": Bäume erkennen + Meshes mit Licht (CPU ~3–15 min)
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
Mit Bäumen (`"trees": true`): `fetch.py` mit Job `surface_core` (swissSURFACE3D Raster 0,5 m), `fetch_tlm.py` (Layer
einzelbaum, bodenbedeckung, strasse), dann `trees.py` nach `buildings.py` und vor `export.py` (siehe „Bäume und
Sommerfarben“ unten).

#### Berlin und Potsdam (`fetch_de.py`, EPSG:25833)
```bash
.venv/bin/python fetch_de.py   areas/berlin-spree-mitte.json   # Berlin/Brandenburg laden (nur Neues), statt fetch.py
.venv/bin/python prepare.py    areas/berlin-spree-mitte.json   # danach wie oben: routes, buildings, bake, bridges, export, minimap, lanes
```
Gebiete: `berlin-gruenau` (Regattastrecke), `berlin-spree-mitte` (Spree), `berlin-wannsee` (Wannsee – Pfaueninsel; nur
Berliner Daten, Brandenburger Ufer mit Copernicus-Höhen) und `potsdam-jungfernsee` (Glienicker Brücke – Jungfernsee – Sacrow;
braucht die LGB-Daten). Beide Havel-Gebiete teilen `data/raw/havel-potsdam/`. Mit `"trees": true` vor trees.py
`fetch_de.py <gebiet> --trees-inputs` (chm.tif = bDOM − DGM1, ortho_core.tif). Quellen (alles offene Daten, offizielle Download-Wege, `fetch-log.json` je Gebiet):
- Brandenburg, LGB (data.geobasis-bb.de, dl-de/by-2-0, „© GeoBasis-DE/LGB“): DGM1 (1-km-Kacheln GeoTIFF, deckt auch
  Berlin ab; Kern und Umgebung), DOP20 RGBI (wo Berlin fehlt), LoD2 (CityGML 1.0), bDOM (für Bäume), WMS `bebb_dop20c`.
- Berlin, Geoportal (gdi.berlin.de, dl-de/zero-2-0): TrueOrthophotos Sommer 2025 (JPEG 2000, 2-km-Kacheln in Regions-ZIPs;
  fetch_de.py liest per HTTP-Range nur das Inhaltsverzeichnis und entpackt nur die nötigen Kacheln), LoD2 (CityGML 1.0),
  WMS `truedop_2025_sommer_rgb`.
- Luftbild Kern: je km `image_core/dop_<E>-<N>.tif` (RGB 0,2 m, Berlin vor Brandenburg); Umgebung 2 m per WMS
  (`image_far/`). OSM wie Basel (Overpass; bei Überlast wartet das Skript und versucht es erneut).
Rohdaten in Fundus: siehe unten.

#### Hamburg (`fetch_de.py`, Quelle `"hh"`, EPSG:25832)
Gebiet `hamburg-aussenalster` (Außenalster, Westufer Rotherbaum/Harvestehude). Ablauf wie Berlin: `fetch_de.py`, `prepare.py`,
`routes.py`, `buildings.py`, `fetch_de.py … --trees-inputs`, `trees.py`, `bake.py`, `export.py`, `minimap.py`, `lanes.py`.
Quellen (Transparenzportal Hamburg, LGV, dl-de/by-2-0, „Freie und Hansestadt Hamburg, LGV“): DOP belaubt 2024 (DOP20 RGBI,
1-km-Kacheln aus Bezirks-ZIPs, an den Bezirksgrenzen beschnitten → `"hh_districts"` nennt alle Bezirke des Kerngebiets),
DGM1 2022 und bDOM 2022 (GeoTIFF 1 m, nodata beim Abruf auf −9999 umgeschrieben, sonst liefert `rasterio.merge` Nullen),
LoD2-DE 2026 (CityGML 1.0), WMS `dop_zeitreihe_belaubt` (TIME=2024). Alles per HTTP-Range aus den landesweiten ZIPs, nur
die nötigen Kacheln. Bäume mit `"tree_mix": "broadleaf"` (Laubbaum-Stadtgrün: Nadelbaum nur bei klar spitzer, schlanker Krone).
Im LoD2 fehlen die Turmspitzen von St. Petri, St. Jacobi und St. Michaelis (vorhanden: St. Nikolai, Rathaus, Heinrich-Hertz-Turm).

#### Frankfurt am Main (`fetch_de.py`, Quelle `"he"`, EPSG:25832)
Gebiet `frankfurt-main` (Main von der Osthafenbrücke flussab bis hinter die Friedensbrücke, `"shape": "one_way"`, eine Haltung
zwischen den Staustufen Offenbach und Griesheim). Ablauf wie Hamburg, dazu `bridges.py` nach `bake.py` (neun Brücken, Deck aus
dem DOM1 mit `"deck_from": "dsm"`; Holbeinsteg und Deutschherrnbrücke mit `deck_m`, weil das DOM1 dort Wasser bzw. Fachwerk
und Oberleitung zeigt). Quellen (HVBG Downloadcenter gds.hessen.de, dl-de/zero-2-0, „Geobasisdaten: Hessische Verwaltung für
Bodenmanagement und Geoinformation (HVBG), dl-de/zero-2-0, bearbeitet“): DGM1, DOM1 (statt bDOM), DOP20 (RGB-JPEG mit .jgw)
je Kreis-ZIP, LoD2 je Gemarkung (Auswahl über die gml:Envelope am Dateianfang), WMS `he_dop_rgb` (ausserhalb Hessens weiss →
Lücke). Die Download-Links haben einen täglich wechselnden Datumsordner und werden über die REST-Schnittstelle des
Downloadcenters aufgelöst (`"fetch_de": {"he_kreis": …, "he_lod2_kreis": …}`); HEAD liefert 405, die Grösse kommt aus
`Range: bytes=0-0`. Brückenpfeiler: Eiserner Steg aus OSM, Alte Brücke, Ignatz-Bubis-, Deutschherrn- und Flößerbrücke aus dem
DOP20 (Pfeilerköpfe, Durchfahrtszeichen), Untermain- und Friedensbrücke geschätzt (gleiche Felder). Keine Ruderer-Bahnen: in
den 36-m-Feldern der Untermainbrücke haben eigene Bahn, Rückfahrtversatz und Nachbarbahn nicht Platz (wie Spree).
Nur Stufe `standard` (bake.py `hoch` braucht mehr Arbeitsspeicher, als neben vLLM frei ist).

#### Japan (`fetch_world.py` + `plateau.py`, JGD2011 / UTM, docs/WELTWEIT.md Abschnitt 10)
Gebiete `toda-regatta` (EPSG:6691), `tokyo-sumida` (EPSG:6691, `one_way`, Brücken und Hochstrassen) und `otsu-seta`
(EPSG:6690). Ablauf wie Frankreich, aber Gebäude mit `plateau.py` (PLATEAU-CityGML, Toda/Tokio) statt `buildings.py`
bzw. `buildings_footprints.py` mit GSI-Vektorkachel-Umrissen (Ōtsu, `"buildings": {"type": "gsi"}`); Bäume mit
`"chm_from": "ortho"` (kein offenes DSM); feste Wasserhöhe `"water_level_m"`. Tokio braucht wegen der Dichte
`"bake_bands"`, `"bake_terrain_step_m": 6`, `"bake_keep_tall_m": 150` und `ROWCOACH_PREVIEW_TEX_REDUCE=2 ./run_preview.sh …`.

#### Polen (`fetch_world.py`, GUGiK, ETRS89 / UTM 33/34 N, docs/WELTWEIT.md Abschnitt 11)
Gebiete `krakow-wisla` (EPSG:25834, `one_way`, Weichsel flussab mit neun Brücken) und `warszawa-wisla` (EPSG:25834,
`one_way`, Weichsel flussab mit acht Brücken, Pfeiler aus OSM `bridge:support`) sowie `poznan-malta` (EPSG:25833,
Regattabahn Malta, 2000 m hin und zurück; ohne Brücken). Ablauf wie Frankreich: `fetch_world.py`
(NMT/NMPT über WCS, Ortofotomapa über WMS mit `"axis_order": "ne"`, BDOT10k-Gebäude als GeoPackage-ZIP), `prepare.py`,
`routes.py`, `buildings_footprints.py`, `fetch_world.py … --trees-inputs`, `trees.py`, `bake.py --device cpu`, `bridges.py`,
`export.py`, `minimap.py`, `lanes.py`. Das NMPT (ASCII-Grid) braucht 1–2 min je km²; `--skip-osm` und OSM getrennt holen,
wenn Overpass hängt.

Weitere Gebiete: `areas/rhein-basel.json`, `areas/rhein-stein.json`, `areas/luzern-seebecken.json` (gleiche
Reihenfolge der Schritte; `run_preview.sh <gebiet> standard <strecke> --checks` legt zusätzlich Kontrollbilder quer zur
Fahrt und eine Schrägansicht der Wende unter `build/<gebiet>/checks/` ab).

### Optionen der Gebietsdatei (neben `core_lv95`, `far_lv95`, `fetch`, `routes`)
| Feld | Wirkung |
|---|---|
| `crs` | Koordinatensystem des Gebiets, Standard `"EPSG:2056"` (LV95). Berlin/Brandenburg: `"EPSG:25833"` (ETRS89/UTM 33N). Die Felder `core_lv95`, `far_lv95`, `buildings_lv95`, `start_lv95`, `toward_lv95`, `via_lv95`, `bridge_piers_lv95`, `extra_obstacles_lv95`, `piers_lv95`, `axis_lv95` behalten ihren Namen, ihre Werte stehen im System `crs`. Szene wie bisher: x = E − E0, z = −(N − N0), Ursprung = Mitte des Kerngebiets bzw. `origin_lv95`. course.json trägt `crs` und `origin` (allgemein), Schweizer Gebiete zusätzlich wie bisher `origin_lv95` |
| `fetch_de` | nur für `fetch_de.py` (Berlin/Brandenburg): `{"dgm": true, "ortho": ["be", "bb"], "ortho_far": ["be", "bb"], "lod2": ["be", "bb"], "bdom": true}`, Reihenfolge = Vorrang (Berlin vor Brandenburg) |
| `raster_dirs` | Rohdaten-Ordner für prepare.py, Standard `{"alti_core": "alti_core", "alti_far": "alti_far", "image_far": "image_far"}`; mit fetch_de.py `{"alti_core": "dgm", "alti_far": "dgm"}` |
| `water_level_ref_lv95` | zusätzliche Punkte im Wasser, deren Umgebung (300 m) die Wasserhöhe bei `"osm"` bestimmt (z. B. für `via_lv95`-Strecken oder um eine Schleuse auszuschliessen) |
| `lake_level_m` | feste Wasserhöhe (Seen, `water_source: "dem"`); bei `"osm"` darf es fehlen, dann bestimmt prepare.py die Höhe (`build/<gebiet>/water_meta.json`) |
| `water_source` | `"dem"` (Standard, Zürich): ebene Fläche auf Seehöhe im Höhenmodell. `"osm"`: Wasserpolygone aus OpenStreetMap (Overpass-API, ein Request je Gebiet → `data/raw/<gebiet>/osm/overpass.json`, © OpenStreetMap contributors, ODbL), am Höhenmodell nachgeschärft; Wasserhöhe = Median des Höhenmodells im Wasser nahe den Start-/Zielpunkten; Ufergelände tiefer als Wasserhöhe + 0,3 m wird angehoben (nicht unterhalb eines Wehrs); Gewässer auf anderer Höhe (Teiche, Bäche) bleiben Gelände |
| `copernicus_tiles` | Kacheln des Copernicus DEM GLO-30 (AWS Open Data, z. B. `Copernicus_DSM_COG_10_N47_00_E007_00_DEM`); füllen Höhenlücken ausserhalb der Schweiz (Versatz geschätzt, 250 m weicher Übergang). Luftbildlücken bekommen eine ruhige Geländefarbe mit Schummerung (Sonne 235°/48°), 300 m Übergang; fehlende Luftbildpixel im Kerngebiet kommen aus dem Umgebungsluftbild |
| `dem_ground_points`, `dem_flatten`, `chm_osm_wood` | nur für Gebiete mit Copernicus GLO-30 als einzigem Höhenmodell (Oberflächenmodell, misst Dächer und Kronen mit): `dem_ground_points` führt das Kerngelände an die Grundhöhen der Gebäudeumrisse heran (Rio, IPP-Feld `BASE`), `dem_flatten` ebnet flaches Land ein (graue Öffnung + Obergrenze; Tigre), `chm_osm_wood` legt in OSM-Wald ein synthetisches Kronendach für trees.py an (synthetisches Luftbild ohne Kronenschatten). Details prepare.py, geofetch.chm_from_ortho, docs/WELTWEIT.md Abschnitt 15 |
| `app_qualities` | Stufen, die `install_courses.py` ins App-Bundle kopiert (z. B. `["standard"]`); landet als optionales `bundle_qualities` in course.json |
| `far_step_m`, `far_tex` | Gitterabstand (m) und Texturgrösse (px) des Umgebungsgeländes statt der Werte der Qualitätsstufe (standard 100 m / 2048 px); eine Zahl oder `{stufe: wert}`. Für steile Wände direkt hinter dem Kerngebiet (Nærøyfjord) |
| `terrain_err_scale` | Faktor auf den erlaubten Höhenfehler des Kerngeländes je Abstandsband (Standard 1). Steile Fjordwände ergeben sonst Millionen Dreiecke (Nærøyfjord 2,5) |
| `bridge_piers_lv95` | Brückenpfeiler aus dem Luftbild, nur zur Kontrolle (Abstand in `route_check.json`, rot in der Detailvorschau) |
| `extra_obstacles_lv95` | zusätzliche Hindernisse (Polygone), denen die Strecken ausweichen |
| `trees` | optional, `true`: Bäume und Büsche aus swissSURFACE3D − swissALTI3D (`trees.py`), in `export.py` unter `/Scene/Trees` (je 1-km-Zelle ein Mesh) plus sanfter Kontaktschatten im Gelände. Ohne das Feld ändert sich nichts |
| `trees_budget` | optional, Dreiecke für Bäume je Stufe, z. B. `{"standard": 180000, "hoch": 450000}` (Standard 250 000 / 550 000) |
| `tree_mix` | optional, `"broadleaf"` (Laubbaum-Stadtgrün, Hamburg), `"pine"` (Kiefernwald: schlanke hohe Kronen in dichtem Bestand werden Kiefern mit Krone im oberen Drittel, Pappeln nur einzeln oder in Reihen) oder `"alpine"`; ohne Angabe `"pine"` ausserhalb der Schweiz (`crs` ≠ EPSG:2056) |
| `tree_max_h_m` | optional, Bäume ausserhalb des Waldes über dieser Höhe fallen weg (Gebäudeteile, die in den Grundrissen fehlen; Boston 28). Brücken mit `"route_shift": false` zählen für die Streckenverschiebung in routes.py nicht (enge Durchfahrt von Hand gelegt, z. B. Grand-Junction-Bahnbrücke unter der BU Bridge) |
| `summer_grade` | optional, `true`: Geländetexturen sommerlicher (`summer.py`: Rasen satter und heller, Kronen satter und dunkler, alles leicht wärmer, Dächer und Strassen bleiben) |
| `crs` | Koordinatensystem des Gebiets für die Raster von `trees.py` (Standard `EPSG:2056`) |
| `bridges` | optional, Liste von Brücken für `bridges.py` (swissBUILDINGS3D enthält keine Strassen- und Fussgängerbrücken). Je Brücke: `name`, `slug` (nur a–z, 0–9 und `_`, wird Teil des USD-Meshnamens), `style` (`"beam"` Balken, mit `depth_m` [Feldmitte, Pfeiler] und `haunch_m` als Voute; `"arch"` Bögen mit `spring_m` Kämpferhöhe und `crown_m` Scheitelstärke; `"substructure"` nur Platte und Holzjoche unter einer Brücke, die als Gebäude schon da ist; `"suspension"` Hängebrücke wie `"beam"` plus Türme an den Pfeilern (`tower_m` über dem Deck, `tower_w_m`, `tower_t_m`), Ketten (`chain_sag_m`, `chain_m`) und Hänger (`hanger_m`), Farbe `steel_color`, z. B. Hammersmith Bridge), Grundriss aus `osm_outline` (OSM-Weg man_made=bridge), `axis_lv95` + `width_m` oder `axis_osm_way`; Deckhöhe aus swissTLM3D (3D-Fahrbahnachsen, `fetch_tlm.py`), `deck_m` oder (ohne swissTLM3D, z. B. Berlin) `"deck_from": "dsm"`: Oberflächenmodell bDOM entlang der Achse (Median der mittleren halben Breite je 10 m, minus `deck_dsm_offset_m`, Standard 0,3 m); `underside_m` feste Unterkante (z. B. doppelstöckig); Pfeiler aus `piers_lv95`, `piers_s` (m auf der Achse), `spans_m` (bekannte Spannweiten, mittig auf dem Wasser bzw. mit `spans_center: "axis"` auf der Achse), `spans_equal` (geschätzt) oder `pile_spacing_m`; Form `pier_t_m`, `pier_len_m`, `pier_nose_m`; Aussehen `parapet` (`"stone"`, `"railing"`), `pattern` (`"stone"`, `"concrete"`, `"truss"`, `"wood"`), `color`, `pier_color`; `pier_source` (Text für Kontrolle und Bericht). routes.py verschiebt die Strecke an Pfeilern, die näher als 8 m (Mitte) bzw. 6 m (Rand) an Hin- oder Rückfahrt stehen, in einem weichen Bogen (`pier_shift_window_m` je Strecke, Standard 120 m); `route_check.json` nennt `pier_shifts`. Enge Bögen (Elvet Bridge Durham): je Strecke `"pier_check_back": false` (one_way: nur die Hinfahrt zählt), `pier_edge_min_m`/`pier_center_min_m` (dort 3/4,5 m). `bridges.py` schreibt `build/<gebiet>/bridges/` (Meshes, Atlanten, `meta.json` mit Pfeilern, lichter Höhe an der Bahn und Abständen); `export.py` hängt die Brücken unter `/Scene/Bridges` an (je Brücke ein Mesh). Ohne das Feld bleibt alles wie bisher |

Je Strecke statt `offset_m`/`start_lv95`/`toward_lv95` auch `via_lv95`: Stützpunkte vom Start zur Wende frei auf dem
Wasser (zwei Punkte = gerade Linie, z. B. die 2000-m-Regattastrecke; mehr Punkte mit `smooth_m` zu Bögen geglättet);
`length_m` kürzt auf die halbe Länge. Je Strecke zusätzlich: `smooth_m` (Glättungsfenster, Standard 120 m), `avoid` (Standard true bei `"osm"`: Stege,
Anlegestellen, Brückenpfeiler und Fähranleger aus OSM werden umfahren), `obstacle_dist_m` (Abstand zu ihnen,
Standard 20 m). Liegt das Ufer links der Hinfahrt, fährt die Rückfahrt (App: 12 m links) 12 m näher am Ufer:
dann `offset_m` und `obstacle_dist_m` um etwa 6–12 m grösser wählen. routes.py schreibt bei `"osm"`
`route_preview_<strecke>.png` (SWISSIMAGE-Ausschnitt mit Ufer, Brücken, Stegen, Hin- und Rückfahrt) und `route_check.json`.
fetch.py entpackt die Gebäude-ZIPs selbst nach `buildings_x/`.

### Bäume und Sommerfarben (`trees.py`, `summer.py`)
```bash
.venv/bin/python fetch.py     areas/<gebiet>.json            # Job surface_core: swissSURFACE3D Raster 0,5 m (Kerngebiet)
.venv/bin/python fetch_tlm.py areas/<gebiet>.json            # Einzelbäume, Bodenbedeckung (Wald, Gehölz), Strassen
.venv/bin/python trees.py     areas/<gebiet>.json [standard] [hoch] [--redetect] [--detect-only] [--procs 8]
.venv/bin/python export.py    areas/<gebiet>.json            # danach wie immer; mit Licht-Variante auch --light ambient
```
- Eingaben in `build/<gebiet>/` (fehlen sie, erzeugt `trees.py` sie aus den swisstopo-Rohdaten; andere Gebiete können
  eigene ablegen, Koordinatensystem `crs`): `chm.tif` (Vegetationshöhe = Oberflächenmodell − Geländemodell, float32,
  0,5 m), `building_mask.tif` (uint8, 1 = Gebäude/Brücke, gleiche Rasterung), `ortho_core.tif` (RGB 1 m), dazu
  `dem_core.tif`, `water.geojson`, `routes.geojson`, `buildings_*.npz`; optional swissTLM3D-gpkg.
- Ergebnis `build/<gebiet>/trees/`: `detected.npz` (alle Bäume/Büsche), `stats.json`, `veg.tif` (1 m: 1 Rasen/Wiese,
  2 Krone), je Stufe `<stufe>/trees.npz` + `tree_*.jpg` + `tree_ao.tif` + `meta.json` und `<stufe>-ambient/`
  (gleiche Meshes, Atlas ohne Sonnenschatten; `export.py --light ambient` nimmt sie mit, `replaces` enthält dann `Trees`).
- Detailstufen: standard ≤ 300 m volle Form (Krone 56 Dreiecke + Stamm 6), ≤ 1000 m einfache Form (20 + 6, nur
  Bäume ab 6 m), Büsche ≤ 150 m; hoch ≤ 500/1500 m (90 + 8 bzw. 36 + 6). Weiter weg keine 3D-Bäume, dafür die
  sommerliche Geländetextur. Nur von der Strecke aus sichtbare Bäume; Budget je Stufe (`trees_budget`).
  Kein Kronenrand näher als 12 m bzw. die halbe Baumhöhe an Hin- oder Rückfahrt (`LANE_CLEAR_M`); Kronenradius
  höchstens 0,15 × Höhe + 2 m (Nadelbaum) bzw. 0,35 × Höhe + 1,5 m (Laubbaum), sonst ragen zusammengefasste Kronen
  riesig ins Bild und verdecken HUD und Navigator.
- Erkennung auch bei unbelaubten Bäumen (SWISSIMAGE Zürich ist im Frühjahr beflogen): eine Krone zählt, wenn sie grün
  ist, im TLM-Wald liegt, ein TLM-Einzelbaum darin steht oder ihre Oberfläche rau ist (Fahrzeuge, Zelte sind glatt).
  `summer.py` zieht unbelaubte Kronen in der Geländetextur behutsam ins Laubgrün.
- `summer_grade` braucht `trees/veg.tif` nicht zwingend (sonst nur Grünanteil im Luftbild). Die Luftbildkarte
  (`minimap.py`) bleibt unverändert.

### Verkehr auf dem Wasser (`lanes.py`, KONZEPT.md Abschnitt 16)
Läuft nach `export.py` und `minimap.py` (export.py schreibt course.json neu und verliert dabei `minimap` und `traffic`).
Trägt in jede course.json des Gebiets das optionale Feld `traffic` ein: `vessels` (Schiffsarten), `density`,
`rower_lanes` (Bahnen der virtuellen Ruderer: Versatz `out_m`/`back_m` zur Hinfahrt, konzentrische Halbkreise an
Wende und Start, ≥ 8 m zur eigenen Bahn, ≥ 10 m zum Ufer, ≥ 6 m zu Pfeilern und Stegen) und `vessel_lanes`
(`parallel` ≥ 40 m bzw. für grosse Schiffe ≥ 80 m neben der Strecke, `far` 300–1500 m draussen, `cross` quer über das
Gewässer, alle im Wasser mit ≥ 20–35 m Uferabstand, weg von Pfeilern, Stegen und – quer – 40 m von Brücken).
Schiffsarten: Feld `traffic` der Gebietsdatei (`{"vessels": [...], "density": 1.0}`), sonst Voreinstellung je Gebiet
(Zürich Kursschiff, Motorboot, Segelboot; Luzern Raddampfer, Motorboot, Segelboot; Basel Rheinschiff, Fähre, Motorboot;
Stein am Rhein Kursschiff, Weidling, Motorboot; Spree Berlin-Mitte Kursschiff als Ausflugsdampfer, Motorboot; Havel/Potsdam
Kursschiff als Ausflugsschiff, Segelboot, Motorboot; Grünau Motorboot als Trainerboot, Segelboot). Kontrollbild: `build/<gebiet>/lanes_preview_<strecke>.png`.
Ruderer-Bahnen liegen höchstens 60 m von der eigenen Bahn entfernt; auf den Geraden rückt `compress_lanes` sie so nah
wie möglich heran (innerste 9 m rechts der Hinfahrt bzw. 10 m jenseits der Rückfahrt, je 9 m Abstand; `out_m`/`back_m`),
an Wende und Start gelten `turn_out_m`/`turn_back_m` (80 m Übergang); Schiffslinien ab 12 m ausserhalb der äussersten
Ruderer-Bahn (kleine Boote ab 20 m, Kursschiff ab 40 m, Rheinschiff ab 50 m von der eigenen Bahn). `rower_docks`:
Ein- und Ausstiegsstellen der Ruderer (OSM `sport=rowing` bzw. Name mit Ruder/Rowing/Seeclub, `leisure=marina`,
`leisure=slipway`, `man_made=pier`, höchstens 350 m von der Strecke; sonst die Streckenenden) mit Ein- und Ausfahrt als
Bogen auf die dem Ufer nächste Ruderer-Bahn (grün bzw. orange im Kontrollbild).
Je Gebiet optional (Gebietsdatei `traffic` bzw. Voreinstellungen in lanes.py, derzeit nur Hamburg Außenalster):
`vessel_intervals` (Abstände je Schiffsart in s, z. B. Segelboote alle 45–120 s, Alsterdampfer alle 10–15 min),
`sail_lanes` (Segelrevier: Linien `kind: "sail"` quer durch die Wasserfläche, ≥ 60 m von der Strecke, nur für Segel- und
Tretboote; nur die von der Strecke aus über offenes Wasser sichtbare Fläche) und `rower_around` (Ruderer-Bahnen rund um
die eigene bevorzugen, damit auf beiden Fahrten ein Hase nah daneben fahren kann; passt nur die innerste, kommen weitere
Bahnen ganz auf einer Seite ≥ 8 m ausserhalb dazu). Schiffsarten `alsterdampfer` (25 m) und `tretboot` (4 m) gibt es ab
jetzt in der App. Die innerste Bahn rund um die eigene darf an einzelnen Stellen (Brückenpfeiler) weich nach aussen
ausweichen (`out_bumps`/`back_bumps`: Verschiebung d, Kosinusfenster ±w um s); derzeit nur Basel.
Schmale Flüsse: findet sich keine Bahn, folgen ein zweiter Versuch mit `NARROW_RULES` (Ufer 5 m, Pfeiler 4 m, eigene Bahn
5 m) und ein dritter mit `VERY_NARROW_RULES` (Ufer 1,5 m, Pfeiler 3 m, eigene Bahn 4 m; Oxford Isis, Durham Wear).
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

Die Rohdaten liegen unter `data/raw/…` (nicht in Git) und sind in Fundus registriert: Zürich `dataset:832`, Basel `dataset:833`, Stein am Rhein `dataset:834`, Luzern `dataset:835`, swissTLM3D (Strassen, Bahnen; für die Brücken) `dataset:836`, Berlin-Grünau `dataset:841`, Spree Berlin-Mitte `dataset:842`, Havel (Wannsee, Potsdam) `dataset:843`, Hamburg Außenalster `dataset:845`, Frankfurt Main `dataset:846`, Oxford Isis `dataset:847`, Vaires-sur-Marne `dataset:848`, Lac d’Aiguebelette `dataset:849`, Lac d’Annecy `dataset:850`, Saône Lyon `dataset:851`, Lac d’Allier Vichy `dataset:852`, Toda-Regattastrecke `dataset:853`, Sumida Tokio `dataset:854`, Seta Ōtsu `dataset:855`, Weichsel Kraków `dataset:856`, Weichsel Warszawa `dataset:857`, Malta Poznań `dataset:858`, Alte Donau Wien `dataset:859`, Regattastrecke Linz-Ottensheim `dataset:860`, Traunsee Gmunden `dataset:861`, Henley-Regattastrecke `dataset:862`, Wear Durham `dataset:863`, Themse London Putney–Chiswick `dataset:864`, Charles River Boston `dataset:865`, Oslo Frognerkilen–Bjørvika `dataset:868`, Nærøyfjord Gudvangen `dataset:869`, Río Luján Tigre `dataset:866`, Lagoa Rodrigo de Freitas Rio de Janeiro `dataset:867`; swissSURFACE3D Raster und swissTLM3D Einzelbäume/Bodenbedeckung (für die Bäume) siehe Abschnitt „Bäume und Sommerfarben“.
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

## Figuren und Boote (Spark, `tools/avatars`)
```bash
cd ~/Projects/Software/RowCoach/tools/avatars
../coursebuilder/.venv/bin/python build.py --glb   # → App/RowCoach/Resources/Avatars/*.usdz (+ dist/avatars/*.glb)
./run_preview.sh                                    # → Resources/AvatarPreviews/<id>.png, docs/avatar/overview-*.png,
                                                    #   docs/avatar/check-skintones.png (Abnahme Hauttöne × Licht)
../coursebuilder/.venv/bin/python views.py /tmp/x.png app 0.3 char-01:boat-classic-yellow   # Kamerabild der App
```
Nach Änderungen an `appearance.json` (neue Figurtypen/Bootsstile) nur `run_preview.sh` neu; neue Frisuren,
Ausleger- oder Blattformen brauchen Code in `figure.py`/`boat.py` und `build.py`. Details: docs/avatar/SPEC.md
„Umsetzung 3D“.

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
| `-demoTrafficAheadDelay <s>` | wie `-demoTrafficAhead 1`, aber die beiden Boote kommen erst nach s Sekunden (z. B. 20, also nach dem Laden der Landschaft) |
| `-demoTrafficPlain 1` | andere Boote als rote Quader mit `SimpleMaterial` (Ruderer 1,2 × 1,2 × 8 m, Schiffe in ihrer Länge), um Material und Meshes als Ursache auszuschliessen |
| `-demoRace 1` | zusammen mit `-demoCourse`: Rennen gegen zwei Bots (Anna, Ben), Start mit dem ersten Schlag |
| `-demoRace <N>` | N ≥ 2: grosses Feld mit N Bots (z. B. `300`; `RaceBotField`/`RaceBotTransport`, Tempo um das eigene, Zwischenspurts, Endspurt). Der Planer zeigt nur die nahen voll, weitere vereinfacht bzw. als Silhouetten; HUD „Platz … von …“. Protokoll Kategorie Race: Budget je Gerät, alle 10 s gezeigte Boote je Stufe, Silhouetten, Vorrat |
| `-demoTournament 1` | zusammen mit `-demoCourse`: Turnier zur aktuellen Uhrzeit mit gewürfeltem Mindestfeld (45–387), ich + 0–2 „echte“ Demo-Boote, Rest virtuelle Teilnehmende aus dem Pool (✦, Auswahl nach Ortszeit, Niveau um das eigene Tempo, Rotation). Info-Blatt beim ersten Turnier; nach dem Speichern „Ergebnis und Rangliste“ (lokale Rangliste). Protokoll Kategorie Race: „Pool v1: 5000 …“, „Turnier …: Mindestfeld …, echt …, virtuell …“, „Turnier-Rennen … gewertet: Platz …“ (docs/MULTIPLAYER.md „Virtuelle Teilnehmende“) |
| `-resetVirtualInfo 1` | Info-Blatt „Virtuelle Teilnehmende“ beim nächsten Turnier wieder zeigen: löscht beim Start den UserDefaults-Schlüssel `virtualParticipantsInfoSeen` (Bool, Standard-Domäne der App `com.falkue.RowCoach`). Achtung: `defaults delete com.falkue.RowCoach …` auf dem Mac trifft nicht den Simulator; dort `xcrun simctl spawn booted defaults delete com.falkue.RowCoach virtualParticipantsInfoSeen`, auf dem iPad nur dieses Startargument. Protokoll Kategorie Race: „Info-Blatt virtuelle Teilnehmende: …“ |
| `-raceBudget <stufe>` | Budget des Rennplaners fest statt nach Gerät: `a12x` (6 voll / 12 vereinfacht / 48 Silhouetten), `standard` (10/16/96), `high` (12/20/160) |
| `-demoLookAtSun 1` | nur Testbetrieb: Kamera blickt zur Sonne statt in Fahrtrichtung (Sonne im oberen Bilddrittel), um zu prüfen, ob Abendrot im Himmel und Sonnenscheibe übereinanderliegen; z. B. mit `-demoCourse zuerichsee-utoquai -demoSun evening`. Liegt das Abendrot daneben: `ProceduralTextures.equirectNorthU`/`equirectAzimuthSign` anpassen |
| `-clearDemoHistory 1` | entfernt alle Beispieltrainings beim Start (läuft vor `-seedDemoHistory`; beide zusammen = frisch anlegen) |

Weitere Schalter für Tests (UserDefaults über die Startargumente):
| Argument | Wirkung |
|---|---|
| `-onboarding.done YES` | Einstieg beim ersten Start überspringen (sonst erscheint er bei frischer Installation ohne Fahrten und ohne Profil; mit `-demoCourse` oder `-seedDemoHistory` nie) |
| `-onboarding.done NO` | Einstieg erneut zeigen (wenn Profil noch Standard und keine Fahrten) |
| `-history.showSimulated YES` | Simulatorfahrten im Verlauf zeigen (sonst ausgeblendet; Beispieltrainings erscheinen immer) |
| `-training.spokenCues NO` | gesprochene Ansagen aus (Standard an) |

Hinweise zur UX-Überarbeitung (Gestaltungssystem, Tabs Heute · Strecken · Programme · Pläne · Verlauf):
- Fahrten unter 100 m oder 1 min werden nicht gespeichert. `-demoFinishAfter` deshalb mindestens 60 s (der Simulator
  rudert 2:05 /500 m, also 4 m/s), sonst zeigt die Zusammenfassung „Zu kurz zum Speichern“ ohne Anstrengungsabfrage.
- Der Dialog „Fahrt beenden“ hält die Fahrt an (Zeit steht); „Weiterrudern“ setzt sie mit dem nächsten Schlag fort.
- Neue Dateien seit der Überarbeitung (`Views/DesignSystem.swift`, `Views/RootView.swift`, `Views/ProfileViews.swift`,
  `Session/SpeechCoach.swift`, `Assets.xcassets/AccentColor.colorset`, `Resources/Localizable.xcstrings`,
  `Resources/InfoPlist.xcstrings`): einmal `xcodegen generate`.

### Trainingspläne (Tab „Pläne“, docs/trainingsplaene/UMSETZUNG.md)
- Neue Dateien `RowCoach/Storage/ProgramStore.swift` und `RowCoach/Views/ProgramViews.swift`: einmal `xcodegen generate`.
- Daten: `python3 docs/trainingsplaene/gen_training_plans.py` schreibt `Resources/training_plans.json` und
  `docs/trainingsplaene/PLAENE.md`; danach `python3 App/l10n/check_training_plans.py`. Neue Programme für Pläne kommen
  über `docs/plans-new/<familie>.json` und `python3 App/l10n/merge_plans.py` in `plans.json`.
- Der aktive Plan steht als JSON in UserDefaults (`trainingProgram.active`); zum Zurücksetzen im Tab „Pläne“ →
  aktiver Plan → „Plan beenden“ oder Startargument `-trainingProgram.active ""`.

### Schwelle und Zonen (docs/schwelle/UMSETZUNG.md)
- Neue Dateien `RowCoach/Storage/ThresholdStore.swift` und `RowCoach/Views/ThresholdViews.swift`: einmal
  `xcodegen generate`.
- Profil in UserDefaults `threshold.profile.v1` (beim ersten Start aus `profile.best2k` angelegt; zum Zurücksetzen
  Startargument `-threshold.profile.v1 ""`). Neue Tests über `docs/plans-new/tests.json` und `merge_plans.py`.
- Firestore-Regeln haben das Feld `profile/threshold`: `firebase deploy --only firestore:rules`, bevor eine App mit
  eingeschalteter Synchronisation das Feld sendet.
- Tonkonserven der Testansagen: `python3 tools/coach_audio/render_coach.py` (nur Neues).

### Sprachen (Deutsch und Englisch)
- Texte: `App/RowCoach/Resources/Localizable.xcstrings` (Quelle Deutsch, Englisch übersetzt), Health- und
  Bluetooth-Texte in `InfoPlist.xcstrings`. Beide erzeugt `python3 App/l10n/build_catalog.py` aus den Swift-Dateien
  (`App/l10n/swift_strings.py`) und den Übersetzungen in `App/l10n/en_strings.py`; alle Einträge sind „manual“,
  damit Xcode die Texte aus RowCoachKit (zur Laufzeit im Bundle der App gesucht) nicht als veraltet entfernt.
- Neue Texte im Code: `Text("…")` bzw. `String(localized: "…")`, ganze Sätze. Danach
  `python3 App/l10n/build_catalog.py --check` (fehlende Übersetzungen) und `python3 App/l10n/swift_strings.py report`
  (nicht lokalisierte Literale, z. B. `Text(a ? "x" : "y")`, das Swift nicht lokalisiert).
- Programme: `plans.json` mit zweisprachigen Feldern (`{"de": …, "en": …}`), erzeugt mit `python3 App/l10n/plans_en.py`
  (Übersetzungstabelle im Skript); einsprachige Texte gehen weiter.
- Die Sprache folgt dem System (iOS-Einstellungen → RowCoach → Sprache). Test: Startargument `-AppleLanguages "(en)"`.

Akku-Ausfall nachstellen: Fahrt starten, nach 40 s `xcrun devicectl device process terminate --device <UDID> --pid <PID> --kill`, App neu starten → Wiederherstellung aus `Application Support/active-workout.json`.
