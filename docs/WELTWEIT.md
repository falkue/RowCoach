# Strecken weltweit: Gebiete ausserhalb der Schweiz und Deutschlands

Stand: 27.11.2026. Werkzeuge unter `tools/coursebuilder` (venv `.venv`). Die Einzelheiten stehen in den Docstrings von
`geofetch.py`, `fetch_world.py`, `buildings_footprints.py` und `synth_ortho.py`.

## 1. Koordinatensystem

Jedes neue Gebiet rechnet in einem **UTM-System in Metern** (Feld `"crs"` der Gebietsdatei). Die Felder `core_lv95`,
`far_lv95`, `via_lv95` usw. heissen aus Kompatibilität so, ihre Werte stehen immer in diesem System.

| Region | System | EPSG |
|---|---|---|
| Europa (auch Grossbritannien, Norwegen, Frankreich, Polen, Österreich) | ETRS89 / UTM Zone 28–38 N | 25828–25838 (z. B. 25830 Oxford, 25831 Paris, 25832 Hamburg/Oslo, 25833 Berlin) |
| Japan | JGD2011 / UTM Zone 51–55 N | 6688–6692 (Tokio 6691, Kyōto/Ōtsu 6690) |
| Südamerika (Brasilien, Argentinien, Peru) | SIRGAS 2000 / UTM | 31965–31976 (11–22 N), 31977–31985 (17–25 S; Rio 31983, Tigre und Encontro das Águas 31981, Anavilhanas 31980, Iquitos 31978) |
| Nordamerika (USA, Kanada) | NAD83 / UTM Zone 1–23 N | 26901–26923 (Boston 26919, St. Catharines 26917, Vancouver/Victoria 26910) |
| Island (ETRS89 / UTM 27N gibt es nicht; ISN2016 kennt die App nicht) | WGS84 / UTM Zone 27/28 N | 32627 (Reykjavík, Þingvellir), 32628 (Osten) |
| sonst (z. B. Australien) | WGS84 / UTM | 326zz (Nord), 327zz (Süd) |

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
| Norwegen | Kartverket Høydedata DTM1 1 m (COG 15 × 15 km, 25833), Umgebung auf 4 m | Kartverket DOM1 1 m | Norge i bilder nicht offen → synthetisch (Sentinel-2 + OSM) | OSM-Umrisse + DOM-Höhe | „© Kartverket“, CC BY 4.0, bearbeitet |
| Frankreich | IGN LiDAR HD MNT 1 m, Ersatz RGE ALTI (WMS-R, 2154); Umgebung RGE ALTI 4 m | LiDAR HD MNS 1 m | BD ORTHO 20 cm (WMS-R), Umgebung 2 m | BD TOPO V3 batiment (WFS), Höhe = altitude_maximale_toit − altitude_minimale_sol | „Source : IGN – BD ORTHO®, LiDAR HD, BD TOPO® (Jahr), Licence Ouverte Etalab 2.0, données modifiées“ |
| Japan | GSI DEM5A PNG z15 (Umgebung DEM10B z14) | – (kein offenes DSM) | GSI seamlessphoto z18 (0,4 m), Umgebung z16 | PLATEAU LoD1/LoD2 (6697), sonst GSI-Vektorkacheln building | „出典：国土地理院（地理院タイル）“; „出典：国土交通省 3D都市モデル（Project PLATEAU）<Stadt>（<Jahr>年度）“ |
| Polen | GUGiK NMT 1 m (WCS, 2180, PL-KRON86-NH), Umgebung auf 4 m | GUGiK NMPT 0,5 m (WCS, nur ASCII-Grid) | GUGiK Ortofotomapa HighResolution 20 cm (WMS, Achsfolge N, O), Umgebung StandardResolution 2 m | BDOT10k OT_BUBD_A je Powiat (GeoPackage), Höhe = NMPT − NMT | „Źródło: GUGiK (geoportal.gov.pl)“, Daten des PZGiK bez opłat (Art. 40a Abs. 2 Nr. 1 Pgik) |
| Österreich | BEV ALS-Höhenraster DTM 1 m (COG 50 × 50 km, 3035), Umgebung auf 4 m | BEV ALS DSM 1 m | basemap.at Orthofoto 30 cm (WMTS google3857 z19), Umgebung z16 | OSM-Umrisse + DSM-Höhe | „Datenquelle: BEV – Bundesamt für Eich- und Vermessungswesen …, CC BY 4.0, bearbeitet; Orthofoto: basemap.at, CC BY 4.0, bearbeitet“ |
| USA (Massachusetts) | USGS 3DEP 1-m-DEM (COG je 10 × 10 km, NAD83/UTM, NAVD88), Umgebung auf 4 m | aus der USGS-Lidar-Punktwolke (EPT, höchster Punkt je 1-m-Zelle) | MassGIS Frühjahr 2023 15 cm (Kacheldienst orthos2023, z19), Umgebung z16 | OSM-Umrisse + DSM-Höhe | „U.S. Geological Survey, 3DEP (public domain)“; „MassGIS (Bureau of Geographic Information)“ (erbeten) |
| Brasilien (Rio) | Copernicus GLO-30, im Stadtgebiet an die IPP-Grundhöhen geführt (`dem_ground_points`) | – | synthetisch (IPP-Luftbild Lizenz unklar, NICHT verwendet) | IPP Edificações 2013 (FeatureServer, ALTURA/BASE/TOPO, CC BY 4.0) | „Instituto Pereira Passos (IPP), Prefeitura da Cidade do Rio de Janeiro“, CC BY 4.0, bearbeitet |
| Argentinien (Tigre) | Copernicus GLO-30, eingeebnet (`dem_flatten`) | – | synthetisch | OSM-Umrisse + Microsoft Global ML Building Footprints (CDLA Permissive 2.0), Voreinstellung | Copernicus; © OSM; Microsoft |
| Island | ÍslandsDEM v1.0 10 m (GeoTIFF landesweit, ISN2016/Lambert 8088, auf 1 m interpoliert), Umgebung auf 5 m | – (kein offenes DSM) | synthetisch (LMÍ-Luftbild nicht offen) | OSM-Umrisse, Voreinstellungshöhen | „ÍslandsDEM v1.0, Náttúrufræðistofnun (vormals Landmælingar Íslands)“, CC BY 4.0, bearbeitet |
| Kanada | NRCan HRDEM Mosaic 1 m DTM (COG 500 × 500 km, EPSG:3979, CGVD2013), Umgebung auf 4 m | HRDEM Mosaic 1 m DSM | synthetisch (kein offenes Luftbild gefunden) | OSM-Umrisse + DSM-Höhe | „Natural Resources Canada, HRDEM (CanElevation) … Contains information licensed under the Open Government Licence – Canada“, bearbeitet |
| überall | Copernicus DEM GLO-30 (Umgebung, Lücken) | | Sentinel-2 L2A (Umgebung) | | „© DLR e.V. 2010–2014 und © Airbus Defence and Space GmbH 2014–2018 …“; „Contains modified Copernicus Sentinel data <Jahr>“ |

Hessen ist hier nur aus der Recherche übernommen und noch nicht mit `fetch_world.py` geprüft. Frankreich (Abschnitt 9),
Japan (Abschnitt 10), Polen (Abschnitt 11), Österreich (Abschnitt 12), USA (Abschnitt 13), Südamerika (Abschnitt 15),
Norwegen (Abschnitt 16), Island (Abschnitt 17) und Kanada (Abschnitt 18) sind geprüft.

## 7. Testgebiet Oxford (Isis)

`areas/oxford-isis.json`: Iffley Lock → Folly Bridge, 1839 m hin, 3677 m gesamt, EPSG:25830. EA DTM/DSM 1 m (WCS),
OSM-Umrisse mit DSM-Höhen (8283 Gebäude, 2239 Satteldächer aus dem DSM), synthetisches Luftbild 0,25 m, 5788 Bäume aus
DSM − DTM, Donnington Bridge (Deck aus dem DSM), Umgebung Copernicus GLO-30 + Sentinel-2 (19.06.2025). Fundus
dataset:847. Der Fluss ist 26–60 m breit: Hinweg 6 m rechts der Mitte, Rückfahrt 6 m links; lanes.py findet keine
Ruderer-Bahnen mit den üblichen und den engen Abständen; seit 27.11.2026 mit `VERY_NARROW_RULES`
(lanes.py, Ufer 1,5 m, eigene Bahn 4 m) eine offene Hasen-Linie 5,5 m rechts der Hinfahrt (drei Ausweichstellen; für die
Rückfahrt ist der Fluss an der engsten Stelle mit 22 m zu schmal). Nur `traffic` in course.json neu, Szene unverändert.

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

## 10. Japan (GSI, PLATEAU; JGD2011 / UTM 53/54 N)

Vorlagen `areas/toda-regatta.json` (PLATEAU LoD1/LoD2, Becken), `areas/tokyo-sumida.json` (dichte Stadt, Fluss mit
Brücken und Hochstrassen) und `areas/otsu-seta.json` (ohne PLATEAU: GSI-Gebäudeumrisse).
- Höhen: Quelle `xyz` mit `"decode": "gsi_dem_png"`: `dem5a_png` z15 (Laser 5 m; DEM1A gibt 404) für den Kern,
  `dem_png` z14 (DEM10B) für die Umgebung. Über Wasser ist DEM5A leer; prepare.py füllt aus der Umgebung, die dort 2–3 m
  über dem Spiegel liegt. Deshalb `"water_level_m"` fest setzen (Toda 1,2 m, Sumida 0,2 m, Seta 84,3 m T.P. = Biwa-See):
  dann bleiben grosse Gewässer Wasser, das Gelände darunter kommt 0,8 m unter den Spiegel, Löcher bis 300 m² werden
  geschlossen. Höhen sind T.P. (Tokyo Peil) wie bei PLATEAU.
- Luftbild: `xyz` `seamlessphoto` z18 mit `"res": 0.4` (z19 gibt 404), Umgebung z16 mit `"res": 2`. Aufnahmejahr je
  Kachel verschieden. `xyz_read` rechnet RGB direkt in uint8 um (sonst > 1 GB für grosse Umgebungen).
- Gebäude PLATEAU (`plateau.py`, `"buildings_source": "plateau"`, `"plateau": {"cities": [{name, year, url}]}`): Stadt-ZIP
  der CKAN-API (`package_show?id=plateau-<code>-<stadt>-<jahr>`, Ressource CityGML), per HTTP-Range nur
  `udx/bldg/<Masche>_bldg_6697_op.gml` der 1-km-Maschen im Gebäudegebiet. LoD2-Flächen, sonst LoD1-Volumen (nach der
  Normalen in Dach/Wand). Die Tokioter Bezirksdaten „pref“ enthalten ganze Maschen samt Nachbarbezirken → Doppelte über
  gml:id entfernen (Sumida: 97 000 → 58 000). `"lod2_max_dist_m"` (Tokio 900) nimmt in der Ferne LoD1, ausser
  Gebäuden ab 60 m (`measuredHeight`). `plateau.py … --brid` holt die Brückenmodelle `udx/brid` und nennt je Gebietsbrücke
  die Höhe der Flächen über dem Wasser; den häufigsten Wert der Deckfläche (nicht Median, nicht Pylone/Bögen) als
  `deck_m` eintragen. Toda 2022 hat nur LoD1, Itabashi 2025 LoD2.
- Gebäude ohne PLATEAU (Ōtsu): OSM ist in Japan lückenhaft (Ōtsu 2074 Umrisse, GSI 13 145). `"buildings": {"type":
  "gsi"}` liest die GSI-Vektorkacheln `experimental_bvmap` z16 (Layer `building` aus 基盤地図情報; eigener MVT-Leser
  `geofetch.mvt_decode`, kein Zusatzpaket). Höhe aus `"footprint_defaults"`: `small` 6,5 m, `large` 8 m, `kinds`
  `gsi_sturdy` (堅ろう建物) 12 m, `gsi_highrise` (高層建物) 30 m, `shed` 3,5 m; Satteldach 28° bis 200 m²
  (`pitched_max_m2`, `pitch_deg`).
- Bäume: kein offenes DSM (Tokios Punktwolke 2024 mit ungeklärter Lizenz nicht verwendet). `"chm_from": "ortho"` erzeugt
  chm.tif aus dem Luftbild: grün und rau (Kronenschatten), Höhe aus dem Abstand zum Kronenrand (3–14 m). Uferbäume und
  die Kirschbäume des Sumida-Parks kommen gut; Gebüsch und Schilf am Ufer werden teils zu kleinen Bäumen.
- Brücken ohne DSM: `deck_m` aus PLATEAU-brid (Tokio) oder geschätzt (Toda, Ōtsu); Pfeiler aus dem Luftbild 0,4 m oder
  `spans_equal`. Hochstrassen (Shuto-Expressway) als lange `beam`-Brücken mit `axis_lv95` (Mittellinie beider
  Richtungsfahrbahnen aus OSM) und `piers_s` alle 40 m, ohne Stützen weiter als 12 m im Fluss.
- Speicher (Tokio): bake.py brach bei 2,3 GB ab (Licht für 19 Mio. Texel). `"bake_bands"` gröber, `"bake_terrain_step_m": 6`,
  `"bake_keep_tall_m": 150` (sonst zerfällt der Skytree beim Vereinfachen); Vorschau mit
  `ROWCOACH_PREVIEW_TEX_REDUCE=2`.
- Overpass wie Frankreich über den Spiegel maps.mail.ru mit IPv4.
- Namensnennung: „出典：国土地理院（地理院タイル／地理院地図Vector）“ (GSI-Nutzungsbedingungen, mit CC BY 4.0 vereinbar);
  „出典：国土交通省 3D都市モデル（Project PLATEAU）<Stadt>（<Jahr>年度）“; OSM; Copernicus.
Gebiete: `toda-regatta` (dataset:853), `tokyo-sumida` (dataset:854), `otsu-seta` (dataset:855).

## 11. Polen (GUGiK, ETRS89 / UTM 33/34 N)

Das Landessystem PL-1992 (EPSG:2180) ist kein UTM-System: die Gebiete rechnen in ETRS89 / UTM 34N (EPSG:25834; Kraków,
Warszawa) bzw. 33N (EPSG:25833; Poznań, westlich von 18° O); `geofetch.py` rechnet alles aus 2180 um. Die Flagge kommt
aus `"country": "PL"` (`Course.countryCode` leitet aus 25833 sonst Deutschland ab). Vorlage `areas/krakow-wisla.json`.
- Höhen: Quelle `wcs` mit `"crs": "EPSG:2180"`, `"axes": ["x", "y"]` (x = Ost, y = Nord). NMT als float32-TIFF über
  `…/PZGIK/NMT/GRID1/WCS/DigitalTerrainModelFormatTIFF` (Coverage `DTM_PL-KRON86-NH_TIFF`, 1 m; Umgebung mit
  `SCALEFACTOR` auf 4 m, `block_m` 4000). Das NMPT gibt es offen nur als Arc/Info-ASCII-Grid 0,5 m in einer
  Multipart-Antwort (`…/PZGIK/NMPT/GRID1/WCS/DigitalSurfaceModel`, Coverage `DSM_PL-KRON86-NH`, `"format":
  "image/x-aaigrid"`, `"native_res": 0.5` → SCALEFACTOR 0,5); `geofetch._wcs_payload` packt es aus und legt float32-GeoTIFF
  ab. Gut 1–2 min und 20 MB je km-Block, ein Kerngebiet von 15–30 km² braucht 45–90 min. Beide Modelle in PL-KRON86-NH
  (die EVRF2007-Fassungen liegen 0,1–0,2 m höher; gemischt nicht verwenden). Das NMT füllt Wasser mit einer
  interpolierten Fläche; prepare.py findet die Wasserhöhe zuverlässig (Kraków 198,9 m).
- Luftbild: `wms` `…/PZGIK/ORTO/WMS/HighResolution` (Layer `Raster`, 10 cm oder besser, als 20 cm geholt; MaxWidth 4096 →
  `"max_px": 4000`). Der Dienst verlangt in WMS 1.3.0 die EPSG-Achsfolge Nord, Ost: `"axis_order": "ne"` (sonst ein falsch
  gedrehter Ausschnitt). Umgebung `StandardResolution` mit `"res": 2` (bei kleinen Massstäben liefert HighResolution nichts).
  Aufnahmejahr je Blatt verschieden; neue Bauwerke (z. B. Bahnbrücken Kraków 2021) können im NMPT fehlen, obwohl sie im
  Luftbild stehen → `deck_m` setzen.
- Gebäude: BDOT10k je Powiat (`https://opendata.geoportal.gov.pl/bdot10k/schemat2021/GPKG/<woj>/<teryt>_GPKG.zip`, ~35 MB
  Kraków), Quelle `file` mit `zip_url`, `member` `OT_BUBD_A.gpkg`, `where` `{"KATEGORIAISTNIENIA": "eksploatowany"}`.
  Keine Höhenattribute ausser `LICZBAKONDYGNACJI`; diese bewusst nicht als `levels_field`, damit die Höhe aus NMPT − NMT
  kommt (Altbauten mit hohen Geschossen). Die 3D-Gebäudemodelle (LOD1/LOD2) des GUGiK sind nicht über einen festen
  Download-Pfad je Powiat erreichbar; nicht verwendet.
- Brücken: `deck_from: dsm` passt für Strassenbrücken; Fachwerk-/Bogenbrücken (Stahlbögen über dem Deck) mit `deck_m`.
- Namensnennung: „Źródło: Główny Urząd Geodezji i Kartografii (GUGiK, geoportal.gov.pl) – Ortofotomapa, NMT/NMPT,
  BDOT10k“; die Daten des państwowy zasób geodezyjny i kartograficzny sind seit 2020 frei und kostenlos (Art. 40a Abs. 2
  Nr. 1 Prawo geodezyjne i kartograficzne); OSM; Copernicus.
- Overpass: overpass-api.de und kumi gaben 502/504, overpass.private.coffee lieferte (`ROWCOACH_OVERPASS`, IPv4).
- Umgebungs-NMT: der WCS lieferte nachts nur noch ~80 kB/s (4 MB je km in 50 s); Warszawa und Poznań deshalb ohne
  `dtm_far`, mit `"alti_far": "dgm"` (Kern-NMT, Umgebung Copernicus GLO-30 – im flachen Land unauffällig).
- Pfeiler: In Warszawa trägt OSM die Strompfeiler als `bridge:support=pier` (Umrisse, im Luftbild bestätigt); diese
  Lagen als `piers_lv95` nehmen. Die Weichsel ist frei fliessend (Wasserhöhe aus dem NMT, Warszawa 78,3 m, 0,5 m Gefälle
  über die Strecke); Buhnenfelder am Ostufer verschieben die Wassermitte → Mittellinie über ±175 m glätten.
Gebiete: `krakow-wisla` (dataset:856, one_way, 3,9 km flussab, neun Brücken), `warszawa-wisla` (dataset:857, one_way,
5,1 km flussab, acht Brücken; Kładka Abakanowicz 2024 fehlt im NMPT → `deck_m`-Profil), `poznan-malta`
(dataset:858, EPSG:25833, 2000-m-Regattabahn hin und zurück, Start an den Pontons am Ostende).

## 12. Österreich (BEV, basemap.at; ETRS89 / UTM 33N)

Das Landessystem MGI / Austria Lambert (EPSG:31287) bzw. die Gauß-Krüger-Streifen sind keine UTM-Systeme: alle
österreichischen Gebiete rechnen in ETRS89 / UTM 33N (EPSG:25833; Wien, Linz und das Salzkammergut liegen östlich
von 12° O). Die Flagge kommt aus `"country": "AT"`. Vorlage `areas/wien-alte-donau.json`.
- Höhen: Quelle `cog` mit `"scheme": "bev_als"` und `"product": "DTM"`/`"DSM"` (`geofetch.bev_als_urls`): BEV
  ALS-Höhenraster 1 m, Stichtag 15.09.2025, als COG je 50 × 50 km in EPSG:3035 (LAEA) unter
  `data.bev.gv.at/download/ALS/<DTM|DSM>/20250915/ALS_<…>_CRS3035RES50000mN<N>E<E>.tif` (E/N = Südwestecke, 5–6 GB je
  Datei, aber mit Übersichten und 512er-Blöcken: `cog_read` holt nur die nötigen Blöcke; Kern 30 km² in 1–2 min).
  `dtm_far` mit `"res": 4` aus derselben Quelle (Übersichten). Höhen in Gebrauchshöhen Adria; DGM über Wasser
  interpoliert, prepare.py findet die Wasserhöhe zuverlässig (Alte Donau 156,2 m).
- Luftbild: basemap.at `bmaporthofoto30cm` als `xyz` (`…/basemap/bmaporthofoto30cm/normal/google3857/{z}/{y}/{x}.jpeg`,
  Achtung: Zeile vor Spalte) z19 mit `"res": 0.25` (0,2 m am Boden), Umgebung z16 `"res": 2`. Der Server
  (mapsneu.wien.gv.at) liefert 2–5 Kacheln/s und setzt gelegentlich die Verbindung zurück (Wiederholung greift):
  ≈ 2–4 min je km-Kachel, Wien (30 km²) ≈ 80 min.
- Gebäude: OSM-Umrisse mit Höhe aus DSM − DTM (`buildings_footprints.py`), in Wien vollständig. Stadt Wien
  Baukörpermodell/Orthofoto 15 cm und DORIS Oberösterreich nicht verwendet (wären CC BY 4.0).
- Overpass: Die Flächennutzungsabfrage über 20 km² Wien lief auf allen Spiegeln in 504/Zeitüberschreitung →
  `"osm_split": 3` (fetch_world.py holt `landcover.json` in 3 × 3 Teilen, je 4–8 Tsd. Objekte, in Minuten).
- Namensnennung (CC BY 4.0, siehe LIZENZEN-GEODATEN.md): „Datenquelle: BEV – Bundesamt für Eich- und
  Vermessungswesen, ALS-Höhenraster DTM/DSM 1 m (Stichtag 15.09.2025), CC BY 4.0, bearbeitet; Orthofoto: basemap.at,
  CC BY 4.0, bearbeitet“; OSM; Copernicus.
- Wehre: OSM führt die Donau am Kraftwerk Ottensheim-Wilhering als eine Fläche mit Ober- und Unterwasser (11,8 m
  Unterschied). `"water_cut_lv95"` (Polygon über Wehr und Schleuse, neu in prepare.py) trennt sie; das Oberwasser
  bleibt Gelände in seiner Höhe (Luftbildtextur), sonst läge es als Grube auf dem Spiegel des Regattabeckens und
  lanes.py legte eine Schiffslinie durch das Wehr.
Gebiete: `wien-alte-donau` (dataset:859, one_way 4,3 km nordwärts von der Unteren durch den Durchlass unter der
Wagramer Straße auf die Obere Alte Donau, zwei Brücken), `linz-ottensheim` (dataset:860, 2000 m hin und zurück im
Regattabecken, Start an den Startpontons), `gmunden-traunsee` (dataset:861, Rundkurs 4,6 km gegen den Uhrzeigersinn
vor Gmunden, am Seeschloss Ort vorbei; Traunstein in der Umgebung aus dem BEV-DTM 4 m).

## 13. USA (USGS 3DEP, MassGIS; NAD83 / UTM 19N)

Alle Gebiete in NAD83 / UTM der Zone (EPSG:26901–26923; Boston EPSG:26919); die Flagge kommt aus `"country": "US"`
(Course.countryCode leitet aus 269zz nichts ab). Vorlage `areas/boston-charles.json` (eine Szene, vier Strecken).
- Höhen: Quelle `cog` mit `"scheme": "usgs_1m"` und `"product": "<3DEP-Projekt>"` (`geofetch.usgs_1m_urls`):
  USGS 1-m-DEM als COG je 10 × 10 km unter `prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/1m/Projects/<projekt>/TIFF/
  USGS_1M_<zone>_x<E/10 km>y<⌈N/10 km⌉>_<projekt>.tif` (NAVD88 m, Übersichten bis 1:32; Kern 32 km² in Minuten).
  Welche Projekte ein Gebiet abdecken, sagt die TNM-API (`tnmaccess.nationalmap.gov/api/v1/products?datasets=Digital
  Elevation Model (DEM) 1 meter&bbox=…`); Boston: `MA_CentralEastern_2021_B21` (Lidar Frühjahr 2021, laubfrei).
  `dtm_far` mit `"res": 4` aus denselben Dateien. Das DEM ist hydrogeflacht: Wasserhöhe des Charles River Basin 0,01 m.
- Oberfläche: Die USGS hat kein fertiges DSM. Neuer Quellentyp `ept` (`geofetch.ept_dsm_tiles`, braucht laspy + lazrs im
  venv): die 3DEP-Punktwolke als Entwine Point Tiles (`s3-us-west-2.amazonaws.com/usgs-lidar-public/<projekt>/ept.json`,
  EPSG:3857, Höhen wie das DEM), Knoten bis `max_depth` 10 (≈ 5 Punkte/m², Boston 3855 Knoten, 168 Mio. Punkte,
  ≈ 1,2 GB LAZ, ≈ 2 h bei einer Verbindung), höchster Punkt je 1-m-Zelle ohne Rauschklassen 7/18, Lücken bis 2 m aus der
  Nachbarschaft, Rest (Wasser) aus dem DEM. DSM − DEM auf freiem Boden ≈ 0,0–0,2 m (gleicher Höhenbezug).
- Luftbild: MassGIS-Kacheldienst `orthos2023` (ArcGIS Online, `…/MapServer/tile/{z}/{y}/{x}`, Zeile vor Spalte) als `xyz`
  z19 mit `"res": 0.25`, Umgebung z16 `"res": 2`; 15 cm, Frühjahr (laubfrei: Bäume grau-braun, Rasen fahl).
- Gebäude: OSM-Umrisse (Boston/Cambridge vollständig, 26 354) mit Höhe aus DSM − DEM. Cambridge GIS/BPDA-3D nicht
  verwendet (Lizenz nicht eindeutig).
- Overpass: maps.mail.ru zuerst (`ROWCOACH_OVERPASS`), `"osm_split": 3`.
- Brücken: Deck aus dem DSM (`deck_from: dsm`). Pfeiler der Bogenbrücken liegen im Luftbild unter dem Deck → drei Felder
  mit 40 m Mittelfeld (`spans_m`), bei schräg kreuzenden Brücken 48–52 m, sonst passen Hin- und Rückfahrt nicht durch.
  Die Grand-Junction-Bahnbrücke unter der BU Bridge hat Pfeiler (OSM bridge:support) nur 16 m quer zur Fahrt auseinander:
  neues `"route_shift": false` (bridges.py) nimmt ihre und die BU-Pfeiler aus der Streckenverschiebung; die HOCR-Linie
  ist dort von Hand mittig durch das Feld gelegt (Hindernisabstand 4 m).
- Namensnennung: „Höhen: U.S. Geological Survey, 3D Elevation Program (3DEP) – 1-m-DEM und Lidar-Punktwolke …
  (gemeinfrei/public domain), bearbeitet; Orthofoto: MassGIS (Bureau of Geographic Information), Commonwealth of
  Massachusetts, Luftbild Frühjahr 2023, bearbeitet“; OSM; Copernicus (nur Lücken).
Gebiete: `boston-charles` (dataset:865) mit `boston-hocr` (one_way 4,82 km flussauf von der BU-Bootshalle bis Christian
Herter Park, sieben Brücken), `boston-basin` (one_way 2,93 km von der Longfellow Bridge westwärts unter der Harvard
Bridge bis vor die BU Bridge), `boston-harvard` (Newell/Weld Boathouse ↔ Magazine Beach, 2 × 2,23 km, vier Brücken),
`boston-upper` (Community Rowing ↔ Eliot Bridge, 2 × 3,38 km, zwei Brücken). Stadt überall „Boston“: eine Szene,
die Streckenauswahl gruppiert nach Stadt, und der Charles ist die Grenze zwischen Boston und Cambridge.

## 14. Grossbritannien: London, Henley, Durham (EA LIDAR, synthetisches Luftbild; ETRS89 / UTM 30N)

Alle drei wie Oxford (Vorlage `areas/oxford-isis.json`): EA LIDAR Composite DTM/DSM 1 m über WCS (aus 27700 mit OSTN15),
Umgebung Copernicus GLO-30, synthetisches Luftbild aus Sentinel-2 + OSM, Gebäude aus OSM-Umrissen mit Höhe aus DSM − DTM,
Bäume aus DSM − DTM, `wall_palette` wie Oxford. EPSG:25830 (auch London bei 0,2° W liegt in Zone 30).
- Abruf: Der EA-WCS gab während des Abrufs immer wieder HTTP 429, die Wiederholungen in `geofetch.http` reichen
  (Henley 16, Durham 12, London 35 km-Blöcke je Modell; London ~25 min je Modell). Overpass war gestört (502/504 auf
  allen Spiegeln, overpass-api.de antwortet curl mit 406); maps.mail.ru mit `ROWCOACH_IPV4=1` lieferte nach mehreren
  Versuchen. Bewährt: `fetch_world.py … --skip-osm` für die EA-Daten und OSM getrennt (gleichzeitig, anderer Server).
- `henley-regatta` (dataset:862): Henley Royal Regatta Course, one_way 2118 m flussauf von der Spitze von Temple Island bis
  100 m vor der Henley Bridge (Ziel an Phyllis Court), eine Haltung zwischen Hambleden und Marsh Lock (30,6 m ODN aus dem
  DTM). Henley Bridge (fünf Steinbögen, Pfeiler gleichmässig geschätzt) hinter dem Ziel. Booms nicht modelliert.
- `durham-wear` (dataset:863): one_way ~2,6 km flussab vom Racecourse (oberhalb der Kingfisher Bridge) um die Halbinsel
  bis 75 m hinter die Prebends Bridge, ~100 m vor dem Wehr an der Old Fulling Mill. `water_cut_lv95` über dem Wehr trennt
  das Unterwasser ab (OSM führt beides als eine Fläche). Fluss 26–56 m breit, deshalb Einweg. Elvet Bridge: Pfeiler aus
  OSM `bridge:support` (Vorköpfe ober- und unterstrom gemittelt, ~12 m Raster, Öffnungen ~9,5 m); die Strecke führt durch
  den zweiten Bogen von Osten. Dafür neu in routes.py `"pier_check_back": false` und `pier_edge_min_m`/`pier_center_min_m`
  (one_way, enge Bögen). Sechs Brücken (Kingfisher, Baths, New Elvet, Elvet, Kingsgate, Prebends).
- `london-putney-chiswick` (dataset:864): Championship Course one_way 6,9 km flussauf vom Start 150 m oberhalb der Putney
  Bridge bis 110 m hinter die Chiswick Bridge (die Entscheidung nannte ~3,9 km; mit Barnes Railway Bridge und Chiswick
  Bridge sind es fast die ganzen 6,8 km des Boat Race). Tidenfluss: `"water_level_m": 1.0` (ODN, etwa mittleres Wasser
  bei Putney; Ebbe −1,5, Flut +3,5 m); das OSM-Ufer ist die Hochwasserlinie, die Szene zeigt also eher Flut. Putney Bridge
  (Pfeiler aus OSM), Hammersmith Bridge als neue Brückenart `"suspension"` in bridges.py (Türme auf den Pfeilern, Ketten
  als Parabel, Hänger alle 4 m; Mittelfeld 129,7 m), Barnes Railway Bridge (Balken mit Fachwerkmuster, Bögen über dem
  Deck nicht modelliert), Chiswick Bridge (drei Bögen, Mittelfeld 45,7 m). `"osm_split": 3` für die Flächennutzung.

## 15. Südamerika: Rio de Janeiro und Tigre (Copernicus, synthetisches Luftbild; SIRGAS 2000 / UTM 23S und 21S)

Beide Gebiete haben kein offenes Höhenmodell feiner als Copernicus GLO-30 und kein offenes Luftbild: Höhen aus
Copernicus GLO-30 als `"dtm": {"type": "cog", "urls": [<Copernicus-Kachel>]}` (auf 1 m interpoliert, Kern und
Umgebung `"alti_far": "dgm"`), kein Oberflächenmodell, Luftbild synthetisch aus Sentinel-2 + OSM (`synth_ortho.py`).
SIRGAS 2000 ist der amtliche Bezugsrahmen in ganz Südamerika (POSGAR 2007 in Argentinien ist eine Verdichtung davon),
deshalb auch Tigre in SIRGAS 2000 / UTM 21S (EPSG:31981); die App kennt 31977–31985. Flagge aus `"country"`.
- Copernicus misst Dächer und Kronen mit (Oberflächenmodell): in Rio liegt es im Median 13 m über den Grundhöhen der
  Gebäude, in Tigre stehen Inseln und Stadt als 5–15 m hohe Buckel. Zwei neue Optionen in prepare.py:
  `"dem_ground_points"` (Rio) breitet die Grundhöhen der Gebäudeumrisse (Feld `BASE` der IPP-Umrisse, über
  `keep_fields` in footprints.geojson) mit einem Gauss (40 m) zu einer Geländefläche aus und senkt das Höhenmodell dort
  darauf ab, gewichtet nach der Gebäudedichte (danach Median 0,1 m statt 13 m Unterschied); im Wasser und fern der
  Gebäude bleibt Copernicus. `"dem_flatten"` (Tigre, flaches Delta) öffnet das Höhenmodell grau (Radius 100 m) und
  begrenzt es auf 4,5 m.
- Bäume: kein Oberflächenmodell, und im synthetischen Luftbild ist der Wald eine glatte Textur (`chm_from: ortho`
  fand in Rio nur 9 ha Kronen). Neu `"chm_osm_wood": true` (geofetch.chm_from_ortho): OSM-Wald (natural=wood,
  landuse=forest) bekommt ein synthetisches Kronendach 7–18 m, Gebüsch 2–4 m, mit Lücken und Rauschen, aus dem trees.py
  einzelne Kronen macht (Rio: Mata Atlântica an Catacumba, Cabritos und Corcovado; Tigre: Deltainseln).
- Gebäude Rio: IPP „Edificações (2013)“ (ArcGIS-Item 124f1607b57d4292af5c0dfc2ff8572c, Instituto Pereira Passos,
  Lizenz im Item CC BY 4.0; FeatureServer `services5.arcgis.com/mgrvZxGU0bSJbVld/…/Quadras_Lotes_Edificacoes/
  FeatureServer/0`): Restitution 1 : 2000 aus Bildern 2013 mit `ALTURA`, `BASE`, `TOPO` je Umriss; Turmteile sind
  eigene Umrisse (`PROJECAO_1…6`) mit Höhe ab Grund. Übernommen `Tipo` EDIFICACAO, PROJECAO_1–6, CONSTRUCAO, GALPAO,
  CASA_DE_MAQUINA (ohne Vordächer, Ruinen, Fundamente). Das IPP-Luftbild (Mosaico 2019, „Uso público, citadas as
  fontes e mantidas as informações originais“) verbietet Veränderungen → nicht verwendet.
- Gebäude Tigre: OSM hat im Kern nur 1965 Umrisse. Neu `"supplement": {"type": "msbuildings", "urls": [...]}` in
  fetch_world.py ergänzt Microsoft Global ML Building Footprints (CDLA Permissive 2.0, Quadkey-Datei aus `dataset-links.csv`, hier
  Argentina 210321300, 169 MB) überall, wo kein OSM-Umriss liegt (+5361); ohne Höhen → `footprint_defaults` 5 / 7,5 m.
- Wasser: Rio Lagune 1,0 m (Copernicus, EGM2008); Tigre fest `"water_level_m": 0.9` (Copernicus über dem Fluss
  0,3–1,8 m). Das Meer südlich von Ipanema kommt aus den OSM-Küstenlinien (`common.osm_sea`, Abfrage
  `natural=coastline` in fetch.py) und liegt auf Lagunenhöhe.
- Namensnennung: Copernicus-DEM-Wortlaut (Art. 6 b) und Sentinel-2; Rio „Instituto Pereira Passos (IPP), Prefeitura da
  Cidade do Rio de Janeiro – Edificações (2013), CC BY 4.0, bearbeitet“; Tigre „Microsoft Global ML Building
  Footprints (CDLA Permissive 2.0)“; OSM mit openstreetmap.org/copyright.
Gebiete: `tigre-lujan` (dataset:866; hin und zurück 2 × 2650 m flussab auf dem Río Luján von der Mündung des Río
Reconquista am Paseo Victorica vorbei bis gut 400 m hinter die Mündung des Río Sarmiento, Fluss 63–140 m, Hinweg 8 m
rechts der Mitte, Mittellinie aus dem OSM-Wasser; lanes.py findet eine geschlossene Bahn mit den engen Abständen;
25 MB, 0,60 Mio. Dreiecke), `rio-lagoa` (dataset:867; Rundkurs 5355 m gegen den Uhrzeigersinn vom Ruderstadion am
Westufer, Uferabstand ≥ 57 m; Kern nach Norden bis über den Corcovado erweitert, damit der Gipfel im 1-m-Gelände liegt
– die Bauten am Gipfel kommen aus den IPP-Umrissen, die Christusstatue selbst ist nicht modelliert; der Zuckerhut liegt
in der Umgebung, ist von der Lagune aus aber hinter den Hügeln von Botafogo/Copacabana verdeckt (Sichtlinie im
Höhenmodell geprüft); 71 MB, 1,15 Mio. Dreiecke).

## 16. Norwegen: Oslo und Fjorde (Kartverket, synthetisches Luftbild; ETRS89 / UTM 32N)

Kartverket liefert alle Höhendaten landesweit in EPSG:25833; die Gebiete rechnen trotzdem in der Zone ihres Orts
(Oslo und Gudvangen: ETRS89 / UTM 32N, EPSG:25832), `geofetch.py` rechnet um. Flagge aus `"country": "NO"`. Vorlage
`areas/oslo-frognerkilen.json`.
- Höhen: Quelle `cog` mit `"scheme": "kartverket"` und `"product": "DTM1"`/`"DOM1"` (`geofetch.kartverket_urls`): COG je
  15 × 15 km (10 m Überlappung) unter `nedlasting.geonorge.no/hoydedata/<DTM1|DOM1>/33-<X>-<Y>.tif`, 0,7–1,1 GB je Datei,
  aber mit Übersichten bis 1:64 und 512er-Blöcken – Kern (15–19 km²) und Umgebung (`dtm_far` `"res": 4`, Fjord 22 × 22 km)
  in wenigen Minuten. NN2000, über dem Meer 0 m. Lizenz CC BY 4.0 („© Kartverket“, LIZENZEN-GEODATEN.md).
- Meer: OSM führt das Meer nicht als `natural=water`, sondern nur als Küstenlinie. Neu `common.osm_sea` (Küstenlinien
  zusammenfügen, mit dem um 500 m verkleinerten Umgebungsrahmen in Flächen zerlegen, je Fläche Markierungen rechts =
  Meer / links = Land der Wegrichtung zählen) und `natural=coastline` in der Abfrage von fetch.py; osm_water nimmt das Meer
  dazu (prepare.py, synth_ortho.py, routes.py, lanes.py). Für vorhandene Gebiete: Küstenlinien nachladen und an
  overpass.json anhängen. Feste Wasserhöhe `"water_level_m": 0.0`.
- Luftbild: Norge i bilder (Geovekst) ist nicht offen → synthetisch wie Grossbritannien. Sentinel-2 im Fjord: Juni hat
  Schnee bis weit herab, August tiefe Schatten an den Nordwestwänden → `"months": [7]` (Szene 11.07.2025; Schneefelder
  nur auf der Hochfläche). Oslo: 17.08.2025, einzelne Wolkenreste über dem Wasser (dort zeichnet die App ihr Wasser).
- Gebäude: OSM-Umrisse mit Höhe aus DOM1 − DTM1 (Oslo 7774, Gudvangen wenige Dutzend). FKB-Bygning ist Geovekst
  (nicht offen). Das Opernhaus wird ein flacher Block (schräges Dach nicht modelliert).
- Fjord-Gelände: die steilen Wände ergaben mit den Standardfehlern 1,7 Mio. Dreiecke im Kern. Neue Gebietsfelder in
  export.py: `"terrain_err_scale": 2.5` (erlaubter Höhenfehler je Band × 2,5) und `"far_step_m": 70` (Umgebungsgitter
  statt 100 m; dazu `"far_tex": 3072`); danach 0,65 Mio. Dreiecke Gelände. Auf fast senkrechten Wänden zieht die
  Luftbildtextur senkrechte Streifen (Projektion von oben). `"summer_grade": false` (sonst neongrüne Wiesen).
- Gebiete: `oslo-frognerkilen` (dataset:868, one_way 3,54 km vom Ausgang von Frognerkilen vor den Marinas, gegenüber
  Norske Studenters Roklub auf Bygdøy, vor Filipstad, Tjuvholmen, Aker Brygge und dem Rathaus über die Pipervika, um
  Vippetangen unter der Festung Akershus und nordwärts in die Bjørvika bis vor das Opernhaus; Frognerkilen selbst ist
  voller Stege, deshalb Start am Ausgang), `naeroyfjord-gudvangen` (dataset:869, 2 × 2,61 km hin und zurück auf der
  Fjordmitte vom Fähranleger Gudvangen nordostwärts bis vor Bakka; Fähren Gudvangen–Flåm/Kaupanger als Verkehr).
- Weitere Fjorde (27.11., Vorlage Nærøyfjord, alle EPSG:25832, Wasser 0 m, Umgebung 22 × 22 km DTM1 auf 4 m,
  Sentinel-2 Juli 2025, Stufen standard und hoch, im Bundle nur standard):
  `geirangerfjord` (dataset:872, 2 × 3,70 km von Geiranger nordwestwärts um die Biegung bei Homlung und westwärts bis
  ~2,4 km vor die Sieben Schwestern – bis zu den Wasserfällen wären es 5,6 km Einweg, die Brautschleier liegen noch
  weiter westlich), `lysefjord-preikestolen` (dataset:873, 2 × 3,09 km auf der Fjordmitte unter dem Preikestolen,
  Fjord ~1,1 km breit; Forsand liegt 10 km fjordauswärts, deshalb Start mitten im Fjord, Stadtname Forsand),
  `aurlandsfjord-flaam` (dataset:874, 2 × 2,84 km von Flåm nordnordostwärts bis etwa Kvitt) und `hjorundfjord`
  (dataset:875, 2 × 3,18 km im Norangsfjord, dem inneren Arm des Hjørundfjords, von Øye bis vor die Einmündung bei
  Urke; Kerngebiet bis über den Slogen, 1564 m). Planung der Fjordmitte vor dem Abruf aus Copernicus GLO-30 (Meer
  < 1,5 m) bzw. OSM-Küstenlinie, Kontrolle am DTM1 (Meer = 0 m).
- Steile Wände, zwei neue Gebietsfelder (nur mit dem Feld aktiv): `"steep_rock": {"slope_deg": [48, 66], "color":
  [r, g, b], "strength": 0.92}` in export.py überblendet die Luftbildtextur auf Flächen steiler als 48–66° zu einer
  Felsfarbe, deren Muster von der Höhe abhängt (waagrechte Schichtung) und deren Helligkeit nur grossräumig aus dem
  Luftbild kommt (weichgezeichnet, sonst kehren die Streifen über die Helligkeit zurück); gilt für Kern- und
  Umgebungstextur. Lysefjord mit hellerem Granitton [136, 132, 124], sonst [118, 116, 110]. `"tree_max_slope_deg": 58`
  in trees.py entfernt Bäume, wo das Gelände (5 m geglättet) steiler ist: DOM1 − DTM1 ergibt an fast senkrechten Wänden
  Scheinkronen von Dutzenden Metern, die als dunkle Säulen an der Wand hingen (7–20 % der erkannten Bäume).
  Nærøyfjord ohne die Felder (unverändert).
- `far_step_m`/`far_tex` je Stufe: standard 70 m / 3072 px, hoch 45 m / 4096 px.

## 17. Island: Þingvellir und Reykjavík (ÍslandsDEM, synthetisches Luftbild; WGS84 / UTM 27N)

ETRS89 / UTM 27N gibt es im EPSG-Register nicht (25828 ist die westlichste Zone), Islands amtliches ISN2016 rechnet in
Lambert (EPSG:8088), das die App nicht kennt → WGS84 / UTM 27N (EPSG:32627; Unterschied zu ISN2016 im Dezimeterbereich,
für eine Ruderszene ohne Belang). Flagge aus `"country": "IS"`. Vorlage `areas/thingvellir-thingvallavatn.json`.
- Höhen: ÍslandsDEM v1.0 als eine landesweite GeoTIFF-Datei 10 m (`ftp.natt.is/gisdata/raster/IslandsDEMv1.0_10x10m_
  isn2016_zmasl.tif`, 3 GB, 512er-Blöcke, zstd, ohne Übersichten) über die Quelle `cog` mit `"urls"` – `cog_read` liest
  nur die nötigen Blöcke (Kern in Sekunden, Umgebung 28 × 39 km mit `"res": 5` in wenigen Minuten). Höhen ISN2016 über
  dem Meer; Seen geglättet (Þingvallavatn 99,5 m). Ein 2-m-Modell gibt es nur als Kartendienst. Kein offenes
  Oberflächenmodell → keine Bäume aus der Vegetationshöhe, Gebäude mit `footprint_defaults`.
- Luftbild synthetisch (Sentinel-2 Juli). Neu `"synth_natural"` in synth_ortho.py: ersetzt die Klasse für `natural=…`;
  um Þingvellir ist das ganze Lavafeld (64,13–64,31° N) eine OSM-Fläche `natural=bare_rock`, in Wirklichkeit Moos und
  Birkengebüsch → `{"bare_rock": "unbekannt"}` (Sentinel-Farbe statt Asphaltgrau).
- Bäume: `chm_osm_wood` mit den wenigen OSM-Waldflächen (Birken, Fichten bei Þingvellir), ~30 Bäume.
- Stufen: alle Strecken in `standard` und `hoch` (Bundle nur `standard`, `app_qualities`). `"terrain_err_scale"` gilt
  jetzt auch je Stufe (`{"standard": 1.0, "hoch": 2.0}`, export.py): das 10-m-Modell gibt für „hoch“ keine feineren
  Einzelheiten her.
- Gebiete: `thingvellir-thingvallavatn` (dataset:870; hin und zurück 2 × 2,61 km von der Bucht vor Þingvellir (Mündung
  der Öxará, Lavaklippen) nach Süden auf den offenen See, Uferabstand ≥ 366 m; Umgebung nach Norden bis über die
  Botnssúlur und Ármannsfell, nach Süden bis zum Hengill; standard 0,24 Mio. Dreiecke/6 MB, hoch 0,48 Mio./15 MB mit
  `"far_step_m": {"hoch": 70}` – das Umgebungsgitter 28 × 39 km macht in „hoch“ (50 m) sonst 0,9 Mio. Dreiecke).
  `reykjavik-fossvogur` (dataset:871; hin und zurück 2 × 2,88 km von der Mündung des Fossvogur vor der Nauthólsvík
  nordwestwärts in den Skerjafjörður und vor der Ægisíða nach Norden, Uferabstand ≥ 140 m; Meer aus OSM-Küstenlinien,
  Wasser 0 m, Tidenhub ~4 m nicht modelliert. Der innere Fossvogur bleibt aussen vor: die Fossvogsbrú (Bus, Rad, Fuss)
  ist im Bau, Eröffnung 2028 (OSM `highway=construction`); routes.py meldete sie als drei Brückenquerungen. 7015 Gebäude
  aus OSM (1158 mit Geschossen, sonst `footprint_defaults` 6/9 m); standard 0,33 Mio. Dreiecke/15 MB, hoch 0,79 Mio./31 MB).

## 18. Kanada: St. Catharines, Vancouver, Victoria (NRCan HRDEM, synthetisches Luftbild; NAD83 / UTM 17N und 10N)

NAD83 / UTM der Zone (EPSG:269zz wie USA; NAD83(CSRS) kennt die App nicht, Unterschied ~1–2 m), Flagge aus
`"country": "CA"`. Vorlage `areas/stcatharines-martindale.json`.
- Höhen: NRCan HRDEM Mosaic 1 m (CanElevation) als Quelle `cog` mit `"urls"` auf die Mosaikkachel
  (`canelevation-dem.s3.ca-central-1.amazonaws.com/hrdem-mosaic-1m/<kachel>-mosaic-1m-dtm.tif` bzw. `-dsm.tif`; EPSG:3979,
  500 × 500 km, Übersichten bis 1:32, 512er-Blöcke – Kern und Umgebung in Minuten). Welche Kachel ein Ort braucht, sagt
  der STAC-Katalog: `datacube.services.geo.ca/stac/api/search?collections=hrdem-mosaic-1m&bbox=…` (Martindale 8_2,
  Vancouver 2_3, Victoria 1_3). Keine Daten über grossen Seen und in Alberta-Bergen (Lake Louise: nur MRDEM-30).
- Luftbild synthetisch (Sentinel-2 Juni/Juli), Gebäude OSM-Umrisse mit Höhe aus DSM − DTM, Bäume aus DSM − DTM.
- Wasser: eine Wasserhöhe je Szene. Der Martindale Pond liegt 78,4 m hoch (aufgestaut), der Ontariosee 74,3 m: der
  Ontariosee im Norden des Kerngebiets bleibt deshalb Gelände (Sentinel-Farbe), vom Boot aus hinter Häusern und Bäumen.
- Strecke aus OSM: die Regattastrecke ist als `waterway=fairway`, `sport=rowing` „St. Catharines 2K Course“ (Weg
  256790215) eingetragen, der Startsteg als `man_made=pier` – `via_lv95` folgt ihr, `"avoid": false`.
- Gebiete: `stcatharines-martindale` (dataset:876) mit `stcatharines-henley` (one_way 2,00 km nach Norden vom Startsteg am
  Südende an Henley Island vorbei bis ins Ziel vor Port Dalhousie; lanes.py findet offene Ruderer-Linien und eine
  Fahrrinne; standard 0,37 Mio. Dreiecke/17 MB, davon 0,16 Mio. Bäume; hoch 0,85 Mio./38 MB).
  `vancouver-coal-harbour` (dataset:877; hin und zurück 2 × 1,45 km von Coal Harbour östlich der Marinas südlich an
  Deadman's Island vorbei und am Stanley Park entlang bis 280 m vor Brockton Point; Meer aus OSM-Küstenlinien, Wasser 0 m,
  Tidenhub ~4 m nicht modelliert; Hochhäuser von Downtown aus DSM − DTM; die North Shore Mountains liegen ausserhalb der
  Lidar-Abdeckung und kommen aus Copernicus; standard 0,29 Mio. Dreiecke/11 MB, hoch 0,91 Mio./32 MB).
  `victoria-elk-lake` (dataset:878; Rundkurs 3,28 km gegen den Uhrzeigersinn vom Elk Lake Rowing Centre (Victoria City
  Rowing Club) am Südostufer, Uferabstand ≥ 89 m; Seespiegel 60,3 m; dichter Wald aus DSM − DTM; standard 0,41 Mio.
  Dreiecke/17 MB, hoch 1,0 Mio./41 MB). Die Regattastrecke auf dem Elk Lake (1850 m, sechs Bahnen) ist nicht in OSM
  eingetragen; deshalb die Runde.

## 19. Sightseeing-Touren und Wahrzeichen (`landmarks.py`)

Falk (27.11.2026): Strecken mit richtig coolen Sehenswürdigkeiten, beide Stufen `standard` und `hoch` (Bundle nur
`standard`). Höhenmodelle liefern Wahrzeichen nur als Klotz; deshalb baut `landmarks.py` die zentralen Wahrzeichen als
vereinfachte, klar erkennbare prozedurale Modelle (Typen, Parameter und Ablauf in BUILD.md, Abschnitt „Wahrzeichen“).
- Lage und Ausrichtung aus OSM-Umrissen (Schwerpunkt, Hauptachse des kleinsten umschliessenden Rechtecks), Masse aus
  der Literatur (Wikipedia, Betreiber); je Eintrag `source` in der Gebietsdatei und in `build/<id>/landmarks/meta.json`.
- Freistellung: Grundrisse zu ≥ 30 % in der Freistellfläche und Bäume darin fallen weg (sonst stünde der Klotz aus
  Grundriss/Oberflächenmodell bzw. eine Scheinkrone aus DSM − DTM im Modell).
- Schnelltest eines Typs ohne Gebiet: `LB()` und Typfunktion aufrufen, Arrays mit pyrender aus mehreren Richtungen
  rendern (Materialfarben statt Atlas); so sind Eiffelturm, Notre-Dame, Big Ben, London Eye, Tower Bridge, Rialto,
  Accademia und Salute entstanden.
- Neue Gebietsfelder dafür: `landmarks`, `buildings_max_route_m` (dichte Städte), `dem_fill_nearest` (AHN),
  `preview_views` (App-Vorschaubilder mit den Wahrzeichen voraus). Nahe Vorbeifahrt: Wahrzeichen stehen an Land und
  halten keine Abstände ein; auf dem Wasser genügen die vorhandenen Felder (`obstacle_dist_m`, `pier_check_back`,
  `pier_edge_min_m`/`pier_center_min_m`).

## 20. Paris: Seine vom Eiffelturm bis Notre-Dame (IGN; ETRS89 / UTM 31N)

`paris-seine` (dataset:879): one_way 5,82 km flussauf, Start im Südarm an der Île aux Cygnes (Eiffelturm voraus), unter
16 Brücken hindurch (Bir-Hakeim, Iéna, Debilly, Alma, Invalides, Alexandre III, Concorde, Senghor, Royal, Carrousel,
Arts, Pont Neuf, Saint-Michel, Petit-Pont, au Double, Archevêché), nach dem Pont des Arts südlich um die Spitze der Île
de la Cité in den Petit Bras und an der Südseite von Notre-Dame entlang. Quellen wie Lyon (Abschnitt 9). Seine 26,9 m
NGF aus LiDAR HD; Brückendecks aus dem MNS, Pfeiler gleichmässig geschätzt (OSM hat hier keine `bridge:support`).
Im Petit Bras stehen die Pfeiler eng: `pier_check_back: false`, `pier_edge_min_m` 3, `pier_center_min_m` 5.
- Wahrzeichen: Eiffelturm (OSM way 5013364, Achse 44,8°), Notre-Dame (OSM way 201611261, Fassade nach 297°), vier
  vergoldete Pylone des Pont Alexandre III. Im BD ORTHO ist Notre-Dame verpixelt; das Modell deckt die Stelle ab.
- Dichte: 25 000 BD-TOPO-Gebäude gaben in `standard` 1,4 Mio. Dreiecke; mit `buildings_max_route_m` 650,
  `trees_budget` 170 000/380 000 und `terrain_err_scale` 1,5/1,2: standard 0,78 Mio. Dreiecke/57 MB, hoch 1,61 Mio./122 MB.
- Mit `preview_views` [40, 2500, 5200, 5350]: Eiffelturm am Start, Pont Alexandre III, Notre-Dame zweimal.
- 28.11.: Kerngebiet nach Westen bis E 446,9 km erweitert. Der Start lag 117 m vom Kernrand; dort überlappt das grobe
  Umgebungsgitter (100 m, hoch 50 m) das Kerngebiet, und ein Dreieck zwischen Île aux Cygnes und Ufer lag als schräge
  Platte über dem Südarm (Mac-Test: Boot bis zum Oberkörper darin). Regel: Strecke ≥ 2 × far_step_m vom Kernrand.
  Jetzt standard 0,82 Mio. Dreiecke/59 MB, hoch 1,70 Mio./127 MB.

## 21. London: Themse von Westminster bis Tower Bridge (EA LIDAR, synthetisches Luftbild; ETRS89 / UTM 30N)

`london-westminster-tower` (dataset:883): one_way 4,56 km flussab vom Victoria Tower (Start 300 m oberhalb der
Westminster Bridge) bis 150 m hinter die Tower Bridge, 25 m links der Flussmitte (Parlament näher), vor London Bridge
weich auf die Mitte geführt, damit die Strecke mittig durch das 61-m-Klappfeld der Tower Bridge führt. Quellen und
Verfahren wie Putney–Chiswick (Abschnitt 14), feste Wasserhöhe 1,0 m ODN, `buildings_max_route_m` 750. Zehn Brücken:
Westminster (sieben grüne Bögen, Achse aus OSM-Wegen, OSM hat dort keinen Brückenumriss), Hungerford/Golden Jubilee
(Fachwerk, Pylone der Stege nicht modelliert), Waterloo, Blackfriars (rot), Blackfriars Railway (Solardach nicht
modelliert), Millennium, Southwark, Cannon Street, London Bridge (Pfeiler aus OSM `bridge:support`) und Tower Bridge
(Deck 12 m über der Szenenwasserhöhe, Pfeiler aus den OSM-Turmumrissen 21 × 57 m).
- Wahrzeichen: Elizabeth Tower (Big Ben, Zifferblätter), Victoria Tower, Central Tower, Parlamentsfront als
  `gothic_block` aus OSM relation 1567699 (Innenhöfe überdeckt, von der Themse aus nicht sichtbar), London Eye (Radebene
  aus OSM way 204068874, A-Stütze nach Osten, Fuss 3 m über Wasser), St Paul's Cathedral (Kuppel 110 m, auf 15,8 m
  Grund), Tower Bridge (Türme, Fusswege, Ketten).
- standard 0,59 Mio. Dreiecke/40 MB, hoch 1,08 Mio./75 MB; `preview_views` [30, 250, 3800, 4300].

## 22. Amazonas: Encontro das Águas, Anavilhanas, Iquitos (Copernicus, Meta/WRI-Kronenhöhe, synthetisches Luftbild; SIRGAS 2000 / UTM 21S, 20S, 18S)

Vorgaben von Falk: docs/amazonas/SPEC.md (dort auch „Umsetzung“). Neue Bausteine in `amazonas.py` (Docstring), alle nur mit
ihrem Gebietsfeld aktiv; andere Gebiete bleiben unverändert. Vorlage `areas/anavilhanas.json`.
- CRS: SIRGAS 2000 / UTM der Zone (Encontro 21S/31981 – der Zusammenfluss liegt bei −59,9° knapp östlich der Zonengrenze
  −60°; Anavilhanas 20S/31980; Iquitos 18S/31978, auch in Peru ist SIRGAS amtlich). Flagge aus `"country"` (BR, PE).
- Höhen Copernicus GLO-30 (über Wasser 11 m Manaus, 13 m Anavilhanas, 79 m Iquitos, EGM2008). Wasserstand fest
  (`water_level_m`): Encontro 11,0, Anavilhanas 13,0 (Hochwasser über `flood_lv95`), Iquitos 84,0 (≈ 5 m über dem
  Copernicus-Wasser: die Várzea vor der Stadtterrasse steht unter Wasser, Belén Bajo auf Pfählen im Wasser).
- `flood_lv95` (common.osm_water): überflutete Flächen zählen als Wasser (Anavilhanas: 230–260 m um die Strecken,
  Iquitos: die Várzea vor der Stadtkante). Copernicus misst über dem Regenwald die Kronen: `canopy_ground` (amazonas.py dem,
  nach prepare.py) legt Land nahe der Strecke auf Waldboden und lässt es dahinter weich auf die Copernicus-Fläche ansteigen,
  die als grünes Kronendach den fernen Wald darstellt (Impostor). Iquitos (Stadt): `dem_flatten` (Öffnung 80 m).
- Wald `synth_forest` (trees.py ruft amazonas.forest): Meta/WRI High Resolution Canopy Height Maps (S3
  `dataforgood-fb-data/forests/v1/alsgedi_global_v6_float/chm/<quadkey>.tif`, Quadkey Stufe 9, EPSG:3857, uint8 m, 1,2 m;
  /vsicurl liest nur den Kernausschnitt in Sekunden; CC BY 4.0, Bildquelle Maxar 2016, LIZENZEN-GEODATEN.md). Stämme als
  Poisson-Scheibe (6,5 m im Wasser, keine Gitterreihen), Höhe aus der Kronenhöhe, 2,5 % Urwaldriesen 30–44 m mit
  Schirmkrone, Unterholz mit tiefen Kronen in den Lücken, im Wasser schiefere Stämme mit dunklem Wasserrand (eigener
  Texel), überfluteter Saum bis 8 m vor dem Waldrand. Korridor nur 3 m um die Stämme; Kronen dürfen über die Bahn ragen.
  Formen: voll bis `full_m`, einfach bis `far_from_m`, dahinter die neue Form `far` (16 Dreiecke). Kein Instancing: die
  Pipeline fasst wie immer je km-Zelle ein Mesh mit einem Atlas zusammen (wenige Draw Calls), die LOD-Formen halten das
  Budget (`trees_budget`).
- Pfahlbauten `palafitas` (amazonas.py palafitas, nach buildings_footprints.py): OSM-Grundrisse 12–240 m² in der Zone bzw.
  bis 25 m vom Wasser werden aus den Gebäuden genommen und prozedural gebaut: Boden 1,5–2,5 m über dem Wasser auf Pfählen
  (unten nass und dunkel), Veranda mit Geländer, Bretterwände in bunten Farben mit Tür, Fenstern und Rahmen, Wellblech-
  Satteldach mit Rost oder Palmdach, Stege zwischen Nachbarhäusern, Kanus an der der Strecke abgewandten Seite. Licht wie
  bridges.py vorgerechnet (`bake.trace`). Bis `detail_m` volle Form und feine Textur, bis `mid_m` Eckpfähle, dahinter grob.
- Zwei Wasserfarben `water_tint` (export.py → /Scene/WaterTint): die App zeichnet eine Wasserfarbe; darüber liegt 3 cm
  hoch eine halbdurchsichtige Fläche (UsdPreviewSurface, Deckkraft aus dem Alphakanal von water_tint.png). Encontro:
  Mischungsgrad aus der Helligkeit des Sentinel-2-Mosaiks im Wasser (Rio Negro dunkel, Solimões hell; 15./85. Perzentil),
  geglättet, mit Schlieren an der Grenze, Ränder ausgeblendet; die Strecke folgt der 50-%-Isolinie. Anavilhanas (Schwarzwasser)
  und Iquitos (Weisswasser) mit einer festen Farbe. Keine App-Änderung nötig; auf dem Gerät noch nicht gesehen.
- `lane_rules` (lanes.py): eigene Abstände der Ruderer-Bahnen für das Gebiet (3 m Ufer, 2 m Hindernisse, 5 m eigene Bahn);
  überfluteter Wald (Stämme zusammengefasst) und Pfahlbauten sind Hindernisse. routes.py brauchte nichts: Strecken mit
  `via_lv95` und `"avoid": false` werden nicht umfahren.
- Gebiete: `manaus-encontro` (dataset:880), `anavilhanas` (dataset:881) mit `anavilhanas-kanal` und `anavilhanas-igapo`,
  `iquitos-belen` (dataset:882). Stufen standard und hoch, im Bundle nur standard. Zahlen im Bericht und in
  docs/amazonas/SPEC.md („Umsetzung“).
- 2. Runde (28.11.): Igapó mit Palmen, Büschen am Wasser, Stelzwurzeln, Lianen, Dickichten, Dunst-Farbverlauf und
  spiegelndem Schwarzwasser (`forest_variety`, trees.py Form PALM, `tree_extras`); Mitruderer auf der eigenen Linie
  (`traffic.follow_lane`); Iquitos 5,5 m vor den Hauskörpern mit Veranden zur Strecke. Einzelheiten SPEC „2. Runde“.

## 23. Amsterdam: Amstel und Herengracht (AHN, PDOK Luchtfoto, 3DBAG; ETRS89 / UTM 31N)

ETRS89 / UTM 31N (EPSG:25831) statt RD New (EPSG:28992, kein UTM); `geofetch` rechnet um (PROJ-Gitter
`nl_nsgi_rdtrans2018.tif` lädt `ensure_proj_grids`; neuere pyproj kennen nur `open_license=`, jetzt beide Fassungen).
- Höhen: AHN4 DTM/DSM 0,5 m über PDOK-WCS (`service.pdok.nl/rws/ahn/wcs/v1_0`, Coverages `dtm_05m`/`dsm_05m`,
  `"axes": ["x", "y"]`, `native_res` 0,5 → 1 m). Das DTM ist unter Gebäuden und über Wasser leer (40–60 % der
  Kacheln): neues Gebietsfeld `dem_fill_nearest` (prepare.py) füllt mit dem nächsten Geländewert, sonst stünden
  Copernicus-Dächer unter der Stadt.
- Luftbild: PDOK-WMS Actueel_orthoHR (0,2 m) und Actueel_ortho25 (2 m); der Dienst lehnt Bilder über ~2500 px ab
  (ServiceException) → `"max_px": 2000`.
- Gebäude: 3DBAG lod22 über WFS (`data.3dbag.nl/api/BAG3D/wfs`); BBOX und Antwort in EPSG:28992 → neues Feld
  `"native_crs"` der WFS-Quelle (geofetch.wfs_features, fetch_world.ext_footprints). Höhe `b3_h_max − b3_h_maaiveld`
  (`prefer_top`); 104 000 Teile im Kern, mit `buildings_max_route_m` 300 noch 19 400.
- Wasser: Grachtenwasser fest −0,40 m NAP. OSM trennt die Grachtenflächen an jeder Brücke und lässt an Kreuzungen
  (Reguliersgracht) bis 150 m offen: `water_close_via_m` [14, 11] schliesst Lücken entlang der Stützpunkte,
  `water_force_via_m` 8,5 erzwingt dort einen Wasserstreifen (Stützpunkte auf der Grachtenmitte). routes.py hängt die
  Teile der Rückfahrtlinie an engen Kurven jetzt aneinander (vorher Abbruch).
- `amsterdam-amstel-grachten` (dataset:884): one_way 3,16 km von der Amstel nördlich der Berlagebrug flussab unter
  Nieuwe Amstelbrug, Torontobrug und Hoge Sluis, durch die Magere Brug (Mittelöffnung 10 m, Galgen als Wahrzeichen
  `drawbridge_gallows`), links in die Herengracht und an der Goldenen Biegung entlang bis hinter die Leidsestraat.
  Grachtenbrücken als ein Bogen (Seitenbögen nicht modelliert), lichte Höhe 1,8–2,3 m aus dem AHN-DSM – die Kamera
  (2,2 m über dem Wasser) streift die niedrigsten Brücken kurz. `tree_lane_clear_m` 5 (Ulmen am Kai).
  standard 0,63 Mio. Dreiecke/41 MB, hoch 1,24 Mio./84 MB; Satteldächer der Grachtenhäuser nur dort, wo das DSM
  sie klar zeigt (378), sonst Flachdach auf Firsthöhe.

## 24. Venedig: Canal Grande (Copernicus, synthetisches Luftbild; ETRS89 / UTM 33N)

ETRS89 / UTM 33N (EPSG:25833), Flagge aus `"country": "IT"`, Stadtname „Venedig“ (en „Venice“). Kein offenes LiDAR mit
Dienst gefunden (Regione Veneto IODL 2.0 ohne WCS/Download für die Altstadt, nationales PST-LiDAR ohne Dienst für
die Lagune; LIZENZEN-GEODATEN.md) → Vorlage Tigre: Copernicus GLO-30 eingeebnet (`dem_flatten` max 2 m), Luftbild
synthetisch (Sentinel-2 Juli 2025 + OSM), Gebäude aus OSM-Umrissen mit `footprint_defaults` 11/16 m (1425 mit
Geschossen), Meer aus OSM-Küstenlinien, Wasser 0 m (Tidenhub nicht modelliert).
- Flache Lagune: die fehlerbasierte Vereinfachung des Geländes (bis 3 m Fehler in der Ferne) hob grosse Dreiecke
  zwischen Wasser (−1,8 m) und Land (+2 m) über die Wasserfläche (dunkle Platten im Bacino). Neues Gebietsfeld
  `water_floor_m` (prepare.py, nur mit fester Wasserhöhe): Füllung unter dem Wasser 3,5 m statt 0,8 m tief.
- `venezia-canal-grande` (dataset:885): one_way 3,60 km vom Ponte della Costituzione vor der Ferrovia unter Scalzi,
  Rialto und Accademia hindurch bis ins Bacino di San Marco vor der Piazzetta; Kanal 32–90 m, Mitte aus dem OSM-Wasser
  (alle 30 m quer zentriert). Wahrzeichen: Ponte degli Scalzi und Rialtobrücke (`arch_bridge`, Rialto mit Ladenzeilen
  und Portikus), Ponte dell'Accademia (`truss_arch_bridge`), Santa Maria della Salute (`domed_church` mit Voluten,
  Nebenkuppel, Glockentürmen), Campanile di San Marco, Turm der Dogana, Palazzo Ducale (`gothic_block`). Keine
  Einträge in `bridges` (die drei Brücken haben keine Strompfeiler und sind ganz Wahrzeichen).
- standard 0,70 Mio. Dreiecke/29 MB, hoch 1,03 Mio./49 MB; `preview_views` [60, 1520, 2700, 2900].
