"""Gemeinsame Helfer für den coursebuilder (Gebietsdatei laden, OpenStreetMap-Daten lesen).

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

def _xy(geom):
    lon = np.array([p["lon"] for p in geom])
    lat = np.array([p["lat"] for p in geom])
    e, n = TO_LV95.transform(lon, lat)
    return list(zip(e, n))


def _rings(lines):
    merged = linemerge([LineString(l) for l in lines if len(l) >= 2])
    return [p for p in polygonize(merged)]


def osm_elements(area):
    f = raw_dir(area) / "osm" / "overpass.json"
    return json.loads(f.read_text())["elements"]


def osm_water(area):
    """Wasserflächen (natural=water, waterway=riverbank) als eine Fläche in LV95."""
    polys = []
    for el in osm_elements(area):
        t = el.get("tags", {})
        if not (t.get("natural") == "water" or t.get("waterway") == "riverbank"):
            continue
        if el["type"] == "way" and "geometry" in el:
            pts = _xy(el["geometry"])
            if len(pts) >= 4 and pts[0] == pts[-1]:
                polys.append(Polygon(pts).buffer(0))
        elif el["type"] == "relation":
            outer = [_xy(m["geometry"]) for m in el.get("members", []) if m.get("role") == "outer" and "geometry" in m]
            inner = [_xy(m["geometry"]) for m in el.get("members", []) if m.get("role") == "inner" and "geometry" in m]
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
    for el in osm_elements(area):
        t = el.get("tags", {})
        if el["type"] == "node":
            g = Point(TO_LV95.transform(el["lon"], el["lat"]))
        elif el["type"] == "way" and "geometry" in el:
            pts = _xy(el["geometry"])
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
