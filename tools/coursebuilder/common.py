"""Gemeinsame Helfer für den coursebuilder (Gebietsdatei laden, OpenStreetMap-Daten lesen, Koordinatensystem).

Koordinatensystem je Gebiet: Feld "crs" der Gebietsdatei (Standard "EPSG:2056", LV95; Berlin/Brandenburg
"EPSG:25833", ETRS89/UTM 33N). Die Felder core_lv95, far_lv95, start_lv95 usw. tragen ihren Namen aus
Kompatibilität, ihre Werte stehen immer im Koordinatensystem "crs" des Gebiets.

Gebietsdatei: `lake_level_m` darf fehlen, wenn prepare.py die Wasserhöhe selbst bestimmt (Flüsse, "water_source":
"osm"). Dann steht sie in build/<area>/water_meta.json und load_area() trägt sie als lake_level_m ein, damit alle
anderen Schritte unverändert mit einer festen Wasserhöhe (Szene y = 0) arbeiten.
"""
import json
from pathlib import Path

import numpy as np
from pyproj import Transformer
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import linemerge, polygonize, unary_union

TO_LV95 = Transformer.from_crs(4326, 2056, always_xy=True)
_TO_PROJ = {"EPSG:2056": TO_LV95}
_TO_WGS = {}


def area_crs(area):
    return area.get("crs", "EPSG:2056")


def to_proj(area):
    """Transformer WGS84 (lon, lat) → Koordinatensystem des Gebiets."""
    crs = area_crs(area)
    if crs not in _TO_PROJ:
        _TO_PROJ[crs] = Transformer.from_crs(4326, crs, always_xy=True)
    return _TO_PROJ[crs]


def to_wgs84(crs, e, n):
    """Projizierte Koordinaten (crs) → (lat, lon) in Grad."""
    crs = crs or "EPSG:2056"
    if crs not in _TO_WGS:
        _TO_WGS[crs] = Transformer.from_crs(crs, 4326, always_xy=True)
    lon, lat = _TO_WGS[crs].transform(e, n)
    return lat, lon


def course_origin(course):
    """Ursprung [E0, N0] einer course.json: allgemeines Feld "origin", sonst "origin_lv95" (Schweiz)."""
    return course.get("origin") or course["origin_lv95"]


def ortho_tile(folder, e_km, n_km):
    """Luftbildkachel des Kerngebiets (1 km): SWISSIMAGE 10 cm (…_<E>-<N>_0.1_2056.tif) oder
    fetch_de.py (dop_<E>-<N>.tif, 0,2 m). None, wenn keine da ist."""
    hits = list(folder.glob(f"*_{int(e_km)}-{int(n_km)}_0.1_2056.tif")) or \
        list(folder.glob(f"dop_{int(e_km)}-{int(n_km)}.tif"))
    return hits[0] if hits else None


def load_area(area_file):
    area = json.loads(Path(area_file).read_text())
    if "lake_level_m" not in area:
        meta = Path("build") / area["id"] / "water_meta.json"
        if not meta.exists():
            raise SystemExit(f"Wasserhöhe fehlt: {meta} – zuerst prepare.py {area_file} laufen lassen")
        area["lake_level_m"] = json.loads(meta.read_text())["water_level_m"]
    return area


def raw_dir(area):
    return (Path.cwd() / area["data_dir"]).resolve()


# ----------------------------------------------------------------------------- OpenStreetMap

def _xy(geom, tr=TO_LV95):
    lon = np.array([p["lon"] for p in geom])
    lat = np.array([p["lat"] for p in geom])
    e, n = tr.transform(lon, lat)
    return list(zip(e, n))


def _rings(lines):
    merged = linemerge([LineString(l) for l in lines if len(l) >= 2])
    return [p for p in polygonize(merged)]


def osm_elements(area):
    f = raw_dir(area) / "osm" / "overpass.json"
    return json.loads(f.read_text())["elements"]


def osm_sea(area, els=None, bounds=None):
    """Meer aus den OSM-Küstenlinien (natural=coastline; Land links, Wasser rechts der Wegrichtung) als Fläche im
    Gebietssystem, auf bounds (Standard far_lv95) zugeschnitten. OSM führt das Meer nicht als natural=water, sondern
    nur über die Küstenlinie (Oslofjord, Nærøyfjord). Verfahren: Küstenlinien zusammenfügen, mit dem Rahmen
    verschneiden und in Flächen zerlegen (polygonize); je Fläche entscheiden Markierungen 0,5 m rechts (Meer) bzw. links
    (Land) der Küstenlinie. Ohne Küstenlinie im Gebiet: leere Fläche."""
    from shapely.geometry import box as _box
    tr = to_proj(area)
    els = osm_elements(area) if els is None else els
    lines = [LineString(_xy(el["geometry"], tr)) for el in els
             if el["type"] == "way" and el.get("tags", {}).get("natural") == "coastline" and len(el.get("geometry", [])) >= 2]
    if not lines:
        return Polygon()
    b = bounds or area["far_lv95"]
    # Rahmen 500 m nach innen: Küstenlinien, die knapp im Gebiet enden (Abfrage-Rand, Lücke in OSM), liegen dann
    # ausserhalb und öffnen keine Fläche
    b = [b[0] + 500, b[1] + 500, b[2] - 500, b[3] - 500]
    frame = _box(*b)
    merged = linemerge(lines)
    merged = list(getattr(merged, "geoms", [merged]))
    sea_pts, land_pts = [], []
    for ln in merged:
        c = np.asarray(ln.coords)
        if len(c) < 2:
            continue
        d = np.diff(c, axis=0)
        L = np.hypot(d[:, 0], d[:, 1])
        ok = L > 1.0
        mid = (c[:-1] + c[1:])[ok] / 2
        nrm = np.column_stack([d[ok, 1], -d[ok, 0]]) / L[ok, None]   # rechts der Richtung
        sea_pts.append(mid + 0.5 * nrm)
        land_pts.append(mid - 0.5 * nrm)
    sea_pts = np.vstack(sea_pts) if sea_pts else np.zeros((0, 2))
    land_pts = np.vstack(land_pts) if land_pts else np.zeros((0, 2))
    inb = lambda P: P[(P[:, 0] > b[0]) & (P[:, 0] < b[2]) & (P[:, 1] > b[1]) & (P[:, 1] < b[3])]
    sea_pts, land_pts = inb(sea_pts), inb(land_pts)
    clipped = [g.intersection(frame) for g in merged]
    noded = unary_union([g for g in clipped if not g.is_empty] + [frame.boundary])
    faces = list(polygonize(noded))
    from shapely import contains_xy
    sea = []
    for f in faces:
        ns = int(contains_xy(f, sea_pts[:, 0], sea_pts[:, 1]).sum()) if len(sea_pts) else 0
        nl = int(contains_xy(f, land_pts[:, 0], land_pts[:, 1]).sum()) if len(land_pts) else 0
        if ns > nl:
            sea.append(f)
    return unary_union(sea).buffer(0) if sea else Polygon()


def osm_water(area):
    """Wasserflächen (natural=water, waterway=riverbank) als eine Fläche in LV95 (bzw. crs des Gebiets); dazu das Meer
    aus den Küstenlinien (osm_sea), wenn overpass.json natural=coastline enthält."""
    tr = to_proj(area)
    polys = []
    els = osm_elements(area)
    sea = osm_sea(area, els)
    if not sea.is_empty:
        polys.append(sea)
    for el in els:
        t = el.get("tags", {})
        if not (t.get("natural") == "water" or t.get("waterway") == "riverbank"):
            continue
        if el["type"] == "way" and "geometry" in el:
            pts = _xy(el["geometry"], tr)
            if len(pts) >= 4 and pts[0] == pts[-1]:
                polys.append(Polygon(pts).buffer(0))
        elif el["type"] == "relation":
            outer = [_xy(m["geometry"], tr) for m in el.get("members", [])
                     if m.get("role") == "outer" and "geometry" in m]
            inner = [_xy(m["geometry"], tr) for m in el.get("members", [])
                     if m.get("role") == "inner" and "geometry" in m]
            o = unary_union(_rings(outer)) if outer else None
            if o is None or o.is_empty:
                continue
            if inner:
                o = o.difference(unary_union(_rings(inner)))
            polys.append(o.buffer(0))
    return unary_union(polys)


def osm_obstacles(area):
    """Hindernisse im Wasser, von denen die Strecke Abstand hält: Stege/Anlegestellen (man_made=pier),
    Brückenpfeiler (bridge:support) und Fähranleger. Liefert {Art: [Geometrien LV95]}."""
    out = {"pier": [], "bridge_support": [], "ferry_terminal": [], "bridge": []}
    tr = to_proj(area)
    for el in osm_elements(area):
        t = el.get("tags", {})
        if el["type"] == "node":
            g = Point(tr.transform(el["lon"], el["lat"]))
        elif el["type"] == "way" and "geometry" in el:
            pts = _xy(el["geometry"], tr)
            if len(pts) < 2:
                continue
            closed = len(pts) >= 4 and pts[0] == pts[-1]
            g = Polygon(pts).buffer(0) if closed and t.get("area") != "no" and t.get("highway") is None \
                and t.get("railway") is None else LineString(pts)
        else:
            continue
        if t.get("man_made") == "pier":
            out["pier"].append(g)
        elif "bridge:support" in t:
            out["bridge_support"].append(g)
        elif t.get("amenity") == "ferry_terminal":
            out["ferry_terminal"].append(g)
        elif t.get("man_made") == "bridge" or (t.get("bridge") not in (None, "no") and
                                                (t.get("highway") or t.get("railway"))):
            out["bridge"].append(g)
    return out
