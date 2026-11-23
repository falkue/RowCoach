"""Schritt 7: Fahrlinien für den Verkehr auf dem Wasser (virtuelle Ruderer und Schiffe) je Strecke.

Liest die fertige course.json (nach export.py und minimap.py) und trägt das optionale Feld `traffic` ein:

  "traffic": {
    "vessels": ["kursschiff", "motorboot", "segelboot"],   # Schiffsarten des Gebiets
    "density": 1.0,                                        # Faktor für die Häufigkeit (1 = normal)
    "rower_lanes": [{"out_m": -16, "back_m": 28}, ...],   # Bahnen der virtuellen Ruderer (seitlicher Versatz, m)
    "vessel_lanes": [                                      # gültige Fahrlinien der Schiffe (Szenenkoordinaten)
      {"id": "p-89", "kind": "parallel", "min_dist_m": 101.0, "shore_m": 41.0, "points_xz": [[x, z], ...]},
      {"id": "x-1", "kind": "cross", "min_dist_m": 0.0, "shore_m": 30.0, "points_xz": [...],
       "cross": [{"s": 812.0, "at": 431.0}]}
    ]
  }

Ruderer-Bahnen (App: RowCoachKit `RowerLane`): Hinfahrt mit Versatz out_m, Rückfahrt mit back_m (positiv = links der
Hinfahrt, Seite der eigenen Rückfahrt), an Wende und Start je ein Halbkreis um ((out_m + back_m) / 2) an der Stelle des
grossen Wendebogens der eigenen Bahn. `choose_rower_lanes` sucht eine Familie konzentrischer Bahnen (um die eigene
Bahn herum, ganz rechts oder ganz links), die überall ROWER_SHORE m vom Ufer, ROWER_OBSTACLE m von Pfeilern, Stegen und
Anlegern und ROWER_OWN m von der eigenen Bahn (samt Wenden) entfernt bleibt; höchstens 3 Bahnen.

Schiffslinien:
- parallel: zur Strecke parallele Linien seitlich, mindestens 25 m ausserhalb der äussersten Ruderer-Bahn
  (damit ≥ 40 m von der eigenen Bahn); `min_dist_m` = kleinster Abstand zu Hin-/Rückfahrt und Wenden. Die App lässt
  grosse Schiffe nur auf Linien mit min_dist_m ≥ 80 fahren, kleine ab 40.
- parallel (Fahrrinne, Kennung c±…): fehlt eine lange Linie für grosse Schiffe (≥ 900 m, ≥ 80 m Abstand), sucht
  `channel_lane` einen Weg mit veränderlichem Seitenabstand durch die Brückenöffnungen (≥ 9 m zu Pfeilern).
- far: gerade Linien parallel zur Sehne Start → Wende, 300–1500 m von der Strecke entfernt („am Horizont“).
- cross: Querlinien über das Gewässer (senkrecht zur Strecke). `cross` nennt, wo die Linie die Hinfahrt kreuzt
  (s = m ab Start der Hinfahrt, at = m ab Linienanfang); die App schickt ein Schiff nur los, wenn es die Bahn
  sicher vor dem eigenen Boot (≥ 300 m) und vor den Ruderern gekreuzt hat.
Alle Linien bleiben im Wasser (Abstand zum Ufer `shore_m`), weg von Pfeilern, Stegen, Anlegern und (cross) Brücken.

Schiffsarten: Feld `traffic` der Gebietsdatei ({"vessels": [...], "density": 1.0}), sonst Voreinstellung je Gebiet
(DEFAULT_VESSELS). Zur Kontrolle: build/<gebiet>/lanes_preview_<strecke>.png (Luftbild, Strecke weiss, Ruderer-Bahnen
gelb, Schiffslinien cyan/blau, Querlinien magenta).

Aufruf (nach export.py und minimap.py; CPU, wenige Sekunden): .venv/bin/python lanes.py areas/<gebiet>.json
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
import rasterio
import shapely
from PIL import Image, ImageDraw
from rasterio.windows import from_bounds
from shapely.geometry import LineString, MultiLineString, Point, shape
from shapely.ops import unary_union

from common import load_area, osm_obstacles

RETURN_OFFSET = 12.0          # wie CourseTrack.returnOffset in der App
TURN_BLEND = 40.0             # wie CourseTrack.turnBlend
ROWER_SHORE = 10.0            # m Mindestabstand der Ruderer-Bahnen zum Ufer
ROWER_OBSTACLE = 6.0          # m zu Pfeilern (Rand), Stegen, Anlegern
ROWER_OWN = 8.0               # m zur eigenen Bahn (Hin-, Rückfahrt, Wenden)
VESSEL_SHORE = {"small": 20.0, "large": 35.0}
VESSEL_OBSTACLE = 15.0
CROSS_BRIDGE_DIST = 40.0
MIN_RUN = 300.0               # m kürzeste brauchbare Linie
EXTEND = 600.0                # m Verlängerung über Start und Wende hinaus

DEFAULT_VESSELS = {
    "zuerichsee-unteres-becken": ["kursschiff", "motorboot", "segelboot"],
    "luzern-seebecken": ["raddampfer", "motorboot", "segelboot"],
    "basel-rheinknie": ["rheinschiff", "faehre", "motorboot"],
    "stein-am-rhein": ["kursschiff", "weidling", "motorboot"],
}


# ----------------------------------------------------------------------------- Geometrie der eigenen Bahn

def turn_params(L, D=RETURN_OFFSET, blend=TURN_BLEND):
    """Wie CourseTrack.init: Radius R, Winkel alpha, halbe Wendelänge, Lage des grossen Bogens (a_c)."""
    def alpha(r):
        return math.acos(min(1, max(-1, (D / (2 * r) + 1) / 2))) if r > 0 else 0.0

    def half(r):
        return r * (math.pi + 4 * alpha(r)) / 2

    r = D / 2
    if blend > half(r):
        lo, hi = r, max(r, 1)
        while half(hi) < blend:
            hi *= 2
        for _ in range(60):
            mid = (lo + hi) / 2
            if half(mid) < blend:
                lo = mid
            else:
                hi = mid
        r = (lo + hi) / 2
    a = alpha(r)
    return r, a, min(half(r), L), 2 * r * math.sin(a)


class Path2:
    """Mittellinie der Hinfahrt (Szenenkoordinaten x, z) mit Abtastung wie CourseTrack.sample."""

    def __init__(self, pts, L):
        self.p = np.asarray(pts, float)
        seg = np.diff(self.p, axis=0)
        self.cum = np.r_[0, np.cumsum(np.linalg.norm(seg, axis=1))]
        self.geo = self.cum[-1]
        self.L = L

    def at(self, s):
        g = min(max(s, 0), self.L) * self.geo / self.L
        i = int(np.clip(np.searchsorted(self.cum, g) - 1, 0, len(self.p) - 2))
        u = (g - self.cum[i]) / max(self.cum[i + 1] - self.cum[i], 1e-9)
        p = self.p[i] + (self.p[i + 1] - self.p[i]) * u
        a = self.p[max(i - 1, 0)]
        b = self.p[min(i + 2, len(self.p) - 1)]
        t = b - a
        t /= max(np.linalg.norm(t), 1e-9)
        return p, t

    @staticmethod
    def left(t):
        """Normale zur Rückfahrtseite (links der Hinfahrt), wie CourseTrack.returnSide"""
        return np.array([t[1], -t[0]])


def rower_lane(path, out_m, back_m, step=4.0):
    """Ruderer-Bahn als geschlossene Linie (Szenenkoordinaten), wie RowerLane in der App: Hinfahrt mit seitlichem
    Versatz out_m, Rückfahrt mit back_m (positiv = Rückfahrtseite, back_m > out_m), an Wende und Start je ein
    Halbkreis um (a_c, Mitte) mit Radius (back_m − out_m) / 2; a_c = Lage des grossen Wendebogens der eigenen Bahn."""
    L = path.L
    R, al, half, ac = turn_params(L)
    lc, rho = (out_m + back_m) / 2, (back_m - out_m) / 2
    pts = []
    for s in np.arange(half, L - half, step):          # Hinfahrt
        p, t = path.at(s)
        pts.append(p + path.left(t) * out_m)
    p0, t0 = path.at(L - half)
    n0 = path.left(t0)
    for a in np.arange(0, ac, step):
        pts.append(p0 + t0 * a + n0 * out_m)
    for th in np.linspace(0, math.pi, 40):
        pts.append(p0 + t0 * (ac + rho * math.sin(th)) + n0 * (lc - rho * math.cos(th)))
    for a in np.arange(ac, 0, -step):
        pts.append(p0 + t0 * a + n0 * back_m)
    for s in np.arange(L - half, half, -step):         # Rückfahrt
        p, t = path.at(s)
        pts.append(p + path.left(t) * back_m)
    p1, t1 = path.at(half)
    n1 = path.left(t1)
    for a in np.arange(0, ac, step):
        pts.append(p1 - t1 * a + n1 * back_m)
    for th in np.linspace(0, math.pi, 40):
        pts.append(p1 - t1 * (ac + rho * math.sin(th)) + n1 * (lc + rho * math.cos(th)))
    for a in np.arange(ac, 0, -step):
        pts.append(p1 - t1 * a + n1 * out_m)
    pts.append(pts[0])
    return np.array(pts)


def pear(p, t, n, R, al, step=1.0):
    """Birnenkehre wie CourseTrack (drei Kreisbögen), Start in p mit Richtung t, Wende zur Seite n."""
    arc = R * (math.pi + 4 * al)
    out = []
    for q in np.arange(0, arc + step, step):
        q = min(q, arc)
        if q <= R * al:
            phi = q / R
            a, l = R * math.sin(phi), -R + R * math.cos(phi)
        elif q <= R * (math.pi + 3 * al):
            psi = -al + (q - R * al) / R
            a, l = 2 * R * math.sin(al) + R * math.sin(psi), R * (2 * math.cos(al) - 1) - R * math.cos(psi)
        else:
            psi = math.pi + al - (q - R * (math.pi + 3 * al)) / R
            a, l = -R * math.sin(psi), R * (4 * math.cos(al) - 1) + R * math.cos(psi)
        out.append(p + t * a + n * l)
    return out


def own_footprint(path, step=5.0):
    """Eigene Bahn wie in der App: Hinfahrt, Wende (CourseTrack), Rückfahrt (12 m links) und Startwende (LapTrack)."""
    L, D = path.L, RETURN_OFFSET
    R, al, half, ac = turn_params(L)
    ss = np.arange(half, L - half + step, step)
    out = [path.at(s)[0] for s in ss]
    back = [path.at(s)[0] + path.left(path.at(s)[1]) * D for s in ss]
    p0, t0 = path.at(L - half)
    turn = pear(p0, t0, path.left(t0), R, al)
    p1, t1 = path.at(half)
    start = pear(p1 + path.left(t1) * D, -t1, -path.left(t1), R, al)
    return unary_union([LineString(out), LineString(back), LineString(turn), LineString(start)])


def choose_rower_lanes(path, chk, own, rid):
    """Bahnen der virtuellen Ruderer: eine Familie konzentrischer Bahnen (gleiche Mitte lc, Radien ρ im Abstand
    ≥ 8 m), damit sich keine zwei Bahnen kreuzen. Gesucht wird über drei Lagen der Mitte: um die eigene Bahn herum
    (lc = 6), ganz rechts der Hinfahrt (lc < 0) oder ganz links jenseits der Rückfahrt (lc > 12). Jede Bahn hält
    ROWER_SHORE m zum Ufer, ROWER_OBSTACLE m zu Hindernissen und ROWER_OWN m zur eigenen Bahn (samt Wenden).
    Gewählt wird die Mitte mit den meisten Bahnen (höchstens 3), bei Gleichstand die nähere."""
    D = RETURN_OFFSET
    centers = [D / 2] + [-c for c in range(22, 44, 2)] + [D + c for c in range(22, 50, 2)]
    radii = [float(x) for x in range(8, 42, 2)]
    best = ([], [], 0.0)
    for lc in centers:
        valid = []
        for rho in radii:
            out_m, back_m = lc - rho, lc + rho
            # Bahnen müssen die eigene Bahn ganz umschliessen (lc = 6) oder ganz auf einer Seite liegen
            if not (back_m <= -ROWER_OWN or out_m >= D + ROWER_OWN or (out_m <= -ROWER_OWN and back_m >= D + ROWER_OWN)):
                continue
            pts = rower_lane(path, out_m, back_m)
            if LineString(pts).distance(own) < ROWER_OWN:
                continue
            if chk.shore_dist(pts).min() < ROWER_SHORE or chk.obstacle_dist(pts).min() < ROWER_OBSTACLE:
                continue
            valid.append((rho, pts))
        chosen = []
        for rho, pts in valid:
            if all(abs(rho - c[0]) >= 8 for c in chosen):
                chosen.append((rho, pts))
            if len(chosen) == 3:
                break
        # nähere Bahnen bevorzugen (mittlerer Abstand von der eigenen Bahn)
        closeness = -sum(abs(lc - D / 2) + rho for rho, _ in chosen)
        if len(chosen) > len(best[0]) or (len(chosen) == len(best[0]) and chosen and closeness > best[2]):
            best = (chosen, [lc] * len(chosen), closeness)
    chosen, lcs, _ = best
    lanes = [{"out_m": round(lc - rho, 1), "back_m": round(lc + rho, 1)} for (rho, _), lc in zip(chosen, lcs)]
    print(f"  {rid}: Ruderer-Bahnen {[(x['out_m'], x['back_m']) for x in lanes] or 'keine'}")
    return lanes, [p for _, p in chosen]


# ----------------------------------------------------------------------------- Prüfungen

class Checker:
    """Abstände für viele Punkte auf einmal (Szenenkoordinaten, Arrays N × 2)."""

    def __init__(self, water, obstacles, bridges, e0, n0):
        self.water = water
        self.shore = water.boundary
        self.obstacles = obstacles
        self.bridges = bridges
        self.e0, self.n0 = e0, n0
        shapely.prepare(water)

    def _pts(self, xz):
        xz = np.asarray(xz, float)
        return shapely.points(xz[:, 0] + self.e0, self.n0 - xz[:, 1])

    def shore_dist(self, xz):
        """Abstand zum Ufer (negativ = an Land)"""
        p = self._pts(xz)
        d = shapely.distance(self.shore, p)
        return np.where(shapely.contains(self.water, p), d, -d)

    def obstacle_dist(self, xz):
        if self.obstacles is None:
            return np.full(len(xz), 1e9)
        return shapely.distance(self.obstacles, self._pts(xz))

    def bridge_dist(self, xz):
        if self.bridges is None:
            return np.full(len(xz), 1e9)
        return shapely.distance(self.bridges, self._pts(xz))


def channel_lane(path, chk, side, l_min, l_max, shore_min, obstacle_min, step=20.0, dl=5.0):
    """Fahrrinne entlang der Strecke mit veränderlichem Seitenabstand l(s) (Seite `side` = +1 Rückfahrtseite, −1
    andere Seite, |l| zwischen l_min und l_max): kürzester Weg durch die gültigen Zellen (Ufer ≥ shore_min,
    Hindernisse/Pfeiler ≥ obstacle_min), höchstens dl Meter seitlich je step Meter (≈ 14°), möglichst nah an l_min.
    So fädelt die Linie durch Brückenöffnungen. Liefert die längste zusammenhängende Linie (Punkte) oder None."""
    L = path.L
    ss = np.arange(-EXTEND, L + EXTEND + step, step)
    ls = np.arange(l_min, l_max + dl, dl)
    grid = np.zeros((len(ss), len(ls), 2))
    for i, sv in enumerate(ss):
        p, t = path.at(min(max(sv, 0), L))
        if sv < 0:
            p = p + t * sv
        elif sv > L:
            p = p + t * (sv - L)
        n = path.left(t) * side
        grid[i] = p + np.outer(ls, n)
    flat = grid.reshape(-1, 2)
    ok = ((chk.shore_dist(flat) >= shore_min) & (chk.obstacle_dist(flat) >= obstacle_min)).reshape(len(ss), len(ls))
    INF = 1e18
    cost = np.full((len(ss), len(ls)), INF)
    back = np.zeros((len(ss), len(ls)), int)
    start = np.zeros((len(ss), len(ls)), int)
    pref = (ls - l_min) / dl * 0.2                      # nah an l_min bevorzugt
    for i in range(len(ss)):
        for j in range(len(ls)):
            if not ok[i, j]:
                continue
            best, bj = INF, -1
            if i > 0:
                for k in (j - 1, j, j + 1):
                    if 0 <= k < len(ls) and cost[i - 1, k] < best:
                        best, bj = cost[i - 1, k] + abs(k - j), k
            if bj < 0:
                cost[i, j] = pref[j]
                back[i, j] = -1
                start[i, j] = i
            else:
                cost[i, j] = best + pref[j]
                back[i, j] = bj
                start[i, j] = start[i - 1, bj]
    # längste Linie: Endzelle mit der grössten Länge (i − start), bei Gleichstand geringste Kosten
    best = None
    for i in range(len(ss)):
        for j in range(len(ls)):
            if cost[i, j] < INF:
                length = i - start[i, j]
                key = (length, -cost[i, j])
                if best is None or key > best[0]:
                    best = (key, i, j)
    if best is None:
        return None
    _, i, j = best
    pts = []
    while i >= 0 and j >= 0:
        pts.append(grid[i, j])
        j = back[i, j]
        i -= 1
        if j < 0:
            break
    pts = np.array(pts[::-1])
    if len(pts) * step < MIN_RUN:
        return None
    # leicht glätten, nur wenn es gültig bleibt
    if len(pts) >= 5:
        k = np.ones(3) / 3
        sm = np.column_stack([np.convolve(np.pad(pts[:, 0], 1, mode="edge"), k, "valid"),
                              np.convolve(np.pad(pts[:, 1], 1, mode="edge"), k, "valid")])
        if (chk.shore_dist(sm) >= shore_min).all() and (chk.obstacle_dist(sm) >= obstacle_min).all():
            pts = sm
    return pts


def runs(points, ok, step, min_len):
    """Zusammenhängende gültige Abschnitte einer Punktfolge (Länge ≥ min_len)."""
    out, cur = [], []
    for p, good in zip(points, ok):
        if good:
            cur.append(p)
        else:
            if len(cur) * step >= min_len:
                out.append(np.array(cur))
            cur = []
    if len(cur) * step >= min_len:
        out.append(np.array(cur))
    return out


def offset_line(path, l, step):
    """Parallele zur Hinfahrt im Abstand l (positiv = Rückfahrtseite), über Start und Wende hinaus verlängert.
    Abschnitte, in denen die Parallele umschlägt (Krümmung kleiner als der Versatz), werden verworfen."""
    L = path.L
    pts, ok = [], []
    p, t = path.at(0)
    for e in np.arange(EXTEND, 0, -step):
        pts.append(p - t * e + path.left(t) * l)
    for s in np.arange(0, L, step):
        p, t = path.at(s)
        pts.append(p + path.left(t) * l)
    p, t = path.at(L)
    for e in np.arange(0, EXTEND + step, step):
        pts.append(p + t * e + path.left(t) * l)
    pts = np.array(pts)
    d = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    good = np.r_[True, (d > 0.4 * step) & (d < 2.5 * step)]
    # Richtungsumkehr (Schlaufe) erkennen
    seg = np.diff(pts, axis=0)
    dots = np.r_[True, True, np.einsum("ij,ij->i", seg[1:], seg[:-1]) > 0]
    return pts, good & dots[:len(pts)]


def main(area_file):
    area = load_area(area_file)
    build = Path("build") / area["id"]
    courses = Path("../../courses")
    water = shape(json.loads((build / "water.geojson").read_text())["geometry"]).buffer(0)

    parts = []
    bridge_geoms = []
    if (Path(area["data_dir"]) / "osm" / "overpass.json").exists():
        obs = osm_obstacles(area)
        for kind in ("pier", "bridge_support", "ferry_terminal"):
            for g in obs[kind]:
                gg = g.buffer(5.0 if g.geom_type == "Point" else 1.5)
                if gg.intersects(water):
                    parts.append(gg)
        bridge_geoms += obs.get("bridge", [])
    for poly in area.get("extra_obstacles_lv95", []):
        from shapely.geometry import Polygon
        parts.append(Polygon(poly))
    if area.get("bridges"):
        from bridges import load_bridges
        for b in load_bridges(area):
            parts += b.pier_footprints()
            bridge_geoms.append(b.axis.line.buffer(b.W / 2))
    obstacles = unary_union(parts) if parts else None
    bridges = unary_union(bridge_geoms) if bridge_geoms else None

    cfg = area.get("traffic", {})
    vessels = cfg.get("vessels", DEFAULT_VESSELS.get(area["id"], ["motorboot", "segelboot"]))
    density = float(cfg.get("density", 1.0))

    for r in area["routes"]:
        cj = courses / r["id"] / "course.json"
        c = json.loads(cj.read_text())
        e0, n0 = c["origin_lv95"]

        chk = Checker(water, obstacles, bridges, e0, n0)
        L = c["one_way_m"]
        path = Path2(c["path_xz"], L)
        R, al, half, ac = turn_params(L)
        own = own_footprint(path)

        rower_lanes, rower_lines = choose_rower_lanes(path, chk, own, r["id"])
        lo = min([x["out_m"] for x in rower_lanes], default=0.0)
        hi = max([x["back_m"] for x in rower_lanes], default=RETURN_OFFSET)
        rower_geom = unary_union([LineString(x) for x in rower_lines]) if rower_lines else None

        # --- parallele Schiffslinien
        lanes = []
        step = 10.0
        cand = []
        for base in (25, 45, 75, 115, 165, 235, 335, 485, 685, 935, 1235):
            cand.append(max(hi + base, RETURN_OFFSET + 40))       # Rückfahrtseite, ausserhalb der Ruderer
            cand.append(min(lo - base, -40.0))                     # andere Seite
        seen_kinds = {"parallel": 0, "far": 0}
        accepted = []
        for l in sorted(cand, key=abs):
            pts, geo_ok = offset_line(path, l, step)
            sd = chk.shore_dist(pts)
            od = chk.obstacle_dist(pts)
            ok = geo_ok & (sd >= VESSEL_SHORE["small"]) & (od >= VESSEL_OBSTACLE)
            for run in runs(pts, ok, step, MIN_RUN):
                line = LineString(run)
                md = line.distance(own)
                if md < 40 or (rower_geom is not None and line.distance(rower_geom) < 25):
                    continue
                # nicht zu nah an schon gewählten Linien (gleiche Seite)
                if any(line.distance(LineString(a)) < 35 for a in accepted):
                    continue
                if md >= 300:
                    continue          # weit draussen: gerade Linien (unten)
                kind = "parallel"
                if seen_kinds[kind] >= 3:
                    continue
                shore_min = float(chk.shore_dist(run).min())
                seen_kinds[kind] += 1
                accepted.append(run)
                simp = line.simplify(1.0)
                lanes.append({"id": f"{'p' if kind == 'parallel' else 'f'}{int(round(l))}-{len(lanes) + 1}", "kind": kind,
                              "min_dist_m": round(md, 1), "shore_m": round(shore_min, 1),
                              "points_xz": [[round(x, 1), round(z, 1)] for x, z in simp.coords]})

        # --- Fahrrinne für grosse Schiffe (Flüsse mit Brücken): Seitenabstand folgt den Brückenöffnungen
        if not any(x["kind"] == "parallel" and x["min_dist_m"] >= 80 and len(x["points_xz"]) >= 2
                   and LineString(x["points_xz"]).length >= 900 for x in lanes):
            for side in (1, -1):
                inner = (hi + 30) if side > 0 else (-lo + 30)
                inner = max(inner, (RETURN_OFFSET if side > 0 else 0) + 85)
                ch = channel_lane(path, chk, side, inner, inner + 250, VESSEL_SHORE["large"] - 10, 9.0)
                if ch is None:
                    continue
                line = LineString(ch)
                md = line.distance(own)
                if md < 80 or (rower_geom is not None and line.distance(rower_geom) < 25):
                    continue
                accepted.append(ch)
                lanes.append({"id": f"c{side:+d}-{len(lanes) + 1}", "kind": "parallel", "min_dist_m": round(md, 1),
                              "shore_m": round(float(chk.shore_dist(ch).min()), 1),
                              "points_xz": [[round(float(x), 1), round(float(z), 1)] for x, z in line.simplify(1.0).coords]})
                print(f"  {r['id']}: Fahrrinne Seite {side:+d}, {line.length:.0f} m, Abstand {md:.0f} m")
                break

        # --- weit draussen („am Horizont“): gerade Linien parallel zur Sehne Start → Wende, 300–1500 m entfernt
        p_start, p_turn = path.at(0)[0], path.at(L)[0]
        chord = (p_turn - p_start) / max(np.linalg.norm(p_turn - p_start), 1e-9)
        normal = np.array([chord[1], -chord[0]])
        mid = (p_start + p_turn) / 2
        half_len = np.linalg.norm(p_turn - p_start) / 2 + 1200
        for off in (300, -300, 450, -450, 650, -650, 900, -900, 1200, -1200, 1500, -1500):
            if seen_kinds["far"] >= 2:
                break
            ts = np.arange(-half_len, half_len + step, step)
            pts = np.array([mid + normal * off + chord * k for k in ts])
            sd = chk.shore_dist(pts)
            od = chk.obstacle_dist(pts)
            ok = (sd >= VESSEL_SHORE["large"]) & (od >= VESSEL_OBSTACLE)
            cands = [run for run in runs(pts, ok, step, 400.0)]
            cands = [run for run in cands if LineString(run).distance(own) >= 300]
            if not cands:
                continue
            run = max(cands, key=len)
            line = LineString(run)
            if any(line.distance(LineString(a)) < 150 for a in accepted):
                continue
            seen_kinds["far"] += 1
            accepted.append(run)
            lanes.append({"id": f"f{off}-{len(lanes) + 1}", "kind": "far", "min_dist_m": round(line.distance(own), 1),
                          "shore_m": round(float(sd[ok].min()), 1),
                          "points_xz": [[round(float(x), 1), round(float(z), 1)] for x, z in (run[0], run[-1])]})

        # --- Querlinien
        n_cross = 0
        for frac in (0.5, 0.25, 0.75, 0.1, 0.9):
            if n_cross >= 2:
                break
            s = frac * L
            p, t = path.at(s)
            n = path.left(t)
            ts = np.arange(-3000, 3000 + step, step)
            pts = np.array([p + n * k for k in ts])
            sd = chk.shore_dist(pts)
            od = chk.obstacle_dist(pts)
            bd = chk.bridge_dist(pts)
            ok = (sd >= 25) & (od >= VESSEL_OBSTACLE) & (bd >= CROSS_BRIDGE_DIST)
            i0 = int(np.argmin(np.abs(ts)))
            if not ok[i0]:
                continue
            a = i0
            while a > 0 and ok[a - 1]:
                a -= 1
            b = i0
            while b < len(pts) - 1 and ok[b + 1]:
                b += 1
            length = (b - a) * step
            if length < 120:
                continue
            run = pts[a:b + 1]
            # nicht dicht an einer schon gewählten Querlinie
            if any(LineString(run).distance(LineString(x["points_xz"])) < 150 for x in lanes if x["kind"] == "cross"):
                continue
            n_cross += 1
            shore_min = float(sd[a:b + 1].min())
            lanes.append({"id": f"x{n_cross}", "kind": "cross", "min_dist_m": 0.0, "shore_m": round(shore_min, 1),
                          "points_xz": [[round(float(x), 1), round(float(z), 1)] for x, z in (run[0], run[-1])],
                          "cross": [{"s": round(s, 1), "at": round((i0 - a) * step, 1)}]})

        c["traffic"] = {"vessels": vessels, "density": density, "rower_lanes": rower_lanes,
                        "vessel_lanes": lanes}
        cj.write_text(json.dumps(c, ensure_ascii=False))
        summary = ", ".join(f"{x['id']}({x['kind']}, {x['min_dist_m']:.0f} m, Ufer {x['shore_m']:.0f} m)" for x in lanes)
        rl = [(x["out_m"], x["back_m"]) for x in rower_lanes]
        print(f"{r['id']}: Ruderer {rl}, Schiffe {vessels}, Linien: {summary or 'keine'}")
        preview(area, build, r["id"], c, path, rower_lines, lanes, e0, n0)


def preview(area, build, rid, c, path, rower_lines, lanes, e0, n0):
    pts = np.array(c["path_xz"])
    allp = [pts] + [np.array(x["points_xz"]) for x in lanes] + list(rower_lines)
    cat = np.vstack(allp)
    xmin, zmin = cat.min(axis=0) - 150
    xmax, zmax = cat.max(axis=0) + 150
    bounds = (e0 + xmin, n0 - zmax, e0 + xmax, n0 - zmin)
    W = 1400
    H = int(W * (zmax - zmin) / (xmax - xmin))
    with rasterio.open(build / "ortho_far.tif") as src:
        win = from_bounds(*bounds, src.transform)
        img = src.read([1, 2, 3], window=win, out_shape=(3, H, W), boundless=True, fill_value=40)
    im = Image.fromarray(np.moveaxis(img, 0, -1)).convert("RGB")
    dr = ImageDraw.Draw(im)
    px = lambda p: ((p[0] - xmin) / (xmax - xmin) * W, (p[1] - zmin) / (zmax - zmin) * H)
    for line in rower_lines:
        dr.line([px(p) for p in line], fill=(255, 220, 40), width=1)
    dr.line([px(p) for p in pts], fill=(255, 255, 255), width=3)
    col = {"parallel": (40, 220, 255), "far": (60, 90, 255), "cross": (255, 60, 220)}
    for x in lanes:
        dr.line([px(p) for p in x["points_xz"]], fill=col[x["kind"]], width=3)
        dr.text(px(x["points_xz"][0]), x["id"], fill=col[x["kind"]])
    im.save(build / f"lanes_preview_{rid}.png")


if __name__ == "__main__":
    main(sys.argv[1])
