"""Schritt 3 (Variante): Gebäude aus Grundrissen extrudieren, wo es kein LoD2 gibt (Gebietsfeld "buildings_source":
"footprints"; Ersatz für buildings.py).

Eingabe: <data_dir>/footprints/footprints.geojson (fetch_world.py: OpenStreetMap, ArcGIS-Dienst oder Datei, Umrisse im
Gebietssystem mit den Feldern height, levels, roof_shape, kind), build/<gebiet>/dem_core.tif (prepare.py) und das
Oberflächenmodell <data_dir>/bdom/*.tif (optional, 1 m).

Ergebnis im selben Format wie buildings.py, damit bake.py, trees.py und export.py unverändert laufen:
  build/<gebiet>/buildings_fp_<E>-<N>.npz  (je km-Kachel des Grundriss-Schwerpunkts)
  mit roof_v, roof_f, wall_v, wall_f (Ecken E, N, H im Gebietssystem, float64; Dreiecke int64, nach aussen bzw. oben
  orientiert), bid_roof, bid_wall (Gebäude-Nr. je Dreieck, int32) und centers (cx, cy, zmin, zmax je Gebäude)
  build/<gebiet>/buildings_fp_stats.json   woher die Höhen stammen, Dachformen, Zahl der Gebäude

Höhe je Gebäude, in dieser Reihenfolge:
  a) Attribut height (auch "12 m", "40'"), HAUTEUR/ALTURA usw. über die Feldzuordnung in fetch_world.py, sonst
     building:levels × 3 m (+ 1,5 m bei Steildach); passt ein Satteldach ans Oberflächenmodell, gilt bei blosser
     Geschosszahl dessen Höhe (genauer als 3 m je Geschoss)
  b) Oberflächen- minus Geländemodell im Grundriss (1 m nach innen geschrumpft, damit Nachbarn und Bäume am Rand nicht
     zählen): 90. Perzentil (Steildach: First) bzw. 80. Perzentil (Flachdach); Bäume, die in den Grundriss ragen,
     heben das Perzentil nur, wenn sie mehr als ein Fünftel der Fläche decken
  c) sonst Voreinstellung je Gebäudeart (Haus 7,5 m, Garage/Schuppen 3 m, sonst 9 m)
Grundhöhe: 10. Perzentil des Geländemodells im Grundriss − 0,2 m (Wände reichen etwas in den Boden).

Dach: flach, ausser bei kleinen, fast rechteckigen Grundrissen (≤ 350 m², Fläche ≥ 75 % des kleinsten umschliessenden
Rechtecks, ohne Innenhof): dort wird ein Satteldach an das Oberflächenmodell angepasst – z = Traufe + s · (b/2 − |d|)
für beide Firstrichtungen (längs/quer des Rechtecks), d = Abstand zur Mittellinie; gewählt wird die Richtung mit dem
kleineren Fehler, wenn die Neigung 20–55° beträgt und das Modell die Streuung deutlich erklärt (R² ≥ 0,35). Ohne
Oberflächenmodell: Satteldach mit 40° längs, wenn roof:shape gabled/hipped/… oder die Art ein Wohnhaus ist und die Traufe
mindestens 2,5 m hoch bleibt. Walmdächer werden als Satteldach gezeichnet.

Danach (wie buildings.py) mit "drop_buildings_over_water": Gebäude über dem Wasser entfernen.

Aufruf: .venv/bin/python buildings_footprints.py areas/<gebiet>.json
"""
import json
import math
import re
import sys
from collections import Counter
from pathlib import Path

import numpy as np
import rasterio
from rasterio.features import rasterize
from rasterio.windows import from_bounds
from shapely.geometry import LineString, Polygon, shape
from shapely.geometry.polygon import orient
from shapely.ops import split

from buildings import drop_over_water, triangulate
from geofetch import Grid, _mosaic_into

STOREY = 3.0
DEFAULT_H = {"house": 7.5, "detached": 7.5, "semidetached_house": 7.5, "terrace": 8.0, "residential": 9.0,
             "garage": 2.8, "garages": 2.8, "shed": 2.6, "hut": 2.6, "carport": 2.6, "kiosk": 3.0,
             "boathouse": 6.0, "church": 16.0, "cathedral": 25.0, "college": 13.0, "university": 13.0,
             "apartments": 12.0, "commercial": 10.0, "industrial": 8.0, "retail": 6.0}
PITCHED_KINDS = {"house", "detached", "semidetached_house", "terrace", "bungalow", "farm", "boathouse", "hut",
                 "cabin", "church", "chapel"}
PITCHED_SHAPES = {"gabled", "hipped", "half-hipped", "side_hipped", "gambrel", "mansard", "saltbox", "pyramidal"}


def parse_height(v):
    if v in (None, ""):
        return None
    if isinstance(v, (int, float)):
        return float(v) if v > 0 else None
    s = str(v).strip().replace(",", ".")
    m = re.match(r"^([\d.]+)\s*(m|ft|')?", s)
    if not m:
        return None
    try:
        x = float(m.group(1))
    except ValueError:
        return None
    return x * 0.3048 if m.group(2) in ("ft", "'") else x


def sample(arr, tr, poly, shrink=0.0):
    """Werte eines Rasters im (geschrumpften) Polygon; (Werte, Pixel-Mittelpunkte E, N)."""
    g = poly.buffer(-shrink) if shrink else poly
    if g.is_empty or g.area < 3:
        g = poly
    e0, n0, e1, n1 = g.bounds
    c0 = max(int((e0 - tr.c) / tr.a) - 1, 0)
    c1 = min(int((e1 - tr.c) / tr.a) + 2, arr.shape[1])
    r0 = max(int((n1 - tr.f) / tr.e) - 1, 0)
    r1 = min(int((n0 - tr.f) / tr.e) + 2, arr.shape[0])
    if c1 <= c0 or r1 <= r0:
        return np.zeros(0), np.zeros(0), np.zeros(0)
    sub_tr = tr * tr.translation(c0, r0)
    m = rasterize([g], out_shape=(r1 - r0, c1 - c0), transform=sub_tr, all_touched=g.area < 30).astype(bool)
    rr, cc = np.nonzero(m)
    v = arr[r0:r1, c0:c1][rr, cc]
    E = sub_tr.c + (cc + 0.5) * sub_tr.a
    N = sub_tr.f + (rr + 0.5) * sub_tr.e
    ok = np.isfinite(v)
    return v[ok], E[ok], N[ok]


def mrr_axes(poly):
    """Kleinstes umschliessendes Rechteck: Mitte, Einheitsvektoren (lang, quer), halbe Länge, halbe Breite."""
    r = poly.minimum_rotated_rectangle
    c = np.array(r.exterior.coords[:4])
    e1, e2 = c[1] - c[0], c[2] - c[1]
    l1, l2 = np.linalg.norm(e1), np.linalg.norm(e2)
    if l1 < l2:
        e1, e2, l1, l2 = e2, e1, l2, l1
    return c.mean(axis=0), e1 / max(l1, 1e-9), e2 / max(l2, 1e-9), l1 / 2, l2 / 2, r.area


def fit_gable(vals, E, N, center, u, v, half_w):
    """Satteldach mit First entlang u: z = a + s·(half_w − |d|), d = Abstand quer (v). (a, s, R², rms) oder None."""
    if len(vals) < 12:
        return None
    d = np.abs((E - center[0]) * v[0] + (N - center[1]) * v[1])
    x = half_w - np.minimum(d, half_w)
    A = np.column_stack([np.ones_like(x), x])
    sol, *_ = np.linalg.lstsq(A, vals, rcond=None)
    pred = A @ sol
    ss = ((vals - vals.mean()) ** 2).sum()
    r2 = 1 - ((vals - pred) ** 2).sum() / max(ss, 1e-9)
    return float(sol[0]), float(sol[1]), float(r2), float(np.sqrt(((vals - pred) ** 2).mean()))


def ring_xy(ring):
    c = np.asarray(ring.coords)[:, :2]
    return c[:-1] if len(c) > 1 and np.allclose(c[0], c[-1]) else c


def add_walls(acc, ring, base, ztop):
    """Wände eines Rings (aussen gegen den Uhrzeigersinn, Höfe im Uhrzeigersinn → Normalen nach aussen)."""
    n = len(ring)
    if n < 3:
        return
    a, b = ring, np.roll(ring, -1, axis=0)
    za, zb = ztop(a), ztop(b)
    keep = np.linalg.norm(b - a, axis=1) > 0.05
    a, b, za, zb = a[keep], b[keep], za[keep], zb[keep]
    m = len(a)
    v = np.empty((4 * m, 3))
    v[0::4, :2], v[0::4, 2] = a, base
    v[1::4, :2], v[1::4, 2] = b, base
    v[2::4, :2], v[2::4, 2] = b, zb
    v[3::4, :2], v[3::4, 2] = a, za
    o = 4 * np.arange(m)[:, None]
    f = np.vstack([np.hstack([o, o + 1, o + 2]), np.hstack([o, o + 2, o + 3])])
    acc.append((v, f))


def roof_tris(acc, poly, zfun):
    """Dachfläche(n) eines Polygons triangulieren (Ecken mit z = zfun(xy)), Normalen nach oben."""
    poly = orient(poly, 1.0)
    rings = [ring_xy(poly.exterior)] + [ring_xy(i) for i in poly.interiors]
    rings3 = [np.column_stack([r, zfun(r)]) for r in rings if len(r) >= 3]
    if not rings3:
        return
    t = triangulate(rings3)
    if t is None:
        return
    v, f = t
    nz = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])[:, 2]
    f[nz < 0] = f[nz < 0][:, [0, 2, 1]]
    acc.append((v, f))


def densify_at_ridge(ring, center, v):
    """Punkte einfügen, wo eine Kante die Firstlinie (d = 0) kreuzt, damit die Giebelspitze in der Wand liegt."""
    out = []
    d = (ring - center) @ v
    for k in range(len(ring)):
        a, b = ring[k], ring[(k + 1) % len(ring)]
        da, db = d[k], d[(k + 1) % len(ring)]
        out.append(a)
        if da * db < 0:
            t = da / (da - db)
            out.append(a + t * (b - a))
    return np.array(out)


def build_one(poly, base, top, gable):
    """Wand- und Dachdreiecke eines Gebäudes. gable = None (flach) oder (center, u, v, half_w, eave, slope)."""
    walls, roofs = [], []
    poly = orient(poly.simplify(0.15, preserve_topology=True), 1.0)
    if poly.is_empty or poly.geom_type != "Polygon":
        return None
    if gable is None:
        zf = lambda p: np.full(len(p), top)  # noqa: E731
        add_walls(walls, ring_xy(poly.exterior), base, zf)
        for i in poly.interiors:
            add_walls(walls, ring_xy(i), base, zf)
        roof_tris(roofs, poly, zf)
    else:
        c, u, v, hw, eave, s = gable
        zf = lambda p: eave + s * (hw - np.minimum(np.abs((p - c) @ v), hw))  # noqa: E731
        ring = densify_at_ridge(ring_xy(poly.exterior), c, v)
        add_walls(walls, ring, base, zf)
        L = 4 * (hw + poly.length)
        ridge = LineString([c - L * u, c + L * u])
        try:
            pieces = list(split(poly, ridge).geoms)
        except Exception:  # noqa: BLE001
            pieces = [poly]
        for pc in pieces:
            if pc.geom_type == "Polygon" and pc.area > 0.05:
                roof_tris(roofs, pc, zf)
    if not roofs:
        return None
    return walls, roofs


def main(area_file):
    from common import load_area
    area = load_area(area_file)
    build = Path("build") / area["id"]
    raw = (Path.cwd() / area["data_dir"]).resolve()
    crs = area["crs"]
    bounds = area.get("buildings_lv95", area["core_lv95"])
    feats = json.loads((raw / "footprints" / "footprints.geojson").read_text())["features"]
    with rasterio.open(build / "dem_core.tif") as s:
        dem, dtr = s.read(1).astype(np.float32), s.transform
    dsm_files = sorted((raw / "bdom").glob("*.tif"))
    if dsm_files:
        g = Grid(tuple(bounds), 1.0, crs)
        dsm, str_ = _mosaic_into(dsm_files, g, resampling=rasterio.enums.Resampling.bilinear), g.transform
    else:
        dsm = None
    for old in build.glob("buildings_fp_*.npz"):
        old.unlink()
    sheets = {}
    stats = Counter()
    e0, n0, e1, n1 = bounds
    for ft in feats:
        p = ft["properties"]
        poly = shape(ft["geometry"])
        if poly.geom_type != "Polygon" or poly.area < 6:
            continue
        cx, cy = poly.centroid.x, poly.centroid.y
        if not (e0 <= cx <= e1 and n0 <= cy <= n1):
            continue
        gv, _, _ = sample(dem, dtr, poly)
        if len(gv) == 0:
            continue
        ground = float(np.percentile(gv, 10))
        base = ground - 0.2
        kind = (p.get("kind") or "yes").lower()
        shape_tag = (p.get("roof_shape") or "").lower()
        h_attr = parse_height(p.get("height"))
        lv = parse_height(p.get("levels"))
        vals = E = N = None
        if dsm is not None:
            vals, E, N = sample(dsm, str_, poly, shrink=1.0)
            vals = vals - ground
        c, u, v, hl, hw, rarea = mrr_axes(poly)
        small_rect = poly.area <= 350 and poly.area / max(rarea, 1e-9) >= 0.75 and not poly.interiors
        gable = None
        top = None
        src = None
        if h_attr:
            top, src = h_attr, "attribut"
        elif lv:
            top, src = lv * STOREY + (1.5 if shape_tag in PITCHED_SHAPES else 0.0), "geschosse"
        if vals is not None and len(vals) >= 4:
            if small_rect and shape_tag != "flat" and len(vals) >= 12:
                best = None
                for uu, vv, hh in ((u, v, hw), (v, u, hl)):
                    fit = fit_gable(vals, E, N, c, uu, vv, hh)
                    if fit and 0.36 <= fit[1] <= 1.43 and fit[2] >= 0.35 and fit[0] >= 2.0:
                        if best is None or fit[3] < best[0][3]:
                            best = (fit, uu, vv, hh)
                if best:
                    (a, s, r2, rms), uu, vv, hh = best
                    if h_attr:  # Attribut height = First, Neigung aus dem Oberflächenmodell (Geschosszahl: DSM)
                        a = max(2.2, top - s * hh)
                    gable = (c, uu, vv, hh, ground + a, s)
                    top = a + s * hh
                    src = "attribut" if h_attr else "oberflaechenmodell"
                    stats["dach_sattel_dsm"] += 1
            if top is None:
                q = np.percentile(vals, 90 if small_rect else 80)
                top, src = float(np.clip(q, 2.5, 150)), "oberflaechenmodell"
        if top is None:
            top, src = DEFAULT_H.get(kind, 9.0 if poly.area > 120 else 4.0), "voreinstellung"
        top = float(np.clip(top, 2.3, 200))
        if gable is None and shape_tag != "flat" and (shape_tag in PITCHED_SHAPES or
                                                       (vals is None and kind in PITCHED_KINDS)) and small_rect:
            s = math.tan(math.radians(40))
            eave = top - s * hw
            if eave >= 2.5:
                gable = (c, u, v, hw, ground + eave, s)
                stats["dach_sattel_attribut"] += 1
        stats[f"hoehe_{src}"] += 1
        res = build_one(poly, base, ground + top, gable)
        if res is None:
            stats["fehler_triangulation"] += 1
            continue
        walls, roofs = res
        key = f"{int(cx // 1000)}-{int(cy // 1000)}"
        sh = sheets.setdefault(key, {"roof": [], "wall": [], "centers": []})
        bid = len(sh["centers"])
        allz = []
        for kind_, parts in (("roof", roofs), ("wall", walls)):
            for vv_, ff_ in parts:
                sh[kind_].append((vv_, ff_, bid))
                allz.append(vv_[:, 2])
        z = np.concatenate(allz)
        sh["centers"].append([cx, cy, float(z.min()), float(z.max())])
        stats["gebaeude"] += 1
    files = []
    for key, sh in sorted(sheets.items()):
        out = {"centers": np.array(sh["centers"], np.float64).reshape(-1, 4)}
        for k in ("roof", "wall"):
            V, F, B, off = [], [], [], 0
            for vv_, ff_, bid in sh[k]:
                V.append(vv_)
                F.append(ff_ + off)
                B.append(np.full(len(ff_), bid, np.int32))
                off += len(vv_)
            out[f"{k}_v"] = np.vstack(V) if V else np.zeros((0, 3))
            out[f"{k}_f"] = np.vstack(F).astype(np.int64) if F else np.zeros((0, 3), np.int64)
            out[f"bid_{k}"] = np.concatenate(B) if B else np.zeros(0, np.int32)
        f = build / f"buildings_fp_{key}.npz"
        np.savez_compressed(f, **out)
        files.append(f)
        print(f"{f.name}: {len(out['centers'])} Gebäude, Dach {len(out['roof_f'])} / Wand {len(out['wall_f'])} "
              f"Dreiecke", flush=True)
    (build / "buildings_fp_stats.json").write_text(json.dumps(dict(stats), indent=1))
    print("Gebäude aus Grundrissen:", json.dumps(dict(stats)), flush=True)
    if area.get("drop_buildings_over_water"):
        drop_over_water(area, build, files)


if __name__ == "__main__":
    main(sys.argv[1])
