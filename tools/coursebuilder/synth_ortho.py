"""Synthetisches Luftbild für Gebiete ohne offenes hochaufgelöstes Orthofoto (fetch_world: "ortho": {"type": "synthetic"}).

Schreibt je km-Kachel des Kerngebiets <data_dir>/image_core/dop_<E>-<N>.tif (RGB, 0,25 m, JPEG) – dasselbe Layout wie
fetch_de.py, deshalb laufen prepare.py, routes.py, bake.py (Dachfarben), trees.py (Grünanteil), summer.py und export.py
unverändert.

Zutaten (alle offen, Lizenz in fetch-log.json):
  Sentinel-2 (image_far/s2_far.tif, 10 m, fetch_world.py)  grossräumige Farbe und Helligkeit, hochgerechnet; für
       Flächen ohne OSM-Klasse (Felder, Gärten) die Farbe selbst – auf die Palette der Klassen abgestimmt (Verstärkung je
       Kanal so, dass der Sentinel-Median der Wiesen auf die Wiesenfarbe fällt)
  OpenStreetMap (osm/landcover.json)  Flächennutzung (landuse, natural, leisure, amenity=parking, area:highway), Wasser,
       Strassen und Wege (Breite nach highway-Klasse, Belag nach surface), Bahngleise, Stege, Mauern/Hecken
  Gebäudeumrisse (footprints/footprints.geojson)  Dächer in Schiefer-, Ziegel- und Blechtönen (roof:colour, sonst fest
       aus der Gebäude-Nr.), Rand dunkler
  Oberflächen- minus Geländemodell (bdom/, dgm/)  Baumkronen (> 2,5 m, nicht auf Gebäuden) mit Schummerung der Krone
       (wirkt rund) und Schlagschatten von Bäumen und Häusern (Sonne 235°/48° wie bake.py)
Jede Klasse hat eine Grundfarbe und eine Textur aus mehrstufigem Wertrauschen (an Weltkoordinaten verankert, also
nahtlos über Kachelgrenzen): Wiese mit Flecken und Halmkorn, Wald mit Laub und Boden, Asphalt mit Flickstellen,
Kies hell und körnig, Sand, Wasser dunkel mit hellerem Uferstreifen; dazu ein schmaler Uferstreifen (Erde/Schilf) an
Land. Die Sentinel-Helligkeit moduliert die Vegetation leicht (trockene Stellen, Felder), damit es nicht flach wirkt.

Grenzen: keine echten Details (Autos, Bänke, Boote, Markierungen), Felder nur so genau wie Sentinel-2 (10 m),
Gärten hinter Häusern als Sentinel-Farbe mit Rasenstruktur. Vom Boot aus zählen vor allem Ufer, Wiesen, Wege
und Bäume – die stimmen in der Lage (OSM, Lidar).

Aufruf (nach fetch_world.py, vor prepare.py): .venv/bin/python synth_ortho.py areas/<gebiet>.json [--force] [--tile E-N]
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.features import rasterize
from scipy import ndimage
from shapely.geometry import LineString, Polygon, shape
from shapely.ops import unary_union

import geofetch as gf
from common import _rings, _xy, to_proj

RES = 0.25
SUN_AZ, SUN_EL = 235.0, 48.0

# Klassen: Nr. → (Name, Grundfarbe RGB, Rauschstärke, Sentinel-Anteil an der Farbe, Korn)
C = {}


def cls(i, name, rgb, var, s2, grain):
    C[name] = i
    PROPS[i] = (name, np.array(rgb, np.float32), var, s2, grain)


PROPS = {}
cls(0, "unbekannt", (104, 120, 70), 0.10, 1.0, 0.05)
cls(1, "wiese", (100, 126, 62), 0.12, 0.35, 0.07)
cls(2, "rasen", (92, 128, 58), 0.08, 0.25, 0.05)
cls(3, "feld", (128, 128, 78), 0.10, 0.85, 0.05)
cls(4, "wald", (62, 74, 44), 0.16, 0.25, 0.10)
cls(5, "gebuesch", (78, 94, 52), 0.16, 0.30, 0.09)
cls(6, "feucht", (88, 106, 66), 0.14, 0.35, 0.08)
cls(7, "wohnen", (108, 116, 84), 0.12, 0.70, 0.07)
cls(8, "befestigt", (124, 122, 118), 0.07, 0.10, 0.06)
cls(9, "asphalt", (82, 82, 84), 0.06, 0.0, 0.05)
cls(10, "weg_hell", (156, 150, 140), 0.07, 0.0, 0.07)
cls(11, "kies", (176, 164, 140), 0.09, 0.0, 0.12)
cls(12, "erdweg", (134, 116, 90), 0.12, 0.0, 0.10)
cls(13, "sand", (196, 182, 150), 0.07, 0.0, 0.08)
cls(14, "wasser", (48, 62, 58), 0.05, 0.0, 0.02)
cls(15, "gleis", (104, 96, 88), 0.10, 0.0, 0.15)
cls(16, "sportplatz", (86, 136, 58), 0.06, 0.15, 0.04)
cls(17, "boden", (140, 122, 98), 0.12, 0.3, 0.10)
cls(18, "holz", (120, 96, 70), 0.08, 0.0, 0.10)
cls(19, "dach", (110, 104, 100), 0.05, 0.0, 0.04)
cls(20, "ufer", (92, 92, 66), 0.14, 0.2, 0.10)
cls(21, "kleingarten", (104, 112, 70), 0.18, 0.4, 0.10)
cls(22, "friedhof", (90, 118, 64), 0.12, 0.3, 0.07)
cls(23, "hecke", (58, 76, 42), 0.14, 0.0, 0.10)
cls(24, "graben", (66, 76, 52), 0.16, 0.0, 0.12)
VEG = [C[k] for k in ("unbekannt", "wiese", "rasen", "feld", "wald", "gebuesch", "feucht", "wohnen", "sportplatz",
                      "kleingarten", "friedhof", "ufer")]

LANDUSE = {"farmland": "feld", "meadow": "wiese", "grass": "rasen", "recreation_ground": "rasen", "village_green": "rasen",
           "residential": "wohnen", "forest": "wald", "orchard": "gebuesch", "allotments": "kleingarten",
           "cemetery": "friedhof", "commercial": "befestigt", "retail": "befestigt", "industrial": "befestigt",
           "railway": "gleis", "construction": "boden", "brownfield": "boden", "garages": "befestigt",
           "farmyard": "boden", "religious": "rasen", "education": "rasen", "plant_nursery": "gebuesch",
           "flowerbed": "gebuesch", "greenfield": "wiese", "landfill": "boden", "quarry": "sand"}
NATURAL = {"wood": "wald", "scrub": "gebuesch", "heath": "gebuesch", "grassland": "wiese", "wetland": "feucht",
           "sand": "sand", "beach": "sand", "bare_rock": "befestigt", "shingle": "kies", "mud": "boden",
           "water": "wasser", "tree_row": "hecke"}
LEISURE = {"park": "rasen", "garden": "rasen", "pitch": "sportplatz", "playground": "boden", "golf_course": "rasen",
           "nature_reserve": None, "common": "wiese", "sports_centre": "befestigt", "track": "boden",
           "stadium": "befestigt", "marina": "befestigt", "slipway": "befestigt", "dog_park": "wiese"}
ROAD_W = {"motorway": 14, "trunk": 11, "primary": 9, "secondary": 8, "tertiary": 7, "unclassified": 5.5,
          "residential": 5.5, "living_street": 5, "service": 3.5, "motorway_link": 6, "trunk_link": 6,
          "primary_link": 6, "secondary_link": 6, "tertiary_link": 5, "road": 5, "busway": 6}
PATH_W = {"pedestrian": 4, "track": 3, "footway": 2.2, "path": 1.8, "cycleway": 2.5, "bridleway": 2.2,
          "steps": 2.0, "corridor": 0}
PAVED = {"asphalt", "paved", "concrete", "paving_stones", "sett", "concrete:plates", "cobblestone", "chipseal"}
GRAVEL = {"gravel", "fine_gravel", "compacted", "pebblestone"}
DIRT = {"dirt", "ground", "earth", "unpaved", "mud", "grass", "woodchips", "sand"}
ROOFS = [(84, 86, 92), (78, 80, 88), (136, 84, 64), (150, 96, 72), (118, 76, 60), (104, 102, 100), (142, 140, 136),
         (96, 92, 88), (126, 120, 112)]
ROOF_COLOUR = {"red": (150, 82, 62), "brown": (112, 80, 62), "grey": (110, 110, 112), "gray": (110, 110, 112),
               "black": (58, 58, 62), "darkgrey": (76, 76, 80), "white": (190, 190, 186), "green": (88, 112, 92),
               "silver": (160, 162, 164)}


# ----------------------------------------------------------------------------- Rauschen (nahtlos, Weltkoordinaten)

def _hash(i, j, seed):
    h = (i.astype(np.uint64) * np.uint64(73856093)) ^ (j.astype(np.uint64) * np.uint64(19349663)) ^ \
        np.uint64(seed * 83492791 + 1)
    h ^= h >> np.uint64(13)
    h *= np.uint64(0x5bd1e995)
    h ^= h >> np.uint64(15)
    return (h & np.uint64(0xFFFFFF)).astype(np.float32) / float(0xFFFFFF)


def value_noise(bounds, shape_hw, cell, seed):
    """Glattes Rauschen (−0,5…0,5) mit Zellgrösse cell (m), an Weltkoordinaten verankert."""
    e0, n0, e1, n1 = bounds
    h, w = shape_hw
    i0, j0 = math.floor(e0 / cell) - 1, math.floor(n0 / cell) - 1
    i1, j1 = math.floor(e1 / cell) + 3, math.floor(n1 / cell) + 3
    I, J = np.meshgrid(np.arange(i0, i1), np.arange(j0, j1))
    lat = _hash(I - i0 + i0, J, seed) - 0.5  # lat[j, i]
    xs = (e0 + (np.arange(w) + 0.5) * (e1 - e0) / w) / cell - i0
    ys = (n1 - (np.arange(h) + 0.5) * (n1 - n0) / h) / cell - j0
    # separabel: erst Zeilen (Nord), dann Spalten (Ost), kubisch
    tmp = ndimage.map_coordinates(lat, np.vstack([np.repeat(ys, lat.shape[1]), np.tile(np.arange(lat.shape[1]),
                                                                                       len(ys))]),
                                  order=3, mode="nearest").reshape(len(ys), lat.shape[1])
    out = np.empty((h, w), np.float32)
    for r in range(h):
        out[r] = np.interp(xs, np.arange(lat.shape[1]), tmp[r])
    return out


def fbm(bounds, shape_hw, cells, seed, weights=None):
    weights = weights or [0.5 ** k for k in range(len(cells))]
    s = sum(weights)
    out = np.zeros(shape_hw, np.float32)
    for k, (c, wt) in enumerate(zip(cells, weights)):
        out += wt / s * value_noise(bounds, shape_hw, c, seed + 17 * k)
    return out * 1.6


def grain(bounds, shape_hw, seed):
    """Korn je Pixel (−0,5…0,5), an Weltkoordinaten verankert."""
    e0, n0, e1, n1 = bounds
    h, w = shape_hw
    i = np.round((e0 + (np.arange(w) + 0.5) * RES) / RES).astype(np.int64)
    j = np.round((n1 - (np.arange(h) + 0.5) * RES) / RES).astype(np.int64)
    I, J = np.meshgrid(i, j)
    return _hash(I, J, seed) - 0.5


# ----------------------------------------------------------------------------- OSM-Geometrien

def load_layers(area, root):
    """[(Ebene, Fläche (für Reihenfolge), Geometrie, Klasse)] im Gebietssystem, dazu Wasser und Ufer."""
    tr = to_proj(area)
    els = json.loads((root / "osm" / "landcover.json").read_text())["elements"]
    polys, lines = [], []

    def geom_of(el):
        if el["type"] == "way" and "geometry" in el:
            pts = _xy(el["geometry"], tr)
            if len(pts) >= 4 and pts[0] == pts[-1]:
                return Polygon(pts).buffer(0), LineString(pts)
            return None, LineString(pts) if len(pts) >= 2 else None
        if el["type"] == "relation":
            outer = [_xy(m["geometry"], tr) for m in el.get("members", []) if m.get("role") == "outer" and
                     "geometry" in m]
            inner = [_xy(m["geometry"], tr) for m in el.get("members", []) if m.get("role") == "inner" and
                     "geometry" in m]
            g = unary_union(_rings(outer)) if outer else None
            if g is None or g.is_empty:
                return None, None
            if inner:
                g = g.difference(unary_union(_rings(inner)))
            return g.buffer(0), None
        return None, None

    water = []
    for el in els:
        t = el.get("tags", {})
        if el["type"] == "node":
            continue
        poly, line = geom_of(el)
        k = None
        layer = 1
        if t.get("natural") == "water" or t.get("waterway") == "riverbank" or t.get("water"):
            if poly is not None:
                water.append(poly)
            continue
        if "landuse" in t:
            k, layer = LANDUSE.get(t["landuse"]), 1
        if "leisure" in t and LEISURE.get(t["leisure"]):
            k, layer = LEISURE[t["leisure"]], 2
            if t["leisure"] == "pitch" and t.get("surface") in ("asphalt", "concrete", "tartan", "clay"):
                k = "befestigt" if t.get("surface") != "clay" else "boden"
        if "natural" in t and NATURAL.get(t["natural"]):
            k, layer = NATURAL[t["natural"]], 3
            if t["natural"] == "tree_row" and line is not None:
                polys.append((6, 0, line.buffer(3.0), C["hecke"]))
                continue
        if t.get("amenity") in ("parking", "marketplace") or "area:highway" in t:
            k, layer = "befestigt", 4
        if t.get("amenity") in ("school", "university", "college") and k is None:
            k, layer = "rasen", 1
        if t.get("amenity") == "grave_yard":
            k, layer = "friedhof", 1
        if t.get("man_made") in ("pier",):
            g = poly if poly is not None and t.get("area") != "no" else (line.buffer(1.5) if line else None)
            if g is not None:
                polys.append((7, 0, g, C["holz"]))
            continue
        if t.get("man_made") in ("quay", "breakwater", "wastewater_plant", "works") and poly is not None:
            k, layer = "befestigt", 4
        if t.get("highway") == "pedestrian" and poly is not None and t.get("area") == "yes":
            k, layer = "weg_hell", 5
        if k is not None and poly is not None and not poly.is_empty:
            polys.append((layer, -poly.area, poly, C[k]))
            continue
        # Linien
        if line is None:
            continue
        hw = t.get("highway")
        sf = t.get("surface", "")
        if hw in ROAD_W:
            w = float(t.get("width", ROAD_W[hw]) if str(t.get("width", "")).replace(".", "").isdigit() else ROAD_W[hw])
            k = "asphalt" if sf not in GRAVEL | DIRT else ("kies" if sf in GRAVEL else "erdweg")
            lines.append((5 + (0.5 if hw != "service" else 0), w, line, C[k]))
        elif hw in PATH_W and PATH_W[hw] > 0:
            w = PATH_W[hw]
            if sf in PAVED:
                k = "asphalt" if sf == "asphalt" and hw == "cycleway" else "weg_hell"
            elif sf in GRAVEL:
                k = "kies"
            elif sf in DIRT:
                k = "erdweg"
            else:
                # ohne surface: Gehwege und Radwege befestigt, Pfade/Feldwege Erde
                k = {"pedestrian": "weg_hell", "footway": "weg_hell", "steps": "weg_hell", "cycleway": "asphalt",
                     "track": "kies"}.get(hw, "erdweg")
            lines.append((5.2, w, line, C[k]))
        elif t.get("railway") in ("rail", "light_rail", "tram", "narrow_gauge") and t.get("tunnel") != "yes":
            lines.append((5.1, 3.4 if t["railway"] != "tram" else 2.4, line, C["gleis"]))
        elif t.get("waterway") in ("stream", "ditch", "drain", "canal") and t.get("tunnel") not in ("yes", "culvert"):
            # Gräben sind meist zugewachsen: dunkles Grün statt offenem Wasser
            k = "wasser" if t["waterway"] in ("canal", "stream") else "graben"
            lines.append((4.5, {"canal": 8, "stream": 2.5}.get(t["waterway"], 1.2), line, C[k]))
        elif t.get("barrier") == "hedge":
            lines.append((5.3, 1.5, line, C["hecke"]))
        elif t.get("barrier") in ("wall", "retaining_wall"):
            lines.append((5.3, 0.5, line, C["befestigt"]))
    for layer, w, line, k in lines:
        polys.append((layer, 0, line.buffer(w / 2, cap_style=2 if k == C["gleis"] else 1), k))
    polys.sort(key=lambda t: (t[0], t[1]))
    # Wasser auch aus overpass.json (Fluss im grösseren Ausschnitt)
    from common import osm_water
    try:
        water.append(osm_water(area))
    except Exception:  # noqa: BLE001
        pass
    return polys, unary_union(water) if water else None


# ----------------------------------------------------------------------------- Kachel rendern

def hillshade(z, res, az=SUN_AZ, el=SUN_EL):
    gy, gx = np.gradient(z, res)
    nx, ny = -gx, gy
    ln = np.sqrt(nx * nx + ny * ny + 1)
    a, e = math.radians(az), math.radians(el)
    s = (math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e))
    return np.clip((nx * s[0] + ny * s[1] + s[2]) / ln, 0, 1)


def cast_shadow(dsm, res, max_m=45.0, az=SUN_AZ, el=SUN_EL):
    """Schlagschatten (0…1) aus dem Oberflächenmodell: Pixel liegt im Schatten, wenn Richtung Sonne etwas höher
    aufragt als der Sonnenstrahl."""
    a = math.radians(az)
    de, dn = math.sin(a), math.cos(a)
    t = math.tan(math.radians(el))
    z = np.nan_to_num(dsm, nan=np.nanmin(dsm) if np.isfinite(dsm).any() else 0)
    depth = np.zeros_like(z)
    for k in range(1, int(max_m / res) + 1):
        dx, dy = de * k, -dn * k  # Spalten nach Osten, Zeilen nach Süden
        sh = ndimage.shift(z, (-dy, -dx), order=1, mode="nearest", prefilter=False)
        depth = np.maximum(depth, sh - z - k * res * t)
    return np.clip(depth / 1.0, 0, 1)


BLOCK, MARGIN = 500, 8.0  # in Blöcken à 500 m rechnen (Speicher), mit Rand für Uferabstand und Weichzeichner


def render_tile(te, tn, area, root, polys, water, roofs, s2_path, gain, chm_files, dtm_files, crs):
    g = gf.tile_grid(te, tn, RES, crs)
    img = np.zeros((3, *g.shape), np.uint8)
    counts = {}
    m = int(MARGIN / RES)
    n = int(BLOCK / RES)
    for i, e in enumerate(range(te * 1000, te * 1000 + 1000, BLOCK)):
        for j, nn in enumerate(range(tn * 1000 + 1000 - BLOCK, tn * 1000 - 1, -BLOCK)):
            gb = gf.Grid((e - MARGIN, nn - MARGIN, e + BLOCK + MARGIN, nn + BLOCK + MARGIN), RES, crs)
            part, klass = render_block(gb, polys, water, roofs, s2_path, gain, chm_files, dtm_files, crs)
            img[:, j * n:(j + 1) * n, i * n:(i + 1) * n] = part[:, m:m + n, m:m + n]
            for k, c in zip(*np.unique(klass[m:m + n, m:m + n], return_counts=True)):
                counts[k] = counts.get(k, 0) + int(c)
            del part, klass
    dest = root / "image_core" / f"dop_{te}-{tn}.tif"
    gf.write_tif(dest, img, g, rgb_jpeg=True)
    tot = sum(counts.values())
    print(f"  {dest.name}: " + ", ".join(f"{PROPS[k][0]} {c / tot * 100:.0f} %" for k, c in
                                          sorted(counts.items(), key=lambda t: -t[1]) if c / tot >= 0.02), flush=True)


def render_block(g, polys, water, roofs, s2_path, gain, chm_files, dtm_files, crs):
    b = g.bounds
    hw = g.shape
    # Klassen
    klass = np.zeros(hw, np.uint8)
    bx = (b[0] - 5, b[1] - 5, b[2] + 5, b[3] + 5)
    from shapely.geometry import box
    tb = box(*bx)
    shapes = [(p.intersection(tb), k) for _, _, p, k in polys if p.intersects(tb)]
    shapes = [(s, k) for s, k in shapes if not s.is_empty]
    if shapes:
        klass = rasterize(shapes, out_shape=hw, transform=g.transform, fill=0, dtype=np.uint8)
    wmask = np.zeros(hw, bool)
    if water is not None and water.intersects(tb):
        wmask = rasterize([water.intersection(tb)], out_shape=hw, transform=g.transform).astype(bool)
    # Uferstreifen an Land (1,5–3 m, ausgefranst) und Wasserrand
    dist_w = ndimage.distance_transform_edt(~wmask) * RES if wmask.any() else np.full(hw, 1e3, np.float32)
    nb = fbm(b, hw, [6.0, 2.0], 7)
    bank = (~wmask) & (dist_w < 2.2 + 1.2 * nb) & np.isin(klass, VEG + [C["unbekannt"]])
    klass[bank] = C["ufer"]
    klass[wmask] = C["wasser"]
    # Dächer
    rmask = np.zeros(hw, bool)
    roof_rgb = np.zeros((3, *hw), np.float32)
    rs = [(p.intersection(tb), i + 1) for i, (p, _) in enumerate(roofs) if p.intersects(tb)]
    if rs:
        rid = rasterize(rs, out_shape=hw, transform=g.transform, fill=0, dtype=np.int32)
        rmask = rid > 0
        pal = np.array([np.zeros(3)] + [c for _, c in roofs], np.float32)
        roof_rgb = np.moveaxis(pal[rid], -1, 0)
        edge = rmask & ~ndimage.binary_erosion(rmask, iterations=2)
        roof_rgb[:, edge] *= 0.8
        klass[rmask] = C["dach"]
    # Farbe je Klasse + Textur
    s2 = None
    if s2_path.exists():
        with rasterio.open(s2_path) as s:
            a = s.read([1, 2, 3]).astype(np.float32)
            s2 = gf.warp_array(a, s.transform, s.crs, g, Resampling.cubic, src_nodata=None, dst_nodata=0)
        s2 = ndimage.gaussian_filter(s2, (0, 6, 6))  # 10-m-Pixel nicht als Blöcke zeigen
    rgb = np.zeros((3, *hw), np.float32)
    n_coarse = fbm(b, hw, [40.0, 15.0], 11)
    n_mid = fbm(b, hw, [5.0, 1.8], 23)
    n_fine = fbm(b, hw, [0.7], 31)
    gr = grain(b, hw, 41)
    n_hue = fbm(b, hw, [25.0, 8.0], 53)
    for k, (name, base, var, s2w, grn) in PROPS.items():
        m = klass == k
        if not m.any() or k == C["dach"]:
            continue
        col = np.repeat(base[:, None], m.sum(), axis=1)
        if s2 is not None and s2w > 0:
            sc = s2[:, m] * gain[:, None]
            col = col * (1 - s2w) + sc * s2w
        tex = 1 + var * (0.9 * n_coarse[m] + 0.8 * n_mid[m] + 0.5 * n_fine[m]) + grn * gr[m]
        col = col * tex[None]
        if k in VEG or k in (C["wald"], C["hecke"]):  # Farbton: gelblicher bzw. bläulicher
            col[0] *= 1 + 0.06 * n_hue[m]
            col[2] *= 1 - 0.06 * n_hue[m]
        rgb[:, m] = col
    rgb[:, rmask] = roof_rgb[:, rmask] * (1 + 0.05 * n_fine[rmask] + 0.04 * gr[rmask])[None]
    # Wasser: am Rand heller und bräunlicher (flaches Wasser), sonst dunkel
    if wmask.any():
        din = ndimage.distance_transform_edt(wmask) * RES
        shallow = np.clip(1 - din / 4.0, 0, 1)[wmask]
        rgb[:, wmask] = rgb[:, wmask] * (1 - 0.5 * shallow) + np.array([86, 88, 70], np.float32)[:, None] * \
            (0.5 * shallow)
    # Weiche Klassengrenzen (nicht bei Dächern)
    soft = ndimage.gaussian_filter(rgb, (0, 0.9, 0.9))
    rgb = np.where(rmask[None], rgb, soft)
    # Baumkronen und Schatten aus dem Oberflächenmodell
    g1 = gf.Grid((b[0] - 50, b[1] - 50, b[2] + 50, b[3] + 50), 0.5, crs)
    dsm = gf._mosaic_into(chm_files, g1, resampling=Resampling.bilinear) if chm_files else None
    if dsm is not None and np.isfinite(dsm).any():
        dtm = gf._mosaic_into(dtm_files, g1, resampling=Resampling.bilinear)
        chm = np.clip(np.nan_to_num(dsm - dtm, nan=0.0), 0, 60)
        chm_s = ndimage.gaussian_filter(chm, 0.8)
        hs = hillshade(chm_s, 0.5)
        shadow = ndimage.gaussian_filter(cast_shadow(np.where(np.isfinite(dsm), dsm, dtm), 0.5), 1.0)
        crop = (slice(100, -100), slice(100, -100))
        up = lambda x: ndimage.zoom(x[crop], 2, order=1)[:hw[0], :hw[1]]  # noqa: E731
        chm_u, hs_u, sh_u = up(chm_s), up(hs), up(shadow)
        canopy = (chm_u > 2.5) & ~ndimage.binary_dilation(rmask, iterations=3) & ~wmask
        canopy = ndimage.binary_opening(canopy, iterations=2)
        if canopy.any():
            n_crown = fbm(b, hw, [7.0, 2.5, 0.9], 61)
            base = np.array([60, 80, 42], np.float32)
            cc = base[:, None] * (1 + 0.18 * n_crown[canopy] + 0.10 * gr[canopy])[None]
            cc[0] *= 1 + 0.10 * n_hue[canopy]
            cc[2] *= 1 - 0.08 * n_hue[canopy]
            flat = hillshade(np.zeros((3, 3)), 1.0)[1, 1]
            cc *= (0.55 + 0.6 * hs_u[canopy] / flat)[None]
            w = np.clip((chm_u[canopy] - 2.5) / 1.5, 0, 1)
            rgb[:, canopy] = rgb[:, canopy] * (1 - w) + cc * w
        dark = np.where(wmask, 0.25, 0.5) * sh_u
        rgb *= (1 - dark)[None]
        rgb[2] *= 1 + 0.12 * sh_u  # Schatten etwas bläulich
    return np.clip(rgb + 0.5, 0, 255).astype(np.uint8), klass


def roof_list(root):
    out = []
    f = root / "footprints" / "footprints.geojson"
    if not f.exists():
        return out
    for i, ft in enumerate(json.loads(f.read_text())["features"]):
        p = ft["properties"]
        c = ROOF_COLOUR.get(str(p.get("roof_colour") or "").lower())
        if c is None:
            h = (i * 2654435761) % (2 ** 32)
            g = shape(ft["geometry"])
            pal = ROOFS if g.area < 400 else [ROOFS[5], ROOFS[6], ROOFS[7], ROOFS[0]]  # grosse Dächer: grau
            c = pal[h % len(pal)]
            j = ((h >> 8) % 1000) / 1000 - 0.5
            c = tuple(np.clip(np.array(c) * (1 + 0.1 * j), 0, 255))
        out.append((shape(ft["geometry"]), np.array(c, np.float32)))
    return out


def s2_gain(area, root, polys, s2_path):
    """Verstärkung je Kanal: Sentinel-Median auf Wiesen/Rasen → Wiesenfarbe der Palette."""
    if not s2_path.exists():
        return np.ones(3, np.float32)
    g = gf.Grid(tuple(area["core_lv95"]), 10.0, area["crs"])
    with rasterio.open(s2_path) as s:
        a = gf.warp_array(s.read([1, 2, 3]).astype(np.float32), s.transform, s.crs, g, Resampling.average,
                          dst_nodata=0)
    sel = [p for _, _, p, k in polys if k in (C["wiese"], C["rasen"])]
    m = rasterize(sel, out_shape=g.shape, transform=g.transform).astype(bool) if sel else np.zeros(g.shape, bool)
    m &= a.max(axis=0) > 0
    if m.sum() < 30:
        return np.ones(3, np.float32)
    med = np.array([np.median(a[k][m]) for k in range(3)], np.float32)
    gain = PROPS[C["wiese"]][1] / np.maximum(med, 1)
    print(f"Sentinel-2 → Palette: Median Wiese {med.round(1)}, Verstärkung {gain.round(2)}", flush=True)
    return gain


def main(area_file, force=False, only=None):
    area = json.loads(Path(area_file).read_text())
    root = (Path.cwd() / area["data_dir"]).resolve()
    crs = area["crs"]
    polys, water = load_layers(area, root)
    roofs = roof_list(root)
    s2_path = root / "image_far" / "s2_far.tif"
    gain = s2_gain(area, root, polys, s2_path)
    alti = area.get("raster_dirs", {}).get("alti_core", "dgm")
    chm_files = sorted((root / "bdom").glob("*.tif"))
    dtm_files = sorted((root / alti).glob("*.tif"))
    print(f"synth_ortho: {len(polys)} Flächen/Linien, {len(roofs)} Dächer, Wasser "
          f"{0 if water is None else water.area / 1e6:.2f} km²", flush=True)
    for te, tn in gf.km_tiles(area["core_lv95"]):
        if only and f"{te}-{tn}" != only:
            continue
        if (root / "image_core" / f"dop_{te}-{tn}.tif").exists() and not force:
            continue
        render_tile(te, tn, area, root, polys, water, roofs, s2_path, gain, chm_files, dtm_files, crs)
    gf.log_source(root, {"source": "synthetisches Luftbild (synth_ortho.py)", "role": "ortho",
                         "inputs": "Sentinel-2 (image_far/s2_far.tif), OpenStreetMap (osm/landcover.json), "
                                   "Gebäudeumrisse, Oberflächen- und Geländemodell", "res_m": RES,
                         "licence": "abgeleitet: Contains modified Copernicus Sentinel data; © OpenStreetMap "
                                    "contributors (ODbL); Höhenquellen siehe dtm/dsm"})


if __name__ == "__main__":
    tile = sys.argv[sys.argv.index("--tile") + 1] if "--tile" in sys.argv else None
    main(sys.argv[1], force="--force" in sys.argv, only=tile)
