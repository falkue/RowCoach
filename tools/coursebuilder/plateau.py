"""Gebäude aus Project PLATEAU (Japan, 3D-Stadtmodelle des MLIT, CityGML 2.0) holen und triangulieren.

Ersetzt für japanische Gebiete buildings.py: liest die Stadt-ZIPs (G-Space Center / PLATEAU-CMS, HTTP-Range) nur
für die Gebäudedateien udx/bldg/<Netzcode>_bldg_6697_*.gml, deren Netzmasche (JIS X 0410, 1-km-Masche = 8 Ziffern)
das Gebäudegebiet berührt, und schreibt dasselbe npz-Format wie buildings.py:
  build/<gebiet>/buildings_<netzcode>.npz  mit roof_v, roof_f, wall_v, wall_f, bid_roof, bid_wall, centers
Koordinaten: PLATEAU liefert EPSG:6697 (JGD2011 geographisch + Höhe T.P., Achsen Breite, Länge, Höhe); umgerechnet
in das UTM-System des Gebiets ("crs", z. B. EPSG:6691 für Tokio). Die Höhen (T.P.) passen zum GSI-Höhenmodell.

Detailstufe je Gebäude: LoD2 (bldg:boundedBy → RoofSurface/WallSurface → lod2MultiSurface, auch in
BuildingParts), sonst LoD1 (lod1Solid, Flächen nach der Normalen: oben = Dach, senkrecht = Wand, unten weg).
LoD3 (Fenster, Türen; z. B. Sumida) wird nicht gelesen. "plateau": {"lod2_max_dist_m": 700} nimmt für Gebäude, die
weiter als 700 m von der Strecke (routes.geojson) stehen, LoD1 statt LoD2 (dichte Städte: bake.py braucht sonst zu
viel Speicher); Hochhäuser ab 60 m behalten LoD2.

Gebietsdatei:
  "buildings_source": "plateau",
  "plateau": {"cities": [{"name": "戸田市", "year": 2022, "url": "https://assets.cms.plateau.reearth.io/…_citygml_…zip"},
                         …]}
  (URLs aus der CKAN-API: https://www.geospatial.jp/ckan/api/3/action/package_show?id=plateau-11224-toda-shi-2022,
   Ressource „CityGML“; Namensnennung „出典：国土交通省 3D都市モデル（Project PLATEAU）<Stadt>（<Jahr>年度）“)
  "drop_buildings_over_water": true   wie buildings.py

Rohdaten: <data_dir>/plateau/<stadt-slug>/<netzcode>_bldg_6697_op.gml (mehrere Städte → mehrere Dateien je Masche;
die npz heissen dann buildings_<netzcode>_<k>.npz). Gebäude, die in mehreren Städten vorkommen (Tokios Bezirksdaten
„pref“ enthalten ganze Maschen samt Nachbarbezirken), zählen nur einmal (gml:id).

Brücken: --brid holt die PLATEAU-Brückenmodelle (udx/brid) und nennt je Gebietsbrücke die Höhe der Flächen über
dem Wasser (nach prepare.py; Vorschlag für deck_m, wo es kein Oberflächenmodell gibt).

Aufruf: .venv/bin/python plateau.py areas/<gebiet>.json [--fetch-only | --brid]
"""
import io
import json
import re
import shutil
import sys
import time
import zipfile
from pathlib import Path

import numpy as np
from lxml import etree
from pyproj import Transformer
from shapely.geometry import Point

from buildings import drop_over_water, free, parse_poslist, triangulate
from fetch_tlm import HttpFile

BLDG_NS = "http://www.opengis.net/citygml/building/2.0"
GML_NS = "http://www.opengis.net/gml"
Q = lambda t: "{%s}%s" % (BLDG_NS, t)  # noqa: E731
SURF = {Q("RoofSurface"): "roof", Q("WallSurface"): "wall"}


def mesh_bounds(code):
    """Netzcode (6, 8 oder 9 Ziffern) → (lon0, lat0, lon1, lat1)."""
    p, u = int(code[0:2]), int(code[2:4])
    lat, lon, dlat, dlon = p / 1.5, u + 100.0, 2 / 3, 1.0
    if len(code) >= 6:
        q, v = int(code[4]), int(code[5])
        dlat, dlon = dlat / 8, dlon / 8
        lat, lon = lat + q * dlat, lon + v * dlon
    if len(code) >= 8:
        r, w = int(code[6]), int(code[7])
        dlat, dlon = dlat / 10, dlon / 10
        lat, lon = lat + r * dlat, lon + w * dlon
    if len(code) >= 9:
        m = int(code[8]) - 1
        dlat, dlon = dlat / 2, dlon / 2
        lat, lon = lat + (m // 2) * dlat, lon + (m % 2) * dlon
    return lon, lat, lon + dlon, lat + dlat


def slug(city):
    return re.sub(r"[^a-z0-9]+", "-", Path(city["url"]).name.lower().split("_city")[0].split("_pref")[0]
                  .split("_20")[0]).strip("-")


def fetch(area, root, kind="bldg"):
    """Gebäude- (kind "bldg") bzw. Brückendateien ("brid") der Maschen im Gebäudegebiet per HTTP-Range aus den
    Stadt-ZIPs entpacken."""
    to_ll = Transformer.from_crs(area["crs"], "EPSG:4326", always_xy=True)
    e0, n0, e1, n1 = area.get("buildings_lv95", area["core_lv95"])
    xs, ys = to_ll.transform([e0, e1, e0, e1], [n0, n0, n1, n1])
    lon0, lat0, lon1, lat1 = min(xs), min(ys), max(xs), max(ys)
    files = []
    for city in area["plateau"]["cities"]:
        d = root / "plateau" / slug(city)
        if kind != "bldg":
            d = d / kind
        idx_f = d / ("index.json" if kind == "bldg" else f"index-{kind}.json")
        if idx_f.exists() and json.loads(idx_f.read_text()).get("_url") == city["url"]:
            idx = json.loads(idx_f.read_text())
        else:
            z = zipfile.ZipFile(io.BufferedReader(HttpFile(city["url"]), 1 << 16))
            idx = {"_url": city["url"], "members": [i.filename for i in z.infolist()
                                                    if re.search(rf"udx/{kind}/\d+_{kind}_6697.*\.gml$", i.filename)]}
            d.mkdir(parents=True, exist_ok=True)
            idx_f.write_text(json.dumps(idx, indent=0, ensure_ascii=False))
        want = []
        for m in idx["members"]:
            code = Path(m).name.split("_")[0]
            b = mesh_bounds(code)
            if b[0] < lon1 and b[2] > lon0 and b[1] < lat1 and b[3] > lat0:
                want.append(m)
        print(f"{city['name']} ({city['year']}): {len(want)} von {len(idx['members'])} {kind}-Dateien im Gebiet",
              flush=True)
        todo = [m for m in want if not (d / Path(m).name).exists()]
        if todo:
            zz = zipfile.ZipFile(io.BufferedReader(HttpFile(city["url"]), buffer_size=8 << 20))
            d.mkdir(parents=True, exist_ok=True)
            for m in todo:
                dest = d / Path(m).name
                tmp = dest.with_name(dest.name + ".part")
                with zz.open(m) as src, open(tmp, "wb") as dst:
                    shutil.copyfileobj(src, dst, 4 << 20)
                tmp.rename(dest)
                print(f"  {dest.name}: {dest.stat().st_size / 1e6:.1f} MB", flush=True)
                time.sleep(0.2)
        files += [d / Path(m).name for m in want]
    return files


def rings_of(poly, tr):
    rings = []
    for rp in poly:
        pl = rp.find(".//{%s}posList" % GML_NS)
        if pl is None:
            continue
        p = parse_poslist(pl)  # (lat, lon, h)
        if len(p) < 3:
            continue
        e, n = tr.transform(p[:, 1], p[:, 0])
        rings.append(np.column_stack([e, n, p[:, 2]]))
    return rings


def convert(gml, area, out, seen_ids=None):
    """Eine PLATEAU-Gebäudedatei → npz wie buildings.py. LoD2-Flächen, sonst LoD1-Volumen."""
    tr = Transformer.from_crs("EPSG:6697", area["crs"], always_xy=True)
    e0, n0, e1, n1 = area.get("buildings_lv95", area["core_lv95"])
    acc = {k: {"v": [], "f": [], "bid": [], "off": 0} for k in ("roof", "wall")}
    centers, n_lod = [], {1: 0, 2: 0}
    far_m = area.get("plateau", {}).get("lod2_max_dist_m")
    far_line = None
    rf = Path("build") / area["id"] / "routes.geojson"
    if far_m and rf.exists():
        from shapely.geometry import shape
        from shapely.ops import unary_union
        far_line = unary_union([shape(f["geometry"]) for f in json.loads(rf.read_text())["features"]])

    def add(kind, rings, bid, pts_all):
        t = triangulate(rings)
        if t is None:
            return
        v, f = t
        a = acc[kind]
        a["v"].append(v); a["f"].append(f + a["off"]); a["bid"].append(np.full(len(f), bid, np.int32))
        a["off"] += len(v)
        pts_all.append(v)

    for _, b in etree.iterparse(str(gml), events=("end",), tag=Q("Building"), huge_tree=True):
        if b.getparent() is not None and etree.QName(b.getparent()).localname != "cityObjectMember":
            continue  # nur Gebäude der obersten Ebene (BuildingParts liegen darin)
        gid = b.get("{%s}id" % GML_NS)
        if seen_ids is not None and gid:
            if gid in seen_ids:  # die "pref"-Datensätze Tokios enthalten ganze Maschen, auch Nachbarbezirke
                free(b)
                continue
            seen_ids.add(gid)
        bid = len(centers)
        pts_all = []
        lod2 = [(SURF[s.tag], ms) for s in b.iter(*SURF) for ms in s.findall(Q("lod2MultiSurface"))]
        if lod2 and far_line is not None:  # weit weg von der Strecke: LoD1 genügt (viel weniger Dreiecke)
            pl = b.find(".//{%s}posList" % GML_NS)
            if pl is not None and next(b.iter(Q("lod1Solid")), None) is not None:
                q = np.array(pl.text.split()[:3], dtype=np.float64)
                e, n = tr.transform(q[1], q[0])
                if far_line.distance(Point(e, n)) > far_m:
                    mh = b.find(Q("measuredHeight"))
                    try:
                        h = float(mh.text) if mh is not None else None
                    except ValueError:
                        h = None
                    if h is None:  # ohne Attribut: Höhe der LoD2-Flächen
                        zs = [float(v) for _, ms in lod2 for pl1 in ms.iter("{%s}posList" % GML_NS)
                              for v in pl1.text.split()[2::3]]
                        h = max(zs) - min(zs) if zs else 0.0
                    if h < 60:  # Hochhäuser und Türme (Skytree) behalten ihre Form
                        lod2 = []
        if lod2:
            for kind, ms in lod2:
                for poly in ms.iter("{%s}Polygon" % GML_NS):
                    rings = rings_of(poly, tr)
                    if rings:
                        add(kind, rings, bid, pts_all)
            lod = 2
        else:
            lod = 1
            for solid in b.iter(Q("lod1Solid")):
                for poly in solid.iter("{%s}Polygon" % GML_NS):
                    rings = rings_of(poly, tr)
                    if not rings:
                        continue
                    ext = rings[0]
                    nrm = np.zeros(3)
                    for p, q in zip(ext, np.roll(ext, -1, axis=0)):
                        nrm += [(p[1] - q[1]) * (p[2] + q[2]), (p[2] - q[2]) * (p[0] + q[0]),
                                (p[0] - q[0]) * (p[1] + q[1])]
                    ln = np.linalg.norm(nrm)
                    if ln < 1e-9:
                        continue
                    nz = nrm[2] / ln
                    if nz > 0.7:
                        add("roof", rings, bid, pts_all)
                    elif abs(nz) < 0.7:
                        add("wall", rings, bid, pts_all)
        if pts_all:
            allp = np.vstack(pts_all)
            c = allp[:, :2].mean(axis=0)
            if e0 <= c[0] <= e1 and n0 <= c[1] <= n1:
                centers.append([*c, allp[:, 2].min(), allp[:, 2].max()])
                n_lod[lod] += 1
            else:  # ausserhalb: Dreiecke dieses Gebäudes wieder verwerfen
                for a in acc.values():
                    while a["bid"] and a["bid"][-1][0] == bid:
                        a["off"] -= len(a["v"].pop()); a["f"].pop(); a["bid"].pop()
        free(b)
    res = {"centers": np.array(centers, dtype=np.float64).reshape(-1, 4)}
    for k, a in acc.items():
        res[f"{k}_v"] = np.vstack(a["v"]) if a["v"] else np.zeros((0, 3))
        res[f"{k}_f"] = np.vstack(a["f"]) if a["f"] else np.zeros((0, 3), np.int64)
        res[f"bid_{k}"] = np.concatenate(a["bid"]) if a["bid"] else np.zeros(0, np.int32)
    np.savez_compressed(out, **res)
    return (f"{gml.parent.name}/{gml.name}: {len(centers)} Gebäude (LoD2 {n_lod[2]}, LoD1 {n_lod[1]}), "
            f"Dach {len(res['roof_f'])} / Wand {len(res['wall_f'])} Dreiecke"), n_lod


def brid_decks(area, root, water_level):
    """Deckhöhen der Gebietsbrücken aus PLATEAU-Brückenmodellen (udx/brid, LoD2/3): je Brücke (OSM-Umriss bzw.
    -Achse) die oberen Flächen über dem Wasser → Höhe über dem Wasserspiegel (Median, 90 %) als Vorschlag für
    deck_m in der Gebietsdatei. Liest nur Koordinaten (Breite, Länge, Höhe), keine Semantik."""
    from shapely.geometry import LineString, Polygon, shape
    from common import _xy, to_proj
    files = fetch(area, root, "brid")
    tr = Transformer.from_crs("EPSG:6697", area["crs"], always_xy=True)
    pts = []
    for g in files:
        for _, pl in etree.iterparse(str(g), events=("end",), tag="{%s}posList" % GML_NS, huge_tree=True):
            p = np.array(pl.text.split(), dtype=np.float64).reshape(-1, 3)
            e, n = tr.transform(p[:, 1], p[:, 0])
            pts.append(np.column_stack([e, n, p[:, 2]]))
            pl.clear()
    P = np.vstack(pts) if pts else np.zeros((0, 3))
    els = {e["id"]: e for e in json.loads((root / "osm" / "overpass.json").read_text())["elements"]}
    water = shape(json.loads((Path("build") / area["id"] / "water.geojson").read_text())["geometry"])
    from shapely import contains_xy
    out = {}
    for b in area.get("bridges", []):
        if "osm_outline" in b:
            zone = Polygon(_xy(els[b["osm_outline"]]["geometry"], to_proj(area)))
        elif "axis_osm_way" in b:
            zone = LineString(_xy(els[b["axis_osm_way"]]["geometry"], to_proj(area))).buffer(b.get("width_m", 20) / 2)
        else:
            zone = LineString(b["axis_lv95"]).buffer(b.get("width_m", 20) / 2)
        zone = zone.intersection(water.buffer(-5))
        if zone.is_empty or not len(P):
            continue
        m = contains_xy(zone, P[:, 0], P[:, 1])
        z = P[m, 2] - water_level
        if len(z) < 10:
            print(f"{b['slug']}: keine PLATEAU-Brückenpunkte über dem Wasser", flush=True)
            continue
        out[b["slug"]] = [round(float(np.percentile(z, 50)), 2), round(float(np.percentile(z, 90)), 2),
                          round(float(z.max()), 2), int(m.sum())]
        print(f"{b['slug']}: Median {out[b['slug']][0]} m, 90 % {out[b['slug']][1]} m, max {out[b['slug']][2]} m "
              f"über dem Wasser ({out[b['slug']][3]} Punkte)", flush=True)
    return out


def main(area_file, fetch_only=False):
    area = json.loads(Path(area_file).read_text())
    root = (Path.cwd() / area["data_dir"]).resolve()
    out = Path("build") / area["id"]
    out.mkdir(parents=True, exist_ok=True)
    files = fetch(area, root)
    if fetch_only:
        return
    for old in out.glob("buildings_*.npz"):
        old.unlink()
    seen, written, tot, ids = {}, [], {1: 0, 2: 0}, set()
    for g in files:  # nacheinander (Speicher), je Datei einige 10 MB
        code = g.name.split("_")[0]
        k = seen.get(code, 0)
        seen[code] = k + 1
        dest = out / (f"buildings_{code}.npz" if k == 0 else f"buildings_{code}_{k}.npz")
        msg, n = convert(g, area, dest, ids)
        tot[1] += n[1]; tot[2] += n[2]
        written.append(dest)
        print(msg, flush=True)
    (out / "buildings_plateau_stats.json").write_text(json.dumps({"files": len(files), "lod2": tot[2],
                                                                  "lod1": tot[1]}, indent=1))
    print(f"PLATEAU: {tot[2]} Gebäude LoD2, {tot[1]} LoD1", flush=True)
    if area.get("drop_buildings_over_water"):
        drop_over_water(area, out, written)


if __name__ == "__main__":
    if "--brid" in sys.argv:
        a = json.loads(Path(sys.argv[1]).read_text())
        lvl = json.loads((Path("build") / a["id"] / "water_meta.json").read_text())["water_level_m"]
        brid_decks(a, (Path.cwd() / a["data_dir"]).resolve(), lvl)
    else:
        main(sys.argv[1], fetch_only="--fetch-only" in sys.argv)
