"""Prüft je Strecke den Abstand der Bahn (Hinfahrt und Rückfahrt 12 m links) zum Rand des Kerngebiets.

Regel (Paris, 28.11.2026): Die Strecke muss je Qualitätsstufe mindestens 2 × far_step_m vom Kernrand entfernt bleiben.
Am Kernrand überlappt das grobe Umgebungsgitter (export.py: Standard 100 m bzw. 50 m in "hoch", Gebietsfeld
"far_step_m") das Kerngebiet; ein grosses Dreieck zwischen Land und Wasser kann dort als schräge Platte über der Bahn
liegen. Ein Verstoss heisst nur „Vorschau an dieser Stelle prüfen“ (run_preview.sh … --at <d>), nicht zwingend Fehler.

Nur Rechnen, kein Neubau: liest ../../courses/<strecke>/course.json (path_xz, origin, qualities, scene) und
areas/<gebiet>.json (core_lv95, far_step_m).
Aufruf (aus tools/coursebuilder, kein venv nötig):  python3 check_core_margin.py [--all]
Ausgabe: Tabelle der Verstösse (mit --all alle Strecken); Exit-Code 1, wenn es Verstösse gibt.
"""
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
COURSES = HERE.parents[1] / "courses"
FAR_STEP = {"standard": 100.0, "hoch": 50.0}   # wie export.QUALITY
BACK_OFF = 12.0                                  # Rückfahrt 12 m links der Hinfahrt (App)


def far_step(area, level):
    v = area.get("far_step_m")
    if isinstance(v, dict):
        return float(v.get(level, FAR_STEP[level]))
    return float(v) if v is not None else FAR_STEP[level]


def margins(path_en, core):
    """(minimaler Randabstand in m, Distanz entlang der Strecke an der engsten Stelle)."""
    e0, n0, e1, n1 = core
    best, best_d, cum = math.inf, 0.0, 0.0
    for i, (e, n) in enumerate(path_en):
        if i:
            cum += math.hypot(e - path_en[i - 1][0], n - path_en[i - 1][1])
        m = min(e - e0, e1 - e, n - n0, n1 - n)
        if m < best:
            best, best_d = m, cum
    return best, best_d


def back_lane(path_en):
    out = []
    for i in range(len(path_en)):
        a = path_en[max(i - 1, 0)]
        b = path_en[min(i + 1, len(path_en) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy) or 1.0
        out.append((path_en[i][0] - dy / L * BACK_OFF, path_en[i][1] + dx / L * BACK_OFF))
    return out


def main():
    show_all = "--all" in sys.argv
    areas = {json.loads(f.read_text())["id"]: json.loads(f.read_text()) for f in sorted((HERE / "areas").glob("*.json"))}
    rows, bad = [], 0
    for cj in sorted(COURSES.glob("*/course.json")):
        c = json.loads(cj.read_text())
        aid = c["scene"].split("/")[0]
        area = areas.get(aid)
        if not area or "path_xz" not in c:
            continue
        e0, n0 = c.get("origin") or c.get("origin_lv95")
        path = [(e0 + x, n0 - z) for x, z in c["path_xz"]]
        m_out, d_out = margins(path, area["core_lv95"])
        m, d, lane = m_out, d_out, "hin"
        if c.get("turns", 0) and not c.get("loop"):
            m_b, d_b = margins(back_lane(path), area["core_lv95"])
            if m_b < m:
                total = c.get("total_m", 0) or 0
                m, d, lane = m_b, (total - d_b if total else d_b), "rück"
        for level in c.get("qualities", ["standard"]):
            need = 2 * far_step(area, level)
            ok = m >= need
            bad += not ok
            if show_all or not ok:
                rows.append((c["id"], aid, level, round(m, 1), need, lane, round(d), "ok" if ok else "VERSTOSS"))
    print(f"{'Strecke':32} {'Gebiet':28} {'Stufe':8} {'Abstand':>8} {'Soll':>6} {'Bahn':5} {'bei d':>6}")
    for r in rows:
        print(f"{r[0]:32} {r[1]:28} {r[2]:8} {r[3]:8.1f} {r[4]:6.0f} {r[5]:5} {r[6]:6d}  {r[7]}")
    print(f"{bad} Verstösse")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
