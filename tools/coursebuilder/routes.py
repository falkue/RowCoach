"""Schritt 2: Ruderstrecken entlang des Ufers erzeugen.

Jede Strecke folgt der Uferlinie in festem Abstand (offset_m) auf dem See, von einem Startpunkt
Richtung eines Zielpunkts, bis die halbe Länge erreicht ist; dort liegt der Wendepunkt.
Die Rückfahrt ist dieselbe Linie rückwärts (im 3D etwas versetzt, damit sich die Bahnen nicht decken).

Statt dem Ufer zu folgen, kann eine Strecke auch frei auf dem Wasser liegen (Regattastrecke, Querung eines Sees):
  via_lv95       Stützpunkte [[E, N], ...] (crs des Gebiets) vom Start zur Wende; zwei Punkte = gerade Linie
                 (Länge = Abstand, z. B. genau 2000 m), mehr Punkte = Polylinie, mit smooth_m geglättet (Ecken
                 werden zu Bögen, gerade Stücke bleiben gerade). length_m kürzt auf length_m / 2 (Hinweg).
                 offset_m, start_lv95 und toward_lv95 entfallen; Hindernisse werden nicht umfahren, aber
                 route_check.json nennt die Abstände.

Form der Strecke (Feld "shape", Standard "out_and_back"):
  out_and_back   hin, Wende, zurück (length_m = ganze Strecke, Hinweg = length_m / 2)
  one_way        nur hin, ohne Wende (length_m = ganze Strecke); im Training beginnt jede Runde wieder am Start
  loop           geschlossener Rundkurs durch via_lv95 (letzter Punkt = erster Punkt wird ergänzt), kreisförmig
                 geglättet; length_m = ganze Runde; jede Runde schliesst nahtlos an
  one_way und loop gehen nur mit via_lv95. export.py schreibt "turns": 0 und total_m = one_way_m.

Optionale Felder je Strecke (für Flüsse und Strecken nah an der Promenade):
  smooth_m       Fensterbreite der Glättung (gleitender Mittelwert) in m (Standard 120 m wie Zürich)
  avoid          true (Standard bei "water_source": "osm"): Stege/Anlegestellen (man_made=pier), Brückenpfeiler
                 (bridge:support) und Fähranleger aus OSM werden aus der versetzten Wasserfläche ausgeschnitten;
                 die Strecke weicht ihnen in einem Bogen aus
  obstacle_dist_m  Mindestabstand der Linie zu diesen Hindernissen (Standard 20 m; die Glättung kann ihn um
                 wenige Meter unterschreiten, route_check.json nennt den tatsächlichen Wert)
Optionale Felder je Gebiet:
  extra_obstacles_lv95  weitere Hindernisse als Polygone [[[E, N], ...], ...], denen alle Strecken ausweichen
  bridge_piers_lv95     Brückenpfeiler [[E, N], ...] (aus dem Luftbild), nur zur Kontrolle: route_check.json nennt
                        den kleinsten Abstand von Hin- und Rückfahrtlinie (12 m links, wie in der App)
  bridges               Brücken (siehe bridges.py): deren Pfeiler halten Hin- und Rückfahrt frei. Liegt ein Pfeiler
                        näher als 8 m (Mitte) bzw. 6 m (Rand) an einer der beiden Bahnen, verschiebt routes.py die
                        Strecke dort seitlich in einem weichen Bogen (± pier_shift_window_m, Standard 120 m), bis der
                        Rand 8,5 m frei ist – zur Flussmitte hin, ausser die Uferseite braucht weniger Weg und lässt
                        mindestens 22 m zum Ufer. route_check.json nennt die Verschiebung (pier_shifts).
                        Je Strecke: "pier_check_back": false (one_way: nur die Hinfahrt zählt), "pier_edge_min_m"
                        und "pier_center_min_m" (enge Bögen, z. B. Elvet Bridge Durham: 3 / 4,5 m).

Ergebnis: build/<area>/routes.geojson, route_preview.png (Luftbild + Strecken zur Kontrolle) und je Strecke
route_preview_<id>.png (Ausschnitt aus SWISSIMAGE 10 cm mit Brücken, Stegen, Ufer und Abständen) sowie
route_check.json (Abstand zum Ufer, zu Hindernissen und Brücken, Lage von Start und Wende).
"""
import json
import sys
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image, ImageDraw
from rasterio.windows import from_bounds
from shapely.geometry import LineString, Point, Polygon, box, mapping, shape
from shapely.ops import substring, unary_union

from common import load_area, ortho_tile, osm_obstacles


def shore_path(water, offset, start, toward, length, smooth_m=120.0, cut=None):
    inner = water.buffer(-offset, join_style="round").buffer(0)
    if cut is not None:
        inner = inner.difference(cut).buffer(0)
    if inner.geom_type == "MultiPolygon":
        inner = max(inner.geoms, key=lambda g: g.area)
    ring = LineString(inner.exterior.coords)
    L = ring.length
    s0 = ring.project(Point(start))
    s1 = ring.project(Point(toward))
    # Richtung wählen, in der toward schneller erreicht wird
    fwd = (s1 - s0) % L
    direction = 1 if fwd <= L / 2 else -1
    pts = []
    step = 2.0
    for d in np.arange(0, length * 1.15 + step, step):
        s = (s0 + direction * d) % L
        pts.append(ring.interpolate(s).coords[0])
    line = LineString(pts)
    # leicht glätten (gleitender Mittelwert), dann auf 1 m neu abtasten
    xy = np.array(line.coords)
    k = int(round(smooth_m / (2 * step)))
    pad = np.pad(xy, ((k, k), (0, 0)), mode="edge")
    kernel = np.ones(2 * k + 1) / (2 * k + 1)
    sm = np.column_stack([np.convolve(pad[:, 0], kernel, "valid"), np.convolve(pad[:, 1], kernel, "valid")])
    line = LineString(sm)
    line = substring(line, 0, min(length, line.length))
    n = int(line.length) + 1
    return LineString([line.interpolate(i).coords[0] for i in range(n)] + [line.coords[-1]])


def via_path(points, length=None, smooth_m=120.0, closed=False):
    """Strecke durch Stützpunkte (frei auf dem Wasser), geglättet wie shore_path, auf 1 m abgetastet.
    closed=True: Rundkurs, kreisförmig geglättet; Anfang und Ende fallen zusammen."""
    if closed:
        pts = [tuple(p) for p in points]
        if pts[0] != pts[-1]:
            pts.append(pts[0])
        line = LineString(pts)
        if smooth_m > 0:
            step = 2.0
            xy = np.array([line.interpolate(d).coords[0] for d in np.arange(0, line.length, step)])
            k = int(round(smooth_m / (2 * step)))
            pad = np.vstack([xy[-k:], xy, xy[:k]]) if k > 0 else xy
            kernel = np.ones(2 * k + 1) / (2 * k + 1)
            sm = np.column_stack([np.convolve(pad[:, 0], kernel, "valid"), np.convolve(pad[:, 1], kernel, "valid")])
            line = LineString(np.vstack([sm, sm[:1]]))
        n = int(line.length)
        coords = [line.interpolate(i).coords[0] for i in range(n)] + [line.coords[0]]
        return LineString(coords)
    line = LineString(points)
    if len(points) > 2 and smooth_m > 0:
        step = 2.0
        xy = np.array([line.interpolate(d).coords[0] for d in np.arange(0, line.length, step)] + [points[-1]])
        k = int(round(smooth_m / (2 * step)))
        # Enden gerade verlängern statt festhalten, damit Start und Ende auf der Linie bleiben
        a = xy[0] + (xy[0] - xy[1]) * np.arange(k, 0, -1)[:, None]
        b = xy[-1] + (xy[-1] - xy[-2]) * np.arange(1, k + 1)[:, None]
        pad = np.vstack([a, xy, b])
        kernel = np.ones(2 * k + 1) / (2 * k + 1)
        line = LineString(np.column_stack([np.convolve(pad[:, 0], kernel, "valid"),
                                           np.convolve(pad[:, 1], kernel, "valid")]))
    if length is not None:
        line = substring(line, 0, min(length, line.length))
    n = int(line.length) + 1
    return LineString([line.interpolate(min(i, line.length)).coords[0] for i in range(n)] + [line.coords[-1]])


PIER_CENTER_MIN, PIER_EDGE_MIN, PIER_EDGE_TARGET, SHORE_MIN = 8.0, 6.0, 8.5, 22.0


def _lane_dists(fp, out, back):
    return (min(out.distance(fp.centroid), back.distance(fp.centroid)), min(out.distance(fp), back.distance(fp)))


def shift_for_piers(line, piers, water, length, window=120.0, back_off=12.0, center_min=PIER_CENTER_MIN,
                    edge_min=PIER_EDGE_MIN, edge_target=PIER_EDGE_TARGET):
    """Strecke seitlich verschieben, wo ein Brückenpfeiler zu nahe an Hin- oder Rückfahrt liegt. back_off=0: nur
    die Hinfahrt zählt (one_way mit "pier_check_back": false, z. B. enge Bögen der Elvet Bridge in Durham)."""
    shifts = []
    shore = water.boundary
    for _ in range(3):
        back = line.parallel_offset(back_off, "left") if back_off else line
        bad = [fp for fp in piers if line.distance(fp) < 60 and
               (lambda d: d[0] < center_min or d[1] < edge_min)(_lane_dists(fp, line, back))]
        if not bad:
            break
        xy = np.array(line.coords)
        keep = np.r_[True, np.linalg.norm(np.diff(xy, axis=0), axis=1) > 1e-6]
        xy = xy[keep]
        seg = np.diff(xy, axis=0)
        cum = np.r_[0, np.cumsum(np.linalg.norm(seg, axis=1))]
        t = np.vstack([seg[:1], seg[:-1] + seg[1:], seg[-1:]])
        t /= np.linalg.norm(t, axis=1, keepdims=True)
        nl = np.column_stack([-t[:, 1], t[:, 0]])  # links = Seite der Rückfahrt
        off = np.zeros(len(xy))
        for fp in bad:
            c = np.array(fp.centroid.coords[0])
            s0 = line.project(fp.centroid)
            i = int(np.clip(np.searchsorted(cum, s0), 0, len(xy) - 1))
            lat = float((c - xy[i]) @ nl[i])
            hw = max(abs(float((np.array(v) - c) @ nl[i])) for v in fp.exterior.coords)
            opts = [lat - hw - edge_target - back_off, lat + hw + edge_target]  # Pfeiler links / rechts

            def shore_ok(d):
                return min(shore.distance(Point(xy[i] + nl[i] * (d + k))) for k in (0.0, back_off)) >= SHORE_MIN

            ok = [d for d in opts if shore_ok(d)] or opts
            d = min(ok, key=abs)
            w = np.where(np.abs(cum - s0) < window, 0.5 * (1 + np.cos(np.pi * (cum - s0) / window)), 0.0)
            off += d * w
            shifts.append({"pier_lv95": [round(v) for v in c], "at_m": round(s0), "shift_m": round(d, 1)})
        line = LineString(xy + nl * off[:, None])
        line = substring(line, 0, min(length, line.length))
    return line, shifts


def obstacles_for(area, water):
    if area.get("water_source") != "osm":
        return None, {}
    obs = osm_obstacles(area)
    parts = []
    for kind in ("pier", "bridge_support", "ferry_terminal"):
        for g in obs[kind]:
            gg = g.buffer(5.0 if g.geom_type == "Point" else 1.5)
            if gg.intersects(water):
                parts.append(gg)
    for poly in area.get("extra_obstacles_lv95", []):
        parts.append(Polygon(poly))
    return (unary_union(parts) if parts else None), obs


def check_route(line, water, obstacles, obs, offset, piers=()):
    """Kennzahlen zur Kontrolle: Abstand zum Ufer, zu Hindernissen, Brücken nahe Start/Wende."""
    pts = [Point(c) for c in line.coords[::5]]
    back = line.parallel_offset(12, "left")
    shore = water.boundary
    d_shore = np.array([shore.distance(p) for p in pts])
    res = {"one_way_m": round(line.length, 1),
           "shore_dist_m": {"min": round(float(d_shore.min()), 1), "p10": round(float(np.percentile(d_shore, 10)), 1),
                            "median": round(float(np.median(d_shore)), 1),
                            "p90": round(float(np.percentile(d_shore, 90)), 1)}}
    if obstacles is not None:
        res["obstacle_min_dist_m"] = round(min(obstacles.distance(p) for p in pts), 1)
        res["obstacle_min_dist_back_m"] = round(min(obstacles.distance(Point(c)) for c in back.coords[::5]), 1)
    bridges = unary_union(obs.get("bridge", [])) if obs.get("bridge") else None
    if bridges is not None:
        a, b = Point(line.coords[0]), Point(line.coords[-1])
        res["bridge_dist_start_m"] = round(bridges.distance(a), 1)
        res["bridge_dist_turn_m"] = round(bridges.distance(b), 1)
        crossings = [g for g in obs["bridge"] if g.intersects(line)]
        res["bridges_crossed"] = len(crossings)
    if piers:
        res["pier_min_dist_out_m"] = round(min(line.distance(Point(p)) for p in piers), 1)
        res["pier_min_dist_back_m"] = round(min(back.distance(Point(p)) for p in piers), 1)
    d_back = np.array([shore.distance(Point(c)) for c in back.coords[::5]])
    res["shore_dist_back_m"] = {"min": round(float(d_back.min()), 1), "median": round(float(np.median(d_back)), 1)}
    res["start_lv95"] = [round(c) for c in line.coords[0]]
    res["turn_lv95"] = [round(c) for c in line.coords[-1]]
    return res


def detail_preview(area, out, rid, line, water, obs, obstacles, piers=()):
    """Ausschnitt um eine Strecke aus SWISSIMAGE 10 cm (auf ~0,4 m/px), mit Ufer, Hindernissen und Brücken."""
    from rasterio.merge import merge
    raw = (Path.cwd() / area["data_dir"]).resolve()
    e0, n0, e1, n1 = line.buffer(160).bounds
    res = max((e1 - e0), (n1 - n0)) / 3000.0
    res = max(res, 0.25)
    files = []
    for te in range(int(e0 // 1000), int(e1 // 1000) + 1):
        for tn in range(int(n0 // 1000), int(n1 // 1000) + 1):
            tp = ortho_tile(raw / "image_core", te, tn)
            files += [tp] if tp is not None else []
    if not files:
        return
    srcs = [rasterio.open(f) for f in files]
    img, _ = merge(srcs, bounds=(e0, n0, e1, n1), res=res, indexes=[1, 2, 3])
    for s_ in srcs:
        s_.close()
    im = Image.fromarray(np.moveaxis(img, 0, -1)).convert("RGB")
    px = lambda c: ((c[0] - e0) / res, (n1 - c[1]) / res)
    dr = ImageDraw.Draw(im)
    clip = box(e0, n0, e1, n1)

    def draw(g, col, w):
        if g.is_empty:
            return
        if g.geom_type in ("Polygon",):
            dr.line([px(c) for c in g.exterior.coords], fill=col, width=w)
            for ring in g.interiors:
                dr.line([px(c) for c in ring.coords], fill=col, width=w)
        elif g.geom_type in ("LineString", "LinearRing"):
            dr.line([px(c) for c in g.coords], fill=col, width=w)
        elif g.geom_type == "Point":
            x, y = px(g.coords[0]); dr.ellipse([x - 6, y - 6, x + 6, y + 6], outline=col, width=w)
        elif hasattr(g, "geoms"):
            for gg in g.geoms:
                draw(gg, col, w)

    draw(water.intersection(clip), (0, 200, 255), 2)
    for g in obs.get("bridge", []):
        draw(g.intersection(clip), (255, 0, 255), 3)
    if obstacles is not None:
        draw(obstacles.intersection(clip), (255, 140, 0), 3)
    for pp in area.get("bridge_piers_lv95", []):
        draw(Point(pp).buffer(3), (255, 0, 0), 3)
    for fp in piers:  # Pfeiler der Brücken (bridges.py)
        draw(fp.intersection(clip), (255, 0, 0), 3)
    back = line.parallel_offset(12, "left")  # Rückfahrt (App: 12 m links der Hinfahrt)
    draw(back, (255, 255, 120), 2)
    draw(line, (255, 40, 40), 4)
    a, b = px(line.coords[0]), px(line.coords[-1])
    dr.ellipse([a[0] - 10, a[1] - 10, a[0] + 10, a[1] + 10], fill=(255, 255, 255), outline=(0, 0, 0))
    dr.ellipse([b[0] - 10, b[1] - 10, b[0] + 10, b[1] + 10], fill=(255, 40, 40), outline=(0, 0, 0))
    dr.text((a[0] + 14, a[1] - 8), "Start", fill=(255, 255, 255))
    dr.text((b[0] + 14, b[1] - 8), "Wende", fill=(255, 255, 255))
    # Massstab 100 m
    dr.rectangle([20, im.height - 40, 20 + 100 / res, im.height - 32], fill=(255, 255, 255))
    dr.text((20, im.height - 28), "100 m", fill=(255, 255, 255))
    im.save(out / f"route_preview_{rid}.png")


def main(area_file):
    area = load_area(area_file)
    out = Path("build") / area["id"]
    water = shape(json.loads((out / "water.geojson").read_text())["geometry"])
    obstacles, obs = obstacles_for(area, water)
    feats = []
    checks = {}
    piers = []
    if area.get("bridges"):
        from bridges import pier_footprints
        piers = pier_footprints(area)
    for r in area["routes"]:
        route_shape = r.get("shape", "out_and_back")
        assert route_shape in ("out_and_back", "one_way", "loop"), f"{r['id']}: unbekannte Form {route_shape}"
        assert route_shape == "out_and_back" or "via_lv95" in r, f"{r['id']}: {route_shape} braucht via_lv95"
        half = r.get("length_m", 0) / (2 if route_shape == "out_and_back" else 1)
        cut = None
        if obstacles is not None and r.get("avoid", True):
            cut = obstacles.buffer(r.get("obstacle_dist_m", 20.0))
        if "via_lv95" in r:
            line = via_path(r["via_lv95"], half if "length_m" in r and route_shape != "loop" else None,
                            r.get("smooth_m", 120.0), closed=route_shape == "loop")
            half = line.length
        else:
            line = shore_path(water, r["offset_m"], r["start_lv95"], r["toward_lv95"], half,
                              r.get("smooth_m", 120.0), cut=cut)
        shifts = []
        if piers:
            kw = {}
            if r.get("pier_check_back") is False:
                kw["back_off"] = 0.0
            if "pier_edge_min_m" in r:   # enge Bögen: kleinere Abstände je Strecke
                kw.update(edge_min=r["pier_edge_min_m"], edge_target=r["pier_edge_min_m"] + 0.5,
                          center_min=r.get("pier_center_min_m", r["pier_edge_min_m"] + 1.5))
            line, shifts = shift_for_piers(line, piers, water, half, r.get("pier_shift_window_m", 120.0), **kw)
            n = int(line.length) + 1
            line = LineString([line.interpolate(i).coords[0] for i in range(n)] + [line.coords[-1]])
            for sh in shifts:
                print(f"  Pfeiler {sh['pier_lv95']}: Strecke bei {sh['at_m']} m um {sh['shift_m']} m verschoben")
        feats.append({"type": "Feature", "properties": {"id": r["id"], "title": r["title"],
                      "shape": route_shape, "one_way_m": round(line.length, 1),
                      "total_m": round((2 if route_shape == "out_and_back" else 1) * line.length, 1)},
                      "geometry": mapping(line)})
        print(f"{r['id']}: {line.length:.0f} m hin, Wende bei {tuple(round(c) for c in line.coords[-1])}")
        if area.get("water_source") == "osm":
            checks[r["id"]] = check_route(line, water, obstacles, obs, r.get("offset_m", 0),
                                          area.get("bridge_piers_lv95", []))
            if piers:
                back = line.parallel_offset(12, "left")
                near = [fp for fp in piers if line.distance(fp) < 60]
                if near:
                    checks[r["id"]]["bridge_pier_center_min_m"] = round(min(_lane_dists(fp, line, back)[0]
                                                                            for fp in near), 1)
                    checks[r["id"]]["bridge_pier_edge_min_m"] = round(min(_lane_dists(fp, line, back)[1]
                                                                          for fp in near), 1)
                checks[r["id"]]["pier_shifts"] = shifts
            print("  ", json.dumps(checks[r["id"]]))
            detail_preview(area, out, r["id"], line, water, obs, obstacles, piers)
    (out / "routes.geojson").write_text(json.dumps({"type": "FeatureCollection", "features": feats}))
    if checks:
        (out / "route_check.json").write_text(json.dumps(checks, indent=1))

    # Vorschau
    e0, n0, e1, n1 = area["core_lv95"]
    with rasterio.open(out / "ortho_far.tif") as src:
        win = from_bounds(e0, n0, e1, n1, src.transform)
        img = src.read([1, 2, 3], window=win)
    im = Image.fromarray(np.moveaxis(img, 0, -1)).convert("RGB")
    sx = im.width / (e1 - e0)
    sy = im.height / (n1 - n0)
    px = lambda c: ((c[0] - e0) * sx, (n1 - c[1]) * sy)
    dr = ImageDraw.Draw(im)
    polys = water.geoms if water.geom_type == "MultiPolygon" else [water]
    for p in polys:
        dr.line([px(c) for c in p.exterior.coords], fill=(0, 200, 255), width=2)
    colors = [(255, 60, 60), (255, 220, 0), (60, 255, 60)]
    for f, col in zip(feats, colors):
        cs = f["geometry"]["coordinates"]
        dr.line([px(c) for c in cs], fill=col, width=5)
        a, b = px(cs[0]), px(cs[-1])
        dr.ellipse([a[0] - 9, a[1] - 9, a[0] + 9, a[1] + 9], fill=(255, 255, 255))
        dr.ellipse([b[0] - 9, b[1] - 9, b[0] + 9, b[1] + 9], fill=col, outline=(0, 0, 0))
        dr.text((a[0] + 12, a[1] - 8), f["properties"]["title"], fill=(255, 255, 255))
    im.save(out / "route_preview.png")
    print("Vorschau:", out / "route_preview.png")


if __name__ == "__main__":
    main(sys.argv[1])
