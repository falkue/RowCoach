"""Schritt 7b: Verhalten am Streckenende für Strecken ohne Wende (Form one_way, `turns` 0).

Im Training (Programm länger als die Strecke) fährt die App nach dem Ziel weiter. Wie, steht in course.json:

  "end_behavior": "turn" | "loop" | "fade"
  "return_offset_m": 12.0      # nur "turn": Rückfahrtlinie, Versatz zur Hinfahrt (positiv = links der Hinfahrt)
  "turn_radius_m": 13.0        # nur "turn": Radius der Birnenkehre an Ziel und Start

- turn: am Ziel dieselbe Birnenkehre wie auf Strecken mit Wende, zurück auf der versetzten Rückfahrtlinie, am Start
  die Startkehre (RowCoachKit `LapTrack`); eine Runde = hin und zurück.
- loop: Rundkurse (`"loop": true`) bzw. Start und Ziel liegen nah beieinander (< 60 m, ähnliche Richtung): die Runde
  schliesst an (kleine Lücken überblendet die App über die letzten Meter).
- fade: kein Platz zum Wenden: am Ziel ausblenden, am Start wieder einblenden (sanfter Übergang statt Sprung).

Ohne Feld leitet die App den Wert ab (`Course.resolvedEndBehavior`: loop wie oben, sonst turn mit 12 m und 13 m).
Dieses Skript prüft je one_way-Strecke an Wasserfläche, Hindernissen (Stege, Pfeiler, Anleger) und den offenen
Ruderer-Linien (traffic.rower_lanes), welche Rückfahrt und Kehre passen. Reihenfolge der Kandidaten: Versatz 12 m mit
Standardradius (Kehre wie auf Strecken mit Wende), dann engere Kehren (9 m, 6 m = Halbkreis), dann kleinerer Versatz
mit fast gedrehtem Boot (8 m/4 m, 6 m/3 m: „Wenden im Kanal“); je zuerst links (Standardseite), dann rechts.
Erste Stufe mit üblichen Abständen (Ufer ≥ 5 m, Hindernisse ≥ 6 m, Ruderer-Linien ≥ 6 m), dann enge Abstände
(Ufer ≥ 2 m, Hindernisse ≥ 3 m, Ruderer ≥ 4 m). Passt nichts: fade.

Aufruf (nach lanes.py; CPU, wenige Sekunden je Gebiet):
  .venv/bin/python end_turns.py areas/<gebiet>.json [...]   schreibt die Felder in courses/<id>/course.json
  --check                                                   nur anzeigen
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from shapely.geometry import LineString

from common import course_origin, load_area
from lanes import Checker, Path2, area_geometry, open_lane_line, pear

LOOP_GAP_M = 60.0               # Start–Ziel näher als das (und ähnliche Richtung): Runde statt Wende
LOOP_HEADING_DEG = 45.0
MIN_TURN_HALF = 15.0            # wie CourseTrack.minTurnHalf: enge Kehren dauern mindestens 2 × 15 m
DEFAULT_OFFSET = 12.0
CANDIDATES = [(12.0, None), (12.0, 9.0), (12.0, 6.0), (8.0, 6.0), (8.0, 4.0), (6.0, 6.0), (6.0, 3.0),
              (0.0, 6.0), (0.0, 4.5), (0.0, 3.0)]
TIERS = [{"shore": 5.0, "obstacle": 6.0, "lanes": 6.0, "turn_lanes": 3.0},
         {"shore": 2.0, "obstacle": 3.0, "lanes": 4.0, "turn_lanes": 1.5}]


def turn_geometry(D, R=None, blend=40.0):
    """Wie CourseTrack.init: Radius, Winkel alpha, halbe Wendelänge (Ruderdistanz, mindestens MIN_TURN_HALF)."""
    def alpha(r):
        return math.acos(min(1, max(-1, (D / (2 * r) + 1) / 2))) if r > 0 else 0.0

    def half(r):
        return r * (math.pi + 4 * alpha(r)) / 2

    if R is None:
        r = D / 2
        if blend > half(r):
            lo, hi = r, max(r, 1)
            while half(hi) < blend:
                hi *= 2
            for _ in range(60):
                mid = (lo + hi) / 2
                lo, hi = (mid, hi) if half(mid) < blend else (lo, mid)
            r = (lo + hi) / 2
    else:
        r = max(R, D / 2)
    return r, alpha(r), max(half(r), MIN_TURN_HALF)


def loop_like(c):
    """Rundkurs oder Start und Ziel nah beieinander mit ähnlicher Richtung (wie Course.resolvedEndBehavior)"""
    if c.get("loop"):
        return True
    p = np.asarray(c["path_xz"], float)
    if len(p) < 3:
        return False
    if np.linalg.norm(p[-1] - p[0]) >= LOOP_GAP_M:
        return False
    k = min(10, len(p) - 1)
    a, b = p[k] - p[0], p[-1] - p[-1 - k]
    cosang = float(a @ b) / max(np.linalg.norm(a) * np.linalg.norm(b), 1e-9)
    return cosang >= math.cos(math.radians(LOOP_HEADING_DEG))


def footprint(path, D, side, R, al, h, step=3.0):
    """Rückfahrtlinie und beide Kehren (Punkte, Szenenkoordinaten)"""
    L = path.L
    back = []
    for s in np.arange(h, L - h + step / 2, step):
        p, t = path.at(s)
        back.append(p + path.left(t) * D * side)
    p0, t0 = path.at(L - h)
    end = pear(p0, t0, path.left(t0) * side, R, al)
    p1, t1 = path.at(h)
    start = pear(p1 + path.left(t1) * D * side, -t1, -path.left(t1) * side, R, al)
    return np.asarray(back), np.asarray(end), np.asarray(start)


def evaluate(c, chk, path):
    """Kandidaten prüfen: Rückfahrtlinie (bei Versatz 0 = Hinfahrtlinie, schon von routes.py geprüft) und beide Kehren
    gegen Ufer und Hindernisse, Abstand zu den Ruderer-Linien (an den Kehren lockerer: dort ziehen die Hasen davon)."""
    lane_lines = []
    for x in (c.get("traffic") or {}).get("rower_lanes", []):
        lane_lines.append(LineString(open_lane_line(path, x["out_m"], x.get("out_bumps", []))))
    results = []
    for D, Rw in CANDIDATES:
        R, al, h = turn_geometry(D, Rw)
        if path.L < 2 * h + 50:
            continue
        for side in ((1, -1) if D > 0 else (1,)):
            back, end, start = footprint(path, D, side, R, al, h)
            turns = np.vstack([end, start])
            r = {"D": D, "side": side, "R": round(R, 1), "half": round(h, 1),
                 "turn_shore": float(chk.shore_dist(turns).min()), "turn_obstacle": float(chk.obstacle_dist(turns).min()),
                 "turn_lanes": min([min(LineString(end).distance(ll), LineString(start).distance(ll))
                                    for ll in lane_lines], default=1e9)}
            if D > 0:
                r["shore"] = float(chk.shore_dist(back).min())
                r["obstacle"] = float(chk.obstacle_dist(back).min())
                r["lanes"] = min([LineString(back).distance(ll) for ll in lane_lines], default=1e9)
            else:
                r["shore"] = r["obstacle"] = r["lanes"] = 1e9     # Rückfahrt auf der Hinfahrtlinie
            results.append(r)

    def ok(r, t):
        return (r["shore"] >= t["shore"] and r["obstacle"] >= t["obstacle"] and r["lanes"] >= t["lanes"]
                and r["turn_shore"] >= t["shore"] and r["turn_obstacle"] >= t["obstacle"]
                and r["turn_lanes"] >= t["turn_lanes"])
    for tier_i, tier in enumerate(TIERS):
        for r in results:
            if ok(r, tier):
                return r, tier_i, results
    return None, None, results


def describe(r):
    def f(v):
        return "–" if v >= 1e8 else f"{v:.1f}"
    return (f"D={r['D'] * r['side']:+.0f} R={r['R']}: Rückfahrt Ufer {f(r['shore'])}/Hind. {f(r['obstacle'])}/Ruderer "
            f"{f(r['lanes'])}, Kehren Ufer {f(r['turn_shore'])}/Hind. {f(r['turn_obstacle'])}/Ruderer {f(r['turn_lanes'])}")


def main(argv):
    check = "--check" in argv
    files = [a for a in argv if not a.startswith("-")]
    courses = Path("../../courses")
    rows = []
    for af in files:
        area = load_area(af)
        build = Path("build") / area["id"]
        geo = None
        for r in area["routes"]:
            cj = courses / r["id"] / "course.json"
            if not cj.exists():
                continue
            c = json.loads(cj.read_text())
            if c.get("turns", 1) != 0:
                continue
            fields = {}
            if loop_like(c):
                fields = {"end_behavior": "loop"}
                note = "Rundkurs" if c.get("loop") else "Start nah am Ziel"
            else:
                if geo is None:
                    geo = area_geometry(area, build)
                water, obstacles, bridges, _ = geo
                e0, n0 = course_origin(c)
                chk = Checker(water, obstacles, bridges, e0, n0)
                path = Path2(c["path_xz"], c["one_way_m"])
                best, tier, results = evaluate(c, chk, path)
                if "-v" in argv:
                    for x in results:
                        print("    " + describe(x))
                if best is None:
                    fields = {"end_behavior": "fade"}
                    b = max(results, key=lambda x: min(x["shore"], x["obstacle"], x["turn_shore"], x["turn_obstacle"]))
                    note = "kein Platz zum Wenden; am nächsten: " + describe(b)
                else:
                    fields = {"end_behavior": "turn", "return_offset_m": best["D"] * best["side"],
                              "turn_radius_m": best["R"]}
                    note = f"{'üblich' if tier == 0 else 'eng'}, Kehre {2 * best['half']:.0f} m; " + describe(best)
            rows.append((r["id"], fields, note))
            print(f"{r['id']}: {fields} – {note}", flush=True)
            old = {k: c.get(k) for k in ("end_behavior", "return_offset_m", "turn_radius_m") if k in c}
            if not check and old != fields:
                for k in ("end_behavior", "return_offset_m", "turn_radius_m"):
                    c.pop(k, None)
                c.update(fields)
                cj.write_text(json.dumps(c, ensure_ascii=False))
    return rows


if __name__ == "__main__":
    main(sys.argv[1:])
