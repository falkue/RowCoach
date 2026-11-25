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

from common import course_origin, load_area, osm_obstacles, to_proj

RETURN_OFFSET = 12.0          # wie CourseTrack.returnOffset in der App
TURN_BLEND = 40.0             # wie CourseTrack.turnBlend
ROWER_SHORE = 10.0            # m Mindestabstand der Ruderer-Bahnen zum Ufer
ROWER_OBSTACLE = 6.0          # m zu Pfeilern (Rand), Stegen, Anlegern
DEBUG_COMPRESS = False
START_BEHIND = 10.0           # m, Mitte des Starthalbkreises vor s = 0 (RowerLane.startBehind)
ROWER_MAX_OFFSET = 60.0       # m, äusserste Ruderer-Bahn höchstens so weit von der eigenen Bahn
ROWER_VESSEL_GAP = 12.0       # m zwischen Schiffslinie und Ruderer-Bahn
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
    # Berlin und Potsdam: Ausflugsschiffe/-dampfer als Kursschiff, Trainerboote als Motorboot
    "berlin-spree-mitte": ["kursschiff", "motorboot"],
    "berlin-wannsee": ["kursschiff", "segelboot", "motorboot"],
    "potsdam-jungfernsee": ["kursschiff", "segelboot", "motorboot"],
    "berlin-gruenau": ["motorboot", "segelboot"],
    # Hamburg Außenalster: Alsterdampfer (ATG) als Kursschiff, viele Segeljollen, Trainer- und Polizeiboote als Motorboot
    # (Tretboote und Mietruderboote hat die App noch nicht; Vorschlag „alsterdampfer“/„tretboot“ siehe Bericht Team Q)
    "hamburg-aussenalster": ["alsterdampfer", "segelboot", "motorboot", "tretboot"],
}

# Gebiete mit eigenen Abständen je Schiffsart (s, Dichte normal; App: CourseTraffic.vesselIntervals) und eigenen
# Segelrevieren (Linien quer durch die Wasserfläche, nur für Segel- und Tretboote)
DEFAULT_VESSEL_INTERVALS = {
    # Außenalster an einem Sommertag: viele Segeljollen, Alsterdampfer etwa alle 10–15 min
    "hamburg-aussenalster": {"segelboot": [45, 120], "alsterdampfer": [600, 900], "motorboot": [300, 600],
                             "tretboot": [180, 420]},
}
SAIL_AREAS = {"hamburg-aussenalster"}
# Ruderer-Bahnen rund um die eigene Bahn bevorzugen (sonst: die Familie mit den meisten Bahnen)
AROUND_AREAS = {"hamburg-aussenalster", "zuerichsee-unteres-becken", "luzern-seebecken"}


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
    """Mittellinie der Hinfahrt (Szenenkoordinaten x, z) mit Abtastung wie CourseTrack.sample bzw. Centerline in der
    App: Tangente je Stützpunkt = Mittel der angrenzenden Segmente, dazwischen linear interpoliert."""

    def __init__(self, pts, L):
        self.p = np.asarray(pts, float)
        seg = np.diff(self.p, axis=0)
        n = np.linalg.norm(seg, axis=1, keepdims=True)
        segt = seg / np.maximum(n, 1e-9)
        self.cum = np.r_[0, np.cumsum(n[:, 0])]
        self.geo = self.cum[-1]
        self.L = L
        a = np.vstack([segt[:1], segt])
        b = np.vstack([segt, segt[-1:]])
        t = a + b
        self.t = t / np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-9)

    def at(self, s):
        g = min(max(s, 0), self.L) * self.geo / self.L
        i = int(np.clip(np.searchsorted(self.cum, g, side="right") - 1, 0, len(self.p) - 2))
        u = (g - self.cum[i]) / max(self.cum[i + 1] - self.cum[i], 1e-9)
        p = self.p[i] + (self.p[i + 1] - self.p[i]) * u
        t = self.t[i] + (self.t[i + 1] - self.t[i]) * u
        t = t / max(np.linalg.norm(t), 1e-9)
        return p, t

    @staticmethod
    def left(t):
        """Normale zur Rückfahrtseite (links der Hinfahrt), wie CourseTrack.returnSide"""
        return np.array([t[1], -t[0]])


def lane_lateral(s, L, half, straight_m, turn_m):
    """Versatz auf der Geraden mit weichem Übergang zum Wendeversatz (wie RowerLane.lateral in der App)."""
    ramp = min(80.0, (L - 2 * half) / 2)
    d = min(s - half, (L - half) - s)
    x = min(max(d / ramp, 0.0), 1.0) if ramp > 0 else 1.0
    w = 1 - x * x * (3 - 2 * x)
    return straight_m + (turn_m - straight_m) * w


def rower_lane(path, out_m, back_m, step=4.0, turn_out=None, turn_back=None):
    """Ruderer-Bahn als geschlossene Linie (Szenenkoordinaten), wie RowerLane in der App: Hinfahrt mit seitlichem
    Versatz out_m, Rückfahrt mit back_m (positiv = Rückfahrtseite, back_m > out_m); vor Wende und Start weich (80 m)
    auf turn_out/turn_back; an der Wende ein Halbkreis um (a_c, Mitte) mit Radius (turn_back − turn_out) / 2
    (a_c = Lage des grossen Wendebogens der eigenen Bahn), am Start ein Halbkreis mit Mitte START_BEHIND m hinter der
    Startlinie (wie RowerLane.startBehind in der App)."""
    L = path.L
    R, al, half, ac = turn_params(L)
    t_out = out_m if turn_out is None else turn_out
    t_back = back_m if turn_back is None else turn_back
    lc, rho = (t_out + t_back) / 2, (t_back - t_out) / 2
    pts = []
    for s in np.arange(half, L - half, step):          # Hinfahrt
        p, t = path.at(s)
        pts.append(p + path.left(t) * lane_lateral(s, L, half, out_m, t_out))
    p0, t0 = path.at(L - half)
    n0 = path.left(t0)
    for a in np.arange(0, ac, step):
        pts.append(p0 + t0 * a + n0 * t_out)
    for th in np.linspace(0, math.pi, 40):
        pts.append(p0 + t0 * (ac + rho * math.sin(th)) + n0 * (lc - rho * math.cos(th)))
    for a in np.arange(ac, 0, -step):
        pts.append(p0 + t0 * a + n0 * t_back)
    for s in np.arange(L - half, half, -step):         # Rückfahrt
        p, t = path.at(s)
        pts.append(p + path.left(t) * lane_lateral(s, L, half, back_m, t_back))
    p1, t1 = path.at(half)
    n1 = path.left(t1)
    A = half + START_BEHIND                             # Starthalbkreis ganz hinter der Startlinie
    for a in np.arange(0, A, step):
        pts.append(p1 - t1 * a + n1 * t_back)
    for th in np.linspace(0, math.pi, 40):
        pts.append(p1 - t1 * (A + rho * math.sin(th)) + n1 * (lc + rho * math.cos(th)))
    for a in np.arange(A, 0, -step):
        pts.append(p1 - t1 * a + n1 * t_out)
    pts.append(pts[0])
    return np.array(pts)


def reverses(pts):
    """Läuft die Bahn irgendwo rückwärts (Versatz grösser als der Krümmungsradius der Strecke)?"""
    seg = np.diff(np.asarray(pts), axis=0)
    n = np.linalg.norm(seg, axis=1)
    seg, n = seg[n > 1e-6], n[n > 1e-6]
    bad = np.einsum("ij,ij->i", seg[1:], seg[:-1]) <= 0
    # winzige Schlaufen (zusammen < 1 m, z. B. an einem Knick der Strecke) sieht man nicht
    return bool(n[1:][bad].sum() >= 1.0)


def around_family(path, chk, own, rid):
    """Bahnen rund um die eigene (wie TrafficDefaults.rowerLanes in der App): auf den Geraden 9/18/27 m rechts der
    Hinfahrt und 10/19/28 m jenseits der Rückfahrt, an Wende und Start die Halbkreise ±22/30/38 m um die Mitte. So
    liegt auf beiden Fahrten eine Bahn gleicher Richtung nah daneben (Hasen). Von innen nach aussen, solange jede
    Bahn Ufer, Hindernisse, eigene Bahn und Nachbarbahn einhält."""
    family = [(-9.0, 22.0, -16.0, 28.0), (-18.0, 31.0, -24.0, 36.0), (-27.0, 40.0, -32.0, 44.0)]
    lanes_, lines = [], []
    for o, b, to, tb in family:
        pts = rower_lane(path, o, b, turn_out=to, turn_back=tb)
        g = LineString(pts)
        if (g.distance(own) < ROWER_OWN or chk.shore_dist(pts).min() < ROWER_SHORE
                or chk.obstacle_dist(pts).min() < ROWER_OBSTACLE or reverses(pts)
                or any(g.distance(LineString(q)) < 7.5 for q in lines)):
            break
        lanes_.append({"out_m": o, "back_m": b, "turn_out_m": to, "turn_back_m": tb})
        lines.append(pts)
    print(f"  {rid}: Bahnen rund um die eigene: {len(lanes_)}")
    return lanes_, lines


def compress_lanes(path, chk, own, lanes, rid, base_r=9.0, base_l=10.0, avoid=()):
    """Bahnen auf den Geraden näher an die eigene rücken (Falk 24.11.2026: innerste ca. 9 m rechts der Hinfahrt bzw.
    10 m jenseits der Rückfahrt, weitere je ≥ 9 m dahinter, nie weiter als ihr Wendeversatz). Je Seite der eigenen
    Bahn (rechts: l < 0, links: l > 12) werden die Linien nach Abstand geordnet; eine Bahn, deren nähere Lage gegen
    Ufer, Hindernisse oder die eigene Bahn verstösst, behält ihre Lage."""
    D = RETURN_OFFSET
    lines = []                          # (Seite, Abstand von der eigenen Linie, Bahn, Schlüssel)
    for i, ln in enumerate(lanes):
        for key in ("out_m", "back_m"):
            l = ln[key]
            if l < 0:
                lines.append(("rechts", -l, i, key))
            elif l > D:
                lines.append(("links", l - D, i, key))
    def attempt(base_r, base_l):
        new = [dict(x) for x in lanes]
        for side, base in (("rechts", base_r), ("links", base_l)):
            prev = None
            for _, dist, i, key in sorted([x for x in lines if x[0] == side], key=lambda x: x[1]):
                want = base if prev is None else prev + 9.0
                d = min(dist, max(want, base))
                new[i][key] = round(-d if side == "rechts" else D + d, 1)
                prev = d
        out = []
        for old, ln in zip(lanes, new):
            cand = {"out_m": ln["out_m"], "back_m": ln["back_m"], "turn_out_m": old["out_m"],
                    "turn_back_m": old["back_m"]}
            pts = rower_lane(path, cand["out_m"], cand["back_m"], turn_out=old["out_m"], turn_back=old["back_m"])
            if (LineString(pts).distance(own) < ROWER_OWN or chk.shore_dist(pts).min() < ROWER_SHORE
                    or chk.obstacle_dist(pts).min() < ROWER_OBSTACLE or reverses(pts)):
                if DEBUG_COMPRESS and base_r > 1e8 and base_l > 1e8:
                    print("    DEBUG", cand, LineString(pts).distance(own), chk.shore_dist(pts).min(), chk.obstacle_dist(pts).min())
                return None
            out.append((cand, pts))
        geoms = [LineString(p) for _, p in out]
        if any(geoms[i].distance(geoms[j]) < 7.5 for i in range(len(geoms)) for j in range(i + 1, len(geoms))):
            return None
        if any(g.distance(LineString(q)) < 7.5 for g in geoms for q in avoid):
            return None
        return out

    # so nah wie möglich: innerste Linie 9 bzw. 10 m, sonst schrittweise weiter weg
    # je Seite unabhängig: zuerst beide ganz nah, dann schrittweise weiter weg (1e9 = Seite unverändert)
    extras = (0, 3, 6, 9, 12, 16, 20, 1e9)
    out = None
    for er, el in sorted(((a_, b_) for a_ in extras for b_ in extras), key=lambda x: (min(x[0], 40) + min(x[1], 40))):
        out = attempt(base_r + er, base_l + el)
        if out is not None:
            break
    if out is None:
        print(f"  {rid}: Zusammenrücken nicht möglich (Ufer, Pfeiler oder Abstände)")
        return [dict(x) for x in lanes], [rower_lane(path, x["out_m"], x["back_m"]) for x in lanes]
    print(f"  {rid}: Geraden {[(x['out_m'], x['back_m']) for x, _ in out]}")
    return [x for x, _ in out], [p for _, p in out]


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
    ss = np.arange(0, L - half + step, step)            # ohne Runden beginnt/endet die Fahrt geradeaus bei s = 0
    out = [path.at(s)[0] for s in ss]
    back = [path.at(s)[0] + path.left(path.at(s)[1]) * D for s in ss]
    p0, t0 = path.at(L - half)
    turn = pear(p0, t0, path.left(t0), R, al)
    p1, t1 = path.at(half)
    start = pear(p1 + path.left(t1) * D, -t1, -path.left(t1), R, al)
    return unary_union([LineString(out), LineString(back), LineString(turn), LineString(start)])


def choose_rower_lanes(path, chk, own, rid, beyond=None):
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
            # neben einer schon gewählten Bahn rund um die eigene: ganz rechts bzw. ganz links davon
            if beyond is not None and not (back_m <= beyond[0] or out_m >= beyond[1]):
                continue
            # nah an der eigenen Bahn (Falk 24.11.2026: typisch 10–20 m, höchstens ca. 50 m)
            if out_m < -ROWER_MAX_OFFSET or back_m > D + ROWER_MAX_OFFSET:
                continue
            pts = rower_lane(path, out_m, back_m)
            if LineString(pts).distance(own) < ROWER_OWN:
                continue
            if chk.shore_dist(pts).min() < ROWER_SHORE or chk.obstacle_dist(pts).min() < ROWER_OBSTACLE:
                continue
            if reverses(pts):                          # Versatz in engen Bögen schlägt um
                continue
            valid.append((rho, pts))
        chosen = []
        for rho, pts in valid:
            if all(abs(rho - c[0]) >= 8 and LineString(pts).distance(LineString(c[1])) >= 7.5 for c in chosen):
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


DOCK_TAGS = (("rowing", 0), ("marina", 1), ("slipway", 1), ("pier", 2))


def dock_kind(tags):
    """Art einer möglichen Ein- und Ausstiegsstelle aus OSM-Tags (None = keine)."""
    name = (tags.get("name") or "").lower()
    if tags.get("sport") == "rowing" or "ruder" in name or "rowing" in name or "aviron" in name or "seeclub" in name:
        return "rowing"
    if tags.get("leisure") == "marina":
        return "marina"
    if tags.get("leisure") == "slipway":
        return "slipway"
    if tags.get("man_made") == "pier":
        return "pier"
    return None


def bezier(a, c, b, n=13):
    return [tuple((1 - t) ** 2 * np.asarray(a) + 2 * (1 - t) * t * np.asarray(c) + t * t * np.asarray(b))
            for t in np.linspace(0, 1, n)]


def choose_docks(area, path, chk, own, rower_lanes, osm_els, rid, max_docks=3):
    """Ein- und Ausstiegsstellen der Ruderer (App: `RowerDockSpec`): Ruderclubs, Häfen, Slipanlagen und Stege aus OSM
    in höchstens 350 m Abstand zur Strecke; ohne solche die beiden Streckenenden (nächster Uferpunkt).
    Je Stelle: Startpunkt im Wasser (≥ 5 m vom Ufer, ≥ 3 m von Hindernissen), Ziel ist die Ruderer-Bahn, die dem
    Startpunkt am nächsten liegt (also keine andere Ruderer-Bahn dazwischen). Einfahrt als Bogen (quadratische
    Bézierkurve) vom Steg über den Querpunkt A auf der Bahn zu einem Punkt 40 m weiter (trifft die Bahn tangential in
    Fahrtrichtung), Ausfahrt von 40 m vor A über A zurück zum Steg. Beide Bögen müssen im Wasser bleiben (≥ 3 m Ufer,
    ≥ 2 m Hindernisse). Stellen im Abstand < 150 m entlang der Strecke werden zusammengelegt."""
    if not rower_lanes:
        return []
    L, D = path.L, RETURN_OFFSET
    R, al, half, ac = turn_params(L)
    e0, n0 = chk.e0, chk.n0
    to_scene = lambda e, n: np.array([e - e0, n0 - n])
    proj = to_proj(area)
    cands = []
    for el in osm_els:
        kind = dock_kind(el.get("tags", {}))
        if kind is None:
            continue
        if el["type"] == "node":
            e, n = proj.transform(el["lon"], el["lat"])
            cands.append((dict(DOCK_TAGS)[kind], kind, el.get("tags", {}).get("name"), to_scene(e, n)))
        elif "geometry" in el:
            g = el["geometry"]
            e, n = proj.transform(np.mean([q["lon"] for q in g]), np.mean([q["lat"] for q in g]))
            cands.append((dict(DOCK_TAGS)[kind], kind, el.get("tags", {}).get("name"), to_scene(e, n)))
    out_line = LineString([path.at(s)[0] for s in np.arange(0, L + 5, 5)])
    near = [c for c in cands if out_line.distance(Point(c[3])) <= 350]
    near.sort(key=lambda c: (c[0], out_line.distance(Point(c[3]))))
    if not near:
        # Streckenenden: nächster Uferpunkt (Rand der Wasserfläche) bei Start und Wende
        for s_end, name in ((0.0, "Start"), (L, "Wende")):
            p = path.at(s_end)[0]
            q = chk.shore.interpolate(chk.shore.project(Point(p[0] + e0, n0 - p[1])))
            near.append((3, "end", name, to_scene(q.x, q.y)))
    lane_samples = []      # (Punkt, s, Seite out/back, Bahnindex)
    # die innerste Bahn gehört in der App den Hasen (bei mehreren Bahnen): dort keine Gäste
    D = RETURN_OFFSET
    close = [min(min(abs(v), abs(v - D)) for v in (ln["out_m"], ln["back_m"])) for ln in rower_lanes]
    inner = int(np.argmin(close)) if len(rower_lanes) > 1 else None
    for li, ln in enumerate(rower_lanes):
        if li == inner:
            continue
        for s in np.arange(half + 130, L - half - 130, 5.0):    # ausserhalb des Übergangs vor Wende/Start (80 m)
            p, t = path.at(s)
            lane_samples.append((p + path.left(t) * ln["out_m"], s, "out", li))
            lane_samples.append((p + path.left(t) * ln["back_m"], s, "back", li))
    if not lane_samples:
        return []
    pts = np.array([x[0] for x in lane_samples])
    docks, used_s = [], []
    for prio, kind, name, P in near:
        if len(docks) >= max_docks:
            break
        i = int(np.argmin(np.linalg.norm(pts - P, axis=1)))
        A, s, seg, li = lane_samples[i]
        # Startpunkt: vom Steg Richtung Bahn, bis es Wasser mit Abstand ist
        direction = (A - P) / max(np.linalg.norm(A - P), 1e-9)
        start = None
        for k in np.arange(0, min(np.linalg.norm(A - P), 400), 2.0):
            q = P + direction * k
            if chk.shore_dist([q])[0] >= 5 and chk.obstacle_dist([q])[0] >= 3:
                start = q
                break
        if start is None or np.linalg.norm(A - start) < 15:
            continue
        if any(abs(s - u) < 150 for u in used_s):
            continue
        t = path.at(s)[1]
        fwd = t if seg == "out" else -t
        J_in, J_out = A + fwd * 40, A - fwd * 40
        enter = bezier(start, A, J_in)
        exit_ = bezier(J_out, A, start)
        arr = np.array(enter + exit_)
        if chk.shore_dist(arr).min() < 3 or chk.obstacle_dist(arr).min() < 2:
            continue
        u_of = (lambda sv: sv) if seg == "out" else (lambda sv: 2 * L - sv)
        s_in = s + 40 if seg == "out" else s - 40
        s_out = s - 40 if seg == "out" else s + 40
        used_s.append(s)
        docks.append({"id": f"d{len(docks) + 1}", "name": name or {"rowing": "Ruderclub", "marina": "Hafen",
                      "slipway": "Slipanlage", "pier": "Steg"}.get(kind, "Ufer"), "kind": kind, "lane": li,
                      "join_u": round(u_of(s_in), 1), "exit_u": round(u_of(s_out), 1),
                      "enter_xz": [[round(float(x), 1), round(float(z), 1)] for x, z in enter],
                      "exit_xz": [[round(float(x), 1), round(float(z), 1)] for x, z in exit_]})
    print(f"  {rid}: Stege {[(d['name'], d['kind'], d['lane']) for d in docks] or 'keine'}")
    return docks


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


def sail_lanes(path, chk, own, rower_geom, rid, step=10.0, max_lanes=10):
    """Segelrevier: gerade Linien quer durch die Wasserfläche in acht Richtungen (alle 22,5°) und fünf Lagen um die
    Mitte der Strecke, im Wasser mit ≥ 30 m Uferabstand, ≥ 15 m zu Hindernissen, ≥ 60 m zur eigenen Bahn und ≥ 30 m zu
    den Ruderer-Bahnen; je Linie der längste Abschnitt ≥ 250 m, untereinander ≥ 40 m (parallel) – Kreuzungen regelt
    die App (keine zwei Schiffe zugleich an derselben Stelle). Nur Segel- und Tretboote fahren hier."""
    L = path.L
    mid = np.mean([path.at(s)[0] for s in np.linspace(0, L, 21)], axis=0)
    p_start, p_turn = path.at(0)[0], path.at(L)[0]
    chord = (p_turn - p_start) / max(np.linalg.norm(p_turn - p_start), 1e-9)
    normal = np.array([chord[1], -chord[0]])
    out, lines = [], []
    # nur die Wasserfläche, auf der die Strecke liegt (nicht ein Nachbarbecken wie die Binnenalster)
    w = chk.water
    pm = Point(mid[0] + chk.e0, chk.n0 - mid[1])
    comp = min(w.geoms, key=lambda g: g.distance(pm)) if w.geom_type == "MultiPolygon" else w
    comp_b = comp.buffer(1)

    route_pts = np.array([path.at(sv)[0] for sv in np.linspace(0, L, 81)])

    def same_water(run):
        """auf derselben Wasserfläche und von der Strecke aus über offenes Wasser zu sehen (Sichtlinie ±40 m im Wasser,
        also nicht durch eine enge Durchfahrt in ein Nachbarbecken)"""
        m = run[len(run) // 2]
        q = route_pts[int(np.argmin(np.linalg.norm(route_pts - m, axis=1)))]
        sight = LineString([(m[0] + chk.e0, chk.n0 - m[1]), (q[0] + chk.e0, chk.n0 - q[1])])
        return comp_b.contains(sight.buffer(40)) and all(comp_b.contains(Point(x + chk.e0, chk.n0 - z)) for x, z in (run[0], run[-1]))
    for side in (1, -1):
        for off in (120, 240, 360, 480, 600):
            centre = mid + normal * side * off
            for k in range(8):
                if len(out) >= max_lanes:
                    break
                ang = math.pi * k / 8
                d = chord * math.cos(ang) + normal * math.sin(ang)
                ts = np.arange(-2000, 2000 + step, step)
                pts = np.array([centre + d * t for t in ts])
                ok = (chk.shore_dist(pts) >= 30) & (chk.obstacle_dist(pts) >= 15)
                runs_ = runs(pts, ok, step, 250.0)
                best = None
                for run in runs_:
                    line = LineString(run)
                    if line.distance(own) < 60 or (rower_geom is not None and line.distance(rower_geom) < 30):
                        continue
                    if not same_water(run):
                        continue
                    if best is None or len(run) > len(best):
                        best = run
                if best is None:
                    continue
                line = LineString(best)
                if any(line.distance(o) < 40 and not line.crosses(o) for o in lines):
                    continue
                lines.append(line)
                out.append({"id": f"s{len(out) + 1}", "kind": "sail", "min_dist_m": round(line.distance(own), 1),
                            "shore_m": round(float(chk.shore_dist(best).min()), 1),
                            "points_xz": [[round(float(x), 1), round(float(z), 1)] for x, z in (best[0], best[-1])]})
    print(f"  {rid}: Segelrevier {len(out)} Linien")
    return out


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
    osm_els = []
    if (Path(area["data_dir"]) / "osm" / "overpass.json").exists():
        from common import osm_elements
        osm_els = osm_elements(area)
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
    intervals = cfg.get("vessel_intervals", DEFAULT_VESSEL_INTERVALS.get(area["id"]))
    sail = bool(cfg.get("sail_lanes", area["id"] in SAIL_AREAS))
    density = float(cfg.get("density", 1.0))

    for r in area["routes"]:
        cj = courses / r["id"] / "course.json"
        c = json.loads(cj.read_text())
        e0, n0 = course_origin(c)

        chk = Checker(water, obstacles, bridges, e0, n0)
        L = c["one_way_m"]
        path = Path2(c["path_xz"], L)
        R, al, half, ac = turn_params(L)
        own = own_footprint(path)

        around = around_family(path, chk, own, r["id"]) if cfg.get("rower_around", area["id"] in AROUND_AREAS) else None
        if around and len(around[0]) == 1:
            # nur die innerste passt rund um die eigene: weitere Bahnen ganz auf einer Seite, ≥ 8 m ausserhalb davon
            extra, extra_lines = choose_rower_lanes(path, chk, own, r["id"], beyond=(-24.0, 36.0))
            if extra:
                extra, extra_lines = compress_lanes(path, chk, own, extra, r["id"], 18.0, 19.0, avoid=around[1])
                if all(LineString(p).distance(LineString(around[1][0])) >= 7.5 for p in extra_lines):
                    around = (around[0] + extra, around[1] + extra_lines)
        if around and len(around[0]) >= 2:
            rower_lanes, rower_lines = around
        else:
            rower_lanes, rower_lines = choose_rower_lanes(path, chk, own, r["id"])
            rower_lanes, rower_lines = compress_lanes(path, chk, own, rower_lanes, r["id"])
        lo = min([x["out_m"] for x in rower_lanes], default=0.0)
        hi = max([x["back_m"] for x in rower_lanes], default=RETURN_OFFSET)
        rower_geom = unary_union([LineString(x) for x in rower_lines]) if rower_lines else None

        # --- parallele Schiffslinien
        lanes = []
        step = 10.0
        cand = []
        # kleine Boote sollen in 20–40 m vorbeifahren (Falk 24.11.2026): ab 15 m ausserhalb der äussersten
        # Ruderer-Bahn, mindestens 20 m von der eigenen Bahn
        for base in (15, 25, 40, 60, 90, 130, 180, 250, 350, 500, 700, 950, 1250):
            cand.append(max(hi + base, RETURN_OFFSET + 20))       # Rückfahrtseite, ausserhalb der Ruderer
            cand.append(min(lo - base, -20.0))                     # andere Seite
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
                if md < 20 or (rower_geom is not None and line.distance(rower_geom) < ROWER_VESSEL_GAP):
                    continue
                # nicht zu nah an schon gewählten Linien (gleiche Seite)
                if any(line.distance(LineString(a)) < 30 for a in accepted):
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
        if not any(x["kind"] == "parallel" and x["min_dist_m"] >= 50 and len(x["points_xz"]) >= 2
                   and LineString(x["points_xz"]).length >= 900 for x in lanes):
            for side in (1, -1):
                inner = (hi + 15) if side > 0 else (-lo + 15)
                inner = max(inner, (RETURN_OFFSET if side > 0 else 0) + 55)
                ch = channel_lane(path, chk, side, inner, inner + 250, VESSEL_SHORE["large"] - 10, 9.0)
                if ch is None:
                    continue
                line = LineString(ch)
                md = line.distance(own)
                if md < 50 or (rower_geom is not None and line.distance(rower_geom) < ROWER_VESSEL_GAP):
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

        if sail:
            lanes += sail_lanes(path, chk, own, rower_geom, r["id"])
        docks = choose_docks(area, path, chk, own, rower_lanes, osm_els, r["id"])
        c["traffic"] = {"vessels": vessels, "density": density, "rower_lanes": rower_lanes,
                        "vessel_lanes": lanes, "rower_docks": docks}
        if intervals:
            c["traffic"]["vessel_intervals"] = intervals
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
    col = {"parallel": (40, 220, 255), "far": (60, 90, 255), "cross": (255, 60, 220), "sail": (255, 255, 255)}
    for x in lanes:
        dr.line([px(p) for p in x["points_xz"]], fill=col[x["kind"]], width=3)
        dr.text(px(x["points_xz"][0]), x["id"], fill=col[x["kind"]])
    for d in c["traffic"].get("rower_docks", []):
        dr.line([px(p) for p in d["enter_xz"]], fill=(80, 255, 80), width=2)
        dr.line([px(p) for p in d["exit_xz"]], fill=(255, 140, 0), width=2)
        a = px(d["enter_xz"][0])
        dr.ellipse([a[0] - 6, a[1] - 6, a[0] + 6, a[1] + 6], outline=(80, 255, 80), width=2)
        dr.text((a[0] + 8, a[1] - 6), d.get("name") or d["id"], fill=(80, 255, 80))
    im.save(build / f"lanes_preview_{rid}.png")


if __name__ == "__main__":
    main(sys.argv[1])
