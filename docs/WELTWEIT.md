# Strecken weltweit: Gebiete ausserhalb der Schweiz und Deutschlands

Stand: 25.11.2026. Werkzeuge unter `tools/coursebuilder` (venv `.venv`). Die Einzelheiten stehen in den Docstrings von
`geofetch.py`, `fetch_world.py`, `buildings_footprints.py` und `synth_ortho.py`.

## 1. Koordinatensystem

Jedes neue Gebiet rechnet in einem **UTM-System in Metern** (Feld `"crs"` der Gebietsdatei). Die Felder `core_lv95`,
`far_lv95`, `via_lv95` usw. heissen aus Kompatibilität so, ihre Werte stehen immer in diesem System.

| Region | System | EPSG |
|---|---|---|
| Europa (auch Grossbritannien, Norwegen, Frankreich) | ETRS89 / UTM Zone 28–38 N | 25828–25838 (z. B. 25830 Oxford, 25831 Paris, 25832 Hamburg/Oslo, 25833 Berlin) |
| Japan | JGD2011 / UTM Zone 51–55 N | 6688–6692 (Tokio 6691, Kyōto/Ōtsu 6690) |
| Südamerika (Brasilien) | SIRGAS 2000 / UTM | 31965–31976 (11–22 N), 31977–31985 (17–25 S; Rio 31983) |
| Nordamerika | NAD83 / UTM Zone 1–23 N | 26901–26923 |
| sonst (z. B. Argentinien, Australien) | WGS84 / UTM | 326zz (Nord), 327zz (Süd) |

Die Zone folgt aus der Länge: `zone = floor((lon + 180) / 6) + 1`. Daten in anderen Systemen (British National Grid
27700, Lambert-93 2154, JGD2011 geographisch 6697 von PLATEAU, Web-Mercator-Kacheln, WGS84) rechnet `geofetch.py`
beim Holen um. Fehlende PROJ-Gitter (z. B. OSTN15 für 27700) lädt `ensure_proj_grids()` von cdn.proj.org; ohne sie
liegen britische Daten bis 2 m neben OpenStreetMap.

Die App (`RowCoachKit/Route.swift`, `GeoProjection`/`UTMProjection`) kennt alle diese Systeme, auch die Südhalbkugel
(Falscher Hochwert 10 000 000 m); Tests gegen PROJ in `UTMProjectionTests`. LV95 (2056) bleibt für die Schweiz.

## 2. Ablauf für ein neues Gebiet

```
cd tools/coursebuilder
.venv/bin/python fetch_world.py      areas/<id>.json        # Höhen, Sentinel-2, OSM, Gebäudeumrisse
.venv/bin/python synth_ortho.py      areas/<id>.json        # nur ohne offenes Luftbild ("ortho": synthetic)
.venv/bin/python prepare.py          areas/<id>.json
.venv/bin/python routes.py           areas/<id>.json
.venv/bin/python buildings_footprints.py areas/<id>.json    # statt buildings.py, wenn es kein LoD2 gibt
.venv/bin/python fetch_world.py      areas/<id>.json --trees-inputs
.venv/bin/python trees.py            areas/<id>.json standard
.venv/bin/python bake.py             areas/<id>.json standard --device cuda   # GPU über die Warteschlange
.venv/bin/python bridges.py          areas/<id>.json          # nur mit "bridges"
.venv/bin/python export.py           areas/<id>.json standard
.venv/bin/python minimap.py          areas/<id>.json
.venv/bin/python lanes.py            areas/<id>.json
./run_preview.sh <id> standard <route-id> --checks
python3 publish_catalog.py && python3 install_courses.py
```

Schritte für einen Länder-Agenten:
1. Gewässer und Strecke wählen; Zone bestimmen, `crs` nach der Tabelle oben.
2. `areas/<id>.json` anlegen (Vorlage `areas/oxford-isis.json`): `country` (ISO), `city`, `core_lv95` (Strecke + 600–800 m),
   `far_lv95` (± 5–7 km), `buildings_lv95`, `"water_source": "osm"`, `raster_dirs` (`alti_core: dgm`,
   `alti_far: dgm_far` oder `dgm`), `"buildings_source": "footprints"` falls kein LoD2, `trees`, `tree_mix`,
   `summer_grade`, `water_level_ref_lv95` (zwei Punkte im Wasser nahe der Strecke).
3. Block `fetch_world` mit den Quellen des Landes füllen (Typen `wcs`, `cog`/`scheme`, `xyz`, `sentinel2`, `arcgis`,
   `file`, `synthetic`; je Quelle `source` und `licence`). Neues Kachelschema → Funktion in `geofetch.TILE_SCHEMES`.
4. `fetch_world.py` laufen lassen; nennt es andere `copernicus_tiles`, diese in die Gebietsdatei übernehmen.
5. Nach `prepare.py` die Strecke festlegen. Schmale Flüsse: `via_lv95` entlang der Mittellinie (alle 30–40 m ein
   Punkt, `smooth_m` 60–80), `shape` `out_and_back`/`one_way`/`loop`; Brücken (`bridges`, `deck_from: dsm`) eintragen.
6. Pipeline durchlaufen lassen, die Vorschaubilder selbst ansehen, nachbessern.
7. `attribution` mit allen Quellen (Tabelle unten) und Datensatz in Fundus registrieren (`fundus.cli datasets add
   <data_dir> --reference --project rowcoach …`).

## 3. Helfer (`geofetch.py`)

- `http()`/`download()`: eine Verbindung je Server, Pause 0,3–1 s, Wiederholung mit 5–120 s Wartezeit, User-Agent
  `RowCoach-coursebuilder/0.2 (private research)`.
- `cog_read()`: COG über `/vsicurl/` mit WarpedVRT direkt ins Zielraster (nur die nötigen Blöcke).
- `wcs_tiles()`: WCS 2.0.1 in 1-km-Blöcken (Cache je Block), optional `SCALEFACTOR` für grobe Umgebungsraster.
- `xyz_read()`: XYZ-Kacheln (JPEG/PNG; Höhen mit `gsi_dem_png`, `terrarium`, `mapbox`) → Zielraster.
- `arcgis_features()`: FeatureServer/MapServer seitenweise (resultOffset, sonst Objekt-IDs).
- `s2_far()`: Sentinel-2 L2A (Earth Search), Szenen nach örtlicher SCL-Wolkenmaske, Mosaik, Tonwertkorrektur.
- `overpass()`, `copernicus_tiles()`, `log_source()` (fetch-log.json), `trees_inputs()` (chm.tif, ortho_core.tif).

## 4. Gebäude aus Grundrissen (`buildings_footprints.py`)

Gleiches npz-Format wie `buildings.py` (`buildings_fp_<E>-<N>.npz`); bake.py, trees.py und export.py laufen
unverändert. Höhe: Attribut (height, Geschosse, HAUTEUR, ALTURA …) → Oberflächen- minus Geländemodell (Perzentil im
geschrumpften Grundriss) → Voreinstellung je Art. Dach flach oder Satteldach (an das Oberflächenmodell angepasst,
Firstrichtung längs oder quer); Grundhöhe aus dem Geländemodell. Statistik in `build/<id>/buildings_fp_stats.json`.
Mit `"buildings_source": "footprints"` vereinfacht bake.py diese Gebäude nicht weiter (sonst Spitzen aus den
Satteldächern); `"wall_palette": [[r, g, b], …]` (0–1) setzt landestypische Fassadenfarben (Oxford: Kalkstein,
Backstein, heller Putz). Bei so kleinen Netzen rechnet bake.py auch auf der CPU in Sekunden (`--device cpu`).

## 5. Synthetisches Luftbild (`synth_ortho.py`)

Für Länder ohne offenes Orthofoto (Grossbritannien, Norwegen, Argentinien): 0,25 m je km-Kachel nach
`image_core/dop_<E>-<N>.tif`. Sentinel-2 als Grundfarbe, OSM-Flächen und -Wege als texturierte Schichten (Wiese,
Rasen, Wald, Gebüsch, Felder, Wohngebiet, Asphalt, Kies, Erdwege, Sand, Wasser, Gleise, Stege, Hecken), Dächer aus den
Grundrissen, Baumkronen und Schlagschatten aus dem Oberflächenmodell, Uferstreifen; Rauschen an Weltkoordinaten
verankert (nahtlos). Gebäude, die in OSM fehlen (hoch, glatt, > 40 m² im Oberflächenmodell), werden als graues
Dach statt als Baumkrone gezeichnet; bebaute Sentinel-Pixel in Wohngebieten werden zu Hofgrau statt rosa.

## 6. Quellen und Namensnennung

| Land | Höhe | Oberfläche | Luftbild | Gebäude | Namensnennung |
|---|---|---|---|---|---|
| Grossbritannien | EA LIDAR Composite DTM 1 m (WCS, 27700) | EA First Return DSM 1 m | keins offen → synthetisch (Sentinel-2 + OSM) | OSM-Umrisse + DSM-Höhe | „© Environment Agency copyright and/or database right <Jahr>“, OGL v3; Copernicus Sentinel; © OSM (ODbL) |
| Norwegen | Kartverket DTM1 (COG, 25833) | Kartverket DOM1 | keins offen → synthetisch | OSM-Umrisse + DOM-Höhe | „© Kartverket“, NLOD 2.0 |
| Frankreich | IGN LiDAR HD MNT 1 m, Ersatz RGE ALTI (WMS-R, 2154); Umgebung RGE ALTI 4 m | LiDAR HD MNS 1 m | BD ORTHO 20 cm (WMS-R), Umgebung 2 m | BD TOPO V3 batiment (WFS), Höhe = altitude_maximale_toit − altitude_minimale_sol | „Source : IGN – BD ORTHO®, LiDAR HD, BD TOPO® (Jahr), Licence Ouverte Etalab 2.0, données modifiées“ |
| Japan | GSI DEM5A PNG z15 | – (PLATEAU-Höhen) | GSI seamlessphoto z18 | PLATEAU LoD1/LoD2 (6697) | „出典：国土地理院（地理院タイル）“; „出典：国土交通省 3D都市モデル（Project PLATEAU）<Stadt>（<Jahr>年度）“ |
| Brasilien (Rio) | Copernicus GLO-30 | – | Sentinel-2 / synthetisch (IPP-Luftbild NICHT verwenden) | IPP FeatureServer BASE/TOPO/ALTURA (CC BY 4.0) | „Prefeitura do Rio de Janeiro – IPP“, CC BY 4.0 |
| Argentinien (Tigre) | Copernicus GLO-30 | – | synthetisch | OSM-Umrisse, Voreinstellung | Copernicus; © OSM |
| überall | Copernicus DEM GLO-30 (Umgebung, Lücken) | | Sentinel-2 L2A (Umgebung) | | „© DLR e.V. 2010–2014 und © Airbus Defence and Space GmbH 2014–2018 …“; „Contains modified Copernicus Sentinel data <Jahr>“ |

Hessen und Japan sind hier nur aus der Recherche übernommen und noch nicht mit `fetch_world.py` geprüft. Frankreich ist
geprüft (Abschnitt 9).

## 7. Testgebiet Oxford (Isis)

`areas/oxford-isis.json`: Iffley Lock → Folly Bridge, 1839 m hin, 3677 m gesamt, EPSG:25830. EA DTM/DSM 1 m (WCS),
OSM-Umrisse mit DSM-Höhen (8283 Gebäude, 2239 Satteldächer aus dem DSM), synthetisches Luftbild 0,25 m, 5788 Bäume aus
DSM − DTM, Donnington Bridge (Deck aus dem DSM), Umgebung Copernicus GLO-30 + Sentinel-2 (19.06.2025). Fundus
dataset:847. Der Fluss ist 26–60 m breit: Hinweg 6 m rechts der Mitte, Rückfahrt 6 m links; lanes.py findet keine
Ruderer-Bahnen (wie Spree), nur Schiffsarten.

## 8. Bekannte Grenzen

- Synthetisches Luftbild: keine Autos, Boote, Markierungen, Beete; Felder und Gärten nur in Sentinel-2-Genauigkeit
  (10 m); Klassengrenzen folgen OSM (fehlt eine Fläche in OSM, zeigt sie die Sentinel-Farbe mit Wiesenstruktur).
- Gebäude aus Grundrissen: nur Flach- und Satteldächer, keine Gauben, Türme, Kuppeln; Fassaden einfarbig wie bei LoD2;
  Bäume über dem Grundriss können die Höhe aus dem Oberflächenmodell überschätzen.
- Ohne Oberflächenmodell (Copernicus-only-Gebiete) keine Bäume aus der Vegetationshöhe und Gebäudehöhen nur aus
  Attributen oder Voreinstellungen.
- Wasserhöhe: Lidar hat über Wasser oft Lücken; prepare.py nimmt den Median nahe `water_level_ref_lv95`.
- EA-WCS (Grossbritannien): langsam, einzelne Anfragen laufen in Zeitüberschreitungen (120 s, dann neuer Versuch),
  bei vielen Anfragen HTTP 429. Deshalb nur das Kerngebiet in 1 m holen (~25 Blöcke je Modell, 20–30 min) und die
  Umgebung aus Copernicus GLO-30 (`alti_far: dgm`); `dtm_far` mit `SCALEFACTOR` geht technisch, ist dort aber zu viel.
- Arbeitsspeicher: Die Spark teilt den Speicher mit vLLM (oft nur 2–3 GB frei). synth_ortho.py rechnet deshalb in
  Blöcken à 500 m (~1 GB); ein Kerngebiet von 20 km² braucht rund 50 min.

## 9. Frankreich (IGN Géoplateforme, EPSG:25831)

Quellentypen `wms` (Höhen und Luftbild, `geofetch.wms_tiles`) und `wfs` (Gebäude, `geofetch.wfs_features`); Vorlage
`areas/vaires-sur-marne.json`. Die Géoplateforme liefert GeoTIFFs mit kaputtem WKT (Datum „unknown“): `wms_tiles`
rechnet die Georeferenz aus der angefragten BBOX in EPSG:2154 und nimmt nie die der Datei. Höchstbreite 5010 px:
Luftbild 0,2 m je km-Kachel in 2 × 2 Teilblöcken, Höhen 1 m in einem Block je km. Ganzes Gebiet (8 km² Kern) in ~10 min.
Lambert-93 und UTM 31N haben denselben Mittelmeridian (3° O), die Raster sind fast deckungsgleich.
BD TOPO `hauteur` liegt im Median 2,3 m unter dem LiDAR-HD-First (Traufe), `altitude_maximale_toit −
altitude_minimale_sol` nur 0,2 m darüber (1595 Gebäude, Vaires) → `"prefer_top": true`, sonst `hauteur + 2 m`.
Overpass gestört (overpass-api.de und Spiegel 502/Zeitüberschreitung, IPv6-Route hängt): `fetch_world.py … --skip-osm`
holt nur die IGN-Daten; OSM danach mit `ROWCOACH_IPV4=1 ROWCOACH_OVERPASS=https://maps.mail.ru/osm/tools/overpass/api/interpreter`.
Bekannt: Hinter einem Stauwehr (Vichy, Pont-Barrage) liegt das Unterwasser in der Ferne auf Seehöhe (Fernwasser eben).
Gebiete: `vaires-sur-marne` (dataset:848), `lac-aiguebelette` (dataset:849), `lac-annecy` (dataset:850, Rundkurs), `lyon-saone` (dataset:851, one_way, neun Brücken), `vichy-allier` (dataset:852).
